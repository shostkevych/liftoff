import SwiftUI
import SwiftTerm

/// LocalProcessTerminalView that reports clicks so the app can track focus.
final class FocusTrackingTerminalView: LocalProcessTerminalView {
    var onFocus: (() -> Void)?
    /// The window store that owns this terminal. Keyboard shortcuts and hook
    /// suggestions route here, so they hit the right window when several are open.
    weak var store: AppStore?

    func installFocusClickRecognizer() {
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleFocusClick))
        click.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(click)
    }

    @objc private func handleFocusClick() {
        onFocus?()
    }

    // MARK: Focus-follows-mouse

    private var hoverFocusArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverFocusArea { removeTrackingArea(hoverFocusArea) }
        // Track the whole visible terminal; only while this window is key so
        // moving the mouse over a background window doesn't steal focus.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        hoverFocusArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Hovering a terminal focuses it (active pane + keyboard responder).
        if window?.firstResponder !== self { onFocus?() }
    }

    // MARK: Companion mirroring — tap raw PTY output, inject input, snapshot.

    /// Fires with every chunk of raw bytes the PTY emits (after the terminal
    /// itself consumes it). Used to mirror output to the iOS companion.
    var onOutput: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        lastOutputTime = Date()
        onOutput?(slice)
    }

    // MARK: OSC 52 clipboard capture (for Summarize on mouse-reporting TUIs)

    /// The last text a TUI copied via OSC 52, plus the pasteboard changeCount at
    /// that moment. Mouse-reporting agents (opencode, grok) copy the selection
    /// themselves instead of letting the terminal select, so Summarize falls back
    /// to this — but only while it's still the top of the clipboard, so we never
    /// summarize unrelated content the user copied afterwards.
    @MainActor static var lastTerminalCopyText: String?
    @MainActor static var lastTerminalCopyChangeCount: Int = -1

    override func clipboardCopy(source: Terminal, content: Data) {
        super.clipboardCopy(source: source, content: content)   // writes NSPasteboard
        if let str = String(data: content, encoding: .utf8), !str.isEmpty {
            Self.lastTerminalCopyText = str
            Self.lastTerminalCopyChangeCount = NSPasteboard.general.changeCount
        }
    }

    // MARK: Busy (output-activity) tracking

    /// Fires on the main thread when the terminal transitions between
    /// actively-producing-output and idle.
    var onBusyChanged: ((Bool) -> Void)?
    private var lastOutputTime = Date.distantPast
    private var busyState = false
    private var busyTimer: Timer?
    /// How long after the last output we still consider the terminal busy.
    private let busyIdleWindow: TimeInterval = 0.6

    func startBusyTracking() {
        guard busyTimer == nil else { return }
        busyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let busy = Date().timeIntervalSince(self.lastOutputTime) < self.busyIdleWindow
            if busy != self.busyState {
                self.busyState = busy
                self.onBusyChanged?(busy)
            }
        }
    }

    /// Send raw bytes (keystrokes) from a remote companion to the process.
    func sendBytes(_ bytes: [UInt8]) {
        process.send(data: bytes[...])
    }

    /// Current visible buffer as plain text, for an attach-time snapshot.
    func snapshotData() -> Data {
        getTerminal().getBufferAsData()
    }

    /// Resize the PTY/grid to mirror a remote companion's dimensions.
    func applyRemoteSize(cols: Int, rows: Int) {
        guard cols > 1, rows > 1 else { return }
        forcedGridSize = (cols, rows)
    }

    /// Restore frame-based sizing when the companion detaches.
    func clearRemoteSize() {
        forcedGridSize = nil
    }

    // MARK: Foreground-process polling (agent icons, Warp-style).

    var onForegroundCommand: ((String, pid_t) -> Void)?
    private var agentPollTimer: Timer?
    /// Last foreground process group we polled. Skipping the sysctl round-trip
    /// when the pgid is unchanged keeps the foreground command stable.
    private var lastPolledPgid: pid_t = -1

    func startAgentPolling() {
        guard agentPollTimer == nil else { return }
        agentPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.process.childfd >= 0 else { return }
            let fd = self.process.childfd
            let pgid = tcgetpgrp(fd)
            guard pgid > 0 else { return }
            // Same foreground group as last poll — its command line can't have
            // changed, so skip the expensive sysctl pass entirely.
            guard pgid != self.lastPolledPgid else { return }
            self.lastPolledPgid = pgid
            // sysctl (KERN_PROC_PGRP + KERN_PROCARGS2 per process) is variable-size
            // buffer work — run it off the main thread, hop back to deliver.
            DispatchQueue.global(qos: .utility).async {
                let commandLine = Self.foregroundCommand(pgid: pgid)
                DispatchQueue.main.async {
                    self.onForegroundCommand?(commandLine, pgid)
                }
            }
        }
    }

    func stopAgentPolling() {
        agentPollTimer?.invalidate()
        agentPollTimer = nil
        lastPolledPgid = -1
    }

    /// Invalidate the busy-tracking timer so it stops firing after dispose().
    func stopBusyTracking() {
        busyTimer?.invalidate()
        busyTimer = nil
    }

    /// Combined detection signal for the whole foreground process group: each
    /// process's `comm` name (catches renamed binaries like `grok`) plus its
    /// full argv (catches `node .../codex` shebang scripts). Scanning the group
    /// also catches agents whose real work runs in a child process.
    private static func foregroundCommand(pgid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, pgid]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return "" }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return "" }
        let actual = size / MemoryLayout<kinfo_proc>.stride

        var parts: [String] = []
        for i in 0..<min(actual, procs.count) {
            let pid = procs[i].kp_proc.p_pid
            let comm = withUnsafeBytes(of: procs[i].kp_proc.p_comm) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if !comm.isEmpty { parts.append(comm) }
            let argv = commandLine(for: pid)
            if !argv.isEmpty { parts.append(argv) }
        }
        return parts.joined(separator: " ")
    }

    /// Raw argv buffer (exec path + args) of a pid via KERN_PROCARGS2 —
    /// catches script-based CLIs like `node .../claude` that comm names miss.
    private static func commandLine(for pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return "" }

        // KERN_PROCARGS2 layout: [int argc][exec_path\0][padding\0…]
        // [argv[0]\0 … argv[argc-1]\0][envp…]. We must read ONLY the exec path
        // and argv — the environment block follows and would otherwise leak vars
        // like a `codex` in PATH into every process's command string.
        let count = buffer.count
        guard count > MemoryLayout<Int32>.size else { return "" }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size

        func readString() -> String {
            let start = offset
            while offset < count && buffer[offset] != 0 { offset += 1 }
            let str = String(decoding: buffer[start..<offset], as: UTF8.self)
            while offset < count && buffer[offset] == 0 { offset += 1 } // skip null(s)
            return str
        }

        var parts: [String] = []
        let execPath = readString()
        if !execPath.isEmpty { parts.append(execPath) }
        var read: Int32 = 0
        while read < argc && offset < count {
            let arg = readString()
            if !arg.isEmpty { parts.append(arg) }
            read += 1
        }
        return parts.joined(separator: " ")
    }

    /// The config-dir env var of a running agent session in this process group,
    /// if set — agents inherit it into their children, so we read it from
    /// whichever process exposes it. Resolves which config folder the session
    /// actually uses (nil = the agent's default). Generic over the env-key so
    /// both Claude (`CLAUDE_CONFIG_DIR`) and opencode (`OPENCODE_CONFIG_DIR`)
    /// share the same sysctl walk.
    static func configDir(pgid: pid_t, envKey: String) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, pgid]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return nil }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return nil }
        let actual = size / MemoryLayout<kinfo_proc>.stride
        for i in 0..<min(actual, procs.count) {
            if let dir = envValue(for: procs[i].kp_proc.p_pid, key: envKey),
               !dir.isEmpty {
                return dir
            }
        }
        return nil
    }

    /// Read a single environment variable of a pid via KERN_PROCARGS2. The env
    /// block follows the argv block in the same buffer, so we skip argv first.
    private static func envValue(for pid: pid_t, key: String) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let count = buffer.count
        guard count > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size

        func readString() -> String {
            let start = offset
            while offset < count && buffer[offset] != 0 { offset += 1 }
            let str = String(decoding: buffer[start..<offset], as: UTF8.self)
            while offset < count && buffer[offset] == 0 { offset += 1 }
            return str
        }

        _ = readString()                 // exec path
        var read: Int32 = 0
        while read < argc && offset < count { _ = readString(); read += 1 }

        let prefix = key + "="
        while offset < count {
            let entry = readString()     // remaining strings are env KEY=VALUE
            if entry.hasPrefix(prefix) { return String(entry.dropFirst(prefix.count)) }
        }
        return nil
    }

    /// Hide SwiftTerm's scroller UI; scrolling itself keeps working.
    func hideScrollers() {
        for case let scroller as NSScroller in subviews {
            scroller.isHidden = true
        }
    }

    override func layout() {
        super.layout()
        hideScrollers()
    }

    // MARK: Right-click context menu (Copy / Paste / Select All).

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hasSelection = (getSelection()?.isEmpty == false)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(contextCopy), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(contextPaste), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(contextSelectAll), keyEquivalent: "")
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        let summarizeItem = NSMenuItem(title: "Summarize Selection", action: #selector(contextSummarize), keyEquivalent: "")
        summarizeItem.target = self
        summarizeItem.isEnabled = hasSelection
        menu.addItem(summarizeItem)

        return menu
    }

    @objc private func contextCopy() { copy(self) }
    @objc private func contextPaste() { paste(self) }
    @objc private func contextSelectAll() { selectAll(self) }
    @objc private func contextSummarize() { store?.summarizeSelection(text: getSelection()) }

    // MARK: Drag & drop of files — pastes shell-escaped paths.

    func enableFileDrop() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return false }
        let escaped = urls.map { shellEscape($0.path) }.joined(separator: " ")
        // Deliver as a bracketed paste when the app enabled it (Claude Code
        // then treats image paths as attachments, e.g. "[Image #1]").
        if getTerminal().bracketedPasteMode {
            send(txt: "\u{1b}[200~" + escaped + "\u{1b}[201~")
        } else {
            send(txt: escaped + " ")
        }
        window?.makeFirstResponder(self)
        onFocus?()
        return true
    }

    // MARK: Standard editing keystrokes (Warp/iTerm conventions).
    // SwiftTerm's keyDown isn't open, so a local event monitor intercepts first.

    @MainActor private static var keyMonitorInstalled = false
    /// App-level shortcuts (Cmd+E, Cmd+1...5) are dispatched here instead of via
    /// SwiftUI .commands, because the system Edit/Window menus claim those key
    /// equivalents first (Cmd+E = "Use Selection for Find", Cmd+1/2 = window tabs).
    /// A local key monitor sees the event before any menu, so it always wins.
    /// The monitor resolves the focused terminal's own `store`, so shortcuts hit
    /// whichever window is frontmost.
    @MainActor
    static func installKeyboardShortcuts() {
        guard !keyMonitorInstalled else { return }
        keyMonitorInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌘⇧+1…9 quick-switches projects on the frontmost window. Handled
            // before (and independent of) terminal focus so it works anywhere.
            if handleProjectQuickSwitch(event) { return nil }
            guard let terminal = event.window?.firstResponder as? FocusTrackingTerminalView else {
                return event
            }
            return terminal.handleShortcut(event) ? nil : event
        }
        // Holding ⌘⇧ shows the numbered project-switcher HUD; releasing hides it.
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let store = AppStore.shared {
                store.projectSwitcherVisible = flags == [.command, .shift] && !store.projects.isEmpty
            }
            return event
        }
    }

    /// ⌘⇧+1…9 → switch the frontmost window to that project. Returns true when
    /// the event was a quick-switch chord (so the monitor swallows it).
    @MainActor
    private static func handleProjectQuickSwitch(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift]
        else { return false }
        // Top-row digit keycodes 1…9 (0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19).
        let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard let index = digits.firstIndex(of: event.keyCode), let store = AppStore.shared
        else { return false }
        store.quickSwitch(toIndex: index)
        return true
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Clipboard (handled here so it works without a focused Edit menu).
        // Ctrl+C still reaches the shell as SIGINT — only Cmd+C copies.
        if flags == .command {
            switch event.keyCode {
            case 8: // C -> copy selection (no-op passthrough when nothing selected)
                if let sel = getSelection(), !sel.isEmpty { copy(self); return true }
                return false
            case 9: // V -> paste
                paste(self); return true
            case 0: // A -> select all
                selectAll(self); return true
            default:
                break
            }
        }

        // App-level layout shortcuts (handled here to beat the system menus).
        // These mirror the terminal pane's right-click context menu.
        if flags == [.command, .shift], let store = self.store {
            switch event.keyCode {
            case 2: // Shift+D -> new full (non-split) tab
                store.newTerminalInActiveProject(); return true
            default:
                break
            }
        }

        if flags == .command, let store = self.store {
            switch event.keyCode {
            case 17: // T -> new terminal
                store.newTerminalInActiveProject(); return true
            case 2: // D -> split the focused terminal side by side
                store.splitActiveTerminal(); return true
            case 14: // E -> expand focused split terminal
                store.toggleExpandActiveTerminal(); return true
            case 3: // F -> summarize selection (capture it now, before focus shifts)
                store.summarizeSelection(text: getSelection()); return true
            case 24: // = -> zoom in
                store.zoomTerminals(by: 1); return true
            case 27: // - -> zoom out
                store.zoomTerminals(by: -1); return true
            case 31: // O -> open project
                store.requestNewProject(); return true
            case 11: // B -> toggle project sidebar
                store.toggleSidebar(); return true
            case 13: // W -> close terminal
                store.closeActiveTerminal(); return true
            case 15: // R -> rename tab (custom name pins the title)
                store.renameActiveTerminal(); return true
            case 18, 19, 20, 21, 23: // 1 2 3 4 5 -> terminal split width n/(n+1)
                let map: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5]
                if let n = map[event.keyCode] { store.setActiveTerminalFraction(numerator: n) }
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 36 where flags.contains(.shift): // Shift+Enter -> newline (meta+CR, used by Claude Code etc.)
            send(txt: "\u{1b}\r")
            return true
        case 123: // Left arrow
            if flags.contains(.option) { send(txt: "\u{1b}b"); return true }   // word back
            if flags == .command { send(txt: "\u{01}"); return true }          // line start (^A)
        case 124: // Right arrow
            if flags.contains(.option) { send(txt: "\u{1b}f"); return true }   // word forward
            if flags == .command { send(txt: "\u{05}"); return true }          // line end (^E)
        case 51: // Backspace
            if flags == .command { send(txt: "\u{15}"); return true }          // clear line (^U)
            if flags.contains(.option) { send(txt: "\u{1b}\u{7f}"); return true } // delete word back
        default:
            break
        }
        return false
    }

    /// Save an image dropped from a remote (web) client to a temp file and
    /// paste its path, mirroring the local file-drop behaviour so Claude Code
    /// treats it as an attachment.
    func pasteUploadedImage(_ data: Data, name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Liftoff-uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + "-" + safeName)
        guard (try? data.write(to: url)) != nil else { return }
        let escaped = shellEscape(url.path)
        if getTerminal().bracketedPasteMode {
            send(txt: "\u{1b}[200~" + escaped + "\u{1b}[201~")
        } else {
            send(txt: escaped + " ")
        }
    }

    private func shellEscape(_ path: String) -> String {
        // Only quote when needed; single-quote with embedded-quote handling.
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./~")
        if path.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Wraps SwiftTerm's LocalProcessTerminalView and keeps one live NSView
/// per session so the shell survives SwiftUI view updates.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    var isActive = true
    /// The window store that owns this terminal (declared before `onFocus` so the
    /// trailing-closure `onFocus` stays the last memberwise-init parameter).
    var store: AppStore? = nil
    var onFocus: (() -> Void)? = nil

    @MainActor
    static var cache: [UUID: FocusTrackingTerminalView] = [:]

    @MainActor
    static var fontSize: CGFloat = 13

    /// Cmd+= / Cmd+-: apply a new font size to every live terminal.
    @MainActor
    static func applyFontSize(_ size: CGFloat) {
        fontSize = size
        for view in cache.values {
            view.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    func makeNSView(context: Context) -> FocusTrackingTerminalView {
        if let existing = Self.cache[session.id] {
            existing.onFocus = onFocus
            return existing
        }
        let view = FocusTrackingTerminalView(frame: .zero)
        view.onFocus = onFocus
        view.store = store
        view.installFocusClickRecognizer()
        view.enableFileDrop()
        let session = self.session
        view.onForegroundCommand = { [weak owner = store] commandLine, pgid in
            let agent = Agent.detect(in: commandLine)
            if session.runningAgent != agent {
                session.runningAgent = agent
                if agent == .claude {
                    // Target the exact ~/.claude* folder this session uses, on
                    // the window that owns this terminal.
                    let dir = FocusTrackingTerminalView.configDir(pgid: pgid, envKey: "CLAUDE_CONFIG_DIR")
                        .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                        ?? HookSetup.defaultConfigDir
                    owner?.maybeSuggestHookSetup(agent: .claude, configDir: dir)
                } else if agent == .opencode {
                    let dir = FocusTrackingTerminalView.configDir(pgid: pgid, envKey: "OPENCODE_CONFIG_DIR")
                        .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                        ?? OpenCodeHookSetup.defaultConfigDir
                    owner?.maybeSuggestHookSetup(agent: .opencode, configDir: dir)
                }
            }
        }
        view.onBusyChanged = { busy in
            guard session.isBusy != busy else { return }
            session.isBusy = busy
            CompanionServer.shared.terminalActivityChanged()
        }
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: Self.fontSize, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        view.selectedTextBackgroundColor = NSColor.white

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")
        env.append("LIFTOFF=1")
        env.append("TERM_PROGRAM=Liftoff")
        // Lets our Claude UserPromptSubmit hook route the work title back to
        // exactly this terminal session (see HookSetup / NotificationServer).
        env.append("LIFTOFF_SESSION_ID=\(session.id.uuidString)")

        FileManager.default.changeCurrentDirectoryPath(session.workingDirectory.path)
        view.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: nil
        )
        view.startAgentPolling()
        view.startBusyTracking()
        Self.cache[session.id] = view
        return view
    }

    func updateNSView(_ nsView: FocusTrackingTerminalView, context: Context) {
        nsView.onFocus = onFocus
        nsView.nativeBackgroundColor = .black
        // Only hand keyboard focus to this terminal when it *becomes* active.
        // updateNSView fires on every SwiftUI update that touches the owning
        // view (tag prompts, overlay toggles, store changes); refocusing each
        // time would fight the user and steal focus from popups/text fields.
        if isActive && !context.coordinator.wasActive {
            DispatchQueue.main.async {
                guard let window = nsView.window, window.firstResponder !== nsView else { return }
                window.makeFirstResponder(nsView)
            }
        }
        context.coordinator.wasActive = isActive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    static func dispose(_ session: TerminalSession) {
        if let view = cache.removeValue(forKey: session.id) {
            view.stopAgentPolling()
            view.stopBusyTracking()
            view.process.terminate()
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let session: TerminalSession
        /// Tracks the previous `isActive` value so updateNSView only refocuses
        /// on a false→true transition instead of every SwiftUI update.
        var wasActive = false

        init(session: TerminalSession) {
            self.session = session
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                self.session.title = title.isEmpty ? "zsh" : title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
