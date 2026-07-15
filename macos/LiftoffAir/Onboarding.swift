import SwiftUI
import UIKit
import AVFoundation

/// Decoded contents of the Mac's "Air → Connect" QR code.
struct AirPayload {
    let port: Int
    let name: String
    let ips: [String]
    /// Persistent auth token (v2+). Nil for legacy v1 codes (requires re-pairing).
    let token: String?
    let relay: String?

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ips = obj["ips"] as? [String], !ips.isEmpty else { return nil }
        self.ips = ips
        self.port = obj["port"] as? Int ?? 48624
        self.name = obj["name"] as? String ?? "Mac"
        self.token = obj["token"] as? String
        self.relay = obj["relay"] as? String
    }
}

/// First-launch flow: welcome → scan intro → camera scan → connect.
/// Addresses are stored silently and raced by the connection client.
struct OnboardingView: View {
    let onConnect: (String) -> Void
    /// Enter the offline showcase mode (no Mac required).
    let onDemo: () -> Void

    private enum Step: Equatable {
        case welcome
        case scanIntro
        case scanning
    }

    @State private var step: Step = .welcome
    @State private var showCameraDeniedAlert = false

    var body: some View {
        ZStack {
            background
            content
                .padding(28)
        }
        .preferredColorScheme(.dark)
        .tint(.brand)
        .animation(.easeInOut(duration: 0.3), value: step)
        .alert("Camera Access Needed", isPresented: $showCameraDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Liftoff Air needs camera access to scan the pairing code shown on your Mac. Enable it in Settings.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeScreen
        case .scanIntro:
            scanIntroScreen
        case .scanning:
            ScannerScreen(
                onCancel: { step = .scanIntro },
                onScan: handleScan
            )
        }
    }

    // MARK: Screens

    private var welcomeScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            if let logo = Brand.logo {
                Image(uiImage: logo)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .opacity(0.85)
            }
            VStack(spacing: 12) {
                Text("Welcome to Liftoff Air")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("The companion app for Liftoff desktop. Mirror and control the AI coding sessions running on your Mac — anywhere on your network.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Link(destination: URL(string: "https://liftoff.shostkevych.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text("Get Liftoff for Mac")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.brand)
                }
                .padding(.top, 2)
            }
            Spacer()
            primaryButton("Get Started", icon: "arrow.right") { step = .scanIntro }
            Button("Try the demo", action: onDemo)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var scanIntroScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.brand)
            VStack(spacing: 12) {
                Text("Scan the Air Code")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("On your Mac, open Liftoff and choose **Air → Connect** from the menu bar. Then scan the QR code that appears.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Spacer()
            primaryButton("Scan Air Code", icon: "camera.fill", action: requestCameraThenScan)
        }
    }

    // MARK: Logic

    /// Request camera permission (or route to Settings if previously denied)
    /// before showing the live scanner.
    private func requestCameraThenScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            step = .scanning
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { step = .scanning } else { showCameraDeniedAlert = true }
                }
            }
        default:
            showCameraDeniedAlert = true
        }
    }

    private func handleScan(_ value: String) {
        guard let payload = AirPayload(json: value) else { return }
        // Never expose interface addresses in the UI. Keep all candidates so
        // the client can silently find a reachable local path when needed.
        UserDefaults.standard.set(payload.ips, forKey: "companionHosts")
        if let token = payload.token {
            UserDefaults.standard.set(token, forKey: "companionToken")
        }
        if let relay = payload.relay, !relay.isEmpty {
            UserDefaults.standard.set(relay, forKey: "relayBaseURL")
        }
        onConnect(payload.ips[0])
    }

    // MARK: Shared pieces

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [Color(white: 0.10), Color.black],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Full-screen camera scanner with a framing reticle and a cancel control.
private struct ScannerScreen: View {
    let onCancel: () -> Void
    let onScan: (String) -> Void

    var body: some View {
        ZStack {
            QRScannerView(onScan: onScan)
                .ignoresSafeArea()
                .padding(-28) // cancel parent padding so the preview is full-bleed

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.brand, lineWidth: 3)
                    .frame(width: 240, height: 240)
                Text("Point at the QR code on your Mac")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                Spacer()
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
