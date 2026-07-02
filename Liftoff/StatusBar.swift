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

        let header = NSMenuItem(title: "Liftoff", action: nil, keyEquivalent: "")
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
        let barColor = (store.tagColor(for: project.folder).map { NSColor($0) }) ?? .secondaryLabelColor
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

        let view = ProjectMenuItemView(
            name: project.name,
            subtitle: "\(tabs) tab\(tabs == 1 ? "" : "s")",
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
