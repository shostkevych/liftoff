import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater. The feed URL, public key,
/// automatic-check flag, and 1-hour interval all come from Info.plist
/// (SUFeedURL / SUPublicEDKey / SUEnableAutomaticChecks / SUScheduledCheckInterval),
/// so this just owns the controller's lifetime and exposes a manual check.
@MainActor
final class Updater {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// Start the updater once (from app bootstrap). Sparkle then performs the
    /// scheduled background checks on its own every SUScheduledCheckInterval.
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// User-initiated check (the About screen button). Shows Sparkle's standard
    /// UI: "you're up to date" or the update/install prompt.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// When the last check ran, for the About screen status line.
    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }
}
