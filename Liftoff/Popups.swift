import SwiftUI

/// Full-window blur + dim behind a popup; click anywhere to dismiss.
struct PopupBackdrop: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .transition(.opacity)
    }
}

/// Shared dark-glass card chrome for overlay popups.
private struct PopupCard: ViewModifier {
    var width: CGFloat
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.55)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
    }
}

private struct PopupHeader: View {
    let title: String
    let icon: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }
}

/// About Liftoff: app icon, version, and a button to check for updates
/// (Sparkle also checks automatically every hour in the background).
struct AboutPopup: View {
    let dismiss: () -> Void

    @State private var checking = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let path = Bundle.main.path(forResource: "icon", ofType: "png"),
               let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 84, height: 84)
            }
            Text("Liftoff")
                .font(.system(size: 22, weight: .semibold))
            Text(version)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button {
                checking = true
                Updater.shared.checkForUpdates()
                // Sparkle drives its own UI from here; re-enable shortly after.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { checking = false }
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(checking)

            Text("Checks automatically every hour.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 320)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
    }
}

/// Cmd+F result popup: Cerebras summary of the selected terminal text.
struct SummaryPopup: View {
    let state: AppStore.SummaryState
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopupHeader(title: "Summary", icon: "sparkles", dismiss: dismiss)
            switch state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing with Cerebras…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            case .result(let text):
                MarkdownText(markdown: text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                attribution
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .modifier(PopupCard(width: 560))
    }

    /// Footer crediting the inference provider and model.
    private var attribution: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
            Text("Inference run on Cerebras · model ")
                + Text("gpt-oss-120b").font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Color.brand)
        .padding(.top, 2)
    }
}

/// Air → Connect overlay: QR code that pairs the iOS companion. The code
/// encodes every reachable IP this Mac has so the phone can pick a live one.
struct AirConnectPopup: View {
    let dismiss: () -> Void

    private let payload: String
    private let ips: [String]

    init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        // Scan interfaces once per popup open (not on every body evaluation) and
        // share the result between the QR payload and the listed addresses.
        let ips = AirPairing.localIPv4Addresses()
        self.ips = ips
        self.payload = AirPairing.payload(ips: ips)
    }

    var body: some View {
        VStack(spacing: 16) {
            PopupHeader(title: "Connect Liftoff Air", icon: "iphone.gen3.radiowaves.left.and.right", dismiss: dismiss)

            if let qr = AirPairing.qrImage(from: payload, side: 220) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            } else {
                Text("No network interfaces found.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(height: 220)
            }

            Text("Open Liftoff Air on your iPhone and scan this code to pair.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if !ips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ips, id: \.self) { ip in
                        HStack(spacing: 6) {
                            Image(systemName: "wifi")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(ip)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(22)
        .modifier(PopupCard(width: 320, cornerRadius: 14))
    }
}

/// Air → Set Web Password overlay: set/clear the passcode the browser client
/// must enter. An empty passcode disables web access entirely.
struct WebPasswordPopup: View {
    @Environment(AppStore.self) private var store
    let dismiss: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopupHeader(title: "Web Password", icon: "lock.shield", dismiss: dismiss)

            Text("The browser client can only connect after entering this passcode. Leave it empty to block web access entirely.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Passcode", text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focused)
                .onSubmit(save)

            HStack {
                if !store.webPassword.isEmpty {
                    Label("Web access enabled", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.green)
                } else {
                    Label("Web access disabled", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
            }
        }
        .padding(20)
        .modifier(PopupCard(width: 360))
        .onAppear {
            draft = store.webPassword
            focused = true
        }
    }

    private func save() {
        store.setWebPassword(draft)
        dismiss()
    }
}

/// Air → Set Cerebras API Key overlay: set/clear the key used for AI features
/// (Cmd+F summary, greeting). Without a key, AI features are disabled.
struct CerebrasKeyPopup: View {
    @Environment(AppStore.self) private var store
    let dismiss: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopupHeader(title: "Cerebras API Key", icon: "key.horizontal", dismiss: dismiss)

            Text("Required for AI features — Cmd+F summaries and the welcome greeting. Stored securely in the system Keychain.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Provider reference + model in use.
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://cloud.cerebras.ai")!) {
                    Label("Get a free key — cloud.cerebras.ai", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Color.brand)
                Spacer()
                Text("gpt-oss-120b")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(.quaternary))
            }

            SecureField("csk-…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focused)
                .onSubmit(save)

            HStack {
                if !store.cerebrasApiKey.isEmpty {
                    Label("Key set", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.green)
                } else {
                    Label("No key — AI features disabled", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
            }
        }
        .padding(20)
        .modifier(PopupCard(width: 360))
        .onAppear {
            draft = store.cerebrasApiKey
            focused = true
        }
    }

    private func save() {
        store.setCerebrasApiKey(draft)
        dismiss()
    }
}

/// Shown when an untagged project is opened (and from the header context menu):
/// pick a label + palette color, reuse an existing tag, or skip.
/// Cmd+R / tab right-click: set a custom tab name that nested processes
/// (via OSC titles or agent hooks) can't overwrite.
struct RenameTerminalPopup: View {
    let terminal: TerminalSession
    let dismiss: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PopupHeader(title: "Rename Tab", icon: "pencil", dismiss: dismiss)

            Text("A custom name sticks — programs running in this terminal can't change it. Leave it empty to go back to automatic titles.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Tab name", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focused)
                .onSubmit(save)

            HStack(spacing: 12) {
                if terminal.customTitle != nil {
                    Button("Use Automatic Title") {
                        terminal.customTitle = nil
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.brand)
            }
            .padding(.top, 4)
        }
        .padding(26)
        .modifier(PopupCard(width: 420))
        .onAppear {
            name = terminal.customTitle ?? terminal.title
            focused = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        terminal.customTitle = trimmed.isEmpty ? nil : trimmed
        dismiss()
    }
}

struct ProjectTagPopup: View {
    @Environment(AppStore.self) private var store
    let folder: URL
    let dismiss: () -> Void

    @State private var label: String = ""
    @State private var colorHex: String = TagPalette.first
    @State private var familyIndex: Int = 0
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PopupHeader(title: "Tag Project", icon: "tag", dismiss: skip)

            Text("Tag “\(folder.lastPathComponent)” so it's easy to spot. Pick a name and color, reuse one below, or skip.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Label (e.g. Work, Personal)", text: $label)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focused)
                .onSubmit(save)

            // Two-level color picker: a hue per family, then its shades.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(Array(TagPalette.families.enumerated()), id: \.element.id) { index, family in
                        swatch(hex: family.base, selected: familyIndex == index, diameter: 24) {
                            familyIndex = index
                            colorHex = family.base
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(TagPalette.families[familyIndex].shades, id: \.self) { hex in
                        swatch(hex: hex, selected: colorHex == hex, diameter: 28) {
                            colorHex = hex
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            // Quick reuse of tag labels already in use (the color stays the
            // project's own pick — tags carry no color).
            if !store.knownTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent tags")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    FlowChips(labels: store.knownTags, selected: label) { picked in
                        label = picked
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Skip") { skip() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.brand)
            }
            .padding(.top, 4)
        }
        .padding(26)
        .modifier(PopupCard(width: 520))
        .onAppear {
            if let existing = store.tag(forPath: folder.path) {
                label = existing.label
                colorHex = existing.colorHex
                isEditing = true
            }
            familyIndex = TagPalette.familyIndex(of: colorHex)
            focused = true
        }
    }

    /// A single circular color swatch with a selection ring.
    private func swatch(hex: String, selected: Bool, diameter: CGFloat, tap: @escaping () -> Void) -> some View {
        Circle()
            .fill(Color(hex: hex) ?? .secondary)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 3 : 0))
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            .contentShape(Circle())
            .onTapGesture(perform: tap)
    }

    private func save() {
        store.resolveTagPrompt(
            ProjectTag(label: label.trimmingCharacters(in: .whitespacesAndNewlines), colorHex: colorHex),
            for: folder)
        dismiss()
    }

    /// Skipping stores a color-only tag so this folder isn't asked again.
    private func skip() {
        store.resolveTagPrompt(ProjectTag(label: "", colorHex: colorHex), for: folder)
        dismiss()
    }
}

/// Wrapping row of reusable tag-label chips, packed left-to-right (no fixed
/// columns, so no dead space). Tags carry no color, so the chips are neutral —
/// picking one just fills in the label; the active one is highlighted.
private struct FlowChips: View {
    let labels: [String]
    var selected: String = ""
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                let isOn = label.caseInsensitiveCompare(selected) == .orderedSame
                Button { pick(label) } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isOn ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.white.opacity(0.07))))
                        .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0.4 : 0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Leading-aligned wrapping layout (flex-wrap): each row fills the available
/// width before wrapping, so chips pack tightly with no column gutters.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Shown the first time an agent session (Claude Code or opencode) is detected
/// and Liftoff's notification hook isn't installed yet: offers to wire it into
/// the agent's config folder.
struct HookSetupPopup: View {
    @Environment(AppStore.self) private var store
    let agent: Agent
    let configDir: URL

    /// The human-readable agent name for copy.
    private var agentName: String {
        agent == .opencode ? "opencode" : "Claude Code"
    }

    /// The config file the hook lands in, with the home folder abbreviated.
    private var settingsPath: String {
        let suffix = agent == .opencode ? "plugins/liftoff-notify.js" : "settings.json"
        return (configDir.appendingPathComponent(suffix).path as NSString)
            .abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopupHeader(title: "\(agentName) Notifications", icon: "bell.badge", dismiss: { store.declineHookSetup() })

            Text("Liftoff can notify you when \(agentName) needs your attention or finishes a task — even when you're in another app or on Liftoff Air.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                hookRow(icon: "bell", text: "Native banner per project when \(agentName) pauses for input")
                hookRow(icon: "checkmark.circle", text: "A ping when a response finishes")
                hookRow(icon: "gearshape", text: agent == .opencode
                        ? "Adds a notify plugin to \(settingsPath)"
                        : "Adds Notification + Stop hooks to \(settingsPath)")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))

            HStack(spacing: 12) {
                Button("Not now") { store.declineHookSetup() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Spacer()
                Button("Set up notifications") { store.installNotificationHook() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.brand)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .modifier(PopupCard(width: 420, cornerRadius: 14))
    }

    private func hookRow(icon: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.brand)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Cmd+H overlay: hotkeys and features reference.
struct HelpPopup: View {
    let dismiss: () -> Void

    private static let sections: [(title: String, items: [(keys: String, text: String)])] = [
        ("Projects & Panes", [
            ("⌘O", "Open project picker pane (recents, ⌘-click multi-select)"),
            ("⌘W", "Close terminal — closes project when last one"),
            ("⌘E", "Expand focused split terminal to fill project (toggle)"),
            ("⌘1–5", "Split terminal width: n/(n+1) of project"),
            ("Drag 1px divider", "Resize panes / split terminals freely"),
            ("Right-click header", "Custom project color / close project"),
        ]),
        ("Terminals", [
            ("⌘T", "New terminal tab in focused project"),
            ("⌘⇧T", "Restore closed terminal — shell kept alive 10 s"),
            ("⌘D", "Split focused terminal — new tab when the pane is narrow"),
            ("⌘L", "Toggle terminal tab bars (all projects)"),
            ("⌘= / ⌘-", "Zoom all terminals"),
            ("Drag & drop files", "Insert shell-escaped paths"),
        ]),
        ("Editing", [
            ("⇧↩", "Newline without submitting (agentic CLIs)"),
            ("⌥← / ⌥→", "Jump word back / forward"),
            ("⌘← / ⌘→", "Line start / end"),
            ("⌥⌫ / ⌘⌫", "Delete word / whole line"),
        ]),
        ("AI", [
            ("⌘F", "Summarize selected text with Gemma"),
            ("Notifications", "Claude Code pushes per project via hooks"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopupHeader(title: "Liftoff — Hotkeys", icon: "keyboard", dismiss: dismiss)
            ForEach(Self.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    ForEach(section.items, id: \.keys) { item in
                        HStack(alignment: .center, spacing: 14) {
                            KeycapRow(spec: item.keys)
                                .frame(width: 180, alignment: .leading)
                            Text(item.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(24)
        .modifier(PopupCard(width: 660, cornerRadius: 14))
    }
}

/// Renders a shortcut spec like "⌘O" or "⌥← / ⌥→" as keycap chips.
/// Non-shortcut specs (plain words) render as a single pill.
struct KeycapRow: View {
    let spec: String

    private static let modifiers: Set<Character> = ["⌘", "⌥", "⇧", "⌃"]
    private static let keySymbols: Set<Character> = ["←", "→", "↩", "⌫", "↑", "↓"]

    var body: some View {
        HStack(spacing: 6) {
            let combos = spec.components(separatedBy: " / ")
            ForEach(Array(combos.enumerated()), id: \.offset) { index, combo in
                if index > 0 {
                    Text("/").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                comboView(combo)
            }
        }
    }

    @ViewBuilder
    private func comboView(_ combo: String) -> some View {
        let isShortcut = combo.first.map { Self.modifiers.contains($0) || Self.keySymbols.contains($0) } ?? false
        if isShortcut {
            HStack(spacing: 3) {
                ForEach(Array(tokens(combo).enumerated()), id: \.offset) { _, token in
                    Keycap(label: token)
                }
            }
        } else {
            Text(combo)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.07)))
        }
    }

    /// "⌘1–5" -> ["⌘", "1–5"]; "⌥⌫" -> ["⌥", "⌫"].
    private func tokens(_ combo: String) -> [String] {
        var result: [String] = []
        var rest = combo[...]
        while let first = rest.first, Self.modifiers.contains(first) {
            result.append(String(first))
            rest = rest.dropFirst()
        }
        let remainder = rest.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty {
            result.append(remainder)
        }
        return result
    }
}

struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 16)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}
