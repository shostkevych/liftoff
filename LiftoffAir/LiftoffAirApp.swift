import SwiftUI

@main
struct LiftoffAirApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Gates the app on first-launch pairing: until the user scans a Mac's Air
/// code and picks an IP, we show onboarding instead of the session list.
private struct RootView: View {
    @AppStorage("airPaired") private var paired = false
    @AppStorage("airDemo") private var demo = false

    /// On the simulator there's no camera to scan a pairing code, so skip the
    /// whole onboarding flow and connect straight to the Mac running the app
    /// (the simulator shares the host's loopback interface).
    private static let simulatorHost = "127.0.0.1"

    var body: some View {
        #if targetEnvironment(simulator)
        SessionListView()
            .onAppear {
                UserDefaults.standard.set(Self.simulatorHost, forKey: "companionHost")
                paired = true
            }
        #else
        if paired || demo {
            SessionListView()
        } else {
            OnboardingView(onConnect: { host in
                UserDefaults.standard.set(host, forKey: "companionHost")
                paired = true
            }, onDemo: { demo = true })
        }
        #endif
    }
}
