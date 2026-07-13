import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A borderless overlay window that can still take keyboard focus. Terminal
/// input needs a key window, but `.borderless` windows refuse key status by
/// default — this subclass opts back in.
final class KeyableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Cmd+I "instant terminal": a compact, borderless, movable shell at `~` that
/// floats above whatever app is frontmost. The hotkey is registered system-wide
/// (Carbon), so it works even when Liftoff isn't the active app. Each summon
/// spawns a fresh shell. Because it stays floating (no auto-hide on focus loss),
/// you can click into another app, copy something, click back, and paste.
/// Cmd+I again dismisses it and kills that shell; Esc passes through to the
/// shell as normal.
@MainActor
final class InstantTerminalController: NSObject {
    static let shared = InstantTerminalController()

    private var hotKeyRef: EventHotKeyRef?
    private var window: KeyableOverlayWindow?
    private var session: TerminalSession?

    /// The visible panel. The window itself is larger by `margin` on every side
    /// so the drop shadow has transparent room to render.
    private let panelSize = CGSize(width: 950, height: 575)
    /// Transparent border around the panel — the only region that drags the
    /// window (the terminal keeps the mouse for selection).
    private let margin: CGFloat = 22

    // MARK: Global hotkey

    /// Register ⌘I as a system-wide hotkey. Safe to call once at launch.
    func registerHotKey() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { InstantTerminalController.shared.toggle() }
            return noErr
        }, 1, &eventType, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4C494654 /* 'LIFT' */), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_I), UInt32(cmdKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: Show / hide

    func toggle() { window == nil ? show() : hide() }

    private func show() {
        guard window == nil else { return }

        // The screen currently under the mouse cursor.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let session = TerminalSession(title: "zsh", workingDirectory: Self.homeDirectory)
        self.session = session

        let content = InstantTerminalContent(session: session, panelSize: panelSize)

        let windowSize = CGSize(width: panelSize.width + margin * 2,
                                height: panelSize.height + margin * 2)
        let origin = CGPoint(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.midY - windowSize.height / 2
        )
        let window = KeyableOverlayWindow(
            contentRect: CGRect(origin: origin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true // native window shadow, hugs the rounded panel
        window.level = .floating
        window.isMovable = true
        // Dragging is driven per-view by `mouseDownCanMoveWindow` (see the drag
        // handle behind the panel), so the terminal keeps the mouse for text
        // selection while the surrounding border moves the window.
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: content)

        // Come forward and take keyboard focus even over another app.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.invalidateShadow() // recompute shadow against the rounded content

        self.window = window
        // Focus the terminal immediately so the user can type without clicking.
        // The hosted view is created during layout, so retry until it exists.
        focusTerminal(session, in: window, attempt: 0)
    }

    /// Make the freshly-created terminal the window's first responder. The view
    /// isn't in the cache until SwiftUI lays the hosting view out, so retry a
    /// handful of runloop turns before giving up.
    private func focusTerminal(_ session: TerminalSession, in window: NSWindow, attempt: Int) {
        guard self.window === window else { return } // dismissed already
        if let view = TerminalHostView.cache[session.id] {
            window.makeFirstResponder(view)
            return
        }
        guard attempt < 20 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.focusTerminal(session, in: window, attempt: attempt + 1)
        }
    }

    private func hide() {
        if let session { TerminalHostView.dispose(session); self.session = nil }
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    private static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}

/// The overlay contents: a compact, borderless, rounded terminal panel at `~`
/// with the native window shadow. A full-bleed drag handle sits behind the
/// panel so the transparent border (and the black inset) move the window, while
/// the terminal view itself keeps the mouse for text selection.
private struct InstantTerminalContent: View {
    let session: TerminalSession
    let panelSize: CGSize

    var body: some View {
        ZStack {
            Color.clear
            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panel: some View {
        ZStack {
            Color.black
            TerminalHostView(session: session, isActive: true, store: nil)
                .padding(12)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            // A real AppKit view — a SwiftUI overlay would be composited *below*
            // the terminal's hosted NSView and stay invisible.
            WindowDragHandle()
                .frame(width: 32, height: 24)
                .padding(10)
                .help("Drag to move")
        }
    }
}

/// A self-drawing AppKit grip that drags the containing borderless window.
/// Rendered as an NSView (with its own visuals) so it sits above the terminal's
/// hosted view; `performDrag` hands the move off to the window server.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class GripView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.cornerRadius = 7

            let symbol = NSImage(
                systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
                accessibilityDescription: "Drag to move"
            )
            let image = NSImageView(image: symbol ?? NSImage())
            image.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
            image.contentTintColor = NSColor.white.withAlphaComponent(0.6)
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
            NSLayoutConstraint.activate([
                image.centerXAnchor.constraint(equalTo: centerXAnchor),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
