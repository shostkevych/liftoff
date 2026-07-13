import AppKit
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {}

    private static let soundName = "LiftoffNotification.caf"

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        installSound()
    }

    /// Show banners even when Liftoff is the foreground app — otherwise macOS
    /// silently suppresses them until you switch away (the "delayed" notifications).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// macOS resolves UNNotificationSound names via ~/Library/Sounds,
    /// so copy the bundled sound there on first launch.
    private func installSound() {
        guard let bundled = Bundle.main.url(forResource: "notification", withExtension: "caf") else { return }
        let soundsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Sounds")
        let target = soundsDir.appendingPathComponent(Self.soundName)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        try? FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: bundled, to: target)
    }

    func post(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound(named: UNNotificationSoundName(Self.soundName))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
