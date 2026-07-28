import SwiftUI

/// Small glass pill in the bottom-right corner showing how much RAM every
/// terminal in the app is holding. Hovering expands it into a per-tab breakdown
/// where each row is a live tab: click to jump to it, or close it from here.
struct MemoryOverlay: View {
    @State private var monitor = MemoryMonitor.shared
    @State private var expanded = false
    /// Terminal awaiting close confirmation (nil = no dialog).
    @State private var pendingClose: Row?

    /// Rows shown before the tail is folded into a single summary line.
    private static let visibleRows = 8

    /// One terminal, resolved across every open window so the breakdown matches
    /// the "whole app" total on the pill.
    struct Row: Identifiable {
        let store: AppStore
        let project: Project
        let terminal: TerminalSession
        let bytes: UInt64
        var id: UUID { terminal.id }
    }

    private var rows: [Row] {
        AppStore.allStores.flatMap { store in
            store.projects.flatMap { project in
                project.terminals.map { terminal in
                    Row(store: store, project: project, terminal: terminal,
                        bytes: monitor.bytesBySession[terminal.id] ?? 0)
                }
            }
        }
        .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .trailing, spacing: 0) {
            if expanded { breakdown(rows: rows) }
            pill
        }
        .onHover { hovering in
            // Keep the panel up while a confirmation is on screen, otherwise the
            // dialog's own focus takes the pointer out and the panel vanishes
            // under it.
            withAnimation(.snappy(duration: 0.18)) {
                expanded = hovering || pendingClose != nil
            }
        }
        .padding(10)
        .task { monitor.start() }
        .confirmationDialog(
            pendingClose.map { "Kill “\(NativeTab.cleanTitle($0.terminal.displayTitle))”?" } ?? "",
            isPresented: Binding(get: { pendingClose != nil },
                                 set: { if !$0 { pendingClose = nil } }),
            titleVisibility: .visible
        ) {
            Button("Kill Terminal", role: .destructive) {
                if let row = pendingClose {
                    row.store.closeTerminal(row.terminal, in: row.project)
                }
                pendingClose = nil
                expanded = false
            }
            Button("Cancel", role: .cancel) { pendingClose = nil }
        } message: {
            Text("This kills the shell and everything running in it. Cmd+Shift+T reopens it for a few seconds.")
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Image(systemName: "memorychip")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
            Text(Self.format(monitor.totalBytes))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func breakdown(rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Terminal Memory")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            // A long tab list would cover the terminal — show the heaviest few
            // and fold the rest into one line.
            ForEach(rows.prefix(Self.visibleRows)) { row in
                MemoryRow(row: row,
                          select: { focus(row) },
                          close: { pendingClose = row })
            }
            if rows.count > Self.visibleRows {
                let rest = rows.dropFirst(Self.visibleRows)
                HStack(spacing: 8) {
                    Text("\(rest.count) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 6)
                    Text(Self.format(rest.reduce(0) { $0 + $1.bytes }))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
        }
        .padding(6)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .padding(.bottom, 6)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Bring the owning window forward, show that project, and select the tab.
    private func focus(_ row: Row) {
        row.store.hostWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        row.store.selectOnly(row.project)
        row.project.select(row.terminal)
        expanded = false
    }

    static func format(_ bytes: UInt64) -> String { MemoryMonitor.format(bytes) }
}

/// One tab in the memory breakdown, rendered like the app's own tab bar:
/// terminal icon (or busy spinner), agent badge, tab title.
private struct MemoryRow: View {
    let row: MemoryOverlay.Row
    let select: () -> Void
    let close: () -> Void

    @State private var hovering = false

    private var isActive: Bool { row.project.activeTerminalID == row.terminal.id }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if row.terminal.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .tint(row.terminal.runningAgent?.color ?? .secondary)
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
            .frame(width: 12)

            if let agent = row.terminal.runningAgent {
                Text(agent.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(agent.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(agent.color.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(agent.color.opacity(0.35), lineWidth: 0.5))
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(NativeTab.cleanTitle(row.terminal.displayTitle))
                    .font(.system(size: 11.5))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Several projects can be open at once, so name the owner —
                // otherwise two "zsh" tabs are indistinguishable.
                Text(row.project.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Text(MemoryOverlay.format(row.bytes))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Button(action: close) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.red.opacity(hovering ? 0.18 : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .help("Kill this terminal")
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.white.opacity(0.07)) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
