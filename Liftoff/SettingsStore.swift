import Foundation

/// All app settings live in ~/.liftoff/settings.json.
/// Sensitive values (webPassword, cerebrasApiKey) are stored in the system Keychain.
enum SettingsStore {
    struct Settings: Codable {
        var recentProjectPaths: [String] = []
        var terminalFontSize: CGFloat = 13
        var projectTags: [String: ProjectTag] = [:]
        var hasSeenWelcome: Bool = false
        var declinedHookDirs: [String] = []
        var keepAwake: Bool = true
        /// Project folder paths the user pinned — reopened on next launch.
        var pinnedProjectPaths: [String] = []
        /// Width of the expanded project sidebar (points).
        var sidebarWidth: CGFloat = 220
        /// Persistent token for companion auth. Generated once, survives restarts.
        var companionToken: String = ""

        enum CodingKeys: String, CodingKey {
            case recentProjectPaths, terminalFontSize, projectTags, projectColors,
                 hasSeenWelcome, declinedHookDirs, keepAwake, pinnedProjectPaths,
                 sidebarWidth, companionToken
            // Legacy webPassword + cerebrasApiKey decoded during migration then dropped.
        }

        init(recentProjectPaths: [String] = [], terminalFontSize: CGFloat = 13,
             projectTags: [String: ProjectTag] = [:], hasSeenWelcome: Bool = false,
             declinedHookDirs: [String] = [], keepAwake: Bool = true,
             pinnedProjectPaths: [String] = [], sidebarWidth: CGFloat = 220,
             companionToken: String = "") {
            self.recentProjectPaths = recentProjectPaths
            self.terminalFontSize = terminalFontSize
            self.projectTags = projectTags
            self.hasSeenWelcome = hasSeenWelcome
            self.declinedHookDirs = declinedHookDirs
            self.keepAwake = keepAwake
            self.pinnedProjectPaths = pinnedProjectPaths
            self.sidebarWidth = sidebarWidth
            self.companionToken = companionToken
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            recentProjectPaths = try c.decodeIfPresent([String].self, forKey: .recentProjectPaths) ?? []
            terminalFontSize = try c.decodeIfPresent(CGFloat.self, forKey: .terminalFontSize) ?? 13
            projectTags = try c.decodeIfPresent([String: ProjectTag].self, forKey: .projectTags) ?? [:]
            if let legacy = try c.decodeIfPresent([String: String].self, forKey: .projectColors) {
                for (path, hex) in legacy where projectTags[path] == nil {
                    projectTags[path] = ProjectTag(label: "", colorHex: hex)
                }
            }
            hasSeenWelcome = try c.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? false
            declinedHookDirs = try c.decodeIfPresent([String].self, forKey: .declinedHookDirs) ?? []
            keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
            pinnedProjectPaths = try c.decodeIfPresent([String].self, forKey: .pinnedProjectPaths) ?? []
            sidebarWidth = try c.decodeIfPresent(CGFloat.self, forKey: .sidebarWidth) ?? 220
            companionToken = try c.decodeIfPresent(String.self, forKey: .companionToken) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(recentProjectPaths, forKey: .recentProjectPaths)
            try c.encode(terminalFontSize, forKey: .terminalFontSize)
            try c.encode(projectTags, forKey: .projectTags)
            try c.encode(hasSeenWelcome, forKey: .hasSeenWelcome)
            try c.encode(declinedHookDirs, forKey: .declinedHookDirs)
            try c.encode(keepAwake, forKey: .keepAwake)
            try c.encode(pinnedProjectPaths, forKey: .pinnedProjectPaths)
            try c.encode(sidebarWidth, forKey: .sidebarWidth)
            try c.encode(companionToken, forKey: .companionToken)
        }
    }

    static let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".liftoff")
    static let file = directory.appendingPathComponent("settings.json")

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return persistedMigrateLegacy(Settings())
        }

        // Migrate legacy secrets from JSON to Keychain
        if let legacyData = try? Data(contentsOf: file),
           let legacy = try? JSONSerialization.jsonObject(with: legacyData) as? [String: Any] {
            if let pw = legacy["webPassword"] as? String, !pw.isEmpty {
                _ = KeychainHelper.store(key: "webPassword", value: pw)
            }
            if let key = legacy["cerebrasApiKey"] as? String, !key.isEmpty {
                _ = KeychainHelper.store(key: "cerebrasApiKey", value: key)
            }
        }

        // Generate a companion token on first-ever load if one doesn't exist
        guard !settings.companionToken.isEmpty else {
            return persistedMigrateLegacy(settings)
        }
        return settings
    }

    /// First-launch or token-less config: generate a token and ensure legacy
    /// JSON fields are stripped from disk on the next save.
    private static func migrateLegacy(_ settings: Settings) -> Settings {
        var s = settings
        if s.companionToken.isEmpty {
            s.companionToken = LiftoffCrypto.generateToken()
        }
        return s
    }

    /// Same as `migrateLegacy`, but persists a freshly generated token so every
    /// subsequent `load()` returns the same value. Without this, each load mints
    /// a new random token — the QR's token and the server's expected token would
    /// never match, and companion auth always fails.
    private static func persistedMigrateLegacy(_ settings: Settings) -> Settings {
        let s = migrateLegacy(settings)
        if settings.companionToken.isEmpty, !s.companionToken.isEmpty {
            save(s)
        }
        return s
    }

    static func save(_ settings: Settings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        let directory = Self.directory
        let file = Self.file
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let tmp = directory.appendingPathComponent("settings.tmp")
            try? data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmp)
        }
    }

    // MARK: Keychain-backed secrets

    /// Web password for browser client access. Empty string means web access is disabled.
    static var webPassword: String {
        get { KeychainHelper.read(key: "webPassword") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(key: "webPassword")
            } else {
                KeychainHelper.store(key: "webPassword", value: newValue)
            }
        }
    }

    /// Cerebras API key for AI features. Empty string means AI features are disabled.
    static var cerebrasApiKey: String {
        get { KeychainHelper.read(key: "cerebrasApiKey") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(key: "cerebrasApiKey")
            } else {
                KeychainHelper.store(key: "cerebrasApiKey", value: newValue)
            }
        }
    }
}
