import Foundation
import Network

/// Tiny localhost HTTP listener so CLI hooks can trigger notifications
/// without going through the URL scheme (which spawns windows).
/// GET /notify?title=...&message=...
@MainActor
final class NotificationServer {
    static let shared = NotificationServer()
    static let port: UInt16 = 48623

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
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                if let data, let request = String(data: data, encoding: .utf8) {
                    Task { @MainActor in Self.handle(request: request) }
                }
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: .main)
        self.listener = listener
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

        guard components.path == "/notify" else { return }

        let items = components.queryItems ?? []
        let title = items.first { $0.name == "title" }?.value ?? "Claude Code"
        let message = items.first { $0.name == "message" }?.value ?? "Needs your attention"
        let source = items.first { $0.name == "source" }?.value

        // opencode notifications come from our own plugin (source=opencode) and
        // never from another agent importing Claude's config, so they're always
        // genuine — skip the cross-agent suppression below.
        // Other agents (e.g. grok) import Claude's settings.json and run this
        // same hook — grok fires it on every turn/tool call, which spams. The
        // hook title is the project folder name; if that project's foreground
        // agent is a non-Claude CLI, drop the notification.
        guard source == "opencode" || !isNonClaudeAgentProject(named: title) else { return }

        NotificationManager.shared.post(title: title, message: message)
    }

    /// Apply a Claude prompt as the matching session's tab title. Only Claude
    /// installs the UserPromptSubmit hook, but other agents can import Claude's
    /// settings.json — so restrict to sessions actually running Claude.
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
                   session.runningAgent == .claude {
                    session.title = title
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
