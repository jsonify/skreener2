import AppKit

/// A capsule button in the style of iOS: filled with the accent colour, or a translucent tint over the dark bar; an
/// SF Symbol and/or a title (a symbol alone makes it a circle). Dims while pressed. `isOn` fills a tinted button with
/// the accent colour too, for the current tool or a toggle that is on.
class PillButton: NSButton {
    enum Style { case filled, tinted }

    /// Space between the symbol and the title, the same on every pill button. The symbol and title are laid out
    /// here rather than by the button cell, whose own spacing is wider and varies with the content.
    static let iconGap: CGFloat = 5
    /// The dark capsule the buttons sit on (the scrolling-capture bar, the editor's bars and tab row).
    static let barColor = NSColor(white: 0.12, alpha: 0.94)
    static let barBorderColor = NSColor.white.withAlphaComponent(0.15)
    /// The `.tinted` fill: a translucent white over the dark bar.
    static let tintColor = NSColor.white.withAlphaComponent(0.16)

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let content = NSStackView()
    private let run: () -> Void
    private let style: Style
    private let height: CGFloat
    fileprivate var pressed = false { didSet { applyColors() } }
    private var widthConstraint: NSLayoutConstraint?

    var isOn = false { didSet { applyColors() } }
    /// A small ▾ after the content, for buttons that open a menu.
    var showsChevron = false {
        didSet { chevron.isHidden = !showsChevron; updateWidth() }
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }

    /// `height` 30 is the scrolling-capture bar's size; the editor uses smaller pills.
    init(title: String?, symbol: String?, style: Style = .tinted, height: CGFloat = 30, run: @escaping () -> Void = {}) {
        self.run = run
        self.style = style
        self.height = height
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.cornerCurve = .continuous
        icon.contentTintColor = .white
        label.font = .systemFont(ofSize: height >= 30 ? 13 : 12, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(chevronConfig)
        chevron.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        chevron.isHidden = true
        content.addArrangedSubview(icon)
        content.addArrangedSubview(label)
        content.addArrangedSubview(chevron)
        content.spacing = Self.iconGap
        content.setCustomSpacing(3, after: label)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        content.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        content.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setContent(title: title, symbol: symbol)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setContent(title: String?, symbol: String?) {
        let config = NSImage.SymbolConfiguration(pointSize: height >= 30 ? 12 : 11, weight: height >= 30 ? .bold : .semibold)
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title)?.withSymbolConfiguration(config) }
        setContent(title: title, image: image)
    }

    /// `image` may be a template symbol (drawn white) or a picture such as a colour swatch.
    func setContent(title: String?, image: NSImage?) {
        icon.image = image
        icon.isHidden = image == nil   // the stack leaves hidden views out, gap included
        label.stringValue = title ?? ""
        label.isHidden = title == nil
        // The chevron sits close to a symbol, a little further from a title.
        content.setCustomSpacing(title == nil ? 2 : Self.iconGap, after: icon)
        setAccessibilityLabel(title ?? toolTip)
        updateWidth()
    }

    private func updateWidth() {
        widthConstraint?.isActive = false
        // A circle when there is only a symbol; otherwise room either side of the content.
        let circle = label.isHidden && chevron.isHidden
        let pad: CGFloat = height >= 30 ? 28 : (label.isHidden ? 16 : 22)
        widthConstraint = widthAnchor.constraint(equalToConstant: circle ? height : ceil(content.fittingSize.width) + pad)
        widthConstraint?.isActive = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks on the symbol or title belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)   // tracks the click until the button is released
        pressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        let base: NSColor = style == .filled || isOn ? .controlAccentColor : Self.tintColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (pressed ? base.blended(withFraction: 0.3, of: .black) ?? base : base).cgColor
        }
    }

    @objc private func fire() { run() }
}

/// A pill that opens a menu, standing in for NSPopUpButton with the same calls (addItem, tags, selectedTag, its own
/// target/action). A pop-up shows the chosen item and sends its action when the choice changes; a pull-down
/// (`pullsDown`) shows its first item as the face and leaves the other items to their own actions.
final class PillPopUp: PillButton {
    let pullsDown: Bool
    private(set) var indexOfSelectedItem = -1

    init(pullsDown: Bool, height: CGFloat = 26) {
        self.pullsDown = pullsDown
        super.init(title: nil, symbol: nil, height: height)
        menu = NSMenu()
        showsChevron = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var itemArray: [NSMenuItem] { menu?.items ?? [] }
    var lastItem: NSMenuItem? { menu?.items.last }
    var selectedItem: NSMenuItem? { itemArray.indices.contains(indexOfSelectedItem) ? itemArray[indexOfSelectedItem] : nil }
    func selectedTag() -> Int { selectedItem?.tag ?? -1 }

    func addItem(withTitle title: String) {
        let item = NSMenuItem(title: title, action: pullsDown ? nil : #selector(picked(_:)), keyEquivalent: "")
        if !pullsDown { item.target = self }
        menu?.addItem(item)
        if !pullsDown, indexOfSelectedItem < 0 { indexOfSelectedItem = itemArray.count - 1 }
        synchronizeTitleAndSelectedItem()
    }

    func selectItem(at index: Int) {
        indexOfSelectedItem = itemArray.indices.contains(index) ? index : -1
        synchronizeTitleAndSelectedItem()
    }

    func selectItem(withTag tag: Int) {
        selectItem(at: itemArray.firstIndex { $0.tag == tag && !$0.isSeparatorItem } ?? -1)
    }

    /// Shows the first item (a pull-down) or the chosen one on the button.
    func synchronizeTitleAndSelectedItem() {
        let face = pullsDown ? itemArray.first : selectedItem
        let title = face?.title ?? ""
        setContent(title: title.isEmpty ? nil : title, image: face?.image)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let menu else { return }
        if pullsDown {
            menu.items.first?.isHidden = true
        } else {
            for (i, item) in menu.items.enumerated() { item.state = i == indexOfSelectedItem ? .on : .off }
        }
        pressed = true
        _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), in: self)
        pressed = false
    }

    /// The menu opens from a click, not from a right-click.
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    @objc private func picked(_ item: NSMenuItem) {
        guard let i = menu?.index(of: item), i >= 0 else { return }
        selectItem(at: i)
        sendAction(action, to: target)
    }
}

/// The dark capsule pill buttons sit on, like the scrolling-capture bar: its views in a row, inset from the edges.
final class PillBar: NSView {
    let row = NSStackView()

    init(_ views: [NSView], spacing: CGFloat = 2, inset: CGFloat = 3) {
        super.init(frame: .zero)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        layer?.backgroundColor = PillButton.barColor.cgColor
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = PillButton.barBorderColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        views.forEach(row.addArrangedSubview)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}

/// A round swatch of the current colour. Clicking it offers a few colours and More Colors… (the colour panel); a
/// change goes to its target/action.
final class ColorPill: NSButton {
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    private static let presets: [(String, NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen),
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink), ("Black", .black), ("White", .white),
    ]

    init(size: CGFloat = 26) {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        PillButton.tintColor.setFill(); ring.fill()
        let dot = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5))
        color.setFill(); dot.fill()
        NSColor.white.withAlphaComponent(0.5).setStroke(); dot.lineWidth = 1; dot.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSMenu()
        for (name, c) in Self.presets {
            let item = NSMenuItem(title: name, action: #selector(presetPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c
            item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
                let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
                c.setFill(); p.fill()
                NSColor.separatorColor.setStroke(); p.stroke()
                return true
            }
            m.addItem(item)
        }
        m.addItem(.separator())
        let more = NSMenuItem(title: "More Colors…", action: #selector(showPanel), keyEquivalent: "")
        more.target = self
        m.addItem(more)
        _ = m.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), in: self)
    }

    @objc private func presetPicked(_ item: NSMenuItem) {
        guard let c = item.representedObject as? NSColor else { return }
        color = c
        sendAction(action, to: target)
    }

    @objc private func showPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(panelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func panelChanged(_ panel: NSColorPanel) {
        color = panel.color
        sendAction(action, to: target)
    }
}
