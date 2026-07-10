import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.projects.isEmpty && store.placeholderPanes.isEmpty {
                ProjectPicker(onOpen: { urls in
                    urls.forEach { store.addProject(folder: $0) }
                }, onTerminal: {
                    store.addProject(folder: URL(fileURLWithPath: NSHomeDirectory()))
                })
            } else {
                splitLayout
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(VisualEffectBackground().ignoresSafeArea())
        .background(WindowChromeRemover())
        .background(WindowCapture { store.hostWindow = $0 })
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            if let state = store.summaryState {
                ZStack(alignment: .top) {
                    PopupBackdrop { store.dismissSummary() }
                    SummaryPopup(state: state) { store.dismissSummary() }
                        .padding(.top, 48)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .overlay {
            if let terminal = store.renamingTerminal {
                ZStack {
                    PopupBackdrop { store.renamingTerminal = nil }
                    RenameTerminalPopup(terminal: terminal) { store.renamingTerminal = nil }
                        .id(terminal.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.helpVisible {
                ZStack {
                    PopupBackdrop { store.helpVisible = false }
                    HelpPopup { store.helpVisible = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.airConnectVisible {
                ZStack {
                    PopupBackdrop { store.airConnectVisible = false }
                    AirConnectPopup { store.airConnectVisible = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.webPasswordVisible {
                ZStack {
                    PopupBackdrop { store.webPasswordVisible = false }
                    WebPasswordPopup { store.webPasswordVisible = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.cerebrasKeyVisible {
                ZStack {
                    PopupBackdrop { store.cerebrasKeyVisible = false }
                    CerebrasKeyPopup { store.cerebrasKeyVisible = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if let folder = store.tagPromptFolder {
                ZStack {
                    // Skip (store color-only tag) when dismissing the backdrop.
                    PopupBackdrop {
                        store.resolveTagPrompt(ProjectTag(label: "", colorHex: TagPalette.first), for: folder)
                    }
                    ProjectTagPopup(folder: folder) {}
                        .id(folder.path)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if let dir = store.hookSetupDir {
                ZStack {
                    PopupBackdrop { store.declineHookSetup() }
                    HookSetupPopup(agent: store.hookSetupAgent ?? .claude, configDir: dir)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.newProjectVisible {
                ZStack(alignment: .topTrailing) {
                    ProjectPicker(onOpen: { urls in
                        urls.forEach { store.addProject(folder: $0) }
                        store.newProjectVisible = false
                    }, onTerminal: {
                        store.addProject(folder: URL(fileURLWithPath: NSHomeDirectory()))
                        store.newProjectVisible = false
                    })
                    Button { store.newProjectVisible = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if store.aboutVisible {
                ZStack {
                    PopupBackdrop { store.aboutVisible = false }
                    AboutPopup { store.aboutVisible = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.welcomeVisible {
                ZStack {
                    PopupBackdrop {}
                        .allowsHitTesting(true)
                    WelcomeGuide { store.finishWelcome() }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.whatsNewVisible {
                ZStack {
                    PopupBackdrop { store.whatsNewVisible = false }
                    WhatsNewPopup(notes: store.whatsNewNotes) { store.whatsNewVisible = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .overlay {
            if store.projectSwitcherVisible {
                ProjectSwitcherOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: store.summaryState == nil)
        .animation(.smooth(duration: 0.3), value: store.welcomeVisible)
        .animation(.snappy(duration: 0.2), value: store.helpVisible)
        .animation(.snappy(duration: 0.2), value: store.airConnectVisible)
        .animation(.snappy(duration: 0.2), value: store.webPasswordVisible)
        .animation(.snappy(duration: 0.2), value: store.cerebrasKeyVisible)
        .animation(.snappy(duration: 0.2), value: store.newProjectVisible)
        .animation(.snappy(duration: 0.2), value: store.aboutVisible)
        .animation(.snappy(duration: 0.2), value: store.tagPromptFolder)
        .animation(.snappy(duration: 0.2), value: store.hookSetupDir)
        .animation(.snappy(duration: 0.15), value: store.projectSwitcherVisible)
    }

    private var splitLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            if store.sidebarCollapsed {
                SidebarRail()
                Divider()
            } else {
                ProjectSidebar()
                PaneDivider(onDrag: { delta in store.resizeSidebar(by: delta) },
                            onEnded: { store.commitSidebarWidth() })
            }
            expandedSplit
        }
    }

    private var expandedSplit: some View {
        GeometryReader { geo in
            let ids = store.paneIDs
            // Cmd+E can blow the focused project to the full window. Hidden siblings
            // keep their real width as *content* (so their terminals don't reflow to
            // the minimum and SIGWINCH-scramble running TUIs) while their layout
            // *slot* collapses to zero — no remount, no flicker.
            let expandedID = store.expandedProjectID.flatMap { ids.contains($0) ? $0 : nil }
            let normalTotal = geo.size.width - CGFloat(max(0, ids.count - 1)) * PaneDivider.thickness
            let normalWidths = store.paneWidths(ids: ids, total: max(normalTotal, 0))
            let fullWidth = max(geo.size.width, 0)
            HStack(spacing: 0) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if index > 0 && expandedID == nil {
                        PaneDivider { delta in
                            store.dragDivider(ids: ids, index: index - 1, deltaPoints: delta, totalWidth: normalTotal)
                        }
                    }
                    let layoutWidth = expandedID == nil ? normalWidths[index] : (id == expandedID ? fullWidth : 0)
                    let contentWidth = expandedID == nil ? normalWidths[index] : (id == expandedID ? fullWidth : normalWidths[index])
                    Group {
                        if let project = store.projects.first(where: { $0.id == id }) {
                            ProjectPane(project: project)
                        } else {
                            PlaceholderPane(id: id)
                        }
                    }
                    .frame(width: contentWidth)
                    .frame(width: layoutWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .opacity(layoutWidth > 0 ? 1 : 0)
                }
            }
        }
    }
}

/// Left sidebar listing every open project. A plain click shows only that
/// project; Cmd+click toggles it into the side-by-side multi-selection.
struct ProjectSidebar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.projects) { project in
                        ProjectSidebarRow(project: project)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(width: store.paneLayout.sidebarWidth)
        .background(SidebarBackground())
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Projects")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button { store.requestNewProject() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Open Project (⌘O)")
            Button { store.toggleSidebar() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("b", modifiers: .command)
            .help("Collapse Sidebar (⌘B)")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

/// One project row in the sidebar.
struct ProjectSidebarRow: View {
    @Environment(AppStore.self) private var store
    let project: Project

    @State private var hovering = false

    private var color: Color { store.tagColor(for: project.folder) ?? .secondary }
    private var isSelected: Bool { store.selectedProjectIDs.contains(project.id) }
    private var isBusy: Bool { project.terminals.contains { $0.isBusy } }
    private var isPinned: Bool { store.isPinned(project) }
    private var tabCount: Int { project.terminals.count }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(tabCount) tab\(tabCount == 1 ? "" : "s") open")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Trailing cluster, vertically centered: tag, then busy/pin.
            if let tag = store.tag(for: project), tag.hasLabel {
                Text(tag.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.45)))
                    .layoutPriority(1)
            }
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .tint(color)
            }
            // Pin indicator: shown only when pinned. Pin/unpin is via right-click.
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(45))
                    .frame(width: 16, height: 16)
                    .help("Pinned — reopens on launch")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? AnyShapeStyle(.quaternary)
                      : (hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear)))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                store.toggleSelection(project)
            } else {
                store.selectOnly(project)
            }
        }
        .onHover { hovering = $0 }
        .help(project.folder.path)
        .contextMenu {
            Button(isPinned ? "Unpin Project" : "Pin Project") { store.togglePin(project) }
            Divider()
            Button(store.tag(for: project) == nil ? "Add Tag…" : "Edit Tag…") {
                store.enqueueTagPrompt(project.folder)
            }
            if store.tag(for: project) != nil {
                Button("Remove Tag") { store.setTag(nil, for: project.folder) }
            }
            Divider()
            Button("Close Project") {
                project.terminals.forEach { TerminalHostView.dispose($0) }
                store.closeProject(project)
            }
        }
    }
}

/// The sidebar collapsed to a thin vertical rail: an expand chevron plus a
/// color dot per project. Clicking a dot selects that project and re-expands.
struct SidebarRail: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            Button { store.toggleSidebar() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("b", modifiers: .command)
            .help("Expand Sidebar (⌘B)")
            Divider().frame(width: 18)
            ForEach(store.projects) { project in
                SidebarRailDot(project: project)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .frame(width: 36)
        .background(SidebarBackground())
    }
}

/// Native muted glass for the sidebar: a behind-window blur tinted with black
/// at 80% opacity, so the desktop shows through faintly through the blur.
struct SidebarBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color.black.opacity(0.5)
        }
        .ignoresSafeArea()
    }
}

struct SidebarRailDot: View {
    @Environment(AppStore.self) private var store
    let project: Project

    @State private var hovering = false

    private var color: Color { store.tagColor(for: project.folder) ?? .secondary }
    private var isSelected: Bool { store.selectedProjectIDs.contains(project.id) }

    var body: some View {
        Circle()
            .fill(color.opacity(isSelected ? 1 : (hovering ? 0.7 : 0.4)))
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.5 : 0), lineWidth: 1.5))
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) {
                    store.toggleSelection(project)
                } else {
                    store.selectOnly(project)
                    store.sidebarCollapsed = false
                }
            }
            .onHover { hovering = $0 }
            .help(project.name)
    }
}

struct ProjectPane: View {
    @Environment(AppStore.self) private var store
    @Bindable var project: Project

    private var isFocused: Bool { store.activeProjectID == project.id }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            tabBar
            Divider()
            terminalSurface
        }
        .contentShape(Rectangle())
        // Simultaneous (not exclusive) so tab/header taps fire instantly instead
        // of waiting out the header's double-tap (solo) disambiguation timeout.
        .simultaneousGesture(TapGesture().onEnded {
            store.activeProjectID = project.id
            store.activePlaceholderID = nil
            store.activate()
        })
    }

    // Native title row: like a window titlebar section per pane.
    private var paneHeader: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(store.tagColor(for: project.folder) ?? .secondary)
                .frame(width: 3, height: 14)
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .lineLimit(1)
            if let tag = store.tag(for: project), tag.hasLabel {
                Text(tag.label)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(.black.opacity(0.35)))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            ZStack {
                Rectangle().fill(.bar)
                (store.tagColor(for: project.folder) ?? .clear)
                    .opacity(isFocused ? 0.5 : 0.3)
            }
        }
        .contentShape(Rectangle())
        // Double-click the header: with several projects shown, collapse to just
        // this one; with a single project, zoom the window to fill the screen.
        .onTapGesture(count: 2) {
            if store.selectedProjectIDs.count > 1 {
                store.selectOnly(project)
            } else {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .help(store.selectedProjectIDs.count > 1 ? "Double-click to show only this project" : "Double-click to fill the screen")
        .contextMenu { headerContextMenu }
    }

    @ViewBuilder
    private var headerContextMenu: some View {
        Button(store.tag(for: project) == nil ? "Add Tag…" : "Edit Tag…") {
            store.enqueueTagPrompt(project.folder)
        }
        if store.tag(for: project) != nil {
            Button("Remove Tag") {
                store.setTag(nil, for: project.folder)
            }
        }
        Divider()
        Button("Close Project") {
            project.terminals.forEach { TerminalHostView.dispose($0) }
            store.closeProject(project)
        }
    }

    // Native Safari/Xcode-style flat tab bar.
    private var tabBar: some View {
        HStack(spacing: 1) {
            ForEach(project.terminals) { terminal in
                NativeTab(
                    title: terminal.displayTitle,
                    agent: terminal.runningAgent,
                    isBusy: terminal.isBusy,
                    isActive: terminal.id == project.activeTerminalID,
                    select: {
                        project.select(terminal)
                        store.activeProjectID = project.id
                    },
                    close: {
                        TerminalHostView.dispose(terminal)
                        project.closeTerminal(terminal)
                        if project.terminals.isEmpty {
                            store.closeProject(project)
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                .contextMenu {
                    Button("Rename Tab…") {
                        focusTerminal(terminal)
                        store.renamingTerminal = terminal
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    if terminal.customTitle != nil {
                        Button("Use Automatic Title") { terminal.customTitle = nil }
                    }
                    Divider()
                    Button("Close Terminal") {
                        TerminalHostView.dispose(terminal)
                        project.closeTerminal(terminal)
                        if project.terminals.isEmpty {
                            store.closeProject(project)
                        }
                    }
                }
            }
            Button {
                project.addTerminal()
                store.activeProjectID = project.id
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("New Terminal")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black)
    }

    private var terminalSurface: some View {
        Group {
            if !project.visibleTerminals.isEmpty {
                GeometryReader { geo in
                    let ids = project.visibleTerminalIDs
                    // Cmd+E expands the focused terminal. Hidden siblings keep their
                    // real width as *content* (so their PTYs don't reflow to the
                    // minimum) while their layout *slot* collapses to zero — no
                    // remount, no SIGWINCH churn, no flicker; dividers hide.
                    let expanded = project.expandedTerminalID.flatMap { ids.contains($0) ? $0 : nil }
                    let normalTotal = geo.size.width - CGFloat(max(0, ids.count - 1)) * PaneDivider.thickness
                    let normalWidths = store.terminalWidths(project, ids: ids, total: max(normalTotal, 0))
                    let fullWidth = max(geo.size.width, 0)
                    HStack(spacing: 0) {
                        ForEach(Array(ids.enumerated()), id: \.element) { index, tid in
                            if index > 0 && expanded == nil {
                                PaneDivider { delta in
                                    store.dragTerminalDivider(project, ids: ids, index: index - 1, deltaPoints: delta, totalWidth: normalTotal)
                                }
                            }
                            if let terminal = project.terminals.first(where: { $0.id == tid }) {
                                let layoutWidth = expanded == nil ? normalWidths[index] : (tid == expanded ? fullWidth : 0)
                                let contentWidth = expanded == nil ? normalWidths[index] : (tid == expanded ? fullWidth : normalWidths[index])
                                terminalCell(terminal)
                                    .padding(6)
                                    .background(Color.black)
                                    // Remote-control cover sits outside the cell padding so it
                                    // blankets the whole pane edge to edge — no black gaps.
                                    .overlay {
                                        if let kind = store.remoteControllers[terminal.id] {
                                            RemoteControlOverlay(kind: kind) {
                                                store.disconnectCompanion(from: terminal.id)
                                            }
                                        }
                                    }
                                    .frame(width: contentWidth)
                                    .frame(width: layoutWidth)
                                    .frame(maxHeight: .infinity)
                                    .clipped()
                                    .opacity(layoutWidth > 0 ? 1 : 0)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Button("New Terminal") { project.addTerminal() }
                        .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func terminalCell(_ terminal: TerminalSession) -> some View {
        let paneFocused = store.activeProjectID == project.id || store.selectedProjectIDs.count == 1
        let terminalActive = terminal.id == project.activeTerminalID || project.visibleTerminals.count == 1
        let fullyActive = paneFocused && terminalActive
        return TerminalHostView(session: terminal, isActive: fullyActive, store: store) {
            project.activeTerminalID = terminal.id
            store.activeProjectID = project.id
            store.activate()
        }
        .id(terminal.id)
        .background(Color.black)
        // Focus dim is applied instantly: animating it also animates the pane's
        // width change on Cmd+D / resize, which reflows the live PTY gradually
        // (repeated SIGWINCH) and scrambles terminal output.
        .opacity(fullyActive ? 1 : 0.45)
        .saturation(fullyActive ? 1 : 0.5)
        .contextMenu { terminalContextMenu(terminal) }
    }

    private func focusTerminal(_ terminal: TerminalSession) {
        project.activeTerminalID = terminal.id
        store.activeProjectID = project.id
    }

    // Terminal actions (formerly in the File menu) now live here, on
    // right-click over a terminal pane. Shortcut hints mirror the key monitor.
    @ViewBuilder
    private func terminalContextMenu(_ terminal: TerminalSession) -> some View {
        Button("New Terminal") {
            project.addTerminal()
            store.activeProjectID = project.id
        }
        .keyboardShortcut("t", modifiers: .command)

        Button("Split Terminal") {
            focusTerminal(terminal)
            store.splitActiveTerminal()
        }

        Button("Rename Tab…") {
            focusTerminal(terminal)
            store.renamingTerminal = terminal
        }
        .keyboardShortcut("r", modifiers: .command)

        Button("Expand Terminal") {
            focusTerminal(terminal)
            store.toggleExpandActiveTerminal()
        }
        .keyboardShortcut("e", modifiers: .command)

        Button("Summarize Selection") {
            focusTerminal(terminal)
            store.summarizeSelection()
        }
        .keyboardShortcut("f", modifiers: .command)

        Divider()

        Button("Zoom In") { store.zoomTerminals(by: 1) }
            .keyboardShortcut("=", modifiers: .command)
        Button("Zoom Out") { store.zoomTerminals(by: -1) }
            .keyboardShortcut("-", modifiers: .command)

        Divider()

        Menu("Terminal Width") {
            ForEach(1...5, id: \.self) { n in
                Button("\(n)/\(n + 1)") {
                    focusTerminal(terminal)
                    store.setActiveTerminalFraction(numerator: n)
                }
            }
        }

        Divider()

        Button("Open Project…") { store.requestNewProject() }
            .keyboardShortcut("o", modifiers: .command)

        Menu("Open Recent") {
            ForEach(store.recentProjectURLs, id: \.path) { url in
                Button(url.lastPathComponent) { store.addProject(folder: url) }
            }
        }

        Divider()

        Button("Close Terminal") {
            focusTerminal(terminal)
            store.closeActiveTerminal()
        }
        .keyboardShortcut("w", modifiers: .command)
    }
}

/// Cmd+Shift HUD: a centered, numbered list of open projects. Appears while
/// ⌘⇧ is held; ⌘⇧+N (1…9) switches to the Nth project. Non-interactive — it
/// floats over the terminals without stealing keyboard focus.
struct ProjectSwitcherOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                Image(systemName: "shift")
                Text("Switch Project")
                    .padding(.leading, 2)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(Array(store.projects.prefix(9).enumerated()), id: \.element.id) { index, project in
                    row(number: index + 1, project: project)
                }
            }

            Text("Hold ⌘⇧ · press a number")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .allowsHitTesting(false)
    }

    private func row(number: Int, project: Project) -> some View {
        let color = store.tagColor(for: project.folder) ?? .secondary
        let isSelected = store.selectedProjectIDs.contains(project.id)
        let tabCount = project.terminals.count
        return HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(color.opacity(0.9)) : AnyShapeStyle(.white.opacity(0.08)))
                )
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 18)
            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text("\(tabCount) tab\(tabCount == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.06) : .clear)
        )
    }
}

/// Shown over a terminal pane while a remote client (mobile or web) is driving it.
struct RemoteControlOverlay: View {
    let kind: RemoteKind
    let disconnect: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.35)
            VStack(spacing: 16) {
                Image(systemName: kind.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(kind.color)
                VStack(spacing: 4) {
                    Text("Controlled from \(kind.label)")
                        .font(.system(size: 16, weight: .semibold))
                    Text("This terminal is being driven by the Liftoff \(kind.label) client.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                Button(role: .destructive, action: disconnect) {
                    Label("Disconnect", systemImage: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(28)
        }
        .transition(.opacity)
    }
}

struct NativeTab: View {
    let title: String
    var agent: Agent? = nil
    var isBusy: Bool = false
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var hovering = false

    /// Title with any leading agent status glyph (spinner dot / bullet /
    /// braille / star) stripped — activity is shown by the spinner instead.
    private var cleanTitle: String {
        let bullets: Set<Character> = ["·", "•", "∙", "◦", "‣", "⁃", "∗", "*",
                                       "✶", "✳", "✱", "✻", "✽", "❋", "✦", "✧",
                                       "●", "◯", "◐", "◓", "◑", "◒"]
        var s = Substring(title)
        while let c = s.first {
            if c.isWhitespace || bullets.contains(c) { s = s.dropFirst(); continue }
            if let u = c.unicodeScalars.first, c.unicodeScalars.count == 1,
               (0x2800...0x28FF).contains(u.value) { s = s.dropFirst(); continue }
            break
        }
        let cleaned = s.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if hovering {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                } else if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .tint(agent?.color ?? .secondary)
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
            .frame(width: 12)
            if let agent {
                Text(agent.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(agent.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(agent.color.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(agent.color.opacity(0.35), lineWidth: 0.5))
                    .fixedSize()
            }
            Text(cleanTitle)
                .font(.system(size: 11.5))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(minWidth: 90, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive
                      ? AnyShapeStyle(.quaternary)
                      : (hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear)))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
