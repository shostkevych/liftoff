import AppKit
import AVFoundation
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

    // MARK: Custom sound

    private static let customSoundKey = "customNotificationSound"
    private static let customPrefix = "LiftoffCustom-"
    private static var soundsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Sounds")
    }

    /// File name (in ~/Library/Sounds) of the user's uploaded sound, if any.
    var customSoundName: String? {
        guard let name = UserDefaults.standard.string(forKey: Self.customSoundKey),
              FileManager.default.fileExists(atPath: Self.soundsDir.appendingPathComponent(name).path)
        else { return nil }
        return name
    }

    private var currentSoundName: String { customSoundName ?? Self.soundName }

    /// Convert any audio file (MP3, M4A, WAV…) to 16-bit PCM CAF — the format
    /// notification sounds require — capped at 29 s, and make it the sound.
    /// Each upload gets a unique name because macOS caches sounds by name.
    func setCustomSound(from source: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let frames = AVAudioFrameCount(min(input.length, AVAudioFramePosition(format.sampleRate * 29)))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try input.read(into: buffer, frameCount: frames)

        try FileManager.default.createDirectory(at: Self.soundsDir, withIntermediateDirectories: true)
        let name = Self.customPrefix + String(Int(Date().timeIntervalSince1970)) + ".caf"
        let target = Self.soundsDir.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let output = try AVAudioFile(forWriting: target, settings: settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try output.write(from: buffer)
        }
        removeCustomSoundFiles(except: name)
        UserDefaults.standard.set(name, forKey: Self.customSoundKey)
    }

    func resetSound() {
        removeCustomSoundFiles(except: nil)
        UserDefaults.standard.removeObject(forKey: Self.customSoundKey)
    }

    private func removeCustomSoundFiles(except keep: String?) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.soundsDir.path)) ?? []
        for file in files where file.hasPrefix(Self.customPrefix) && file != keep {
            try? FileManager.default.removeItem(at: Self.soundsDir.appendingPathComponent(file))
        }
    }

    private var preview: NSSound?
    func playCurrentSound() {
        preview?.stop()
        let url = Self.soundsDir.appendingPathComponent(currentSoundName)
        preview = NSSound(contentsOf: url, byReference: true)
            ?? Bundle.main.url(forResource: "notification", withExtension: "caf").flatMap { NSSound(contentsOf: $0, byReference: true) }
        preview?.play()
    }

    func post(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound(named: UNNotificationSoundName(currentSoundName))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
