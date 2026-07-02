import Foundation

/// Manages Liftoff's Claude Code notification hook in ~/.claude/settings.json.
/// The hook curls Liftoff's local NotificationServer (port 48623) on the
/// Notification and Stop events, so a running agent surfaces native macOS
/// banners (project-aware title) without any extra setup from the user.
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
    private static let marker = "localhost:48623"

    /// Older Liftoff builds installed a separate `claude-notify.sh` script hook
    /// for the same events. It doesn't contain `marker`, so dedup must match it
    /// too — otherwise it lingers alongside the inline hook and fires twice.
    private static let legacyMarker = "claude-notify"

    /// True when our hooks are present in this folder's settings. Requires the
    /// `worktitle` route too, so installs from older builds (notify-only)
    /// self-heal and gain the UserPromptSubmit work-title hook on next prompt.
    static func isInstalled(in configDir: URL) -> Bool {
        guard let data = try? Data(contentsOf: settingsFile(in: configDir)),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(marker) && text.contains("worktitle")
    }

    /// Merge the Notification + Stop hooks into this folder's settings.json,
    /// preserving existing content and other hooks. Returns true on success.
    @discardableResult
    static func install(in configDir: URL) -> Bool {
        let file = settingsFile(in: configDir)
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks["Notification"] = appended(to: hooks["Notification"], command: notificationCommand)
        hooks["Stop"] = appended(to: hooks["Stop"], command: stopCommand)
        hooks["UserPromptSubmit"] = appended(to: hooks["UserPromptSubmit"], command: userPromptSubmitCommand)
        root["hooks"] = hooks

        guard let out = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true)
        return (try? out.write(to: file)) != nil
    }

    /// Append one command entry to an event's matcher array (or create it),
    /// first stripping any prior Liftoff entry so re-running self-heals the
    /// duplicate hooks left by the old, never-matching marker.
    private static func appended(to existing: Any?, command: String) -> [[String: Any]] {
        var matchers = existing as? [[String: Any]] ?? []
        matchers.removeAll { matcher in
            guard let hooks = matcher["hooks"] as? [[String: Any]] else { return false }
            return hooks.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains(marker) || command.contains(legacyMarker)
            }
        }
        matchers.append(["hooks": [["type": "command", "command": command]]])
        return matchers
    }

    /// Fired when Claude needs attention — uses the hook's `message`, and the
    /// project folder name (from `cwd`) as the banner title.
    private static let notificationCommand =
        "I=$(cat); D=$(printf '%s' \"$I\" | jq -r '.cwd // empty'); "
        + "M=$(printf '%s' \"$I\" | jq -r '.message // \"Needs your attention\"'); "
        + "T=$([ -n \"$D\" ] && basename \"$D\" || echo 'Claude Code'); "
        + "curl -sG http://localhost:48623/notify "
        + "--data-urlencode \"title=$T\" --data-urlencode \"message=$M\" >/dev/null 2>&1"

    /// Fired when Claude finishes a response.
    private static let stopCommand =
        "I=$(cat); D=$(printf '%s' \"$I\" | jq -r '.cwd // empty'); "
        + "T=$([ -n \"$D\" ] && basename \"$D\" || echo 'Claude Code'); "
        + "curl -sG http://localhost:48623/notify "
        + "--data-urlencode \"title=$T\" --data-urlencode 'message=Finished' >/dev/null 2>&1"

    /// Fired when the user submits a prompt — sends the prompt text as this
    /// session's "work title" so the tab reflects what Claude is doing. Routed
    /// to the exact terminal via the injected $LIFTOFF_SESSION_ID env var.
    private static let userPromptSubmitCommand =
        "I=$(cat); P=$(printf '%s' \"$I\" | jq -r '.prompt // empty'); "
        + "[ -n \"$LIFTOFF_SESSION_ID\" ] && [ -n \"$P\" ] && "
        + "curl -sG http://localhost:48623/worktitle "
        + "--data-urlencode \"session=$LIFTOFF_SESSION_ID\" --data-urlencode \"title=$P\" >/dev/null 2>&1"
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
    private static let marker = "localhost:48623"

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
      await fetch(`http://localhost:48623/notify?${params}`);
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
