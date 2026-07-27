import Foundation

/// Privacy-first product analytics. The reporter sends only a random
/// installation ID, the app version, and a batched terminal-open count.
/// It never reads project paths, terminal content, commands, user/device names,
/// hardware details, or crash data.
actor AnalyticsReporter {
    static let shared = AnalyticsReporter()

    private enum Keys {
        static let installationID = "analytics.installationID"
        static let pendingTerminals = "analytics.pendingTerminals"
    }

    private struct Heartbeat: Encodable {
        let installationID: String
        let version: String
        let terminalsOpened: Int

        enum CodingKeys: String, CodingKey {
            case installationID = "installation_id"
            case version
            case terminalsOpened = "terminals_opened"
        }
    }

    private let endpoint = URL(string: "https://liftoff-admin.shostkevych.com/api/v1/heartbeat")!
    private let defaults = UserDefaults.standard
    private var heartbeatTask: Task<Void, Never>?

    func start() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            await self.sendHeartbeat()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled else { return }
                await self.sendHeartbeat()
            }
        }
    }

    nonisolated func recordTerminalOpened() {
        Task { await incrementPendingTerminals() }
    }

    private func incrementPendingTerminals() {
        let count = defaults.integer(forKey: Keys.pendingTerminals)
        defaults.set(count + 1, forKey: Keys.pendingTerminals)
    }

    private func sendHeartbeat() async {
        let pendingTerminals = defaults.integer(forKey: Keys.pendingTerminals)
        let heartbeat = Heartbeat(
            installationID: installationID,
            version: appVersion,
            terminalsOpened: pendingTerminals
        )

        guard let body = try? JSONEncoder().encode(heartbeat) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return }

            let currentPending = defaults.integer(forKey: Keys.pendingTerminals)
            defaults.set(max(0, currentPending - pendingTerminals),
                         forKey: Keys.pendingTerminals)
        } catch {
            // Analytics must never affect app behavior. Pending terminal counts
            // remain local and are retried with the next heartbeat.
        }
    }

    private var installationID: String {
        if let existing = defaults.string(forKey: Keys.installationID) {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: Keys.installationID)
        return generated
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "unknown"
    }
}
