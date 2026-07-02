import SwiftUI
import SwiftTerm

/// Renders a streamed Liftoff terminal with a real SwiftTerm emulator at a
/// readable font. The phone drives the size: it reports its own cols/rows to
/// the Mac, which resizes that PTY so TUIs (Claude Code) re-render 1:1 and
/// readable. The Mac pane reflows to match while attached.
///
/// SwiftTerm's stock input accessory and full-screen alternate keyboard are
/// suppressed. Instead every special key lives in one slim, horizontally
/// scrollable bar pinned to the bottom. The soft (letter) keyboard is dropped
/// the moment a line is sent (Return) to maximize terminal space, and the
/// bar's ⌨ button toggles it back.
struct TerminalScreen: View {
    let client: CompanionClient
    let session: CompanionClient.Session
    @StateObject private var bridge = TerminalBridge()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                TerminalSurface(client: client, session: session, bridge: bridge)
                KeyBar(bridge: bridge, bottomInset: geo.safeAreaInsets.bottom)
            }
        }
        .background(Color.black)
    }
}

/// Channel between the SwiftUI key bar and the live `TerminalView`.
final class TerminalBridge: ObservableObject {
    weak var view: SwiftTerm.TerminalView?
    @Published var keyboardUp: Bool = true

    func send(_ bytes: [UInt8]) { view?.send(bytes) }
    func up()    { view?.sendKeyUp() }
    func down()  { view?.sendKeyDown() }
    func left()  { view?.sendKeyLeft() }
    func right() { view?.sendKeyRight() }

    func showKeyboard() {
        guard let view else { return }
        keyboardUp = true
        _ = view.becomeFirstResponder()
    }

    func toggleKeyboard() {
        guard let view else { return }
        if keyboardUp {
            keyboardUp = false
            _ = view.resignFirstResponder()
        } else {
            keyboardUp = true
            _ = view.becomeFirstResponder()
        }
    }
}

private struct TerminalSurface: UIViewRepresentable {
    let client: CompanionClient
    let session: CompanionClient.Session
    let bridge: TerminalBridge

    func makeCoordinator() -> Coordinator { Coordinator(client: client, bridge: bridge) }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let view = SwiftTerm.TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .init(white: 0.92, alpha: 1)
        view.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        // Drop SwiftTerm's own accessory + alternate keyboard; our KeyBar replaces them.
        view.inputAccessoryView = nil

        bridge.view = view
        client.onBytes = { [weak view] data in
            view?.feed(byteArray: [UInt8](data)[...])
        }
        client.attach(session)

        DispatchQueue.main.async {
            _ = view.becomeFirstResponder()
            bridge.keyboardUp = true
        }
        return view
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {}

    /// Navigating away — detach so the Mac restores its size.
    static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.client.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let client: CompanionClient
        let bridge: TerminalBridge
        init(client: CompanionClient, bridge: TerminalBridge) {
            self.client = client
            self.bridge = bridge
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated { client.sendResize(cols: newCols, rows: newRows) }
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Data(data)
            MainActor.assumeIsolated {
                client.sendInput(bytes)
                // On Return, drop the soft keyboard to give the terminal the whole screen.
                if data.contains(0x0d) || data.contains(0x0a) {
                    _ = source.resignFirstResponder()
                    bridge.keyboardUp = false
                }
            }
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        func bell(source: SwiftTerm.TerminalView) {}
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}

/// One slim, horizontally scrollable bar holding every special key, with a
/// pinned ⌨ toggle for the soft letter keyboard.
private struct KeyBar: View {
    @ObservedObject var bridge: TerminalBridge
    let bottomInset: CGFloat

    /// Collapsed = soft keyboard hidden. The bar gets the screen to itself, so
    /// make the keys a touch larger and easier to hit.
    private var expanded: Bool { !bridge.keyboardUp }
    private var rowHeight: CGFloat { expanded ? 46 : 30 }
    private var keyFont: CGFloat { expanded ? 14 : 12 }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    txt("esc") { bridge.send([0x1b]) }
                    txt("tab") { bridge.send([0x09]) }
                    txt("⌃C")  { bridge.send([0x03]) }
                    txt("⌃D")  { bridge.send([0x04]) }
                    txt("⌃Z")  { bridge.send([0x1a]) }

                    sep()
                    sym("chevron.left")  { bridge.left() }
                    sym("chevron.down")  { bridge.down() }
                    sym("chevron.up")    { bridge.up() }
                    sym("chevron.right") { bridge.right() }

                    sep()
                    ForEach(1...10, id: \.self) { n in
                        txt("F\(n)") { bridge.send(EscapeSequences.cmdF[n - 1]) }
                    }

                    sep()
                    ForEach(Array("~|/-+*=%`\\[]{}<>&"), id: \.self) { ch in
                        txt(String(ch)) { bridge.send([UInt8(ch.asciiValue ?? 0)]) }
                    }

                    sep()
                    txt("ins")  { bridge.send(EscapeSequences.cmdInsert) }
                    txt("home") { bridge.send(EscapeSequences.moveHomeNormal) }
                    txt("end")  { bridge.send(EscapeSequences.moveEndNormal) }
                    txt("pgup") { bridge.send(EscapeSequences.cmdPageUp) }
                    txt("pgdn") { bridge.send(EscapeSequences.cmdPageDown) }
                    sym("delete.left") { bridge.send(EscapeSequences.cmdDelKey) }
                }
                .padding(.horizontal, 8)
            }

            // Pinned keyboard toggle.
            Button { bridge.toggleKeyboard() } label: {
                Image(systemName: bridge.keyboardUp ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: expanded ? 16 : 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 44, height: rowHeight)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .padding(.leading, 4)
        }
        .frame(height: rowHeight + 8)
        .padding(.bottom, expanded ? bottomInset : 0)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.10)), alignment: .top)
        .animation(.easeOut(duration: 0.15), value: expanded)
    }

    private func txt(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: keyFont, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
                .padding(.horizontal, expanded ? 12 : 9)
                .frame(minWidth: expanded ? 38 : 30, minHeight: rowHeight)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func sym(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: expanded ? 15 : 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .frame(width: expanded ? 38 : 30, height: rowHeight)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func sep() -> some View {
        Rectangle()
            .frame(width: 0.5, height: 20)
            .foregroundColor(.white.opacity(0.14))
            .padding(.horizontal, 2)
    }
}
