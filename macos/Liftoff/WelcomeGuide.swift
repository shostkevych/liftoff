import SwiftUI

/// First-launch onboarding: a modern, Apple-inspired paged guide that introduces
/// Liftoff, then projects & tags, AI summaries, Liftoff Air, and shortcuts —
/// finishing into the home screen.
struct WelcomeGuide: View {
    let finish: () -> Void

    @State private var step = 0

    private let pages = WelcomePage.all

    var body: some View {
        VStack(spacing: 0) {
            // Paged content — cross-fades / slides between steps.
            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    if index == step {
                        WelcomePageView(page: page)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 24)),
                                removal: .opacity.combined(with: .offset(x: -24))
                            ))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.35), value: step)

            footer
        }
        .frame(width: 720, height: 700)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
                // Soft brand glow drifting with the current page's accent.
                RadialGradient(
                    colors: [pages[step].accent.opacity(0.28), .clear],
                    center: .top, startRadius: 0, endRadius: 520
                )
                .animation(.smooth(duration: 0.6), value: step)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
    }

    private var footer: some View {
        // Skip (leading) and Continue (trailing) on the edges; dots absolutely
        // centered via an overlay so they don't drift with the button widths.
        HStack(spacing: 12) {
            footerButton("Skip", action: finish)
                .opacity(step < pages.count - 1 ? 1 : 0)
                .disabled(step == pages.count - 1)

            Spacer()

            // Back — only once there's a previous page to return to.
            if step > 0 {
                footerButton("Back") { step -= 1 }
                    .transition(.opacity)
            }

            footerButton(step == pages.count - 1 ? "Get Started" : "Continue", action: advance)
                .keyboardShortcut(.return, modifiers: [])
        }
        .overlay {
            HStack(spacing: 7) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? AnyShapeStyle(pages[step].accent) : AnyShapeStyle(.white.opacity(0.2)))
                        .frame(width: i == step ? 18 : 7, height: 7)
                        .animation(.snappy(duration: 0.25), value: step)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .animation(.snappy(duration: 0.25), value: step)
    }

    /// Uniform glass footer button — same width and height across the popup.
    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 96, height: 22)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private func advance() {
        if step < pages.count - 1 {
            step += 1
        } else {
            finish()
        }
    }
}

/// One onboarding page: hero icon, title, subtitle, and supporting highlights.
private struct WelcomePage {
    let icon: String
    /// Optional bundled image resource (without extension) shown instead of the SF Symbol.
    var imageResource: String? = nil
    let accent: Color
    let title: String
    let subtitle: String
    let highlights: [Highlight]

    struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    static let all: [WelcomePage] = [
        WelcomePage(
            icon: "sailboat.fill",
            imageResource: "icon",
            accent: .brand,
            title: "Welcome to Liftoff",
            subtitle: "A macOS terminal built for engineers running AI coding agents across many projects at once.",
            highlights: [
                .init(icon: "square.split.2x1", title: "Multitasking boosted", detail: "Run projects and terminals side by side — split, resize, and switch without losing flow."),
                .init(icon: "bolt.fill", title: "Hotkey & speed oriented", detail: "Keyboard-first from the ground up: everything is one shortcut away."),
                .init(icon: "lock.iphone", title: "Private remote control", detail: "Drive your terminals from iPhone or browser over your own network — nothing leaves your machines."),
                .init(icon: "shippingbox", title: "Software / agent agnostic", detail: "Claude Code, Codex, or any CLI — Liftoff stays out of the way and just works."),
            ]
        ),
        WelcomePage(
            icon: "folder.fill.badge.gearshape",
            accent: .mono,
            title: "Projects & Tags",
            subtitle: "Open folders as projects, then color-code them with tags so you always know where you are.",
            highlights: [
                .init(icon: "tag.fill", title: "Tag any project", detail: "Pick a name and color — reuse tags like Work or Personal across folders."),
                .init(icon: "rectangle.lefthalf.inset.filled", title: "Collapse & solo", detail: "Collapse projects to a thin rail, or double-click a header to focus just one."),
            ]
        ),
        WelcomePage(
            icon: "sparkles",
            accent: .mono,
            title: "AI Summary",
            subtitle: "Select any text in a terminal and let Liftoff summarize it instantly — no copy-paste, no context switch.",
            highlights: [
                .init(icon: "text.viewfinder", title: "Summarize selection", detail: "Press ⌘F to turn a wall of logs or output into a crisp summary."),
                .init(icon: "bell.badge.fill", title: "Smart notifications", detail: "Coding agents push per-project updates so you know the moment they need you."),
            ]
        ),
        WelcomePage(
            icon: "iphone.gen3.radiowaves.left.and.right",
            accent: .mono,
            title: "Liftoff Air",
            subtitle: "Take your terminals with you. Pair your iPhone or a browser and drive any session remotely.",
            highlights: [
                .init(icon: "qrcode", title: "Pair in seconds", detail: "Open Air → Connect and scan the QR code with Liftoff Air on your iPhone."),
                .init(icon: "lock.shield.fill", title: "Web access, secured", detail: "Set a passcode for the browser client — leave it empty to keep web off."),
            ]
        ),
        WelcomePage(
            icon: "keyboard",
            accent: .mono,
            title: "Shortcuts",
            subtitle: "Liftoff is keyboard-first. Here are the moves you'll reach for every day.",
            highlights: [
                .init(icon: "arrow.up.left.and.arrow.down.right", title: "⌘E  /  ⌘1–5", detail: "Expand the focused terminal, or snap its split to a width fraction."),
                .init(icon: "sparkles", title: "⌘F  —  AI summary", detail: "Summarize the selected terminal text instantly with on-device AI."),
                .init(icon: "folder.badge.plus", title: "⌘O  —  Projects", detail: "Open a new project, or jump back into a recent one."),
                .init(icon: "questionmark.circle", title: "⌘H  —  All shortcuts", detail: "Open the full hotkeys reference anytime you need a reminder."),
            ]
        ),
    ]
}

private struct WelcomePageView: View {
    let page: WelcomePage

    /// Loads a loose bundled image resource (e.g. icon.png) by name.
    static func bundledImage(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            // Hero glyph in a soft accent halo.
            ZStack {
                Circle()
                    .fill(page.accent.opacity(0.18))
                    .frame(width: 116, height: 116)
                Circle()
                    .strokeBorder(page.accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 116, height: 116)
                if let resource = page.imageResource, let nsImage = Self.bundledImage(resource) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: page.icon)
                        .font(.system(size: 46, weight: .regular))
                        .foregroundStyle(page.accent)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(page.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 12) {
                ForEach(page.highlights) { item in
                    HighlightRow(item: item, accent: page.accent)
                }
            }
            .frame(maxWidth: 460)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }
}

private struct HighlightRow: View {
    let item: WelcomePage.Highlight
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
