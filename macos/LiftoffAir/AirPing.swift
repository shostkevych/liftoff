import Foundation
import Network

/// Probes whether a Mac is reachable at the companion server's TCP port.
/// Used by the pairing screen to show a live / offline dot per scanned IP.
enum AirPing {
    /// Attempt a TCP connection to `host:48624`; succeeds if it reaches `.ready`
    /// within `timeout` seconds. Cancels and reports false otherwise.
    static func probe(host: String, timeout: TimeInterval = 2.0) async -> Bool {
        await withCheckedContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: 48624)!,
                using: .tcp
            )
            // Guard against resuming the continuation more than once.
            let resumed = ResumeOnce { conn.cancel() }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumed.fire { continuation.resume(returning: true) }
                case .failed, .cancelled:
                    resumed.fire { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            conn.start(queue: .global())

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumed.fire { continuation.resume(returning: false) }
            }
        }
    }

    /// Thread-safe one-shot gate so the continuation resumes exactly once.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let cleanup: () -> Void
        init(cleanup: @escaping () -> Void) { self.cleanup = cleanup }

        func fire(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            cleanup()
            body()
        }
    }
}
