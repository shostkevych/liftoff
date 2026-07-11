import Foundation
import Network
import CryptoKit

/// LAN/VPN server that lets the iOS companion app list open projects/tabs,
/// attach to a terminal, stream its raw PTY output, and send input.
///
/// Protocol: newline-delimited JSON, one message per line. Binary payloads
/// (terminal output/input, snapshots) are base64-encoded.
/// After auth, data payloads (`d` field) are ChaChaPoly-encrypted.
///
/// Client -> server:
///   {"t":"auth","token":"<base64 32-byte token>"}
///   {"t":"list"}
///   {"t":"attach","id":"<terminalUUID>"}
///   {"t":"input","d":"<base64 encrypted bytes>"}
/// Server -> client:
///   {"t":"authok"}
///   {"t":"sessions","items":[...]}
///   {"t":"snapshot","d":"<base64 encrypted data>"}
///   {"t":"output","d":"<base64 encrypted data>"}
@MainActor
final class CompanionServer {
    static let shared = CompanionServer()
    static let port: UInt16 = 48624

    private var listener: NWListener?
    static let wsPort: UInt16 = 48625
    private var wsListener: NWListener?

    /// Shared encryption key derived from the pairing token.
    private var cryptoKey: SymmetricKey {
        LiftoffCrypto.tokenToKey(token)
    }

    /// Current pairing token from settings.
    private var token: String { SettingsStore.load().companionToken }

    private final class Client {
        let connection: NWConnection
        let isWS: Bool
        var attached: UUID?
        var inbox = Data()
        var authed: Bool
        init(_ c: NWConnection, isWS: Bool) {
            connection = c
            self.isWS = isWS
            authed = false // both TCP (companion) and WS clients must auth
        }
    }

    private var clients: [ObjectIdentifier: Client] = [:]
    private var subscribers: [UUID: Set<ObjectIdentifier>] = [:]

    private init() {}

    func start() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let port = NWEndpoint.Port(rawValue: Self.port),
           let listener = try? NWListener(using: params, on: port) {
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn, isWS: false) }
            }
            listener.start(queue: .main)
            self.listener = listener
        }

        let wsParams = NWParameters.tcp
        wsParams.allowLocalEndpointReuse = true
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        wsParams.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        if let wsPort = NWEndpoint.Port(rawValue: Self.wsPort),
           let wsListener = try? NWListener(using: wsParams, on: wsPort) {
            wsListener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn, isWS: true) }
            }
            wsListener.start(queue: .main)
            self.wsListener = wsListener
        }
    }

    // MARK: Connection lifecycle

    private func accept(_ conn: NWConnection, isWS: Bool) {
        let client = Client(conn, isWS: isWS)
        clients[ObjectIdentifier(conn)] = client
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.disconnect(client) }
            default:
                break
            }
        }
        conn.start(queue: .main)
        if isWS { receiveWS(client) } else { receive(client) }
    }

    private func receiveWS(_ client: Client) {
        client.connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty { self.handle(line: data, from: client) }
                if error != nil {
                    self.disconnect(client)
                } else {
                    self.receiveWS(client)
                }
            }
        }
    }

    private func receive(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    client.inbox.append(data)
                    self.drain(client)
                }
                if isComplete || error != nil {
                    self.disconnect(client)
                } else {
                    self.receive(client)
                }
            }
        }
    }

    private func disconnect(_ client: Client) {
        let oid = ObjectIdentifier(client.connection)
        guard clients[oid] != nil else { return }
        if let tid = client.attached {
            release(tid, oid)
        }
        clients[oid] = nil
        client.connection.cancel()
    }

    // MARK: Framing

    private func drain(_ client: Client) {
        while let nl = client.inbox.firstIndex(of: 0x0A) {
            let line = client.inbox[client.inbox.startIndex..<nl]
            client.inbox.removeSubrange(client.inbox.startIndex...nl)
            if !line.isEmpty { handle(line: Data(line), from: client) }
        }
        if client.inbox.count > 1_000_000 {
            disconnect(client)
        }
    }

    // MARK: Message handling

    private func handle(line: Data, from client: Client) {
        guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let t = msg["t"] as? String else { return }

        // --- Auth for TCP (companion) clients ---
        // Raw TCP clients must present the pairing token before any command.
        // The token is embedded in the QR code and unique per Mac.
        if !client.isWS && !client.authed {
            if t == "auth" {
                let expected = token
                guard !expected.isEmpty else {
                    send(["t": "authfail"], to: client)
                    return
                }
                if (msg["token"] as? String) == expected {
                    client.authed = true
                    send(["t": "authok"], to: client)
                } else {
                    send(["t": "authfail"], to: client)
                }
            } else {
                send(["t": "needauth"], to: client)
            }
            return
        }

        // --- Auth for WebSocket (browser) clients ---
        if client.isWS && !client.authed {
            let password = SettingsStore.webPassword
            guard !password.isEmpty else {
                send(["t": "blocked"], to: client)
                return
            }
            if t == "auth" {
                if (msg["pass"] as? String) == password {
                    client.authed = true
                    send(["t": "authok"], to: client)
                } else {
                    send(["t": "authfail"], to: client)
                }
            } else {
                send(["t": "needauth"], to: client)
            }
            return
        }

        switch t {
        case "list":
            sendSessions(to: client)
        case "auth":
            break // already handled above
        case "attach":
            if let idStr = msg["id"] as? String, let id = UUID(uuidString: idStr) {
                attach(client, to: id)
            }
        case "input":
            if let id = client.attached,
               let b64 = msg["d"] as? String,
               let payload = Data(base64Encoded: b64),
               let view = TerminalHostView.cache[id] {
                // Fail closed: drop input that won't decrypt rather than typing
                // raw ciphertext into the user's real terminal.
                let raw: Data?
                if client.isWS {
                    raw = payload
                } else {
                    raw = try? LiftoffCrypto.decrypt(payload, using: cryptoKey)
                }
                if let raw { view.sendBytes([UInt8](raw)) }
            }
        case "upload":
            if let id = client.attached,
               let b64 = msg["d"] as? String,
               let decoded = Data(base64Encoded: b64),
               let view = TerminalHostView.cache[id] {
                let data: Data?
                if client.isWS {
                    data = decoded
                } else {
                    data = try? LiftoffCrypto.decrypt(decoded, using: cryptoKey)
                }
                guard let data, data.count <= 10_000_000 else { return }
                let name = (msg["name"] as? String) ?? "image.png"
                view.pasteUploadedImage(data, name: name)
            }
        case "resize":
            if let id = client.attached,
               let cols = msg["cols"] as? Int,
               let rows = msg["rows"] as? Int {
                TerminalHostView.cache[id]?.applyRemoteSize(cols: cols, rows: rows)
            }
        case "detach":
            if let id = client.attached {
                release(id, ObjectIdentifier(client.connection))
                client.attached = nil
            }
        case "recents":
            sendRecents(to: client)
        case "open":
            if let path = msg["path"] as? String {
                openProject(path, for: client)
            }
        case "openempty":
            openProject(NSHomeDirectory(), for: client)
        case "newtab":
            if let pidStr = msg["pid"] as? String, let pid = UUID(uuidString: pidStr) {
                newTab(in: pid, for: client)
            }
        case "close":
            if let idStr = msg["id"] as? String, let id = UUID(uuidString: idStr) {
                closeTerminal(id)
            }
        default:
            break
        }
    }

    // MARK: Commands

    private func sendSessions(to client: Client) {
        var items: [[String: Any]] = []
        for store in AppStore.allStores {
            for project in store.projects {
                let colorHex = store.colorHex(for: project)
                for term in project.terminals {
                    var item: [String: Any] = [
                        "tid": term.id.uuidString,
                        "title": term.displayTitle,
                        "pid": project.id.uuidString,
                        "pname": project.name,
                    ]
                    if let colorHex { item["color"] = colorHex }
                    if let agent = term.runningAgent { item["agent"] = Self.agentName(agent) }
                    if term.isBusy { item["busy"] = true }
                    items.append(item)
                }
            }
        }
        send(["t": "sessions", "items": items], to: client)
        ensureGreeting(for: client)
    }

    private func sendRecents(to client: Client) {
        guard let store = AppStore.shared ?? AppStore.allStores.first else { return }
        let openPaths = Set(AppStore.allStores.flatMap { $0.projects.map { $0.folder.path } })
        var items: [[String: Any]] = []
        for url in store.recentProjectURLs where !openPaths.contains(url.path) {
            var item: [String: Any] = ["path": url.path, "name": url.lastPathComponent]
            if let hex = store.colorHex(forPath: url.path) { item["color"] = hex }
            items.append(item)
        }
        send(["t": "recents", "items": items], to: client)
    }

    private func openProject(_ path: String, for client: Client) {
        let url = URL(fileURLWithPath: path)
        let newTid: String?
        if let (store, existing) = storeAndProject(forPath: url.path) {
            store.activeProjectID = existing.id
            store.activate()
            newTid = (existing.activeTerminalID ?? existing.terminals.first?.id)?.uuidString
        } else if let store = AppStore.shared ?? AppStore.allStores.first {
            store.addProject(folder: url)
            newTid = store.activeProject?.terminals.last?.id.uuidString
        } else {
            newTid = nil
        }
        sendSessions(to: client)
        if let newTid { send(["t": "opened", "tid": newTid], to: client) }
    }

    private func newTab(in pid: UUID, for client: Client) {
        guard let store = store(forProject: pid),
              let project = store.projects.first(where: { $0.id == pid }) else { return }
        let session = project.addTerminal()
        store.activeProjectID = project.id
        sendSessions(to: client)
        send(["t": "opened", "tid": session.id.uuidString], to: client)
    }

    // MARK: Multi-window store lookup

    private var projectIndex: [UUID: (AppStore, Project)] = [:]
    private var terminalIndex: [UUID: (AppStore, Project)] = [:]
    private var indexRevision: Int = -1

    private func rebuildIndexesIfNeeded() {
        let rev = AppStore.allStores.map(\.structureRevision).max() ?? 0
        guard rev != indexRevision else { return }
        indexRevision = rev
        projectIndex.removeAll(keepingCapacity: true)
        terminalIndex.removeAll(keepingCapacity: true)
        for store in AppStore.allStores {
            for project in store.projects {
                projectIndex[project.id] = (store, project)
                for term in project.terminals {
                    terminalIndex[term.id] = (store, project)
                }
            }
        }
    }

    private func store(forProject pid: UUID) -> AppStore? {
        rebuildIndexesIfNeeded()
        return projectIndex[pid]?.0
    }

    private func storeAndProject(forPath path: String) -> (AppStore, Project)? {
        rebuildIndexesIfNeeded()
        for (store, project) in projectIndex.values where project.folder.path == path {
            return (store, project)
        }
        return nil
    }

    private func storeAndProject(forTerminal id: UUID) -> (AppStore, Project)? {
        rebuildIndexesIfNeeded()
        return terminalIndex[id]
    }

    private func closeTerminal(_ id: UUID) {
        guard let (store, project) = storeAndProject(forTerminal: id),
              let term = project.terminals.first(where: { $0.id == id }) else { return }

        store.closeTerminal(term, in: project)
        broadcastSessions()
    }

    private func broadcastSessions() {
        for client in clients.values where client.authed { sendSessions(to: client) }
    }

    private var activityBroadcastScheduled = false
    func terminalActivityChanged() {
        guard !activityBroadcastScheduled else { return }
        activityBroadcastScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.activityBroadcastScheduled = false
            self.broadcastSessions()
        }
    }

    // MARK: Welcome greeting

    private var greeting: String?
    private var greetingRequested = false

    private func ensureGreeting(for client: Client) {
        if let greeting {
            send(["t": "greeting", "text": greeting], to: client)
            return
        }
        guard !greetingRequested else { return }
        greetingRequested = true
        Task { @MainActor in
            for attempt in 0..<3 {
                let text = await AppStore.cerebrasChat(system: Self.greetingSystem, user: "Generate the greeting.", temperature: 1.2)
                if let text, text.count < 220 {
                    self.greeting = text
                    for c in self.clients.values where c.authed { self.send(["t": "greeting", "text": text], to: c) }
                    return
                }
                if attempt < 2 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
            self.greetingRequested = false
        }
    }

    private func attach(_ client: Client, to id: UUID) {
        if let prev = client.attached {
            release(prev, ObjectIdentifier(client.connection))
        }
        client.attached = id
        subscribers[id, default: []].insert(ObjectIdentifier(client.connection))
        updateControlled()

        guard let view = TerminalHostView.cache[id] else { return }
        view.onOutput = { [weak self] slice in
            let bytes = Data(slice)
            Task { @MainActor in self?.fanout(id, bytes) }
        }
        let term = view.getTerminal()
        send(["t": "size", "cols": term.cols, "rows": term.rows], to: client)
        let snap = view.snapshotData()
        sendSnapshot(snap, to: client)
    }

    /// Send a snapshot payload, encrypted for companion clients.
    /// Fail closed: never fall back to plaintext for a TCP client — the phone
    /// drops undecryptable frames anyway, so the fallback only leaked data.
    private func sendSnapshot(_ data: Data, to client: Client) {
        let payload: String
        if client.isWS {
            payload = data.base64EncodedString()
        } else {
            guard let enc = try? LiftoffCrypto.encrypt(data, using: cryptoKey) else { return }
            payload = enc.base64EncodedString()
        }
        send(["t": "snapshot", "d": payload], to: client)
    }

    func disconnectTerminal(_ id: UUID) {
        // Detach subscribers but keep their connections alive — killing the whole
        // socket just because one terminal closed forced the phone into a full
        // reconnect. The debounced broadcast below refreshes their session lists.
        let oids = subscribers[id] ?? []
        for oid in oids {
            clients[oid]?.attached = nil
        }
        subscribers[id] = nil
        if let view = TerminalHostView.cache[id] {
            view.onOutput = nil
            view.clearRemoteSize()
        }
        updateControlled()
        terminalActivityChanged()
    }

    private func updateControlled() {
        var map: [UUID: RemoteKind] = [:]
        for (tid, oids) in subscribers {
            var kind: RemoteKind?
            for oid in oids {
                guard let c = clients[oid] else { continue }
                if c.isWS { kind = .web; break }
                kind = .mobile
            }
            if let kind { map[tid] = kind }
        }
        for store in AppStore.allStores {
            var local: [UUID: RemoteKind] = [:]
            for project in store.projects {
                for term in project.terminals where map[term.id] != nil {
                    local[term.id] = map[term.id]
                }
            }
            store.remoteControllers = local
        }
    }

    private func release(_ terminalID: UUID, _ oid: ObjectIdentifier) {
        subscribers[terminalID]?.remove(oid)
        if subscribers[terminalID]?.isEmpty ?? true {
            subscribers[terminalID] = nil
            if let view = TerminalHostView.cache[terminalID] {
                view.onOutput = nil
                view.clearRemoteSize()
            }
        }
        updateControlled()
    }

    private func fanout(_ terminalID: UUID, _ bytes: Data) {
        guard let oids = subscribers[terminalID], !oids.isEmpty else { return }
        for oid in oids {
            guard let client = clients[oid] else { continue }
            let payload: String
            if client.isWS {
                payload = bytes.base64EncodedString()
            } else {
                // Fail closed — no plaintext fallback (see sendSnapshot).
                guard let enc = try? LiftoffCrypto.encrypt(bytes, using: cryptoKey) else { continue }
                payload = enc.base64EncodedString()
            }
            send(["t": "output", "d": payload], to: client)
        }
    }

    // MARK: Wire helpers

    private func send(_ dict: [String: Any], to client: Client) {
        guard var data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        if client.isWS {
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "send", metadata: [meta])
            client.connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
        } else {
            data.append(0x0A)
            client.connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private static func agentName(_ agent: Agent) -> String { agent.label }

    private static let greetingSystem = "You write the single welcome line for Liftoff, a macOS terminal built for engineers who run AI coding agents (Claude Code, Codex) across many projects at once. Produce ONE original greeting, 1–2 sentences, max 22 words total, in the voice of an engineering innovation lab: confident, warm, a little poetic about building, shipping, terminals, and machines that work alongside you. Vary the theme each time. Plain text only — no quotes, no emojis, no markdown, no preamble."
}
