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
    /// complete — long hook URLs and MCP bodies can span several reads.
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
        switch components.path {
        case "/mcp": return LiftoffMCP.handle(request)
        case "/notify", "/worktitle", "/agentresult":
            handle(components: components)
            return .ok
        default:
            // Unknown paths (e.g. OAuth discovery under /.well-known) must 404 so
            // MCP clients don't mistake this server for one that needs auth.
            return .notFound
        }
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
        clearNote(sessionID: sessionID)

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

    /// A new prompt starts a new task, so the previous agent note goes stale.
    @MainActor
    private static func clearNote(sessionID: UUID) {
        for store in AppStore.allStores {
            for project in store.projects {
                if let session = project.terminals.first(where: { $0.id == sessionID }) {
                    session.note = nil
                    return
                }
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
    static let notFound = HTTPResponse(status: 404, body: Data())

    var data: Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if !body.isEmpty { head += "Content-Type: \(contentType)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

// MARK: - MCP (Streamable HTTP, JSON responses only)

/// Minimal MCP server at POST /mcp so agents can push their own notifications
/// and tab titles. The terminal is identified by the `X-Liftoff-Session`
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
        let header = request.headers["x-liftoff-session"]
        let session = header.flatMap(UUID.init(uuidString:))
        // Claude sends an empty header outside Liftoff → stay hidden. Codex's
        // shared app-server may send a stale ID or none, so those still get the
        // tools and calls are matched to a tab by `cwd` (unmatched are dropped).
        let hidden = header.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false

        let result: [String: Any]
        switch method {
        case "initialize":
            // Outside a Liftoff terminal (no session header) the server stays
            // silent: no instructions and no tools, so agents never notify.
            var info: [String: Any] = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "liftoff", "version": "1.0"]
            ]
            if !hidden { info["instructions"] = instructions }
            result = info
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": hidden ? [] : tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            result = hidden
                ? toolResult("Not running inside a Liftoff terminal.", isError: true)
                : callTool(name, args, session: session)
        default:
            return json(["jsonrpc": "2.0", "id": id,
                         "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
        return json(["jsonrpc": "2.0", "id": id, "result": result])
    }

    /// Injected into the agent's system prompt, so the behavior travels with
    /// the server instead of every CLAUDE.md / AGENTS.md copy.
    static let instructions = """
        You are running inside a Liftoff terminal tab. The user is often in another app or tab, and \
        Liftoff's `notify` tool is the ONLY way they learn you are done. Rules (mandatory, no exceptions):
        - At the end of EVERY response, call `notify` exactly once as your very last step: first write \
        your full reply, then call `notify`, then end the turn without repeating your reply. This applies \
        to every response, including short answers, opinions, and replies that used no tools.
        - The message is one short sentence with the outcome or gist, e.g. "Login bug fixed, tests pass." \
        or "Answered: recommend building the fetcher service next."
        - If the task failed or is only partly done, start the message with "Failed:".
        - If you end by asking the user anything or waiting for a decision, approval, or input, start \
        the message with "Needs input:" and say what you need.
        - Never call `notify` more than once per response.
        - Always pass `cwd`: the absolute path of your current working directory.
        - Call `set_tab_title` with a short (2-5 word) title when you start working on a new task.
        """

    private static let tools: [[String: Any]] = [
        [
            "name": "notify",
            // Never deferred behind Claude Code's tool search.
            "_meta": ["anthropic/alwaysLoad": true],
            "description": "Send the user a macOS notification from this Liftoff terminal. "
                + "Call it exactly once as the very last step of EVERY response, after writing your "
                + "reply. One short sentence.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "Notification body."],
                    "cwd": ["type": "string", "description": "Absolute path of your current working directory."],
                    "title": ["type": "string", "description": "Optional title; defaults to the project name."]
                ],
                "required": ["message", "cwd"]
            ]
        ],
        [
            "name": "set_tab_title",
            // Never deferred behind Claude Code's tool search.
            "_meta": ["anthropic/alwaysLoad": true],
            "description": "Set this Liftoff terminal tab's title.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "cwd": ["type": "string", "description": "Absolute path of your current working directory."]
                ],
                "required": ["title", "cwd"]
            ]
        ]
    ]

    private static func callTool(_ name: String, _ args: [String: Any], session: UUID?) -> [String: Any] {
        switch name {
        case "notify":
            guard let message = args["message"] as? String, !message.isEmpty else {
                return toolResult("Missing `message`.", isError: true)
            }
            guard let located = resolve(session: session, cwd: args["cwd"] as? String) else {
                return toolResult("Ignored: not running inside a Liftoff terminal.")
            }
            let title = (args["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? located.project.folder.lastPathComponent
            NotificationManager.shared.post(title: title, message: message)
            located.terminal.note = message
            return toolResult("Notification sent.")
        case "set_tab_title":
            guard let title = args["title"] as? String,
                  let terminal = resolve(session: session, cwd: args["cwd"] as? String)?.terminal else {
                return toolResult("No title or not running inside a Liftoff terminal.", isError: true)
            }
            terminal.title = String(title.prefix(60))
            return toolResult("Title set.")
        default:
            return toolResult("Unknown tool: \(name)", isError: true)
        }
    }

    /// The session header wins when it names a live tab; otherwise pick the
    /// agent tab whose folder contains `cwd`, preferring the deepest match.
    private static func resolve(session: UUID?, cwd: String?) -> (project: Project, terminal: TerminalSession)? {
        if let session, let found = locate(session) { return found }
        guard let cwd, !cwd.isEmpty else { return nil }
        let target = URL(fileURLWithPath: cwd).standardizedFileURL.path
        func contains(_ folder: URL) -> Bool {
            let base = folder.standardizedFileURL.path
            return target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        }
        var best: (project: Project, terminal: TerminalSession, score: Int)?
        for store in AppStore.allStores {
            for project in store.projects {
                // Only tabs with a live agent can be the caller; this also keeps a
                // plain home-folder terminal from catching every path.
                for terminal in project.terminals where terminal.runningAgent != nil {
                    let folders = [terminal.workingDirectory, project.folder].filter(contains)
                    guard let depth = folders.map({ $0.standardizedFileURL.path.count }).max() else { continue }
                    let score = depth * 2 + (project.activeTerminalID == terminal.id ? 1 : 0)
                    if score > (best?.score ?? -1) { best = (project, terminal, score) }
                }
            }
        }
        return best.map { ($0.project, $0.terminal) }
    }

    private static func locate(_ id: UUID) -> (project: Project, terminal: TerminalSession)? {
        for store in AppStore.allStores {
            for project in store.projects {
                if let terminal = project.terminals.first(where: { $0.id == id }) {
                    return (project, terminal)
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
