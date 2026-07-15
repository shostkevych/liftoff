import Foundation
import Network
import Observation
import CryptoKit
import os

let companionLog = Logger(subsystem: "com.shostkevych.liftoffair", category: "companion")

private final class RelayWebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onOpen?()
    }
}

/// Direct-first client for the Liftoff Mac companion server, with an opaque
/// WebSocket relay as fallback.
/// Protocol: newline-delimited JSON; binary payloads are base64-encoded.
/// After auth, data payloads (`d` field) are ChaChaPoly-encrypted with the
/// pairing token as the shared key.
@MainActor
@Observable
final class CompanionClient {
    struct Session: Identifiable, Hashable {
        let tid: String
        let title: String
        let pid: String
        let pname: String
        let agent: String?
        let color: String?
        let busy: Bool
        var id: String { tid }

        var displayTitle: String {
            let bullets: Set<Character> = ["·", "•", "∙", "◦", "‣", "⁃", "∗", "*",
                                           "✶", "✳", "✱", "✻", "✽", "❋", "✦", "✧",
                                           "●", "◯", "◐", "◓", "◑", "◒"]
            var s = Substring(title)
            while let c = s.first {
                if c.isWhitespace || bullets.contains(c) { s = s.dropFirst(); continue }
                if let u = c.unicodeScalars.first, c.unicodeScalars.count == 1,
                   (0x2800...0x28FF).contains(u.value) { s = s.dropFirst(); continue }
                break
            }
            let cleaned = s.trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? title : cleaned
        }
    }

    struct Recent: Identifiable, Hashable {
        let path: String
        let name: String
        let color: String?
        var id: String { path }
    }

    var sessions: [Session] = []
    var recents: [Recent] = []
    var state: String = "disconnected"
    private(set) var connectionKind: String?
    var hasLoaded = false
    var attachedID: String?
    var greeting: String?
    var openedTid: String?
    /// True once authok has been received from the Mac.
    private(set) var authed = false

    @ObservationIgnored var onBytes: ((Data) -> Void)?
    @ObservationIgnored var onSize: ((Int, Int) -> Void)?

    private enum Transport {
        case tcp(NWConnection)
        case relay(URLSessionWebSocketTask, URLSession)

        func cancel() {
            switch self {
            case .tcp(let connection): connection.cancel()
            case .relay(let task, let session):
                task.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
            }
        }
    }

    private final class Attempt {
        let id = UUID()
        let transport: Transport
        var inbox = Data()
        var keepalive: Task<Void, Never>?
        var awaitingUpgradeSnapshot = false
        var upgradeFrames: [Data] = []

        init(_ transport: Transport) { self.transport = transport }

        func cancel() {
            keepalive?.cancel()
            transport.cancel()
        }
    }

    @ObservationIgnored private var attempts: [UUID: Attempt] = [:]
    @ObservationIgnored private var active: Attempt?
    @ObservationIgnored private var connectGeneration = UUID()
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var directProbeTask: Task<Void, Never>?
    @ObservationIgnored private var shouldReconnect = false
    @ObservationIgnored private var lastDirectLoss = Date.distantPast
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let pathMonitorQueue = DispatchQueue(label: "com.shostkevych.liftoffair.network-path")

    private(set) var host: String
    private let token: String
    @ObservationIgnored private let cryptoKey: SymmetricKey
    /// Offline showcase mode: no socket; sessions and terminal output are canned.
    /// Used for the App Review demo and a no-Mac first look.
    @ObservationIgnored let demo: Bool

    init(host: String, token: String, demo: Bool = false) {
        self.host = host
        self.token = token
        self.demo = demo
        self.cryptoKey = LiftoffCrypto.tokenToKey(token)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.shouldReconnect else { return }
                companionLog.info("network path changed; reconnecting relay-first")
                if self.connectionKind == "local" { self.lastDirectLoss = Date() }
                self.connect()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    deinit { pathMonitor.cancel() }

    @discardableResult
    func updateHost(_ newHost: String) -> Bool {
        let trimmed = newHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != host else { return false }
        disconnect()
        host = trimmed
        var hosts = UserDefaults.standard.stringArray(forKey: "companionHosts") ?? []
        hosts.removeAll { $0 == trimmed }
        hosts.insert(trimmed, at: 0)
        UserDefaults.standard.set(hosts, forKey: "companionHosts")
        sessions = []
        hasLoaded = false
        state = "disconnected"
        connect()
        return true
    }

    func connect() {
        if demo { startDemo(); return }
        shouldReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        cancelTransports()
        authed = false
        state = "connecting"
        connectionKind = nil
        let generation = UUID()
        connectGeneration = generation

        // Prefer the relay without exposing network details. If it cannot
        // authenticate promptly, silently try every saved local address.
        startRelay(generation: generation)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, self.connectGeneration == generation else { return }
            self.startDirectCandidates(generation: generation)
        }
    }

    private func startDirectCandidates(generation: UUID) {
        guard connectGeneration == generation else { return }
        if let active, case .tcp = active.transport { return }
        let alreadyTryingLocal = attempts.values.contains { attempt in
            if case .tcp = attempt.transport { return true }
            return false
        }
        guard !alreadyTryingLocal else { return }
        let hosts = directCandidates()
        companionLog.info("probing \(hosts.count) saved Direct candidate(s)")
        for candidate in hosts { startDirect(host: candidate, generation: generation) }
    }

    private func directCandidates() -> [String] {
        var hosts = UserDefaults.standard.stringArray(forKey: "companionHosts") ?? []
        hosts.insert(host, at: 0)
        return hosts.reduce(into: []) { result, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !result.contains(trimmed) { result.append(trimmed) }
        }
    }

    private func startDirect(host candidateHost: String, generation: UUID) {
        companionLog.info("direct candidate → \(candidateHost, privacy: .public):48624")
        let conn = NWConnection(
            host: NWEndpoint.Host(candidateHost),
            port: NWEndpoint.Port(rawValue: 48624)!,
            using: .tcp
        )
        let attempt = Attempt(.tcp(conn))
        attempts[attempt.id] = attempt
        conn.stateUpdateHandler = { [weak self, weak conn] st in
            Task { @MainActor in
                guard let self, let conn, self.connectGeneration == generation,
                      self.attempts[attempt.id] === attempt || self.active === attempt else { return }
                switch st {
                case .ready:
                    companionLog.info("socket ready — sending auth")
                    self.authenticate(on: attempt)
                case .failed(let e):
                    companionLog.error("socket failed: \(String(describing: e), privacy: .public)")
                    self.fail(attempt, error: e.localizedDescription)
                case .cancelled:
                    companionLog.info("socket cancelled")
                case .waiting(let e):
                    companionLog.warning("socket waiting: \(String(describing: e), privacy: .public)")
                    // A waiting Direct path is not currently usable. Drop it
                    // rather than letting a private address stall indefinitely.
                    self.fail(attempt, error: e.localizedDescription)
                case .preparing:
                    companionLog.info("socket preparing…")
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
        receiveTCP(on: attempt, connection: conn, generation: generation)
    }

    private func startRelay(generation: UUID) {
        guard !token.isEmpty, let url = relayURL() else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(Self.digest("liftoff-relay-capability-v1:" + token))", forHTTPHeaderField: "Authorization")
        let delegate = RelayWebSocketDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        let attempt = Attempt(.relay(task, session))
        attempts[attempt.id] = attempt
        delegate.onOpen = { [weak self, weak attempt] in
            Task { @MainActor in
                guard let self, let attempt, self.connectGeneration == generation,
                      self.attempts[attempt.id] === attempt else { return }
                // The relay HTTP capability is the authentication step. Never
                // expose the raw pairing token in a relay frame. Wait for a
                // valid encrypted Mac response before allowing relay to beat a
                // still-connecting direct candidate.
                self.send(["t": "list"], on: attempt)
            }
        }
        companionLog.info("relay candidate → \(url.absoluteString, privacy: .public)")
        task.resume()
        receiveRelay(on: attempt, task: task, generation: generation)
    }

    private func relayURL() -> URL? {
        let configured = UserDefaults.standard.string(forKey: "relayBaseURL") ?? "wss://relay.shostkevych.com"
        guard var components = URLComponents(string: configured) else { return nil }
        if components.path.isEmpty || components.path == "/" { components.path = "/v1/relay" }
        let session = Self.digest("liftoff-relay-session-v1:" + token)
        components.queryItems = [
            URLQueryItem(name: "user", value: String(session.prefix(16))),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "device", value: "ios"),
            URLQueryItem(name: "role", value: "viewer")
        ]
        return components.url
    }

    nonisolated private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Send the pairing token to the Mac. Once authok arrives we proceed to list.
    private func authenticate(on attempt: Attempt) {
        companionLog.info("authenticating — token len=\(self.token.count) suffix=…\(String(self.token.suffix(4)), privacy: .public)")
        send(["t": "auth", "token": token], on: attempt)
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connectGeneration = UUID()
        cancelTransports()
        authed = false
        state = "disconnected"
    }

    func list() { if demo { return }; send(["t": "list"]) }
    func loadRecents() { if demo { loadDemoRecents(); return }; send(["t": "recents"]) }

    func openRecent(_ path: String) {
        if demo { demoOpen(name: (path as NSString).lastPathComponent, pid: "demo-p-" + path); return }
        send(["t": "open", "path": path])
    }

    func openEmpty() {
        if demo { demoOpen(name: "home", pid: "demo-home"); return }
        send(["t": "openempty"])
    }

    func newTab(pid: String) {
        if demo { demoOpen(name: demoProjectName(pid), pid: pid); return }
        send(["t": "newtab", "pid": pid])
    }

    func closeTerminal(_ tid: String) {
        if attachedID == tid { detach() }
        if demo { sessions.removeAll { $0.tid == tid }; return }
        send(["t": "close", "id": tid])
    }

    func attach(_ session: Session) {
        attachedID = session.tid
        if demo { feedDemoSnapshot(for: session); return }
        send(["t": "attach", "id": session.tid])
    }

    func detach() {
        if !demo { send(["t": "detach"]) }
        attachedID = nil
        onBytes = nil
    }

    /// Forward keystrokes from the terminal view to the Mac, encrypted.
    /// Fail closed: never send plaintext keystrokes — the server drops
    /// undecryptable input anyway.
    func sendInput(_ bytes: Data) {
        if demo { demoEcho(bytes); return }
        guard let enc = try? LiftoffCrypto.encrypt(bytes, using: cryptoKey) else { return }
        send(["t": "input", "d": enc.base64EncodedString()])
    }

    func sendResize(cols: Int, rows: Int) {
        if demo { return }
        send(["t": "resize", "cols": cols, "rows": rows])
    }

    // MARK: Wire

    private func send(_ dict: [String: Any]) {
        guard let active else {
            let t = dict["t"] as? String ?? "?"
            companionLog.warning("send(\(t, privacy: .public)) dropped — no authenticated transport")
            return
        }
        send(dict, on: active)
    }

    private func send(_ dict: [String: Any], on attempt: Attempt) {
        guard var data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let t = dict["t"] as? String ?? "?"
        data.append(0x0A)
        companionLog.debug("send → \(t, privacy: .public) (\(data.count) bytes)")
        switch attempt.transport {
        case .tcp(let connection):
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    companionLog.error("send(\(t, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
                }
            })
        case .relay(let task, _):
            // Relay frames are encrypted as a whole so project/session metadata
            // and protocol commands remain hidden alongside terminal payloads.
            guard let encrypted = try? LiftoffCrypto.encrypt(data, using: cryptoKey) else { return }
            task.send(.data(encrypted)) { error in
                if let error {
                    companionLog.error("relay send(\(t, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    private func receiveTCP(on attempt: Attempt, connection conn: NWConnection, generation: UUID) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, let conn, self.connectGeneration == generation,
                      self.attempts[attempt.id] === attempt || self.active === attempt else { return }
                if let data, !data.isEmpty {
                    self.receive(data, on: attempt)
                }
                if isComplete || error != nil {
                    companionLog.warning("receive ended — isComplete=\(isComplete) error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
                    self.fail(attempt, error: error?.localizedDescription)
                } else {
                    self.receiveTCP(on: attempt, connection: conn, generation: generation)
                }
            }
        }
    }

    private func receiveRelay(on attempt: Attempt, task: URLSessionWebSocketTask, generation: UUID) {
        task.receive { [weak self, weak task] result in
            Task { @MainActor in
                guard let self, let task, self.connectGeneration == generation,
                      self.attempts[attempt.id] === attempt || self.active === attempt else { return }
                switch result {
                case .success(.data(let data)):
                    guard let decrypted = try? LiftoffCrypto.decrypt(data, using: self.cryptoKey) else {
                        self.fail(attempt, error: "relay frame authentication failed")
                        return
                    }
                    self.receiveRelayFrame(decrypted, on: attempt)
                    self.receiveRelay(on: attempt, task: task, generation: generation)
                case .success(.string):
                    self.fail(attempt, error: "relay sent an unsupported text frame")
                case .failure(let error):
                    companionLog.warning("relay receive ended: \(String(describing: error), privacy: .public)")
                    self.fail(attempt, error: error.localizedDescription)
                @unknown default:
                    self.fail(attempt, error: nil)
                }
            }
        }
    }

    private func receive(_ data: Data, on attempt: Attempt) {
        attempt.inbox.append(data)
        while let nl = attempt.inbox.firstIndex(of: 0x0A) {
            let line = attempt.inbox[attempt.inbox.startIndex..<nl]
            let lineData = Data(line)
            attempt.inbox.removeSubrange(attempt.inbox.startIndex...nl)
            if !lineData.isEmpty { process(lineData, on: attempt) }
        }
    }

    /// WebSocket boundaries already preserve messages. The Mac deliberately
    /// sends relay JSON without TCP's newline delimiter.
    private func receiveRelayFrame(_ data: Data, on attempt: Attempt) {
        if data.contains(0x0A) {
            receive(data, on: attempt)
        } else if !data.isEmpty {
            process(data, on: attempt)
        }
    }

    private func process(_ line: Data, on attempt: Attempt) {
        let type = messageType(line)
        if active === attempt {
            handle(line)
        } else if type == "authok" {
            if case .tcp = attempt.transport, let active, case .relay = active.transport {
                // Direct is authenticated while Relay remains live. Prepare the
                // current terminal on Direct before replacing Relay.
                if let attachedID {
                    attempt.awaitingUpgradeSnapshot = true
                    send(["t": "attach", "id": attachedID], on: attempt)
                } else {
                    promote(attempt, replacingRelay: true)
                    authed = true
                    list()
                }
            } else {
                promote(attempt)
                handle(line)
            }
        } else if attempt.awaitingUpgradeSnapshot, type == "size" {
            attempt.upgradeFrames.append(line)
        } else if attempt.awaitingUpgradeSnapshot, type == "snapshot" {
            attempt.upgradeFrames.append(line)
            let frames = attempt.upgradeFrames
            promote(attempt, replacingRelay: true)
            authed = true
            for frame in frames { handle(frame) }
            list()
        } else if case .relay = attempt.transport, type == "sessions" {
            promote(attempt)
            authed = true
            startRelayKeepalive(on: attempt)
            startDirectUpgradeLoop()
            handle(line)
        } else if ["needauth", "authfail"].contains(type) {
            fail(attempt, error: "authentication rejected")
        }
    }

    private func messageType(_ line: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: line) as? [String: Any])?["t"] as? String
    }

    private func promote(_ winner: Attempt, replacingRelay: Bool = false) {
        guard attempts[winner.id] === winner else { return }
        let previous = active
        if let previous {
            guard replacingRelay,
                  case .relay = previous.transport,
                  case .tcp = winner.transport else { return }
        }
        active = winner
        switch winner.transport {
        case .relay: connectionKind = "relay"
        case .tcp: connectionKind = "local"
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        directProbeTask?.cancel()
        directProbeTask = nil
        attempts.removeValue(forKey: winner.id)
        for attempt in attempts.values { attempt.cancel() }
        attempts.removeAll()
        previous?.cancel()
        state = "connected"
        companionLog.info("authenticated transport selected: \(self.connectionKind ?? "unknown", privacy: .public)")
    }

    private func fail(_ attempt: Attempt, error: String?) {
        if active === attempt {
            if case .tcp = attempt.transport { lastDirectLoss = Date() }
            active = nil
            attempt.cancel()
            authed = false
            connectionKind = nil
            state = "disconnected"
            scheduleReconnect()
            return
        }
        guard attempts.removeValue(forKey: attempt.id) != nil else { return }
        attempt.cancel()
        if case .relay = attempt.transport {
            state = "connecting"
            startDirectCandidates(generation: connectGeneration)
        }
        if attempts.isEmpty, active == nil {
            state = error.map { "failed: \($0)" } ?? "disconnected"
            scheduleReconnect()
        }
    }

    private func cancelTransports() {
        directProbeTask?.cancel()
        directProbeTask = nil
        active?.cancel()
        active = nil
        connectionKind = nil
        for attempt in attempts.values { attempt.cancel() }
        attempts.removeAll()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled, self.shouldReconnect, self.active == nil else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    private func startRelayKeepalive(on attempt: Attempt) {
        attempt.keepalive = Task { @MainActor [weak self, weak attempt] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, let attempt, !Task.isCancelled,
                      self.active === attempt else { return }
                // Application traffic makes the relay's read loop refresh its
                // idle deadline; WebSocket control pings are consumed below it.
                self.send(["t": "ping"], on: attempt)
            }
        }
    }

    private func startDirectUpgradeLoop() {
        directProbeTask?.cancel()
        directProbeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let active = self.active,
                      case .relay = active.transport else { return }
                let cooldown = max(1, 15 - Date().timeIntervalSince(self.lastDirectLoss))
                try? await Task.sleep(nanoseconds: UInt64(cooldown * 1_000_000_000))
                guard !Task.isCancelled, let active = self.active,
                      case .relay = active.transport else { return }
                self.startDirectCandidates(generation: self.connectGeneration)
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private func handle(_ line: Data) {
        guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let t = msg["t"] as? String else {
            companionLog.error("unparseable line (\(line.count) bytes): \(String(data: line.prefix(120), encoding: .utf8) ?? "<binary>", privacy: .public)")
            return
        }
        companionLog.debug("recv ← \(t, privacy: .public)")
        switch t {
        case "authok":
            companionLog.info("auth OK")
            authed = true
            list()
        case "needauth", "authfail":
            companionLog.error("auth rejected (\(t, privacy: .public))")
            authed = false
            state = "auth failed"
        case "sessions":
            let items = msg["items"] as? [[String: Any]] ?? []
            sessions = items.map {
                Session(
                    tid: $0["tid"] as? String ?? "",
                    title: $0["title"] as? String ?? "zsh",
                    pid: $0["pid"] as? String ?? "",
                    pname: $0["pname"] as? String ?? "",
                    agent: $0["agent"] as? String,
                    color: $0["color"] as? String,
                    busy: $0["busy"] as? Bool ?? false
                )
            }
            hasLoaded = true
        case "recents":
            let items = msg["items"] as? [[String: Any]] ?? []
            recents = items.map {
                Recent(
                    path: $0["path"] as? String ?? "",
                    name: $0["name"] as? String ?? "",
                    color: $0["color"] as? String
                )
            }
        case "opened":
            openedTid = msg["tid"] as? String
        case "greeting":
            greeting = msg["text"] as? String
        case "size":
            if let cols = msg["cols"] as? Int, let rows = msg["rows"] as? Int {
                onSize?(cols, rows)
            }
        case "snapshot", "output":
            // Fail closed: only render successfully decrypted bytes. Never feed
            // raw ciphertext to the terminal — that's what showed up as garbled,
            // "encrypted-looking" symbols when a frame failed to decrypt.
            if let b64 = msg["d"] as? String, let enc = Data(base64Encoded: b64) {
                if let raw = try? LiftoffCrypto.decrypt(enc, using: cryptoKey) {
                    onBytes?(raw)
                } else {
                    companionLog.error("\(t, privacy: .public) frame failed to decrypt (\(enc.count) bytes)")
                }
            }
        default:
            break
        }
    }

    // MARK: Demo mode

    /// Bring the UI to a connected, populated state with no network.
    private func startDemo() {
        greeting = "Welcome aboard. This is a guided demo — pair your Mac to fly for real."
        sessions = Self.demoSessions
        recents = []
        state = "connected"
        authed = true
        hasLoaded = true
    }

    private static let demoSessions: [Session] = [
        Session(tid: "demo-cc", title: "claude code", pid: "demo-liftoff", pname: "liftoff",
                agent: "Claude", color: "#E0623F", busy: true),
        Session(tid: "demo-zsh", title: "zsh", pid: "demo-liftoff", pname: "liftoff",
                agent: nil, color: "#E0623F", busy: false),
        Session(tid: "demo-srv", title: "npm run dev", pid: "demo-site", pname: "site",
                agent: nil, color: "#3F8DE0", busy: false),
    ]

    private func demoProjectName(_ pid: String) -> String {
        sessions.first { $0.pid == pid }?.pname ?? "project"
    }

    private func loadDemoRecents() {
        recents = [
            Recent(path: "/Users/you/Developer/api", name: "api", color: "#5FD08D"),
            Recent(path: "/Users/you/Developer/web", name: "web", color: "#D0B23F"),
            Recent(path: "/Users/you/Developer/infra", name: "infra", color: "#9B7FE0"),
        ]
    }

    /// Spawn a fresh demo terminal in a project and navigate to it.
    private func demoOpen(name: String, pid: String) {
        let tid = "demo-new-\(sessions.count)"
        sessions.append(Session(tid: tid, title: "zsh", pid: pid, pname: name,
                                agent: nil, color: "#3F8DE0", busy: false))
        openedTid = tid
    }

    /// Feed a canned screen so the attached terminal looks alive.
    private func feedDemoSnapshot(for session: Session) {
        let text = session.agent != nil ? Self.demoClaudeScreen : Self.demoShellScreen
        let bytes = Data(text.utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onBytes?(bytes)
        }
    }

    /// Locally echo typed input so the demo terminal feels interactive, with a
    /// fresh prompt drawn on each Return.
    private func demoEcho(_ bytes: Data) {
        var out = Data()
        for b in bytes {
            if b == 0x0d || b == 0x0a {
                out.append(contentsOf: Array("\r\n".utf8))
                out.append(contentsOf: Array(Self.demoPrompt.utf8))
            } else {
                out.append(b)
            }
        }
        onBytes?(out)
    }

    private static let demoPrompt = "\u{1b}[38;5;208m➜\u{1b}[0m \u{1b}[36mliftoff\u{1b}[0m "

    private static let demoShellScreen =
        "\r\n\u{1b}[38;5;208m  Liftoff Air — Demo\u{1b}[0m\r\n" +
        "\u{1b}[90m  Type away: this terminal echoes locally. Pair your Mac for the real thing.\u{1b}[0m\r\n\r\n" +
        demoPrompt

    private static let demoClaudeScreen =
        "\r\n\u{1b}[38;5;208m✻ Claude Code\u{1b}[0m \u{1b}[90m· liftoff\u{1b}[0m\r\n\r\n" +
        "\u{1b}[36m> add a disconnect option to settings\u{1b}[0m\r\n\r\n" +
        "\u{1b}[97m● I'll add a \"Disconnect Phone\" button that clears the pairing and\r\n" +
        "  returns to onboarding.\u{1b}[0m\r\n\r\n" +
        "\u{1b}[32m  ✔ Updated SettingsSheet.swift\u{1b}[0m\r\n" +
        "\u{1b}[32m  ✔ Updated SessionListView.swift\u{1b}[0m\r\n\r\n" +
        "\u{1b}[90m  ⏳ Building…\u{1b}[0m\r\n\r\n" +
        "\u{1b}[90m  This is a demo session. Pair your Mac to drive real terminals.\u{1b}[0m\r\n\r\n" +
        demoPrompt
}
