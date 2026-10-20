import AppKit

/// Editors shown as tabs of one window. Each editor keeps its own window; the group shows one at a time, in the same
/// frame, and every window draws the group's tab row (pill tabs on a dark capsule, like the scrolling-capture bar).
/// Used instead of AppKit's window tabs, whose tab bar can't be restyled.
@MainActor final class EditorTabGroup {
    private(set) var editors: [EditorWindowController]
    private(set) weak var selected: EditorWindowController?

    init(_ editor: EditorWindowController) {
        editors = [editor]
        selected = editor
    }

    /// Adds `editor` right after `neighbor` (or at the end) and shows it in place of the current tab.
    func add(_ editor: EditorWindowController, after neighbor: EditorWindowController? = nil) {
        let i = neighbor.flatMap { n in editors.firstIndex { $0 === n } }.map { $0 + 1 } ?? editors.count
        editors.insert(editor, at: i)
        editor.tabGroup = self
        select(editor)
    }

    /// Shows `editor`'s window where the current tab's window is and hides the others.
    func select(_ editor: EditorWindowController) {
        guard let w = editor.window, editors.contains(where: { $0 === editor }) else { return }
        if let shown = selected?.window, shown !== w { w.setFrame(shown.frame, display: false) }
        selected = editor
        w.makeKeyAndOrderFront(nil)
        for other in editors where other !== editor { other.window?.orderOut(nil) }
        refresh()
    }

    func select(offset: Int) {
        guard editors.count > 1, let s = selected, let i = editors.firstIndex(where: { $0 === s }) else { return }
        select(editors[(i + offset + editors.count) % editors.count])
    }

    /// Takes `editor` out of the group (it closed or moved to its own window); if it was showing, the tab next to it
    /// takes its place.
    func remove(_ editor: EditorWindowController) {
        guard let i = editors.firstIndex(where: { $0 === editor }) else { return }
        editors.remove(at: i)
        if selected === editor, !editors.isEmpty {
            let next = editors[min(i, editors.count - 1)]
            if let from = editor.window, let w = next.window { w.setFrame(from.frame, display: false) }
            selected = nil
            select(next)
        }
        refresh()
    }

    /// Moves `editor` out into a window of its own, a little offset from where it was.
    func moveToNewWindow(_ editor: EditorWindowController) {
        guard editors.count > 1, let w = editor.window else { return }
        let frame = w.frame
        remove(editor)
        editor.tabGroup = EditorTabGroup(editor)
        editor.tabGroup.refresh()
        w.setFrame(frame.offsetBy(dx: 30, dy: -30), display: false)
        w.makeKeyAndOrderFront(nil)
    }

    /// Brings every open editor into this group, keeping the current tab showing.
    func mergeAll() {
        for e in EditorWindowController.live where e.tabGroup !== self {
            e.window?.orderOut(nil)
            e.tabGroup = self
            editors.append(e)
        }
        if let s = selected { select(s) }
    }

    /// Redraws every window's tab row.
    func refresh() {
        let titles = editors.map { $0.window?.title ?? "" }
        let index = editors.firstIndex { $0 === selected } ?? 0
        for e in editors { e.showTabs(titles, selected: index) }
    }
}

/// The editor's window: the Window menu's tab commands act on its `EditorTabGroup`.
final class EditorWindow: NSWindow {
    private var group: EditorTabGroup? { (windowController as? EditorWindowController)?.tabGroup }

    override func selectNextTab(_ sender: Any?) { group?.select(offset: 1) }
    override func selectPreviousTab(_ sender: Any?) { group?.select(offset: -1) }
    override func moveTabToNewWindow(_ sender: Any?) {
        if let e = windowController as? EditorWindowController { group?.moveToNewWindow(e) }
    }
    override func mergeAllWindows(_ sender: Any?) { group?.mergeAll() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)), #selector(moveTabToNewWindow(_:)):
            return (group?.editors.count ?? 0) > 1
        case #selector(mergeAllWindows(_:)):
            return EditorWindowController.live.contains { $0.tabGroup !== group }
        default:
            return super.validateMenuItem(item)
        }
    }
}

/// The row of editor tabs: a dark capsule holding a pill per tab, the one showing filled with the accent colour.
/// Click a tab to show it; its × or a middle click closes it; right-click for more.
final class EditorTabStrip: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var menuForTab: ((Int) -> NSMenu?)?

    private let capsule = NSView()
    private let row = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        capsule.wantsLayer = true
        capsule.appearance = NSAppearance(named: .darkAqua)
        capsule.layer?.backgroundColor = PillButton.barColor.cgColor
        capsule.layer?.cornerCurve = .continuous
        capsule.layer?.borderWidth = 0.5
        capsule.layer?.borderColor = PillButton.barBorderColor.cgColor
        capsule.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)
        capsule.addSubview(row)
        NSLayoutConstraint.activate([
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsule.heightAnchor.constraint(equalToConstant: 40),
            capsule.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            capsule.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 5),
            row.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -5),
            row.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        capsule.layer?.cornerRadius = capsule.bounds.height / 2
    }

    func show(_ titles: [String], selected: Int) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, title) in titles.enumerated() {
            let tab = TabPill(title: title, selected: i == selected)
            tab.onClick = { [weak self] in self?.onSelect?(i) }
            tab.onClose = { [weak self] in self?.onClose?(i) }
            tab.menuProvider = { [weak self] in self?.menuForTab?(i) }
            row.addArrangedSubview(tab)
        }
    }
}

/// One tab: a pill with the editor's title and a close button (shown on the current tab, and on the others while the
/// pointer is over them).
private final class TabPill: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let selected: Bool
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var hovering = false { didSet { applyState() } }

    init(title: String, selected: Bool) {
        self.selected = selected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilitySelected(selected)

        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?.withSymbolConfiguration(config)
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.toolTip = "Close Tab"
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(closeButton)
        let preferred = widthAnchor.constraint(equalToConstant: 200)
        preferred.priority = .defaultHigh
        let minimum = widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        minimum.priority = .init(700)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            preferred, minimum,
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
            // Centered, with as much room on the right as the close button takes on the left.
            label.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyState()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) { onClose?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyState()
    }

    private func applyState() {
        closeButton.isHidden = !selected && !hovering
        let base: NSColor = selected ? .controlAccentColor : PillButton.tintColor
        let fill = !selected && hovering ? base.withAlphaComponent(0.26) : base
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
        }
        label.textColor = selected ? .white : NSColor.white.withAlphaComponent(0.85)
    }

    @objc private func closeTab() { onClose?() }
}
