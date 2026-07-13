import SwiftUI

@main
struct LiftoffApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1600, height: 1000)
        .commands {
            // Terminal actions live in the right-click context menu over a
            // terminal pane; their shortcuts are handled in the key monitor.
            // Window-targeted menu items act on the frontmost window's store.
            CommandGroup(replacing: .appVisibility) {
                Button("Liftoff Help") {
                    AppStore.shared?.helpVisible.toggle()
                }
                .keyboardShortcut("h", modifiers: .command)
            }
            // Replace the system About panel with our own (version + updates).
            CommandGroup(replacing: .appInfo) {
                Button("About Liftoff") { AppStore.shared?.aboutVisible = true }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
            }
            CommandMenu("Air") {
                Button("Connect…") {
                    AppStore.shared?.airConnectVisible = true
                }
                Button("Set Web Password…") {
                    AppStore.shared?.webPasswordVisible = true
                }
                Button("Set Cerebras API Key…") {
                    AppStore.shared?.cerebrasKeyVisible = true
                }
                Divider()
                Button((AppStore.shared?.keepAwake ?? true) ? "✓ Keep Mac Awake" : "Keep Mac Awake") {
                    if let store = AppStore.shared { store.setKeepAwake(!store.keepAwake) }
                }
            }
        }
    }
}

/// One store per window. SwiftUI instantiates this root view once per
/// `WindowGroup` window, so each window gets its own detached `AppStore`
/// (no shared projects/terminals across windows). Global, window-spanning
/// services start once on the first window.
private struct RootView: View {
    @State private var store = AppStore()

    var body: some View {
        ContentView()
            .environment(store)
            // The whole UI is designed dark-only (black terminal, dark chrome,
            // .ultraThinMaterial panels). Without this, a user on macOS light
            // mode gets adaptive colors (.primary/labelColor → near-black) over
            // those dark surfaces — unreadable dark-on-dark text.
            .preferredColorScheme(.dark)
            .onAppear {
                store.activate()
                Self.bootstrapOnce()
            }
            .onDisappear { store.teardown() }
    }

    /// App-wide services that must start exactly once, regardless of how many
    /// windows open. They reach windows through `AppStore.allStores` / `.shared`.
    @MainActor private static var didBootstrap = false
    @MainActor private static func bootstrapOnce() {
        guard !didBootstrap else { return }
        didBootstrap = true
        // Force dark appearance for AppKit-hosted surfaces that don't inherit
        // SwiftUI's preferredColorScheme: SwiftTerm's NSView, the status-bar
        // menu, and detached NSWindows/popovers. Keeps light-mode users from
        // seeing near-black labelColor text on the app's always-dark chrome.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NotificationManager.shared.requestAuthorization()
        NotificationServer.shared.start()
        CompanionServer.shared.start()
        WebServer.shared.start()
        Updater.shared.start()
        StatusBarController.shared.install()
        FocusTrackingTerminalView.installKeyboardShortcuts()
        InstantTerminalController.shared.registerHotKey()
        if let store = AppStore.shared {
            SleepGuard.shared.apply(store.keepAwake)
            store.restorePinnedProjects()
            store.showWelcomeIfNeeded()
            store.showWhatsNewIfNeeded()
        }
    }
}
