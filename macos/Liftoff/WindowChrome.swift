import SwiftUI

/// Strips the window chrome: no titlebar, no traffic-light buttons.
/// Close/minimize/quit stay available via the system menu bar and shortcuts.
struct WindowChromeRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hands the hosting NSWindow back to the store once it's attached, so the
/// status-bar menu can bring the right window forward.
struct WindowCapture: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { onWindow(w) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Behind-window blur so the chrome reads as a native translucent surface.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Draggable 1px divider for the custom split layout (wide invisible grab area).
struct PaneDivider: View {
    static let thickness: CGFloat = 1
    let onDrag: (CGFloat) -> Void
    var onEnded: (() -> Void)? = nil

    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: Self.thickness)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -5))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        onDrag(value.translation.width - lastTranslation)
                        lastTranslation = value.translation.width
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                        onEnded?()
                    }
            )
    }
}
