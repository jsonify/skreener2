import AppKit

/// Editors shown as tabs of one window. Each editor keeps its own window; the group shows one at a time, in the same
/// frame, and every window draws the group's side dock of thumbnails (#140). Used instead of AppKit's window tabs,
/// whose tab bar can't be restyled.
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

    /// Redraws the dock of every editor window, e.g. after it was hidden or moved to the other side.
    static func refreshAll() {
        var done: [EditorTabGroup] = []
        for e in EditorWindowController.live where !done.contains(where: { $0 === e.tabGroup }) {
            done.append(e.tabGroup)
            e.tabGroup.refresh()
        }
    }

    /// Redraws every window's dock.
    func refresh() {
        // A window holding one screenshot shows no dock, so it needs no thumbnail.
        let several = editors.count > 1
        let items = editors.map { EditorDock.Item(title: $0.window?.title ?? "", thumbnail: several ? $0.dockThumbnail : NSImage()) }
        let index = editors.firstIndex { $0 === selected } ?? 0
        for e in editors { e.showTabs(items, selected: index) }
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
    /// Each tab is its own window, so switching tabs orders one in; without this macOS plays its "window opens" zoom
    /// every time. Settings → Annotate can bring the zoom back.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        animationBehavior = Preferences.windowAnimation
        super.makeKeyAndOrderFront(sender)
    }
    // Window → Show / Hide Screenshots (⌃⌘S, #140)
    @objc func toggleScreenshotDock(_ sender: Any?) { (windowController as? EditorWindowController)?.toggleDock() }
    // Image → Combine Screenshots… (#273)
    @objc func combineScreenshots(_ sender: Any?) { (windowController as? EditorWindowController)?.combineScreenshots() }
    // File → Save / Save As… (#118)
    @objc func saveScreenshot(_ sender: Any?) { (windowController as? EditorWindowController)?.saveScreenshot() }
    @objc func saveScreenshotAs(_ sender: Any?) { (windowController as? EditorWindowController)?.saveScreenshotAs() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)), #selector(moveTabToNewWindow(_:)):
            return (group?.editors.count ?? 0) > 1
        case #selector(mergeAllWindows(_:)):
            return EditorWindowController.live.contains { $0.tabGroup !== group }
        case #selector(toggleScreenshotDock(_:)):
            let open = (windowController as? EditorWindowController)?.isDockOpen == true
            item.title = open ? "Hide Screenshots" : "Show Screenshots"
            return (group?.editors.count ?? 0) > 1
        default:
            return super.validateMenuItem(item)
        }
    }
}

/// The side dock of open screenshots (#140): a thumbnail per editor in the group, the one showing outlined in the
/// accent color. Click one to show it; the × on hover or a middle click closes it; right-click for more. The button
/// in its header collapses it (the footer's dock button brings it back).
final class EditorDock: NSView {
    struct Item {
        var title: String
        var thumbnail: NSImage
    }

    static let width: CGFloat = 148

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onCollapse: (() -> Void)?
    var menuForItem: ((Int) -> NSMenu?)?

    private let header = NSTextField(labelWithString: "")
    private let collapseButton = NSButton()
    private let scroll = NSScrollView()
    private let list = NSStackView()
    private let edge = NSBox()
    private var edgeLeading: NSLayoutConstraint?
    private var edgeTrailing: NSLayoutConstraint?
    private var pinLeading: NSLayoutConstraint?
    private var pinTrailing: NSLayoutConstraint?
    private var views: [DockItemView] = []
    private var selected = -1

    /// Which side of the window the dock is on: the separator goes on the side facing the canvas.
    var onRight = false {
        didSet {
            edgeLeading?.isActive = onRight
            edgeTrailing?.isActive = !onRight
            pinLeading?.isActive = !onRight
            pinTrailing?.isActive = onRight
            collapseButton.image = Self.symbol(onRight ? "sidebar.right" : "sidebar.left")
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .withinWindow
        background.state = .followsWindowActiveState

        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingTail
        collapseButton.image = Self.symbol("sidebar.left")
        collapseButton.isBordered = false
        collapseButton.contentTintColor = .secondaryLabelColor
        collapseButton.toolTip = "Hide Screenshots (⌃⌘S)"
        collapseButton.setAccessibilityLabel("Hide Screenshots")
        collapseButton.target = self
        collapseButton.action = #selector(collapse)

        list.orientation = .vertical
        list.alignment = .centerX
        list.spacing = 10
        list.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        let doc = FlippedView()
        doc.addSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        edge.boxType = .separator
        // Clips while the dock's width animates to and from zero.
        wantsLayer = true
        layer?.masksToBounds = true

        [background, header, collapseButton, scroll, edge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        edgeLeading = edge.leadingAnchor.constraint(equalTo: leadingAnchor)
        edgeTrailing = edge.trailingAnchor.constraint(equalTo: trailingAnchor)
        edgeTrailing?.isActive = true
        // Laid out at full width and pinned to the side facing away from the canvas, so collapsing slides it away
        // instead of squeezing it.
        let content = NSLayoutGuide()
        addLayoutGuide(content)
        pinLeading = content.leadingAnchor.constraint(equalTo: leadingAnchor)
        pinTrailing = content.trailingAnchor.constraint(equalTo: trailingAnchor)
        pinLeading?.isActive = true
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
            edge.topAnchor.constraint(equalTo: topAnchor), edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            header.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: collapseButton.leadingAnchor, constant: -6),
            collapseButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            collapseButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            collapseButton.widthAnchor.constraint(equalToConstant: 22), collapseButton.heightAnchor.constraint(equalToConstant: 22),
            scroll.topAnchor.constraint(equalTo: collapseButton.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            list.topAnchor.constraint(equalTo: doc.topAnchor),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `items`, `selected` outlined. The item views are kept when the count stays the same, so an updated
    /// thumbnail doesn't reset the scroll position or the hover.
    func show(_ items: [Item], selected: Int) {
        header.stringValue = items.count == 1 ? "1 Screenshot" : "\(items.count) Screenshots"
        if views.count != items.count {
            views.forEach { $0.removeFromSuperview() }
            views = items.indices.map { i in
                let v = DockItemView(frame: .zero)
                v.onClick = { [weak self] in self?.onSelect?(i) }
                v.onClose = { [weak self] in self?.onClose?(i) }
                v.menuProvider = { [weak self] in self?.menuForItem?(i) }
                list.addArrangedSubview(v)
                return v
            }
        }
        for (v, item) in zip(views, items) { v.update(item) }
        for (i, v) in views.enumerated() { v.isSelected = i == selected }
        if selected != self.selected, views.indices.contains(selected) {
            layoutSubtreeIfNeeded()
            views[selected].scrollToVisible(views[selected].bounds.insetBy(dx: 0, dy: -10))
        }
        self.selected = selected
    }

    @objc private func collapse() { onCollapse?() }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    }
}

/// One screenshot in the dock: its thumbnail (outlined in the accent color while it is the one showing) with its title
/// under it, and a close button in the corner while the pointer is over it.
private final class DockItemView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var isSelected = false { didSet { applyState() } }

    private static let thumbSize = NSSize(width: 120, height: 80)
    private let frameView = NSView()
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var hovering = false { didSet { applyState() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = 7
        frameView.layer?.cornerCurve = .continuous
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor(white: 0.15, alpha: 0.85)]))
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(config)
        closeButton.isBordered = false
        closeButton.toolTip = "Close"
        closeButton.target = self
        closeButton.action = #selector(closeItem)

        [frameView, label, closeButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        frameView.addSubview(imageView)
        let t = Self.thumbSize
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: t.width + 8),
            frameView.topAnchor.constraint(equalTo: topAnchor),
            frameView.leadingAnchor.constraint(equalTo: leadingAnchor),
            frameView.trailingAnchor.constraint(equalTo: trailingAnchor),
            frameView.heightAnchor.constraint(equalToConstant: t.height + 8),
            imageView.topAnchor.constraint(equalTo: frameView.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor, constant: -4),
            imageView.leadingAnchor.constraint(equalTo: frameView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: frameView.bottomAnchor, constant: 3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: -2),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -2),
            closeButton.widthAnchor.constraint(equalToConstant: 20), closeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        applyState()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ item: EditorDock.Item) {
        imageView.image = item.thumbnail
        label.stringValue = item.title
        toolTip = item.title
        setAccessibilityLabel(item.title)
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
        closeButton.isHidden = !hovering
        setAccessibilitySelected(isSelected)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            frameView.layer?.backgroundColor = (hovering && !isSelected ? NSColor.labelColor.withAlphaComponent(0.06) : .clear).cgColor
            frameView.layer?.borderWidth = isSelected ? 2.5 : 0
            frameView.layer?.borderColor = NSColor.controlAccentColor.cgColor
            imageView.layer?.borderWidth = 0.5
            imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.font = .systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular)
    }

    @objc private func closeItem() { onClose?() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
