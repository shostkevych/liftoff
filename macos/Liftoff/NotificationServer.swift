import AppKit
import Foundation
import Network

/// Tiny localhost HTTP listener so CLI hooks can trigger notifications
/// without going through the URL scheme (which spawns windows).
/// GET /notify?title=...&message=...
@MainActor
final class NotificationServer {
    static let shared = NotificationServer()
    static let port: UInt16 = 48623 + BuildVariant.portOffset

    private var listener: NWListener?

    private init() {}

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params) else { return }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Self.receiveRequest(on: connection, buffer: Data())
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    /// Accumulate until the request (head plus Content-Length body) is
    /// complete — `agentresult` URLs and MCP bodies can span several reads.
    private nonisolated static func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            let request = HTTPRequest(buffer)
            if request == nil && !isComplete && error == nil && buffer.count < 1024 * 1024 {
                receiveRequest(on: connection, buffer: buffer)
                return
            }
            Task { @MainActor in
                let response = request.map(Self.respond) ?? .ok
                connection.send(content: response.data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    @MainActor
    private static func respond(to request: HTTPRequest) -> HTTPResponse {
        guard let components = URLComponents(string: "http://localhost\(request.target)") else { return .ok }
        if components.path == "/mcp" { return LiftoffMCP.handle(request) }
        handle(components: components)
        return .ok
    }

    @MainActor
    private static func handle(components: URLComponents) {
        // UserPromptSubmit hook: set a terminal's "work title" from the prompt.
        if components.path == "/worktitle" {
            let items = components.queryItems ?? []
            guard let sessionID = items.first(where: { $0.name == "session" })?.value,
                  let id = UUID(uuidString: sessionID),
                  let raw = items.first(where: { $0.name == "title" })?.value else { return }
            setWorkTitle(sessionID: id, prompt: raw)
            return
        }

        // Stop hook: an agent finished — summarize its reply for the sidebar.
        if components.path == "/agentresult" {
            let items = components.queryItems ?? []
            guard let sessionID = items.first(where: { $0.name == "session" })?.value,
                  let id = UUID(uuidString: sessionID),
                  let text = items.first(where: { $0.name == "text" })?.value else { return }
            setResultLevel(sessionID: id, reply: text)
            return
        }

        guard components.path == "/notify" else { return }

        let items = components.queryItems ?? []
        let title = items.first { $0.name == "title" }?.value ?? "Claude Code"
        let message = items.first { $0.name == "message" }?.value ?? "Needs your attention"
        let source = items.first { $0.name == "source" }?.value

        // Codex and opencode notifications come from Liftoff's own integrations,
        // so they're always genuine — skip the cross-agent suppression below.
        // Other agents (e.g. grok) import Claude's settings.json and run this
        // same hook — grok fires it on every turn/tool call, which spams. The
        // hook title is the project folder name; if that project's foreground
        // agent is a non-Claude CLI, drop the notification.
        guard source == "opencode"
                || source == "codex"
                || !isNonClaudeAgentProject(named: title) else { return }

        NotificationManager.shared.post(title: title, message: message)
    }

    /// Apply an agent prompt as the matching session's tab title.
    @MainActor
    private static func setWorkTitle(sessionID: UUID, prompt: String) {
        // First non-empty line, whitespace-trimmed, capped for the tab.
        let line = prompt
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !line.isEmpty else { return }
        let title = line.count > 60 ? String(line.prefix(60)) + "…" : line

        for store in AppStore.allStores {
            for project in store.projects {
                if let session = project.terminals.first(where: { $0.id == sessionID }),
                   session.runningAgent == .claude || session.runningAgent == .codex {
                    session.title = title
                    return
                }
            }
        }
    }

    /// Mark an unseen finished agent turn and triage its reply into the
    /// sidebar dot color. Skipped when the user is already looking at it.
    @MainActor
    private static func setResultLevel(sessionID: UUID, reply: String) {
        for store in AppStore.allStores {
            for project in store.projects {
                guard let session = project.terminals.first(where: { $0.id == sessionID }),
                      session.runningAgent == .claude || session.runningAgent == .codex
                else { continue }
                if store.activeProjectID == project.id
                    && project.activeTerminalID == session.id
                    && NSApp.isActive { return }
                session.needsAttention = true
                session.resultLevel = .neutral
                Task { @MainActor in
                    guard let level = await AppStore.classifyResult(reply) else { return }
                    // Dropped if the user focused the tab while we were waiting.
                    guard session.needsAttention else { return }
                    session.resultLevel = level
                }
                return
            }
        }
    }

    /// True when a project whose folder name matches `title` is running an
    /// agent and none of its terminals is Claude (so the hook came from another
    /// agent that merely imported Claude's config).
    @MainActor
    private static func isNonClaudeAgentProject(named title: String) -> Bool {
        for store in AppStore.allStores {
            for project in store.projects where project.folder.lastPathComponent == title {
                let agents = project.terminals.compactMap { $0.runningAgent }
                if agents.contains(.claude) { return false }   // Claude present — allow.
                if !agents.isEmpty { return true }             // Only non-Claude — suppress.
            }
        }
        return false   // Unknown project / no agent detected — allow.
    }
}

// MARK: - HTTP plumbing

struct HTTPRequest {
    let method: String
    let target: String
    let headers: [String: String]   // lowercased names
    let body: Data

    /// Nil until the head and the full Content-Length body have arrived.
    init?(_ buffer: Data) {
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<headEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "") ?? 0
        let body = buffer[headEnd.upperBound...]
        guard body.count >= length else { return nil }
        method = String(parts[0])
        target = String(parts[1])
        self.headers = headers
        self.body = Data(body.prefix(length))
    }
}

struct HTTPResponse {
    var status = 200
    var contentType = "text/plain"
    var body = Data("ok".utf8)

    static let ok = HTTPResponse()
    static let accepted = HTTPResponse(status: 202, body: Data())
    static let notAllowed = HTTPResponse(status: 405, body: Data())

    var data: Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if !body.isEmpty { head += "Content-Type: \(contentType)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

// MARK: - MCP (Streamable HTTP, JSON responses only)

/// Minimal MCP server at POST /mcp so agents can push their own notifications
/// and sidebar dots. The terminal is identified by the `X-Liftoff-Session`
/// header, which agent configs fill from $LIFTOFF_SESSION_ID.
@MainActor
enum LiftoffMCP {
    static func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard request.method == "POST" else { return .notAllowed }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let method = message["method"] as? String else {
            return json(["jsonrpc": "2.0", "id": NSNull(),
                         "error": ["code": -32700, "message": "Parse error"]], status: 400)
        }
        // Notifications (no id) get no reply.
        guard let id = message["id"] else { return .accepted }
        let params = message["params"] as? [String: Any] ?? [:]
        let session = request.headers["x-liftoff-session"].flatMap(UUID.init(uuidString:))

        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "liftoff", "version": "1.0"],
                "instructions": "Liftoff terminal integration. Use `notify` to send the user a desktop notification "
                    + "and color this terminal's sidebar dot (e.g. when a long task completes or fails)."
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            result = callTool(name, args, session: session)
        default:
            return json(["jsonrpc": "2.0", "id": id,
                         "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
        return json(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static let tools: [[String: Any]] = [
        [
            "name": "notify",
            "description": "Send the user a macOS notification from this Liftoff terminal and optionally "
                + "color its sidebar dot. Use for important results the user should see while away.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "Notification body."],
                    "title": ["type": "string", "description": "Optional title; defaults to the project name."],
                    "level": ["type": "string", "enum": ["neutral", "success", "attention", "critical"],
                              "description": "Sidebar dot color: neutral (white), success (green), "
                                  + "attention (yellow), critical (red). Omit to leave the dot unchanged."]
                ],
                "required": ["message"]
            ]
        ],
        [
            "name": "set_tab_title",
            "description": "Set this Liftoff terminal tab's title.",
            "inputSchema": [
                "type": "object",
                "properties": ["title": ["type": "string"]],
                "required": ["title"]
            ]
        ]
    ]

    private static func callTool(_ name: String, _ args: [String: Any], session: UUID?) -> [String: Any] {
        switch name {
        case "notify":
            guard let message = args["message"] as? String, !message.isEmpty else {
                return toolResult("Missing `message`.", isError: true)
            }
            let located = session.flatMap(locate)
            let title = (args["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? located?.1.folder.lastPathComponent ?? "Liftoff"
            NotificationManager.shared.post(title: title, message: message)
            if let level = (args["level"] as? String).flatMap(ResultLevel.init(rawValue:)),
               let located {
                let (store, project, terminal) = located
                let focused = store.activeProjectID == project.id
                    && project.activeTerminalID == terminal.id && NSApp.isActive
                if !focused {
                    terminal.needsAttention = true
                    terminal.resultLevel = level
                }
            }
            return toolResult("Notification sent.")
        case "set_tab_title":
            guard let title = args["title"] as? String, let terminal = session.flatMap(locate)?.2 else {
                return toolResult("No title or not running inside a Liftoff terminal.", isError: true)
            }
            terminal.title = String(title.prefix(60))
            return toolResult("Title set.")
        default:
            return toolResult("Unknown tool: \(name)", isError: true)
        }
    }

    private static func locate(_ id: UUID) -> (AppStore, Project, TerminalSession)? {
        for store in AppStore.allStores {
            for project in store.projects {
                if let terminal = project.terminals.first(where: { $0.id == id }) {
                    return (store, project, terminal)
                }
            }
        }
        return nil
    }

    private static func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func json(_ object: [String: Any], status: Int = 200) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return HTTPResponse(status: status, contentType: "application/json", body: body)
    }
}
