import Foundation

private enum HookEndpoint {
    static let marker = "localhost:\(48623 + BuildVariant.portOffset)"
    static let baseURL = "http://\(marker)"

    /// Liftoff's MCP server (see `LiftoffMCP`), registered per build variant.
    static let mcpName = BuildVariant.portOffset == 0 ? "liftoff" : "liftoff-dev"
    static let mcpURL = "\(baseURL)/mcp"
    static let sessionHeader = "X-Liftoff-Session"
}

/// Find/strip Liftoff's entries in an agent hooks event (matcher array).
private enum LiftoffHooks {
    private static func isLiftoff(_ matcher: [String: Any], markers: [String]) -> Bool {
        guard let hooks = matcher["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return markers.contains { command.contains($0) }
        }
    }

    static func contains(_ existing: Any?, markers: [String]) -> Bool {
        (existing as? [[String: Any]] ?? []).contains { isLiftoff($0, markers: markers) }
    }

    static func removing(_ existing: Any?, markers: [String]) -> [[String: Any]] {
        (existing as? [[String: Any]] ?? []).filter { !isLiftoff($0, markers: markers) }
    }
}

/// Manages Liftoff's Claude Code notification hook in ~/.claude/settings.json.
/// The hook curls Liftoff's local NotificationServer on the
/// UserPromptSubmit event (tab work titles). Notifications come from the agent
/// itself via Liftoff's MCP server; older Notification/Stop hooks are removed.
enum HookSetup {
    /// The default config folder when a session sets no CLAUDE_CONFIG_DIR.
    static let defaultConfigDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude")

    private static func settingsFile(in configDir: URL) -> URL {
        configDir.appendingPathComponent("settings.json")
    }

    /// Substring that uniquely identifies our hook in the settings file. Must
    /// survive JSON escaping — `JSONSerialization` writes `/` as `\/`, so the
    /// marker deliberately avoids slashes (the port alone is unique enough).
    private static let marker = HookEndpoint.marker

    /// Older Liftoff builds installed a separate `claude-notify.sh` script hook
    /// for the same events. It doesn't contain `marker`, so dedup must match it
    /// too — otherwise it lingers alongside the inline hook and fires twice.
    private static let legacyMarker = "claude-notify"

    /// Events whose Liftoff hooks older builds installed and we now remove.
    private static let retiredEvents = ["Notification", "Stop"]

    /// True when the work-title hook and MCP server are set up and no retired
    /// notification hook lingers (so older installs get re-prompted to clean up).
    static func isInstalled(in configDir: URL) -> Bool {
        guard let data = try? Data(contentsOf: settingsFile(in: configDir)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return LiftoffHooks.contains(hooks["UserPromptSubmit"], markers: [marker])
            && !retiredEvents.contains { LiftoffHooks.contains(hooks[$0], markers: [marker, legacyMarker]) }
            && isMCPInstalled(in: configDir)
    }

    /// Claude keeps user-scope MCP servers in `.claude.json` — `~/.claude.json`
    /// for the default folder, otherwise inside the CLAUDE_CONFIG_DIR folder.
    private static func claudeJSON(for configDir: URL) -> URL {
        configDir.standardizedFileURL == defaultConfigDir.standardizedFileURL
            ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
            : configDir.appendingPathComponent(".claude.json")
    }

    private static func isMCPInstalled(in configDir: URL) -> Bool {
        guard let data = try? Data(contentsOf: claudeJSON(for: configDir)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[HookEndpoint.mcpName] as? [String: Any] else { return false }
        return entry["url"] as? String == HookEndpoint.mcpURL
    }

    /// Register Liftoff's MCP server; the session header expands from the
    /// env var Liftoff injects into each terminal.
    @discardableResult
    private static func installMCP(in configDir: URL) -> Bool {
        let file = claudeJSON(for: configDir)
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            root = json
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[HookEndpoint.mcpName] = [
            "type": "http",
            "url": HookEndpoint.mcpURL,
            "headers": [HookEndpoint.sessionHeader: "${LIFTOFF_SESSION_ID:-}"]
        ]
        root["mcpServers"] = servers
        guard let out = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return false }
        return (try? out.write(to: file, options: .atomic)) != nil
    }

    /// Merge the work-title hook into this folder's settings.json, drop retired
    /// Liftoff notification hooks, and register the MCP server.
    @discardableResult
    static func install(in configDir: URL) -> Bool {
        let file = settingsFile(in: configDir)
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in retiredEvents {
            let kept = LiftoffHooks.removing(hooks[event], markers: [marker, legacyMarker])
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var prompt = LiftoffHooks.removing(hooks["UserPromptSubmit"], markers: [marker, legacyMarker])
        prompt.append(["hooks": [["type": "command", "command": userPromptSubmitCommand]]])
        hooks["UserPromptSubmit"] = prompt
        root["hooks"] = hooks

        guard let out = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true)
        guard (try? out.write(to: file)) != nil else { return false }
        return installMCP(in: configDir)
    }

    /// Fired when the user submits a prompt — sends the prompt text as this
    /// session's "work title" so the tab reflects what Claude is doing. Routed
    /// to the exact terminal via the injected $LIFTOFF_SESSION_ID env var.
    private static let userPromptSubmitCommand =
        "I=$(cat); P=$(printf '%s' \"$I\" | jq -r '.prompt // empty'); "
        + "if [ -n \"$LIFTOFF_SESSION_ID\" ] && [ -n \"$P\" ]; then "
        + "curl -sG \(HookEndpoint.baseURL)/worktitle "
        + "--data-urlencode \"session=$LIFTOFF_SESSION_ID\" "
        + "--data-urlencode \"title=$P\" >/dev/null 2>&1 || true; fi"
}

/// Manages Liftoff's Codex work-title hook in ~/.codex/hooks.json plus the MCP
/// server in config.toml. Older PermissionRequest/Stop notify hooks are removed.
enum CodexHookSetup {
    /// The default config folder when a session sets no CODEX_HOME.
    static let defaultConfigDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex")

    private static func hooksFile(in configDir: URL) -> URL {
        configDir.appendingPathComponent("hooks.json")
    }

    private static let marker = HookEndpoint.marker

    private static let retiredEvents = ["PermissionRequest", "Stop"]

    static func isInstalled(in configDir: URL) -> Bool {
        guard let data = try? Data(contentsOf: hooksFile(in: configDir)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return LiftoffHooks.contains(hooks["UserPromptSubmit"], markers: [marker])
            && !retiredEvents.contains { LiftoffHooks.contains(hooks[$0], markers: [marker]) }
            && isMCPInstalled(in: configDir)
    }

    private static var mcpTable: String { "[mcp_servers.\(HookEndpoint.mcpName)]" }

    private static func isMCPInstalled(in configDir: URL) -> Bool {
        let text = (try? String(contentsOf: configDir.appendingPathComponent("config.toml"), encoding: .utf8)) ?? ""
        return text.contains(mcpTable)
    }

    /// Append Liftoff's MCP server to config.toml (left alone if a table with
    /// that name already exists).
    @discardableResult
    private static func installMCP(in configDir: URL) -> Bool {
        guard !isMCPInstalled(in: configDir) else { return true }
        let file = configDir.appendingPathComponent("config.toml")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += """

        \(mcpTable)
        url = "\(HookEndpoint.mcpURL)"
        env_http_headers = { "\(HookEndpoint.sessionHeader)" = "LIFTOFF_SESSION_ID" }

        """
        return (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil
    }

    /// Merge Liftoff's hooks into Codex's hooks.json while preserving any
    /// existing lifecycle hooks.
    @discardableResult
    static func install(in configDir: URL) -> Bool {
        let file = hooksFile(in: configDir)
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            root = json
        }
        guard root["hooks"] == nil || root["hooks"] is [String: Any] else { return false }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in retiredEvents {
            let kept = LiftoffHooks.removing(hooks[event], markers: [marker])
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var prompt = LiftoffHooks.removing(hooks["UserPromptSubmit"], markers: [marker])
        prompt.append(["hooks": [[
            "type": "command",
            "command": userPromptSubmitCommand,
            "timeout": 3
        ]]])
        hooks["UserPromptSubmit"] = prompt
        root["hooks"] = hooks

        guard let out = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true)
        guard (try? out.write(to: file)) != nil else { return false }
        return installMCP(in: configDir)
    }

    private static let userPromptSubmitCommand =
        "I=$(cat); P=$(printf '%s' \"$I\" | jq -r '.prompt // empty'); "
        + "if [ -n \"$LIFTOFF_SESSION_ID\" ] && [ -n \"$P\" ]; then "
        + "curl -sG \(HookEndpoint.baseURL)/worktitle "
        + "--data-urlencode \"session=$LIFTOFF_SESSION_ID\" "
        + "--data-urlencode \"title=$P\" >/dev/null 2>&1 || true; fi"
}

/// Manages Liftoff's opencode notification plugin in
/// ~/.config/opencode/plugins/. opencode exposes lifecycle events through a
/// JS/TS plugin system (not shell hooks), so we drop a small plugin that
/// curls Liftoff's local NotificationServer on session.idle and
/// permission.asked — mirroring the Claude Notification + Stop hooks.
enum OpenCodeHookSetup {
    /// The default config folder when a session sets no OPENCODE_CONFIG_DIR.
    static let defaultConfigDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/opencode")

    private static let pluginFileName = "liftoff-notify.js"

    /// Substring that uniquely identifies our plugin in the plugins folder.
    private static let marker = HookEndpoint.marker

    /// opencode loads plugins from the `plugin/` (singular) directory.
    private static let pluginDirName = "plugin"

    /// True when our notify plugin is already present in this folder.
    static func isInstalled(in configDir: URL) -> Bool {
        let file = configDir
            .appendingPathComponent(pluginDirName)
            .appendingPathComponent(pluginFileName)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    /// Write the plugin into this folder's plugin/ directory, creating it if
    /// needed. Returns true on success.
    @discardableResult
    static func install(in configDir: URL) -> Bool {
        let pluginDir = configDir.appendingPathComponent(pluginDirName)
        try? FileManager.default.createDirectory(
            at: pluginDir, withIntermediateDirectories: true)
        let file = pluginDir.appendingPathComponent(pluginFileName)
        return (try? pluginSource.write(
            to: file, atomically: true, encoding: .utf8)) != nil
    }

    /// The plugin body. Subscribes to lifecycle events and POSTs a localhost
    /// notification to Liftoff. Uses `fetch` (built into Bun) so there are no
    /// shell-quoting concerns; a try/catch silently no-ops when Liftoff isn't
    /// running. The `source=opencode` query item lets NotificationServer tell
    /// these apart from Claude's shell hooks (which have no source).
    private static let pluginSource = """
export const LiftoffNotify = async ({ directory }) => {
  const title = (directory || "opencode").split("/").pop();
  const notify = async (message) => {
    try {
      const params = new URLSearchParams({ title, message, source: "opencode" });
      await fetch(`\(HookEndpoint.baseURL)/notify?${params}`);
    } catch {}
  };
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") await notify("Finished");
      else if (event.type === "permission.asked") await notify("Needs your attention");
      else if (event.type === "session.error") await notify("Session error");
    },
  };
};
"""
}
