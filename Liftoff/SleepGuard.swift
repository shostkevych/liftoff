import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion so the Mac won't idle-sleep while Liftoff runs,
/// keeping the companion (Air) and web servers reachable for remote clients.
/// This prevents *idle system sleep* only — closing a laptop lid still sleeps.
@MainActor
final class SleepGuard {
    static let shared = SleepGuard()

    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    private init() {}

    /// Reflect the desired state (on/off). No-op when already in that state.
    func apply(_ enabled: Bool) {
        enabled ? enable() : disable()
    }

    private func enable() {
        guard !isActive else { return }
        let reason = "Liftoff keeps remote access reachable" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID)
        isActive = (result == kIOReturnSuccess)
    }

    private func disable() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
