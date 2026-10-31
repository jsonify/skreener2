import AppKit

/// An SK-1 button (#344; see `Retro`): an SF Symbol and/or a title on a key, a toggle, a round key or an LCD chip,
/// drawn in the retro palette. `isOn` presses a key down with its orange bar (the current tool) or lights a toggle.
class PillButton: NSButton {
    enum Style {
        /// An SK-1 key: a raised face on a 2 pt skirt, cream, orange or charcoal (`keyVariant`), usually on a
        /// `KeycapTray`. `isOn` presses it down with a glowing orange bar (the current tool); `legend` puts its key in
        /// the top left corner. A symbol-only key is square.
        case keycap
        /// An SK-1 toggle: a small square, orange while `isOn`, and the title in capitals.
        case toggle
        /// A small round cream key, for a symbol (a stepper's arrows, a colour swatch).
        case round
        /// A small olive LCD readout showing the title in mono (`PillPopUp`'s chip).
        case lcd
    }

    /// Space between the symbol and the title, the same on every pill button. The symbol and title are laid out
    /// here rather than by the button cell, whose own spacing is wider and varies with the content.
    static let iconGap: CGFloat = 5
    /// A `.keycap`'s corner radius.
    static let keycapRadius: CGFloat = 6
    /// The skirt under a `.keycap` (and half of it under a `.round`).
    static let keycapSkirt: CGFloat = 2

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let content = NSStackView()
    private let run: () -> Void
    fileprivate let style: Style
    fileprivate let height: CGFloat
    fileprivate var pressed = false { didSet { applyColors() } }
    private var widthConstraint: NSLayoutConstraint?
    private var contentCenterY: NSLayoutConstraint?
    private var contentCenterX: NSLayoutConstraint?
    private var titleText: String?
    /// Room either side of the face for views a subclass adds (`PillPopUp`'s stepper arrows).
    fileprivate var accessoryInsets: (leading: CGFloat, trailing: CGFloat) = (0, 0) { didSet { updateWidth() } }
    /// Keeps a subclass's leading accessory just after the caption.
    fileprivate var leadingAccessory: NSLayoutConstraint?

    var isOn = false {
        didSet {
            applyColors()
            if style == .toggle { setAccessibilityValue(isOn ? 1 : 0) }
        }
    }
    /// A `.keycap`'s colours: cream (the usual key), orange (the main action) or charcoal (Settings).
    var keyVariant = Retro.KeyVariant.cream { didSet { applyColors() } }
    /// A `.keycap`'s key, in small type in its top left corner (e.g. "R" for Rectangle).
    var legend: String? { didSet { needsDisplay = true } }
    /// A caption in small capitals to the left of the button (e.g. "Stroke"), part of the button so it hides with it.
    var caption: String? { didSet { updateWidth(); needsDisplay = true } }
    /// SK-1 titles are in capitals unless this is set (e.g. "Aa").
    var keepsCase = false { didSet { refreshLabel(); updateWidth() } }
    /// A small ▾ after the content, for buttons that open a menu. A symbol-only `.keycap` shows a corner triangle instead.
    var showsChevron = false {
        didSet { updateWidth() }
    }

    /// Tools with variants (Rectangle, Arrow): a small triangle in the corner. A long press, or a click on the
    /// triangle, opens this menu; a plain click still picks the tool.
    var variantMenu: (() -> NSMenu?)? {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }

    /// `height` 30 is the floating bars' key; the editor uses smaller ones.
    init(title: String?, symbol: String?, style: Style = .keycap, height: CGFloat = 30, run: @escaping () -> Void = {}) {
        self.run = run
        self.style = style
        self.height = height
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.cornerCurve = .continuous
        switch style {
        case .keycap: label.font = .systemFont(ofSize: 10, weight: .bold)
        case .toggle: label.font = .systemFont(ofSize: 9.5, weight: .bold)
        case .lcd: label.font = Retro.mono(10, weight: .bold)
        case .round: label.font = .systemFont(ofSize: 10, weight: .bold)
        }
        label.lineBreakMode = .byTruncatingTail
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(chevronConfig)
        chevron.isHidden = true
        content.addArrangedSubview(icon)
        content.addArrangedSubview(label)
        content.addArrangedSubview(chevron)
        content.spacing = Self.iconGap
        content.setCustomSpacing(3, after: label)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        contentCenterX = content.centerXAnchor.constraint(equalTo: centerXAnchor)
        contentCenterX?.isActive = true
        contentCenterY = content.centerYAnchor.constraint(equalTo: centerYAnchor)
        contentCenterY?.isActive = true
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        if style == .toggle {
            setAccessibilityRole(.checkBox)
            setAccessibilityValue(0)
        }
        setContent(title: title, symbol: symbol)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setContent(title: String?, symbol: String?) {
        let config: NSImage.SymbolConfiguration
        switch style {
        case .keycap: config = NSImage.SymbolConfiguration(pointSize: height >= 28 ? 13 : 11, weight: .semibold)
        case .round: config = NSImage.SymbolConfiguration(pointSize: max(7, height * 0.38), weight: .bold)
        case .toggle, .lcd: config = NSImage.SymbolConfiguration(pointSize: height >= 30 ? 12 : 11, weight: height >= 30 ? .bold : .semibold)
        }
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title)?.withSymbolConfiguration(config) }
        setContent(title: title, image: image)
    }

    /// `image` may be a template symbol (drawn white) or a picture such as a colour swatch.
    func setContent(title: String?, image: NSImage?) {
        icon.image = image
        icon.isHidden = image == nil   // the stack leaves hidden views out, gap included
        titleText = title
        refreshLabel()
        label.isHidden = title == nil
        // The chevron sits close to a symbol, a little further from a title.
        content.setCustomSpacing(title == nil ? 2 : Self.iconGap, after: icon)
        setAccessibilityLabel(title ?? toolTip)
        updateWidth()
    }

    /// The title in the style's type and the content colour.
    private func refreshLabel() {
        let text = titleText ?? ""
        let color = label.textColor ?? .labelColor
        let font = label.font ?? Retro.captionFont
        switch style {
        case .lcd:
            label.attributedStringValue = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: 0.5])
        default:
            label.attributedStringValue = NSAttributedString(string: keepsCase ? text : text.uppercased(),
                                                             attributes: [.font: font, .foregroundColor: color, .kern: 0.6])
        }
    }

    /// A symbol-only `.keycap` that opens a menu shows the corner triangle rather than a chevron.
    private var triangleForChevron: Bool { style == .keycap && showsChevron && label.isHidden }
    fileprivate var showsTriangle: Bool { variantMenu != nil || triangleForChevron }

    /// Space the caption takes at the left, gap included.
    private var captionSpace: CGFloat {
        guard let caption, !caption.isEmpty else { return 0 }
        return ceil(Retro.caption(caption, color: .black).size().width) + 7
    }

    /// Where the button itself is drawn: all of it but the caption and any accessories.
    fileprivate var faceRect: NSRect {
        let left = captionSpace + accessoryInsets.leading
        return NSRect(x: left, y: 0, width: max(bounds.width - left - accessoryInsets.trailing, 0), height: bounds.height)
    }

    private func updateWidth() {
        chevron.isHidden = !showsChevron || triangleForChevron
        widthConstraint?.isActive = false
        let fit = ceil(content.fittingSize.width)
        let face: CGFloat
        switch style {
        case .keycap: face = label.isHidden && chevron.isHidden ? height - Self.keycapSkirt : fit + 20
        case .round: face = height
        case .toggle: face = fit + 15
        case .lcd: face = max(fit + 14, 44)
        }
        let left = captionSpace + accessoryInsets.leading, right = accessoryInsets.trailing
        widthConstraint = widthAnchor.constraint(equalToConstant: face + left + right)
        widthConstraint?.isActive = true
        // The content sits in the middle of the face (after a toggle's square).
        contentCenterX?.constant = (left - right) / 2 + (style == .toggle ? 7.5 : 0)
        leadingAccessory?.constant = captionSpace
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    /// The layer shadow follows the key: its whole body when up, the face alone (half as far down) when pressed.
    private func updateShadowPath() {
        let face = faceRect
        guard face.width > 1, face.height > 1 else { layer?.shadowPath = nil; return }
        switch style {
        case .keycap:
            let down = pressed || isOn
            let rect = down ? face.insetBy(dx: 0, dy: Self.keycapSkirt / 2) : face
            // CGPath takes no corner larger than half a side.
            let r = min(Self.keycapRadius, rect.width / 2, rect.height / 2)
            layer?.shadowPath = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .round:
            let d = min(face.width, face.height)
            layer?.shadowPath = CGPath(ellipseIn: NSRect(x: face.midX - d / 2, y: face.midY - d / 2, width: d, height: d), transform: nil)
        default:
            layer?.shadowPath = nil
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks on the symbol or title belong to the button. A hidden pill takes no clicks: its frame can still overlap
    /// a visible neighbour in a stack view.
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        if isEnabled, variantMenu != nil, openVariants(for: event) { return }
        pressed = true
        super.mouseDown(with: event)   // tracks the click until the button is released
        pressed = false
    }

    /// Shows the variants menu for a press on the corner triangle, or one held for 0.4 s. True if it did.
    private func openVariants(for event: NSEvent) -> Bool {
        guard let menu = variantMenu?() else { return false }
        let p = convert(event.locationInWindow, from: nil)
        let inCorner = p.x > bounds.width - 12 && (isFlipped ? p.y > bounds.height - 12 : p.y < 12)
        if !inCorner {
            let release = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: Date(timeIntervalSinceNow: 0.4),
                                            inMode: .eventTracking, dequeue: false)
            if release != nil { return false }
        }
        pressed = true
        _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), in: self)
        pressed = false
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawFace()
        super.draw(dirtyRect)
        if showsTriangle { drawKeyTriangle() }
    }

    /// The caption, then the key, toggle square, round key or LCD chip.
    private func drawFace() {
        let p = Retro.palette(for: self)
        if let caption, !caption.isEmpty {
            let text = Retro.caption(caption, color: Retro.color(p.ink))
            text.draw(at: NSPoint(x: 0, y: (bounds.height - text.size().height) / 2))
        }
        let face = faceRect
        switch style {
        case .keycap:
            let c = Retro.keyColors(keyVariant, p)
            let top = Retro.drawKey(in: face, radius: Self.keycapRadius, colors: c, down: pressed || isOn, flipped: isFlipped)
            if isOn, keyVariant == .cream { Retro.drawOnBar(in: top, flipped: isFlipped) }
            if let legend, !legend.isEmpty {
                let text = NSAttributedString(string: legend, attributes: [.font: Retro.mono(7.5, weight: .bold), .foregroundColor: c.legend])
                let size = text.size()
                text.draw(at: NSPoint(x: top.minX + 3, y: isFlipped ? top.minY + 1.5 : top.maxY - 1.5 - size.height))
            }
        case .round:
            let d = min(face.width, face.height)
            let body = NSRect(x: face.midX - d / 2, y: face.midY - d / 2, width: d, height: d)
            Retro.drawKey(in: body, radius: (d - 1) / 2, colors: Retro.keyColors(.cream, p), down: pressed, skirt: 1, flipped: isFlipped)
        case .toggle:
            let square = NSRect(x: face.minX + 1, y: (bounds.height - 9) / 2, width: 9, height: 9)
            Retro.drawToggleSquare(square, on: isOn, palette: p, flipped: isFlipped)
        case .lcd:
            let h = min(face.height, 20)
            let chip = NSRect(x: face.minX, y: face.midY - h / 2, width: face.width, height: h)
            Retro.drawChipGlass(chip, radius: 3, brightness: p.lcdBrightness * (pressed ? 0.94 : 1), flipped: isFlipped)
        }
    }

    /// The corner triangle of an SK-1 key that opens a menu, inside the face's lower right corner.
    private func drawKeyTriangle() {
        let down = pressed || isOn
        let face = style == .keycap ? Retro.keyFace(in: faceRect, down: down, flipped: isFlipped) : faceRect
        let right = face.maxX - 3, bottom = isFlipped ? face.maxY - 3 : face.minY + 3, up: CGFloat = isFlipped ? -4.5 : 4.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: right, y: bottom))
        path.line(to: NSPoint(x: right, y: bottom + up))
        path.line(to: NSPoint(x: right - 4.5, y: bottom))
        path.close()
        let p = Retro.palette(for: self)
        (style == .keycap ? Retro.keyColors(keyVariant, p).legend : Retro.color(p.inkSoft)).setFill()
        path.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// The ink, and the shadow a key or round key casts (none for a toggle or chip; the rest is drawn).
    private func applyColors() {
        needsDisplay = true   // the variants triangle follows the colors
        let p = Retro.palette(for: self)
        let ink: NSColor
        switch style {
        case .keycap: ink = Retro.keyColors(keyVariant, p).ink
        case .round: ink = Retro.color(p.keyInk)
        case .toggle: ink = Retro.color(isOn ? p.ink : p.inkSoft)
        case .lcd: ink = Retro.color(Retro.lcdInk)
        }
        icon.contentTintColor = ink
        label.textColor = ink
        refreshLabel()
        chevron.contentTintColor = ink.withAlphaComponent(0.6)
        let down = pressed || (style == .keycap && isOn)
        // The content sits on the face, above the skirt, and sinks with it when pressed.
        let skirt: CGFloat = style == .keycap ? Self.keycapSkirt : style == .round ? 1 : 0
        contentCenterY?.constant = down ? skirt / 2 : -skirt / 2
        layer?.backgroundColor = nil
        switch style {
        case .keycap:
            let c = Retro.keyColors(keyVariant, p)
            layer?.shadowColor = c.shadow.cgColor
            layer?.shadowOpacity = down ? c.shadowAlpha * 1.3 : c.shadowAlpha
            layer?.shadowRadius = down ? 1 : (keyVariant == .orange ? 3.5 : 2)
            layer?.shadowOffset = CGSize(width: 0, height: down ? -1 : -2)
        case .round:
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = pressed ? 0 : Float(p.dark ? 0.4 : 0.15)
            layer?.shadowRadius = 1
            layer?.shadowOffset = CGSize(width: 0, height: -1)
        default:
            layer?.shadowOpacity = 0
        }
        updateShadowPath()
    }

    @objc private func fire() { run() }
}

/// A pill that opens a menu, standing in for NSPopUpButton with the same calls (addItem, tags, selectedTag, its own
/// target/action). A pop-up shows the chosen item and sends its action when the choice changes; a pull-down
/// (`pullsDown`) shows its first item as the face and leaves the other items to their own actions.
///
/// With `stepper`, round arrows either side of the face step through the items (a pop-up: the one before or after,
/// sending the action; a pull-down: whatever `onStep` does), and a click on the face still opens the menu. In the
/// `.lcd` style that is the SK-1 stepper: ◀ LCD chip ▶.
final class PillPopUp: PillButton {
    let pullsDown: Bool
    private(set) var indexOfSelectedItem = -1
    /// The stepper's arrows, if it has them.
    private var arrows: [PillButton] = []
    /// What a pull-down's arrows do, with -1 or 1 (e.g. zoom out or in). A pop-up's arrows pick the item before or after.
    var onStep: ((Int) -> Void)?

    /// `stepSymbols` are the arrows' symbols, before and after.
    init(pullsDown: Bool, height: CGFloat = 26, style: Style = .keycap, stepper: Bool = false,
         stepSymbols: (String, String) = ("arrowtriangle.left.fill", "arrowtriangle.right.fill")) {
        self.pullsDown = pullsDown
        super.init(title: nil, symbol: nil, style: style, height: height)
        menu = NSMenu()
        showsChevron = !stepper
        if stepper { addArrows(stepSymbols) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func addArrows(_ symbols: (String, String)) {
        let size: CGFloat = 18, gap: CGFloat = 4
        let before = PillButton(title: nil, symbol: symbols.0, style: .round, height: size) { [weak self] in self?.step(-1) }
        let after = PillButton(title: nil, symbol: symbols.1, style: .round, height: size) { [weak self] in self?.step(1) }
        arrows = [before, after]
        for a in arrows { addSubview(a); a.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true }
        leadingAccessory = before.leadingAnchor.constraint(equalTo: leadingAnchor)
        leadingAccessory?.isActive = true
        after.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        accessoryInsets = (size + gap, size + gap)
        labelArrows()
    }

    override var toolTip: String? { didSet { labelArrows() } }

    private func labelArrows() {
        guard arrows.count == 2 else { return }
        let name = toolTip ?? caption ?? ""
        arrows[0].setAccessibilityLabel(name.isEmpty ? "Previous" : "\(name): previous")
        arrows[1].setAccessibilityLabel(name.isEmpty ? "Next" : "\(name): next")
    }

    /// One step back (-1) or on (1); see `stepper`.
    func step(_ by: Int) {
        guard isEnabled else { return }
        if let onStep { onStep(by); return }
        guard !pullsDown else { return }
        var i = indexOfSelectedItem + by
        while itemArray.indices.contains(i), !Self.choosable(itemArray[i]) { i += by }
        guard itemArray.indices.contains(i) else { NSSound.beep(); return }
        selectItem(at: i)
        sendAction(action, to: target)
    }

    private static func choosable(_ item: NSMenuItem) -> Bool {
        !item.isSeparatorItem && !item.isHidden && item.isEnabled
    }

    /// The arrows take their own clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let p = convert(point, from: superview)
        return arrows.first { !$0.isHidden && $0.frame.contains(p) } ?? hit
    }

    var itemArray: [NSMenuItem] { menu?.items ?? [] }
    var lastItem: NSMenuItem? { menu?.items.last }
    var selectedItem: NSMenuItem? { itemArray.indices.contains(indexOfSelectedItem) ? itemArray[indexOfSelectedItem] : nil }
    override func selectedTag() -> Int { selectedItem?.tag ?? -1 }

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
        _ = menu.popUp(positioning: nil, at: NSPoint(x: faceRect.minX, y: isFlipped ? bounds.height + 4 : -4), in: self)
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

/// An SK-1 tray: a sunken well holding a row of `.keycap` keys (the editor's toolbar), with an optional caption in
/// small capitals under it. The tray is as wide as its keys; a caption wider than that widens the whole, the well
/// staying centred over it.
final class KeycapTray: NSView {
    init(_ views: [NSView], caption: String? = nil, spacing: CGFloat = 3) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let well = Well()
        well.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(row)
        addSubview(well)
        // The keys' skirts fill the bottom of the well, so less room there.
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 5),
            row.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -5),
            row.topAnchor.constraint(equalTo: well.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: well.bottomAnchor, constant: -4),
            well.topAnchor.constraint(equalTo: topAnchor),
            well.centerXAnchor.constraint(equalTo: centerXAnchor),
            well.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        ])
        let snug = widthAnchor.constraint(equalToConstant: 0)
        snug.priority = NSLayoutConstraint.Priority(1)
        snug.isActive = true
        if let caption {
            let label = RetroLabel(caption: caption)
            label.setAccessibilityElement(false)   // the tray is labelled with it
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: well.bottomAnchor, constant: 5),
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            setAccessibilityLabel(caption)
        } else {
            well.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1).isActive = true
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The well, with its light lip under it.
    private final class Well: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let rect = NSRect(x: 0, y: isFlipped ? 0 : 1, width: bounds.width, height: bounds.height - 1)
            Retro.drawWell(rect, radius: PillButton.keycapRadius + 3, palette: Retro.palette(for: self), flipped: isFlipped)
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }
}

/// A small upright switch for a tray, like a hardware toggle: a little cream key with a symbol on it, which stays
/// down while it is on, and an LED under it that glows orange then. A click flips `state` and sends the action.
final class KeySwitch: NSButton {
    private let symbolName: String

    init(symbol: String, tip: String) {
        symbolName = symbol
        super.init(frame: .zero)
        setButtonType(.toggle)
        isBordered = false
        title = ""
        toolTip = tip
        setAccessibilityLabel(tip)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 20).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        let p = Retro.palette(for: self)
        // From the top: the key (20 pt with its skirt), a gap, the LED (4 pt).
        func y(_ fromTop: CGFloat, _ height: CGFloat) -> CGFloat { isFlipped ? fromTop : bounds.height - fromTop - height }
        let body = NSRect(x: 1, y: y(1, 21), width: bounds.width - 2, height: 21)
        let colors = Retro.keyColors(.cream, p)
        let face = Retro.drawKey(in: body, radius: 5, colors: colors, down: on || isHighlighted, flipped: isFlipped)

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [colors.ink]))
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = image.size
            image.draw(in: NSRect(x: face.midX - s.width / 2, y: face.midY - s.height / 2, width: s.width, height: s.height))
        }

        let led = NSRect(x: bounds.midX - 2, y: y(25, 4), width: 4, height: 4)
        if on {
            Retro.drawLamp(in: led, color: Retro.color(Retro.orange), lit: true)
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: led.insetBy(dx: 1.2, dy: 1.2)).fill()
        } else {
            let dot = NSBezierPath(ovalIn: led)
            Retro.color(p.toggleOff).setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            dot.lineWidth = 0.5
            dot.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A round SK-1 swatch showing the current colour. Clicking it offers a few colours and More Colors… (the colour
/// panel); a change goes to its target/action.
final class ColorPill: PillButton {
    var color: NSColor = .systemRed { didSet { setContent(title: nil, image: Self.dot(color)) } }
    /// The colours offered, here and on `SwatchRow`.
    static let presets: [(String, NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen),
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink), ("Black", .black), ("White", .white),
    ]

    init(size: CGFloat = 22) {
        super.init(title: nil, symbol: nil, style: .round, height: size)
        setContent(title: nil, image: Self.dot(color))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A filled circle with a hairline edge (so white shows on white).
    private static func dot(_ c: NSColor, size: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            c.setFill(); p.fill()
            NSColor.black.withAlphaComponent(0.3).setStroke(); p.lineWidth = 0.5; p.stroke()
            return true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSMenu()
        for (name, c) in Self.presets {
            let item = NSMenuItem(title: name, action: #selector(presetPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c
            item.image = Self.dot(c, size: 14)
            m.addItem(item)
        }
        m.addItem(.separator())
        let more = NSMenuItem(title: "More Colors…", action: #selector(showPanel), keyEquivalent: "")
        more.target = self
        m.addItem(more)
        pressed = true
        _ = m.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), in: self)
        pressed = false
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

/// Builders for the windows that take the SK-1 look (#344): the scratch pad, Step Guide, history panel, Combine,
/// Ask Claude, Watch This Area, the shortcut list, the tip popovers and the dialogs. They only wrap the kit
/// (`PillButton`, `KeycapTray`, `RetroLabel`, `ChassisView`); nothing here draws.
enum RetroUI {
    /// A symbol-only key: a 28 pt face on its 2 pt skirt.
    static let iconKeyHeight: CGFloat = 30
    /// A key with a title.
    static let textKeyHeight: CGFloat = 24

    /// A cream key (`variant`: orange for the main action, charcoal for a secondary one) with a title and/or a symbol.
    /// A symbol-only key is spoken as `tip`.
    static func key(_ title: String? = nil, symbol: String? = nil, tip: String? = nil,
                    variant: Retro.KeyVariant = .cream, height: CGFloat? = nil,
                    target: AnyObject? = nil, action: Selector? = nil) -> PillButton {
        let b = PillButton(title: title, symbol: symbol, style: .keycap, height: height ?? (title == nil ? iconKeyHeight : textKeyHeight))
        b.keyVariant = variant
        b.target = target
        b.action = action
        if let tip {
            b.toolTip = tip
            if title == nil { b.setAccessibilityLabel(tip) }
        }
        return b
    }

    /// An orange-square toggle; the handler flips `isOn` (a toggle doesn't flip itself).
    static func toggle(_ title: String, tip: String? = nil, isOn: Bool = false, height: CGFloat = 20,
                       target: AnyObject?, action: Selector?) -> PillButton {
        let b = PillButton(title: title, symbol: nil, style: .toggle, height: height)
        b.isOn = isOn
        b.target = target
        b.action = action
        if let tip { b.toolTip = tip }
        return b
    }

    /// Keys in a sunken tray with a caption under it.
    static func tray(_ caption: String?, _ keys: [NSView]) -> KeycapTray { KeycapTray(keys, caption: caption) }

    /// A pop-up as a cream key with a ▾, for a menu of choices that is too long for a segmented control.
    static func menuKey(tip: String, caption: String? = nil, target: AnyObject?, action: Selector?) -> PillPopUp {
        let p = PillPopUp(pullsDown: false, height: textKeyHeight, style: .keycap)
        p.caption = caption
        p.toolTip = tip
        p.target = target
        p.action = action
        return p
    }

    /// An LCD chip between ◀ ▶ that steps through its items, with an optional caption to its left.
    static func stepper(caption: String? = nil, tip: String? = nil, target: AnyObject?, action: Selector?) -> PillPopUp {
        let p = PillPopUp(pullsDown: false, height: textKeyHeight, style: .lcd, stepper: true)
        p.caption = caption
        p.toolTip = tip
        p.target = target
        p.action = action
        return p
    }

    /// Makes `window`'s content the chassis, with the title bar transparent over it. Returns the chassis, which the
    /// caller fills. The title stays in the title bar; lay content out from `contentTop(of:in:)`.
    static func useChassis(_ window: NSWindow) -> ChassisView {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        let chassis = ChassisView()
        window.contentView = chassis
        return chassis
    }

    /// The top of the area below the title bar (the content's top for a window without one, e.g. a sheet).
    static func contentTop(of window: NSWindow, in content: NSView) -> NSLayoutYAxisAnchor {
        (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
    }

    /// Plain secondary text (a hint, a count) in the soft ink.
    static func hint(_ text: String = "", size: CGFloat = 11, wraps: Bool = false) -> RetroLabel {
        let l = RetroLabel(text: text, tone: .soft, size: size)
        if wraps {
            l.lineBreakMode = .byWordWrapping
            l.maximumNumberOfLines = 0
            l.cell?.wraps = true
        }
        return l
    }
}

extension PillPopUp {
    /// `NSPopUpButton.addItems(withTitles:)`.
    func addItems(withTitles titles: [String]) { titles.forEach { addItem(withTitle: $0) } }

    /// `NSPopUpButton.removeAllItems()`.
    func removeAllItems() {
        menu?.removeAllItems()
        selectItem(at: -1)
    }
}
