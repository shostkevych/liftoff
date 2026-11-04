import AppKit
import SwiftUI

/// A native macOS menu-bar (status bar) item that lists every open project
/// across all Liftoff windows. Clicking a project focuses its window and shows
/// only that project. Each row carries the project's tag color, tag label, any
/// running agent (claude/codex/…), and a live spinner while a terminal is busy.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?

    /// Create the status item once. Safe to call repeatedly.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.toolTip = "Liftoff — open projects"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// icon.png scaled to the menu-bar height and rendered as a template so it
    /// adapts to light/dark menu bars.
    private static func menuBarIcon() -> NSImage? {
        guard let path = Bundle.main.path(forResource: "icon", ofType: "png"),
              let raw = NSImage(contentsOfFile: path) else { return nil }
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        raw.draw(in: NSRect(origin: .zero, size: size),
                 from: .zero, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: Menu building (rebuilt on every open so it's always fresh)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let stores = AppStore.allStores
        let hasProjects = stores.contains { !$0.projects.isEmpty }

        let total = MemoryMonitor.shared.totalBytes
        let header = NSMenuItem(
            title: total > 0 ? "Liftoff — \(MemoryMonitor.format(total)) RAM" : "Liftoff",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !hasProjects {
            let empty = NSMenuItem(title: "No projects open", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let multiWindow = stores.filter { !$0.projects.isEmpty }.count > 1
            for store in stores where !store.projects.isEmpty {
                if multiWindow {
                    let label = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
                    label.isEnabled = false
                    menu.addItem(label)
                }
                for project in store.projects {
                    menu.addItem(projectItem(project, in: store))
                    // Tabs are listed inline under their project rather than in a
                    // submenu, so memory and the kill button are one click away.
                    for terminal in project.terminals {
                        menu.addItem(terminalItem(terminal, in: project, store: store))
                    }
                }
            }
        }

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Liftoff", action: #selector(showApp), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let quit = NSMenuItem(title: "Quit Liftoff", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func projectItem(_ project: Project, in store: AppStore) -> NSMenuItem {
        let item = NSMenuItem()
        let barColor = NSColor(store.accentColor(for: project))
        let tabs = project.terminals.count
        let busy = project.terminals.contains { $0.isBusy }

        var tag: ProjectMenuItemView.Pill?
        if let t = store.tag(for: project), t.hasLabel {
            tag = .init(text: t.label, color: barColor)
        }
        // Distinct agents currently running across this project's terminals.
        var seen = Set<String>()
        var agents: [ProjectMenuItemView.Pill] = []
        for term in project.terminals {
            if let a = term.runningAgent, seen.insert(a.label).inserted {
                agents.append(.init(text: a.label, color: NSColor(a.color)))
            }
        }

        let bytes = MemoryMonitor.shared.bytes(for: project.terminals)
        var subtitle = "\(tabs) tab\(tabs == 1 ? "" : "s")"
        if bytes > 0 { subtitle += " · \(MemoryMonitor.format(bytes))" }

        let view = ProjectMenuItemView(
            name: project.name,
            subtitle: subtitle,
            barColor: barColor,
            tag: tag,
            agents: agents,
            busy: busy
        ) { [weak store] in
            guard let store else { return }
            NSApp.activate(ignoringOtherApps: true)
            store.selectOnly(project)
            (store.hostWindow ?? NSApp.windows.first { $0.isVisible })?.makeKeyAndOrderFront(nil)
        }
        item.view = view
        return item
    }

    private func terminalItem(_ terminal: TerminalSession,
                              in project: Project,
                              store: AppStore) -> NSMenuItem {
        let item = NSMenuItem()
        var agent: TerminalMenuItemView.Pill?
        if let a = terminal.runningAgent {
            agent = .init(text: a.label, color: NSColor(a.color))
        }
        let view = TerminalMenuItemView(
            title: NativeTab.cleanTitle(terminal.displayTitle),
            memory: MemoryMonitor.format(MemoryMonitor.shared.bytesBySession[terminal.id] ?? 0),
            agent: agent,
            busy: terminal.isBusy,
            onClick: { [weak store] in
                guard let store else { return }
                NSApp.activate(ignoringOtherApps: true)
                store.selectOnly(project)
                project.select(terminal)
                (store.hostWindow ?? NSApp.windows.first { $0.isVisible })?.makeKeyAndOrderFront(nil)
            },
            onClose: { [weak store] in
                guard let store else { return }
                Self.confirmClose(terminal, in: project, store: store)
            }
        )
        item.view = view
        return item
    }

    /// Killing a shell takes its running work with it, so always ask first. The
    /// menu has already closed by the time this runs, hence the modal alert.
    private static func confirmClose(_ terminal: TerminalSession,
                                     in project: Project,
                                     store: AppStore) {
        // Let the menu finish dismissing before a modal alert takes the run loop.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Kill “\(NativeTab.cleanTitle(terminal.displayTitle))”?"
            alert.informativeText = "This kills the shell and everything running in it."
            alert.addButton(withTitle: "Kill Terminal")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            store.closeTerminal(terminal, in: project)
        }
    }

    @objc private func showApp() {
        NSApp.activate(ignoringOtherApps: true)
        let store = AppStore.shared
        (store?.hostWindow ?? NSApp.windows.first { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// Custom AppKit view for a project row in the status-bar menu: a tag-colored
/// rail, the project name + tab count, optional tag/agent pills, and a native
/// spinner while a terminal is busy. Drawn by hand so it matches the in-app
/// sidebar styling and supports the system menu highlight.
private final class ProjectMenuItemView: NSView {
    struct Pill { let text: String; let color: NSColor }

    private let name: String
    private let subtitle: String
    private let barColor: NSColor
    private let tagPill: Pill?
    private let agents: [Pill]
    private let busy: Bool
    private let onClick: () -> Void
    private var spinner: NSProgressIndicator?

    private static let height: CGFloat = 42
    private static let pillFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)

    init(name: String, subtitle: String, barColor: NSColor,
         tag: Pill?, agents: [Pill], busy: Bool, onClick: @escaping () -> Void) {
        self.name = name
        self.subtitle = subtitle
        self.barColor = barColor
        self.tagPill = tag
        self.agents = agents
        self.busy = busy
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: Self.height))
        autoresizingMask = [.width]
        if busy {
            let s = NSProgressIndicator()
            s.style = .spinning
            s.controlSize = .small
            s.isIndeterminate = true
            s.translatesAutoresizingMaskIntoConstraints = false
            addSubview(s)
            s.startAnimation(nil)
            spinner = s
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if let spinner {
            let sz: CGFloat = 16
            spinner.frame = NSRect(x: bounds.width - sz - 12,
                                   y: (bounds.height - sz) / 2, width: sz, height: sz)
        }
    }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = isHighlighted
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2),
                         xRadius: 5, yRadius: 5).fill()
        }

        let primary: NSColor = highlighted ? .white : .labelColor
        let secondary: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor

        // Tag-colored rail.
        let rail = NSBezierPath(roundedRect: NSRect(x: 14, y: bounds.midY - 13, width: 3, height: 26),
                                xRadius: 1.5, yRadius: 1.5)
        (highlighted ? NSColor.white : barColor).setFill()
        rail.fill()

        // Trailing pills (agents then tag), laid out right-to-left, leaving room
        // for the spinner when busy.
        var rightEdge = bounds.width - 12 - (busy ? 24 : 0)
        if let tagPill { rightEdge = drawPill(tagPill, rightEdge: rightEdge, highlighted: highlighted) - 6 }
        for agent in agents.reversed() {
            rightEdge = drawPill(agent, rightEdge: rightEdge, highlighted: highlighted) - 6
        }

        // Name + subtitle, clipped so they never overlap the pills.
        let textRight = rightEdge - 8
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: primary,
        ]
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: secondary,
        ]
        let textX: CGFloat = 24
        let width = max(0, textRight - textX)
        drawClipped(name, attrs: nameAttr, rect: NSRect(x: textX, y: bounds.midY + 1, width: width, height: 16))
        drawClipped(subtitle, attrs: subAttr, rect: NSRect(x: textX, y: bounds.midY - 15, width: width, height: 14))
    }

    private func drawClipped(_ text: String, attrs: [NSAttributedString.Key: Any], rect: NSRect) {
        let s = NSString(string: text)
        let bounding = s.boundingRect(with: NSSize(width: .greatestFiniteMagnitude, height: rect.height),
                                      options: [.usesLineFragmentOrigin], attributes: attrs)
        var draw = rect
        if bounding.width > rect.width { draw.size.width = rect.width }
        s.draw(with: draw, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    /// Draws a rounded pill ending at `rightEdge`, returns its left edge x.
    private func drawPill(_ pill: Pill, rightEdge: CGFloat, highlighted: Bool) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.pillFont,
            .foregroundColor: highlighted ? NSColor.white : pill.color.blended(withFraction: 0.15, of: .white) ?? pill.color,
        ]
        let textSize = NSString(string: pill.text).size(withAttributes: attrs)
        let padH: CGFloat = 7, h: CGFloat = 16
        let w = textSize.width + padH * 2
        let x = rightEdge - w
        let rect = NSRect(x: x, y: bounds.midY - h / 2, width: w, height: h)
        let bg = highlighted ? NSColor.white.withAlphaComponent(0.25) : pill.color.withAlphaComponent(0.22)
        bg.setFill()
        NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
        NSString(string: pill.text).draw(
            at: NSPoint(x: x + padH, y: rect.midY - textSize.height / 2), withAttributes: attrs)
        return x
    }

    // Track the mouse so the highlight redraws as the pointer moves over the row.
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        enclosingMenuItem?.menu?.cancelTracking()
        onClick()
    }
}

/// A terminal row listed under its project: busy spinner or terminal glyph,
/// agent pill, tab title, its memory footprint, and a ✕ that kills the shell.
/// Hand-drawn for the same reason as `ProjectMenuItemView` — menu items can't
/// host this layout otherwise.
private final class TerminalMenuItemView: NSView {
    struct Pill { let text: String; let color: NSColor }

    private let title: String
    private let memory: String
    private let agent: Pill?
    private let busy: Bool
    private let onClick: () -> Void
    private let onClose: () -> Void
    private var spinner: NSProgressIndicator?

    private static let height: CGFloat = 30
    private static let pillFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)
    /// Width of the trailing kill hit area.
    private static let closeSize: CGFloat = 22
    /// Tab rows sit indented under their project row, aligned with its title.
    private static let indent: CGFloat = 24

    init(title: String, memory: String, agent: Pill?, busy: Bool,
         onClick: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self.memory = memory
        self.agent = agent
        self.busy = busy
        self.onClick = onClick
        self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: Self.height))
        autoresizingMask = [.width]
        if busy {
            let s = NSProgressIndicator()
            s.style = .spinning
            s.controlSize = .small
            s.isIndeterminate = true
            addSubview(s)
            s.startAnimation(nil)
            spinner = s
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        spinner?.frame = NSRect(x: Self.indent, y: (bounds.height - 14) / 2, width: 14, height: 14)
    }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    /// Hit area of the kill control, at the trailing edge.
    private var closeRect: NSRect {
        NSRect(x: bounds.width - Self.closeSize - 8,
               y: (bounds.height - Self.closeSize) / 2,
               width: Self.closeSize, height: Self.closeSize)
    }

    /// Whether the pointer is over the Kill control specifically, so it can
    /// light up and signal that clicking there kills instead of selecting.
    private var hoveringClose = false

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = isHighlighted
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2),
                         xRadius: 5, yRadius: 5).fill()
        }
        let primary: NSColor = highlighted ? .white : .labelColor
        let secondary: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor

        if !busy, let glyph = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) {
            glyph.isTemplate = true
            let tinted = NSImage(size: NSSize(width: 13, height: 13), flipped: false) { rect in
                secondary.set()
                glyph.draw(in: rect)
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: Self.indent, y: bounds.midY - 6.5, width: 13, height: 13))
        }

        var x: CGFloat = Self.indent + 20
        if let agent {
            x = drawPill(agent, leftEdge: x, highlighted: highlighted) + 6
        }

        // Memory sits between the title and the ✕.
        let memoryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: secondary,
        ]
        let memorySize = NSString(string: memory).size(withAttributes: memoryAttrs)
        let memoryX = closeRect.minX - 8 - memorySize.width
        NSString(string: memory).draw(
            at: NSPoint(x: memoryX, y: bounds.midY - memorySize.height / 2), withAttributes: memoryAttrs)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: primary,
        ]
        let titleRect = NSRect(x: x, y: bounds.midY - 8,
                               width: max(0, memoryX - 8 - x), height: 16)
        NSString(string: title).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: titleAttrs)

        drawKillButton(highlighted: highlighted)
    }

    /// Trailing kill glyph. Always drawn so the affordance is discoverable, and
    /// tinted red rather than hidden — killing a shell is destructive, so it
    /// should read as such before the confirmation appears.
    private func drawKillButton(highlighted: Bool) {
        let rect = closeRect
        let tint: NSColor = highlighted ? .white : .systemRed
        if hoveringClose {
            (highlighted ? NSColor.white.withAlphaComponent(0.28)
                         : NSColor.systemRed.withAlphaComponent(0.22)).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        guard let mark = NSImage(systemSymbolName: "xmark.circle",
                                 accessibilityDescription: "Kill terminal") else { return }
        mark.isTemplate = true
        let size: CGFloat = 13
        let glyphRect = NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2,
                               width: size, height: size)
        let tinted = NSImage(size: glyphRect.size, flipped: false) { r in
            tint.set()
            mark.draw(in: r)
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: glyphRect)
    }

    /// Draws a rounded pill starting at `leftEdge`, returns its right edge x.
    private func drawPill(_ pill: Pill, leftEdge: CGFloat, highlighted: Bool) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.pillFont,
            .foregroundColor: highlighted ? NSColor.white : pill.color.blended(withFraction: 0.15, of: .white) ?? pill.color,
        ]
        let textSize = NSString(string: pill.text).size(withAttributes: attrs)
        let padH: CGFloat = 6, h: CGFloat = 15
        let rect = NSRect(x: leftEdge, y: bounds.midY - h / 2,
                          width: textSize.width + padH * 2, height: h)
        let bg = highlighted ? NSColor.white.withAlphaComponent(0.25) : pill.color.withAlphaComponent(0.22)
        bg.setFill()
        NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
        NSString(string: pill.text).draw(
            at: NSPoint(x: rect.minX + padH, y: rect.midY - textSize.height / 2), withAttributes: attrs)
        return rect.maxX
    }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }

    override func mouseExited(with event: NSEvent) {
        hoveringClose = false
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let over = closeRect.contains(convert(event.locationInWindow, from: nil))
        guard over != hoveringClose else { return }
        hoveringClose = over
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hitClose = closeRect.contains(point)
        // Dismiss the menu first either way — the confirmation is a modal alert
        // and can't come up while the menu owns the event loop.
        enclosingMenuItem?.menu?.cancelTracking()
        if hitClose { onClose() } else { onClick() }
    }
}
