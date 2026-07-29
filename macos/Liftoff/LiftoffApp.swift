import SwiftUI
import AppKit

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
            CommandGroup(after: .help) {
                Button("Show Next Hint") {
                    AppStore.shared?.showNextHint()
                }
                Button((AppStore.shared?.hintsEnabled ?? true)
                       ? "Disable Periodic Hints" : "Enable Periodic Hints") {
                    if let store = AppStore.shared {
                        store.setHintsEnabled(!store.hintsEnabled)
                    }
                }
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

        Settings {
            LiftoffSettingsView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct LiftoffSettingsView: View {
    @State private var selection: SettingsSection? = .promptShortcuts

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.icon)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 22)
                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(selection == section ? .primary : .secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == section ? Color.brand.opacity(0.2) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selection == section ? Color.brand.opacity(0.32) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .frame(width: 220)
            .background(.ultraThinMaterial)

            Divider()

            Group {
                switch selection ?? .promptShortcuts {
                case .promptShortcuts:
                    PromptShortcutsSettingsPane()
                case .projectTags:
                    ProjectTagsSettingsPane()
                case .about:
                    AboutSettingsPane()
                }
            }
        }
        .tint(.brand)
        .frame(width: 900, height: 600)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case promptShortcuts
    case projectTags
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .promptShortcuts: "Prompt Shortcuts"
        case .projectTags: "Project Tags"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .promptShortcuts: "text.quote"
        case .projectTags: "tag"
        case .about: "info.circle"
        }
    }
}

private struct AboutSettingsPane: View {
    @State private var checking = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let path = Bundle.main.path(forResource: "icon", ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("Liftoff")
                .font(.system(size: 26, weight: .semibold))

            Text("The terminal for the AI-agent era.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text(version)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Button {
                checking = true
                Updater.shared.checkForUpdates()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    checking = false
                }
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(checking)

            HStack(spacing: 16) {
                Link("Website", destination: URL(string: "https://liftoff.shostkevych.com")!)
                Link("GitHub", destination: URL(string: "https://github.com/shostkevych/liftoff")!)
            }
            .font(.system(size: 12))

            Text("© 2026 Oleh Shostkevych")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct PromptShortcutsSettingsPane: View {
    @State private var shortcutStore = PromptShortcutStore.shared
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(shortcutStore.shortcuts) { shortcut in
                                Button {
                                    selection = shortcut.id
                                } label: {
                                    shortcutRow(shortcut)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }

                    if shortcutStore.shortcuts.isEmpty {
                        ContentUnavailableView(
                            "No Prompt Shortcuts",
                            systemImage: "text.quote",
                            description: Text("Add prompts you use often.")
                        )
                    }
                }

                Divider()
                HStack(spacing: 8) {
                    Button {
                        selection = shortcutStore.add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        removeSelection()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .frame(height: 34)
            }
            .frame(width: 250)
            .background(Color.white.opacity(0.012))

            Divider()

            if let selection,
               let shortcut = shortcutStore.shortcuts.first(where: { $0.id == selection }) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Prompt Shortcut")
                            .font(.title2.weight(.semibold))
                        Text("Reusable text pasted into the active terminal without sending it.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    TextField("Name", text: nameBinding(for: shortcut.id))
                        .textFieldStyle(.roundedBorder)
                    Text("Prompt")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: promptBinding(for: shortcut.id))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.08))
                        )
                    Text("Hold CMD + SHIFT, switch modes with ← or →, choose with ↑ or ↓, then release to paste.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(36)
                .id(shortcut.id)
            } else {
                ContentUnavailableView(
                    "Select a Shortcut",
                    systemImage: "cursorarrow.click",
                    description: Text("Choose a shortcut to edit it.")
                )
            }
        }
        .onDeleteCommand { removeSelection() }
        .onAppear {
            if selection == nil { selection = shortcutStore.shortcuts.first?.id }
        }
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { shortcutStore.shortcuts.first(where: { $0.id == id })?.name ?? "" },
            set: { shortcutStore.update(id: id, name: $0) }
        )
    }

    private func shortcutRow(_ shortcut: PromptShortcut) -> some View {
        let selected = selection == shortcut.id
        return VStack(alignment: .leading, spacing: 3) {
            Text(shortcut.name.isEmpty ? "Untitled Shortcut" : shortcut.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !shortcut.prompt.isEmpty {
                Text(shortcut.prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.brand.opacity(0.22) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.brand.opacity(0.35) : .clear)
        )
    }

    private func promptBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { shortcutStore.shortcuts.first(where: { $0.id == id })?.prompt ?? "" },
            set: { shortcutStore.update(id: id, prompt: $0) }
        )
    }

    private func removeSelection() {
        guard let selection else { return }
        shortcutStore.remove(id: selection)
        self.selection = shortcutStore.shortcuts.first?.id
    }
}


private struct ProjectTagsSettingsPane: View {
    @State private var tagStore = ProjectTagSettingsStore.shared
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(tagStore.tags) { tag in
                                Button {
                                    selection = tag.id
                                } label: {
                                    tagRow(tag)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }

                    if tagStore.tags.isEmpty {
                        ContentUnavailableView(
                            "No Tags",
                            systemImage: "tag",
                            description: Text("Create reusable tags for your projects.")
                        )
                    }
                }

                Divider()
                HStack(spacing: 8) {
                    Button {
                        selection = tagStore.add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        removeSelection()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .frame(height: 34)
            }
            .frame(width: 250)
            .background(Color.white.opacity(0.012))

            Divider()

            if let selection,
               let tag = tagStore.tags.first(where: { $0.id == selection }) {
                tagEditor(tag)
            } else {
                ContentUnavailableView(
                    "Select a Tag",
                    systemImage: "tag",
                    description: Text("Choose a global tag to edit its name and color.")
                )
            }
        }
        .onAppear {
            tagStore.refresh()
            if selection == nil { selection = tagStore.tags.first?.id }
        }
    }

    private func tagRow(_ tag: ProjectTagDefinition) -> some View {
        let selected = selection == tag.id
        return HStack(spacing: 10) {
            Circle()
                .fill(tag.color)
                .frame(width: 10, height: 10)
            Text(tag.label.isEmpty ? "Untitled Tag" : tag.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.brand.opacity(0.22) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.brand.opacity(0.35) : .clear)
        )
    }

    private func tagEditor(_ tag: ProjectTagDefinition) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Project Tag")
                    .font(.title2.weight(.semibold))
                Text("Reusable across every project. Changes apply to existing assignments.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Tag name", text: labelBinding(id: tag.id))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker(
                        "Custom Color",
                        selection: colorBinding(id: tag.id, fallback: tag.color),
                        supportsOpacity: false
                    )
                    .font(.system(size: 11))
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 6),
                    spacing: 14
                ) {
                    ForEach(TagPalette.families, id: \.name) { family in
                        Button {
                            tagStore.updateColor(family.base, for: tag.id)
                        } label: {
                            Circle()
                                .fill(Color(hex: family.base) ?? .secondary)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if tag.colorHex == family.base {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 2)
                                            .padding(-3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.035))
                )
            }

            Divider()

            Button("Delete Tag", role: .destructive) {
                removeSelection()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(36)
        .id(tag.id)
    }

    private func labelBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { tagStore.tags.first(where: { $0.id == id })?.label ?? "" },
            set: { tagStore.updateLabel($0, for: id) }
        )
    }

    private func colorBinding(id: UUID, fallback: Color) -> Binding<Color> {
        Binding(
            get: { tagStore.tags.first(where: { $0.id == id })?.color ?? fallback },
            set: { tagStore.updateColor(NSColor($0).hexString, for: id) }
        )
    }

    private func removeSelection() {
        guard let selection else { return }
        tagStore.remove(id: selection)
        self.selection = tagStore.tags.first?.id
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
        Task { await AnalyticsReporter.shared.start() }
        StatusBarController.shared.install()
        // Sampled app-wide (overlay pill + status-bar menu both read it), so it
        // starts here rather than with whichever view happens to appear first.
        MemoryMonitor.shared.start()
        FocusTrackingTerminalView.installKeyboardShortcuts()
        InstantTerminalController.shared.registerHotKey()
        if let store = AppStore.shared {
            SleepGuard.shared.apply(store.keepAwake)
            store.restorePinnedProjects()
            store.showWelcomeIfNeeded()
            store.showWhatsNewIfNeeded()
            store.startHintSchedule()
        }
    }
}
