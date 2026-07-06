import SwiftUI
import LocalAuthentication

struct SessionListView: View {
    @AppStorage("companionHost") private var companionHost = ""
    @AppStorage("airPaired") private var paired = false
    @AppStorage("airDemo") private var demo = false
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    /// Whether we've already asked the user about Face ID (so we only prompt once).
    @AppStorage("faceIDPrompted") private var faceIDPrompted = false
    @State private var showFaceIDPrompt = false

    @State private var client: CompanionClient
    @State private var path: [CompanionClient.Session] = []
    @State private var showRecents = false
    @State private var showSettings = false
    @State private var closingSession: CompanionClient.Session?
    /// True once the first session list has arrived — dismisses the launch spinner.
    @State private var initialLoadDone = false
    /// Face ID lock state.
    @State private var unlocked = false
    @Environment(\.scenePhase) private var scenePhase

    /// Re-list (or reconnect) every 5 seconds so the home screen stays fresh.
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init() {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: "companionHost") ?? ""
        let token = defaults.string(forKey: "companionToken") ?? ""
        let demo = defaults.bool(forKey: "airDemo")
        _client = State(wrappedValue: CompanionClient(host: host, token: token, demo: demo))
    }

    /// Sessions grouped by project, preserving server order.
    private var groups: [(pid: String, name: String, color: String?, items: [CompanionClient.Session])] {
        var order: [String] = []
        var map: [String: [CompanionClient.Session]] = [:]
        for s in client.sessions {
            if map[s.pid] == nil { order.append(s.pid) }
            map[s.pid, default: []].append(s)
        }
        return order.map { pid in
            let items = map[pid] ?? []
            return (pid, items.first?.pname ?? "", items.first?.color, items)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                background
                if initialLoadDone {
                    ScrollView {
                        VStack(spacing: 18) {
                            header
                            if groups.isEmpty && client.state != "connected" {
                                Text("Connecting to \(client.host)…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 40)
                            }
                            ForEach(groups, id: \.pid) { group in
                                projectSection(group)
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 90)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await refresh() }
                    .overlay(alignment: .bottomTrailing) { addProjectButton }
                    // Nothing open: invite a blank terminal from the center.
                    .overlay {
                        if groups.isEmpty && client.state == "connected" {
                            newTerminalButton
                        }
                    }
                } else {
                    launchSpinner
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(host: $companionHost, faceIDEnabled: $faceIDEnabled, onApply: { newHost in
                    if client.updateHost(newHost) { initialLoadDone = false }
                }, onDisconnect: disconnectPhone)
            }
            .sheet(isPresented: $showRecents) {
                RecentsSheet(client: client) { showRecents = false }
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .navigationDestination(for: CompanionClient.Session.self) { session in
                TerminalScreen(client: client, session: session)
                    .navigationTitle(session.displayTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) {
                                closingSession = session
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                    }
                    // Dialog must live on the pushed screen, not the root — a
                    // confirmationDialog attached to the covered root view never
                    // presents, so the close button appeared to do nothing.
                    .confirmationDialog(
                        "Close this terminal?",
                        isPresented: Binding(get: { closingSession != nil }, set: { if !$0 { closingSession = nil } }),
                        titleVisibility: .visible
                    ) {
                        Button("Close Terminal", role: .destructive) {
                            if let s = closingSession {
                                path.removeAll()
                                client.closeTerminal(s.tid)
                            }
                            closingSession = nil
                        }
                        Button("Cancel", role: .cancel) { closingSession = nil }
                    }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(.brand)
        .preferredColorScheme(.dark)
        .overlay {
            if faceIDEnabled && !unlocked { lockScreen }
        }
        .onAppear {
            client.connect()
            if faceIDEnabled { authenticate() } else { unlocked = true }
            if !faceIDPrompted { showFaceIDPrompt = true }
        }
        .alert("Enable Face ID?", isPresented: $showFaceIDPrompt) {
            Button("Enable") {
                faceIDEnabled = true
                faceIDPrompted = true
            }
            Button("Not Now", role: .cancel) {
                faceIDEnabled = false
                faceIDPrompted = true
            }
        } message: {
            Text("Lock Liftoff behind Face ID when it opens. You can change this later in Settings.")
        }
        .onChange(of: client.state) { _, new in
            if new != "connected" {
                if !path.isEmpty { path.removeAll() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if client.state != "connected" { client.connect() }
                }
            }
        }
        .onChange(of: client.hasLoaded) { _, loaded in
            if loaded { initialLoadDone = true }
        }
        .onChange(of: client.authed) { _, _ in
            if client.authed { client.list() }
        }
        // Returning to the root (main screen) must always release the terminal on
        // the Mac. Don't rely solely on the terminal view's teardown — pop, swipe-back,
        // and programmatic resets all funnel through `path` becoming empty.
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty && client.attachedID != nil { client.detach() }
        }
        .onChange(of: client.openedTid) { _, _ in navigateToOpened() }
        .onChange(of: client.sessions) { _, sessions in
            // The terminal we're viewing was closed on the Mac — leave its screen.
            // (The server keeps the connection alive on close, so no state change
            // pops us out anymore.)
            if let att = client.attachedID, !path.isEmpty,
               client.hasLoaded, !sessions.contains(where: { $0.tid == att }) {
                path.removeAll()
            }
            navigateToOpened()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if faceIDEnabled { unlocked = false }
            case .active:
                if faceIDEnabled && !unlocked { authenticate() }
            default:
                break
            }
        }
        .onReceive(refreshTimer) { _ in
            if client.authed { client.list() } else { client.connect() }
        }
    }

    private var launchSpinner: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.brand)
            Text("Connecting to \(client.host)…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var lockScreen: some View {
        ZStack {
            background
            VStack(spacing: 16) {
                Image(systemName: "faceid")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brand)
                Button("Unlock") { authenticate() }
                    .font(.system(size: 15, weight: .medium))
                    .tint(.brand)
            }
        }
    }

    /// Prompt for Face ID / passcode. On unavailable hardware we don't lock the user out.
    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Liftoff") { success, _ in
            DispatchQueue.main.async { if success { unlocked = true } }
        }
    }

    /// Unpair: drop the connection, forget the Mac's host + token, and return to
    /// onboarding so the user can scan a new pairing code.
    private func disconnectPhone() {
        client.disconnect()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "companionHost")
        defaults.removeObject(forKey: "companionToken")
        companionHost = ""
        paired = false
        demo = false
    }

    /// Pull-to-refresh: re-list when live, otherwise reconnect.
    @MainActor
    private func refresh() async {
        if client.authed { client.list() } else { client.connect() }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Connection status mirroring the web client's pill (Live / Connecting… / Can't connect).
    private var statusInfo: (label: String, color: Color) {
        switch client.state {
        case "connected":
            return ("Live", Color(red: 0.42, green: 0.82, blue: 0.42))
        case let s where s.hasPrefix("failed"):
            return ("Can't connect", Color(red: 0.91, green: 0.43, blue: 0.29))
        default:
            return ("Connecting…", Color(red: 0.89, green: 0.70, blue: 0.25))
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusInfo.color)
                .frame(width: 7, height: 7)
            Text(statusInfo.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusInfo.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(statusInfo.color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(statusInfo.color.opacity(0.3), lineWidth: 1))
    }

    /// After opening a recent project, navigate into its new terminal once it appears.
    private func navigateToOpened() {
        guard let tid = client.openedTid,
              let session = client.sessions.first(where: { $0.tid == tid }) else { return }
        client.openedTid = nil
        showRecents = false
        path = [session]
    }

    /// Centered glass button shown when nothing is open: opens a blank terminal.
    private var newTerminalButton: some View {
        Button {
            client.openEmpty()
        } label: {
            Text("New Terminal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.black.opacity(0.35))
                    }
                }
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Floating glass "+" to open a project, pinned to the bottom of the list.
    private var addProjectButton: some View {
        Button {
            client.loadRecents()
            showRecents = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 60, height: 60)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(Color.black.opacity(0.35))
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 22)
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [Color(white: 0.10), Color.black],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let logo = Brand.logo {
                Image(uiImage: logo)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .opacity(0.7)
            }
            Text("Liftoff Air")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            statusPill
                .animation(.easeInOut(duration: 0.25), value: client.state)
            if let greeting = client.greeting {
                Text(greeting)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.4), value: client.greeting)
    }

    private func projectSection(_ group: (pid: String, name: String, color: String?, items: [CompanionClient.Session])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(group.color.flatMap { Color(hex: $0) } ?? .secondary)
                    .frame(width: 3, height: 16)
                Text(group.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(group.items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Button {
                    client.newTab(pid: group.pid)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(group.items) { session in
                    SwipeableTabRow(
                        onTap: { path.append(session) },
                        onClose: { client.closeTerminal(session.tid) }
                    ) {
                        tabRow(session, color: group.color)
                    }
                }
            }
        }
    }

    private func tabRow(_ session: CompanionClient.Session, color: String?) -> some View {
        HStack(spacing: 10) {
            Group {
                if session.busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .tint(.brand)
                } else {
                    Image(systemName: session.agent == nil ? "terminal" : "sparkle")
                        .font(.system(size: 13))
                        .foregroundStyle(session.agent == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.brand))
                }
            }
            .frame(width: 18)
            Text(session.displayTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if let agent = session.agent {
                Text(agent)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.brand.opacity(0.4)))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.45)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A tappable row that reveals a red "close" action when swiped left, with a
/// confirmation dialog before closing. Used in place of `List`'s swipeActions
/// since the screen uses a custom ScrollView layout.
private struct SwipeableTabRow<Content: View>: View {
    let onTap: () -> Void
    let onClose: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var confirming = false
    private let revealed: CGFloat = -76

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                confirming = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 44)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)

            content
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    if offset != 0 { withAnimation(.spring(response: 0.3)) { offset = 0 } }
                    else { onTap() }
                }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            if v.translation.width < 0 { offset = max(v.translation.width, revealed) }
                            else if offset != 0 { offset = min(0, revealed + v.translation.width) }
                        }
                        .onEnded { v in
                            withAnimation(.spring(response: 0.3)) {
                                offset = v.translation.width < -40 ? revealed : 0
                            }
                        }
                )
        }
        .confirmationDialog("Close this terminal?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Close Terminal", role: .destructive) {
                withAnimation(.spring(response: 0.3)) { offset = 0 }
                onClose()
            }
            Button("Cancel", role: .cancel) {
                withAnimation(.spring(response: 0.3)) { offset = 0 }
            }
        }
    }
}
