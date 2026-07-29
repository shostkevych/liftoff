import SwiftUI

private struct ProjectPrompt {
    let title: String
    let subtitle: String
}

@MainActor
private enum ProjectPromptRotation {
    private static let prompts = [
        ProjectPrompt(title: "Ready, partner!", subtitle: "What are we going to build?"),
        ProjectPrompt(title: "Systems are green!", subtitle: "What are we launching today?"),
        ProjectPrompt(title: "Blank canvas, full tank.", subtitle: "What should we bring to life?"),
        ProjectPrompt(title: "Engines warmed up!", subtitle: "Where are we heading next?"),
        ProjectPrompt(title: "New mission unlocked.", subtitle: "What should we call it?"),
        ProjectPrompt(title: "Let’s make some magic.", subtitle: "What are we creating?"),
        ProjectPrompt(title: "Your workspace is ready.", subtitle: "What’s the next big idea?"),
        ProjectPrompt(title: "Fresh project, fresh possibilities.", subtitle: "What are we building first?"),
        ProjectPrompt(title: "Tools are ready!", subtitle: "What are we crafting today?"),
        ProjectPrompt(title: "The launchpad is clear.", subtitle: "What’s ready for liftoff?"),
        ProjectPrompt(title: "One idea away.", subtitle: "What will this project become?")
    ]

    private static var remaining: [ProjectPrompt] = []

    static func next() -> ProjectPrompt {
        if remaining.isEmpty {
            remaining = prompts.shuffled()
        }
        return remaining.removeFirst()
    }
}

/// Open-project picker: button + recent projects with Cmd+click multi-select.
struct ProjectPicker: View {
    @Environment(AppStore.self) private var store
    let onOpen: ([URL]) -> Void
    var onTerminal: (() -> Void)? = nil

    @State private var selectedRecents: Set<String> = []
    @State private var appeared = false
    @State private var query = ""
    @State private var searching = false
    @State private var creatingProject = false
    @FocusState private var filterFocused: Bool
    @FocusState private var rootFocused: Bool

    /// Recents matching the filter (name or path), newest first, capped at 8.
    private var filteredRecents: [URL] {
        let all = store.recentProjectURLs
        let matched = query.isEmpty ? all : all.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
        return Array(matched.prefix(8))
    }

    var body: some View {
        VStack(spacing: 20) {
            if let path = Bundle.main.path(forResource: "icon", ofType: "png"),
               let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .opacity(appeared ? 0.7 : 0)
            }
            Text("Liftoff")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(appeared ? 1 : 0)
            if let greeting = store.greeting {
                Text(greeting)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                Button {
                    if let url = store.pickFolder() {
                        onOpen([url])
                    }
                } label: {
                    Label("Open Project", systemImage: "folder")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                Button {
                    creatingProject = true
                } label: {
                    Label("Create Project", systemImage: "folder.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                Button {
                    onTerminal?()
                } label: {
                    Label("New Terminal", systemImage: "terminal")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            if !store.recentProjectURLs.isEmpty {
                recentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: store.greeting)
        .animation(.easeInOut(duration: 0.35), value: appeared)
        // Type anywhere on this screen to start filtering recents.
        .focusable(!store.recentProjectURLs.isEmpty)
        .focusEffectDisabled()
        .focused($rootFocused)
        .onKeyPress(phases: .down) { press in
            // Only intercept until the field takes focus. Append (don't replace)
            // so a fast second keystroke that races the state update isn't lost;
            // once the TextField is first responder, root focus drops and it
            // receives keys directly (so no double-handling).
            guard !store.recentProjectURLs.isEmpty, !filterFocused else { return .ignored }
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            guard let c = press.characters.first,
                  c.isLetter || c.isNumber || "-_. ".contains(c) else { return .ignored }
            searching = true
            query.append(contentsOf: press.characters)
            NSLog("LIFTOFF-SEARCH onKeyPress char=%@ query=%@ filterFocused=%d", press.characters, query, filterFocused ? 1 : 0)
            DispatchQueue.main.async { filterFocused = true }
            return .handled
        }
        .onAppear {
            store.loadGreeting()
            appeared = true
            // Hold key focus so the first keystroke opens the filter.
            DispatchQueue.main.async { rootFocused = true }
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.5)
            }
            .ignoresSafeArea()
        }
        .overlay {
            if creatingProject {
                ZStack {
                    PopupBackdrop { creatingProject = false }
                    CreateProjectFlow(onCreate: { url in
                        onOpen([url])
                        creatingProject = false
                    }, dismiss: {
                        creatingProject = false
                    })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: creatingProject)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
                if !searching {
                    Button {
                        searching = true
                        filterFocused = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.bottom, 2)

            // Filter recents by name or path — revealed by the Search button.
            if searching {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                    TextField("Filter projects", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .focused($filterFocused)
                        .onChange(of: query) { _, v in NSLog("LIFTOFF-SEARCH field.onChange query=%@", v) }
                    Button {
                        query = ""
                        searching = false
                        filterFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Capsule().fill(.ultraThinMaterial))
                .background(Capsule().fill(.white.opacity(0.04)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ForEach(filteredRecents, id: \.path) { url in
                RecentProjectRow(url: url, isSelected: selectedRecents.contains(url.path)) {
                    if NSEvent.modifierFlags.contains(.command) {
                        if selectedRecents.contains(url.path) {
                            selectedRecents.remove(url.path)
                        } else {
                            selectedRecents.insert(url.path)
                        }
                    } else {
                        onOpen([url])
                    }
                }
            }
            if !selectedRecents.isEmpty {
                Button("Open \(selectedRecents.count) Selected") {
                    let urls = store.recentProjectURLs.filter { selectedRecents.contains($0.path) }
                    selectedRecents.removeAll()
                    onOpen(urls)
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: 460)
        .padding(.top, 16)
        .animation(.snappy(duration: 0.2), value: searching)
    }
}

private struct CreateProjectFlow: View {
    @Environment(AppStore.self) private var store
    let onCreate: (URL) -> Void
    let dismiss: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var prompt = ProjectPrompt(
        title: "Ready, partner!",
        subtitle: "What are we going to build?")
    @State private var pickedPrompt = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validName: Bool {
        !trimmedName.isEmpty
            && trimmedName != "."
            && trimmedName != ".."
            && !trimmedName.contains("/")
    }

    var body: some View {
        Group {
            if step == 0 {
                nameStep
            } else {
                ProjectTagPopup(
                    folder: URL(fileURLWithPath: "/\(trimmedName)"),
                    dismiss: dismiss,
                    resolve: { tag in createProject(tag: tag) })
            }
        }
        .alert("Couldn’t Create Project", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            PopupHeader(title: "Create Project", icon: nil, dismiss: dismiss)

            VStack(spacing: 10) {
                if let path = Bundle.main.path(forResource: "icon", ofType: "png"),
                   let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 52, height: 52)
                }

                Text(prompt.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(prompt.subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($nameFocused)
                .onSubmit {
                    if validName { step = 1 }
                }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Spacer()
                Button("Continue") { step = 1 }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.brand)
                    .disabled(!validName)
            }
            .padding(.top, 4)
        }
        .padding(26)
        .modifier(PopupCard(width: 460))
        .onAppear {
            if !pickedPrompt {
                prompt = ProjectPromptRotation.next()
                pickedPrompt = true
            }
            nameFocused = true
        }
    }

    private func createProject(tag: ProjectTag) -> Bool {
        guard let parent = store.pickProjectParentFolder(named: trimmedName) else {
            return false
        }

        let folder = parent.appendingPathComponent(trimmedName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            errorMessage = "A file or folder named “\(trimmedName)” already exists there."
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: false)
            store.setTag(tag, for: folder)
            onCreate(folder)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// Empty pane opened by Cmd+O, replaced by a project once picked.
struct PlaceholderPane: View {
    @Environment(AppStore.self) private var store
    let id: UUID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Project")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.removePlaceholder(id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.bar)
            Divider()
            ProjectPicker(onOpen: { urls in
                urls.forEach { store.addProject(folder: $0) }
                store.removePlaceholder(id)
            }, onTerminal: {
                store.addStandaloneTerminal()
                store.removePlaceholder(id)
            })
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.activePlaceholderID = id
            store.activeProjectID = nil
        }
    }
}

struct RecentProjectRow: View {
    @Environment(AppStore.self) private var store
    let url: URL
    var isSelected = false
    let open: () -> Void

    @State private var hovering = false

    private var tag: ProjectTag? { store.tag(forPath: url.path) }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tag?.color ?? .secondary)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let tag, tag.hasLabel {
                Text(tag.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tag.color.opacity(0.45)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected
                      ? AnyShapeStyle(Color.black.opacity(0.7))
                      : (hovering ? AnyShapeStyle(.white.opacity(0.1)) : AnyShapeStyle(.white.opacity(0.05))))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.25) : .white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
    }
}
