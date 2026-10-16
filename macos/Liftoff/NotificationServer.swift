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

    /// Accumulate until the request head is complete — `agentresult` URLs carry
    /// a whole agent reply and can span several TCP reads.
    private nonisolated static func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) != nil
            if !headEnd && !isComplete && error == nil && buffer.count < 256 * 1024 {
                receiveRequest(on: connection, buffer: buffer)
                return
            }
            if let request = String(data: buffer, encoding: .utf8) {
                Task { @MainActor in Self.handle(request: request) }
            }
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    @MainActor
    private static func handle(request: String) {
        // First line: "GET /notify?title=...&message=... HTTP/1.1"
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://localhost\(parts[1])") else { return }

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
            setResultSummary(sessionID: id, reply: text)
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

    /// Summarize an agent's final reply into the session's sidebar result line.
    /// Skipped when the user is already looking at that terminal.
    @MainActor
    private static func setResultSummary(sessionID: UUID, reply: String) {
        for store in AppStore.allStores {
            for project in store.projects {
                guard let session = project.terminals.first(where: { $0.id == sessionID }),
                      session.runningAgent == .claude || session.runningAgent == .codex
                else { continue }
                if store.activeProjectID == project.id
                    && project.activeTerminalID == session.id
                    && NSApp.isActive { return }
                Task { @MainActor in
                    guard let summary = await AppStore.summarizeResult(reply) else { return }
                    // Dropped if the user focused the tab while we were waiting.
                    if store.activeProjectID == project.id
                        && project.activeTerminalID == session.id
                        && NSApp.isActive { return }
                    session.resultSummary = summary
                    session.resultSummaryAt = Date()
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
