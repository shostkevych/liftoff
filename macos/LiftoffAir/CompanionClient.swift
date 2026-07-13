import Foundation
import Network
import Observation
import CryptoKit
import os

let companionLog = Logger(subsystem: "com.shostkevych.liftoffair", category: "companion")

/// TCP client for the Liftoff Mac companion server.
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
    var hasLoaded = false
    var attachedID: String?
    var greeting: String?
    var openedTid: String?
    /// True once authok has been received from the Mac.
    private(set) var authed = false

    @ObservationIgnored var onBytes: ((Data) -> Void)?
    @ObservationIgnored var onSize: ((Int, Int) -> Void)?

    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var inbox = Data()

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
    }

    @discardableResult
    func updateHost(_ newHost: String) -> Bool {
        let trimmed = newHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != host else { return false }
        disconnect()
        host = trimmed
        sessions = []
        hasLoaded = false
        state = "disconnected"
        connect()
        return true
    }

    func connect() {
        if demo { startDemo(); return }
        // Tear down any previous socket first. Stale connections must not keep
        // reporting state changes — their handlers stomping `state` is what made
        // the UI flap between connected/failed and kick the user out of terminals.
        connection?.cancel()
        authed = false
        inbox.removeAll()
        companionLog.info("connect() → \(self.host, privacy: .public):48624")
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: 48624)!,
            using: .tcp
        )
        conn.stateUpdateHandler = { [weak self, weak conn] st in
            Task { @MainActor in
                guard let self, let conn, self.connection === conn else { return }
                switch st {
                case .ready:
                    companionLog.info("socket ready — sending auth")
                    self.state = "connected"
                    self.authenticate()
                case .failed(let e):
                    companionLog.error("socket failed: \(String(describing: e), privacy: .public)")
                    self.state = "failed: \(e.localizedDescription)"
                case .cancelled:
                    companionLog.info("socket cancelled")
                    self.state = "disconnected"
                case .waiting(let e):
                    companionLog.warning("socket waiting: \(String(describing: e), privacy: .public)")
                    self.state = "waiting: \(e.localizedDescription)"
                case .preparing:
                    companionLog.info("socket preparing…")
                default:
                    break
                }
            }
        }
        connection = conn
        conn.start(queue: .main)
        receive(on: conn)
    }

    /// Send the pairing token to the Mac. Once authok arrives we proceed to list.
    private func authenticate() {
        companionLog.info("authenticating — token len=\(self.token.count) suffix=…\(String(self.token.suffix(4)), privacy: .public)")
        send(["t": "auth", "token": token])
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        authed = false
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
        guard var data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let t = dict["t"] as? String ?? "?"
        data.append(0x0A)
        guard let connection else {
            companionLog.warning("send(\(t, privacy: .public)) dropped — no connection")
            return
        }
        companionLog.debug("send → \(t, privacy: .public) (\(data.count) bytes)")
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                companionLog.error("send(\(t, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
            }
        })
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, let conn, self.connection === conn else { return }
                if let data, !data.isEmpty {
                    self.inbox.append(data)
                    self.drain()
                }
                if isComplete || error != nil {
                    companionLog.warning("receive ended — isComplete=\(isComplete) error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public)")
                    self.authed = false
                    self.state = "disconnected"
                } else {
                    self.receive(on: conn)
                }
            }
        }
    }

    private func drain() {
        while let nl = inbox.firstIndex(of: 0x0A) {
            let line = inbox[inbox.startIndex..<nl]
            let lineData = Data(line)
            inbox.removeSubrange(inbox.startIndex...nl)
            if !lineData.isEmpty { handle(lineData) }
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
