import AppKit

/// A capsule button: an SF Symbol and/or a title (a symbol alone makes it a circle). Dims while pressed. `isOn` fills
/// it with the accent colour, for the current tool or a toggle that is on.
class PillButton: NSButton {
    enum Style {
        /// Accent colour, white content: the main action.
        case filled
        /// Translucent white over the dark bar (the scrolling-capture bar).
        case tinted
        /// A white button with a soft shadow on the window background (a lighter grey in dark mode), like CleanShot's.
        case raised
        /// A rounded-square key with a lit face and a darker skirt under it, on a `KeycapTray` (the editor's toolbar).
        /// `isOn` lights it with the accent colour and a glow.
        case keycap
    }

    /// Space between the symbol and the title, the same on every pill button. The symbol and title are laid out
    /// here rather than by the button cell, whose own spacing is wider and varies with the content.
    static let iconGap: CGFloat = 5
    /// The dark capsule `.tinted` buttons sit on (the scrolling-capture bar; also the editor's toast).
    static let barColor = NSColor(white: 0.12, alpha: 0.94)
    static let barBorderColor = NSColor.white.withAlphaComponent(0.15)
    /// The `.tinted` fill: a translucent white over the dark bar.
    static let tintColor = NSColor.white.withAlphaComponent(0.16)
    /// The `.raised` fill.
    static func raisedColor(dark: Bool) -> NSColor { dark ? NSColor(white: 1, alpha: 0.13) : .white }
    /// A `.keycap`'s corner radius.
    static let keycapRadius: CGFloat = 6
    /// A `.keycap`'s symbol and title: dark on the grey key, in light and dark mode alike.
    static let keycapInk = NSColor(white: 0.13, alpha: 1)

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let content = NSStackView()
    private let run: () -> Void
    private let style: Style
    private let height: CGFloat
    fileprivate var pressed = false { didSet { applyColors() } }
    private var widthConstraint: NSLayoutConstraint?
    private var contentCenterY: NSLayoutConstraint?

    var isOn = false { didSet { applyColors() } }
    /// A `.keycap` with a coloured face of its own (Settings' orange key); `isOn` still lights it in the accent colour.
    var keycapTint: NSColor? { didSet { applyColors() } }
    /// A small ▾ after the content, for buttons that open a menu.
    var showsChevron = false {
        didSet { chevron.isHidden = !showsChevron; updateWidth() }
    }

    /// Tools with variants (Rectangle, Arrow): a small triangle in the corner. A long press, or a click on the
    /// triangle, opens this menu; a plain click still picks the tool.
    var variantMenu: (() -> NSMenu?)? {
        didSet { needsDisplay = true }
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
        label.font = .systemFont(ofSize: height >= 30 ? 13 : 12, weight: style == .tinted || style == .filled ? .semibold : .medium)
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
        content.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        contentCenterY = content.centerYAnchor.constraint(equalTo: centerYAnchor)
        contentCenterY?.isActive = true
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
        let radius = style == .keycap ? Self.keycapRadius : bounds.height / 2
        layer?.cornerRadius = radius
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
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
        if style == .keycap { drawKeycap() }
        super.draw(dirtyRect)
        guard variantMenu != nil else { return }
        // A triangle in the lower right corner, just inside the circle.
        let w = bounds.width, h = bounds.height
        func y(_ fromBottom: CGFloat) -> CGFloat { isFlipped ? h - fromBottom : fromBottom }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: w - 4.5, y: y(5)))
        path.line(to: NSPoint(x: w - 4.5, y: y(10)))
        path.line(to: NSPoint(x: w - 9.5, y: y(5)))
        path.close()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            (isOn || (style == .keycap && keycapTint != nil) ? NSColor.white.withAlphaComponent(0.8)
                : style == .keycap ? Self.keycapInk.withAlphaComponent(0.55) : NSColor.secondaryLabelColor).setFill()
            path.fill()
        }
    }

    /// The colour a `.keycap`'s face is lit with: the accent colour when on, else its own tint, if any.
    private var litColor: NSColor? { isOn ? .controlAccentColor : keycapTint }

    /// The key, as seen from a little above: side walls all round (deepest along the bottom, where the light doesn't
    /// reach) and a slightly dished top face, lit from above. Pressed, the face sinks and the bottom wall shrinks.
    private func drawKeycap() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let r = Self.keycapRadius
        let body = bounds.insetBy(dx: 0.5, dy: 0.5)
        // The face's insets from the body: the side walls left and right, a thin one at the top, a deep one at the bottom.
        let (side, topWall, bottomWall): (CGFloat, CGFloat, CGFloat) = pressed ? (2.5, 2.5, 2.5) : (2.5, 1.5, 4.5)
        let face = NSRect(x: body.minX + side, y: body.minY + (isFlipped ? topWall : bottomWall),
                          width: body.width - 2 * side, height: body.height - topWall - bottomWall)
        // Gradients run from the bottom (start) to the top, whichever way the view is flipped.
        let up: CGFloat = isFlipped ? -90 : 90
        let faceTop: NSColor, faceMid: NSColor, faceBottom: NSColor, wallTop: NSColor, wallBottom: NSColor
        if let lit = litColor {
            let c = lit.usingColorSpace(.sRGB) ?? lit
            faceTop = c.blended(withFraction: 0.35, of: .white) ?? c
            faceMid = c
            faceBottom = c.blended(withFraction: 0.1, of: .white) ?? c
            wallTop = c.blended(withFraction: 0.25, of: .black) ?? c
            wallBottom = c.blended(withFraction: 0.6, of: .black) ?? c
        } else if dark {
            faceTop = NSColor(white: 0.84, alpha: 1); faceMid = NSColor(white: 0.66, alpha: 1); faceBottom = NSColor(white: 0.72, alpha: 1)
            wallTop = NSColor(white: 0.56, alpha: 1); wallBottom = NSColor(white: 0.26, alpha: 1)
        } else {
            faceTop = NSColor(white: 1, alpha: 1); faceMid = NSColor(white: 0.88, alpha: 1); faceBottom = NSColor(white: 0.93, alpha: 1)
            wallTop = NSColor(white: 0.82, alpha: 1); wallBottom = NSColor(white: 0.55, alpha: 1)
        }

        // The walls, darker toward the bottom and shaded at the left and right edges.
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
        NSGradient(starting: wallBottom, ending: wallTop)?.draw(in: bodyPath, angle: up)
        let clear = NSColor.black.withAlphaComponent(0), shade = NSColor.black.withAlphaComponent(dark ? 0.28 : 0.16)
        NSGradient(colors: [shade, clear, clear, shade], atLocations: [0, 0.18, 0.82, 1], colorSpace: .sRGB)?
            .draw(in: bodyPath, angle: 0)

        // The face: lightest at the top, dipping in the middle and catching a little light again at the bottom, so it
        // reads as dished.
        let facePath = NSBezierPath(roundedRect: face, xRadius: r - 1.5, yRadius: r - 1.5)
        NSGradient(colors: [faceBottom, faceMid, faceTop], atLocations: [0, 0.45, 1], colorSpace: .sRGB)?
            .draw(in: facePath, angle: up)
        // Where the face meets the walls: a bright rim along its top, a soft dark line along its bottom.
        let rim = NSBezierPath(roundedRect: face.insetBy(dx: 0.5, dy: 0.5), xRadius: r - 2, yRadius: r - 2)
        rim.lineWidth = 1
        func half(_ top: Bool) -> NSRect {
            let upper = top != isFlipped   // the visually upper half has the larger y unless flipped
            return NSRect(x: face.minX - 1, y: upper ? face.midY : face.minY - 1, width: face.width + 2, height: face.height / 2 + 1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: half(true)).addClip()
        NSColor.white.withAlphaComponent(litColor != nil ? 0.45 : (dark ? 0.55 : 0.95)).setStroke()
        rim.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: half(false)).addClip()
        NSColor.black.withAlphaComponent(dark ? 0.25 : 0.12).setStroke()
        rim.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // A hairline around the whole key.
        NSColor.black.withAlphaComponent(dark ? 0.65 : 0.3).setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        needsDisplay = true   // the variants triangle follows the colors
        let accent = style == .filled || isOn
        let onDark = accent || style == .tinted || (style == .keycap && keycapTint != nil)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let content: NSColor = onDark ? .white : style == .keycap ? Self.keycapInk : .labelColor
        icon.contentTintColor = content
        label.textColor = content
        chevron.contentTintColor = onDark ? NSColor.white.withAlphaComponent(0.75)
            : style == .keycap ? Self.keycapInk.withAlphaComponent(0.6) : .secondaryLabelColor
        if style == .keycap {
            // The content sits on the face, above the deep bottom wall, and sinks with it when pressed.
            let lift: CGFloat = pressed ? 0 : 1.5
            contentCenterY?.constant = isFlipped ? -lift : lift
            applyKeycapShadow(dark: dark)
            return
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            var fill = accent ? .controlAccentColor : style == .tinted ? Self.tintColor : Self.raisedColor(dark: dark)
            if pressed { fill = fill.blended(withFraction: dark ? 0.15 : 0.12, of: .black) ?? fill }
            layer?.backgroundColor = fill.cgColor
            // Raised pills cast a soft shadow.
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = style == .raised ? (dark ? 0.35 : 0.16) : 0
            layer?.shadowRadius = 1.5
            layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        }
    }

    /// No fill on the layer (the key is drawn); a soft drop shadow, or the accent colour's glow when on.
    private func applyKeycapShadow(dark: Bool) {
        layer?.backgroundColor = nil
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let lit = litColor {
                layer?.shadowColor = lit.cgColor
                layer?.shadowOpacity = (dark ? 0.85 : 0.6) * (isOn ? 1 : 0.6)
                layer?.shadowRadius = 6
                layer?.shadowOffset = .zero
            } else {
                // The key standing on the tray floor.
                layer?.shadowColor = NSColor.black.cgColor
                layer?.shadowOpacity = pressed ? 0.3 : (dark ? 0.75 : 0.35)
                layer?.shadowRadius = pressed ? 0.5 : 1.5
                layer?.shadowOffset = CGSize(width: 0, height: pressed ? -0.5 : -2)
            }
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

    init(pullsDown: Bool, height: CGFloat = 26, style: Style = .raised) {
        self.pullsDown = pullsDown
        super.init(title: nil, symbol: nil, style: style, height: height)
        menu = NSMenu()
        showsChevron = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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

/// A recessed tray holding a group of `.keycap` buttons (the editor's toolbar): its keys in a row, inset from the
/// edges, with a darker well and a faint lip along the bottom.
final class KeycapTray: NSView {
    init(_ views: [NSView], spacing: CGFloat = 1, inset: CGFloat = 3) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let r = PillButton.keycapRadius + 3
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let well = NSBezierPath(roundedRect: outer, xRadius: r, yRadius: r)
        // Darker at the top, where the rim shades it.
        let top = dark ? NSColor(white: 0.02, alpha: 1) : NSColor(white: 0.62, alpha: 1)
        let bottom = dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.76, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: well, angle: isFlipped ? -90 : 90)
        // An inner shadow along the top edge, so the floor sits below the rim.
        NSGraphicsContext.saveGraphicsState()
        well.addClip()
        let inner = NSShadow()
        inner.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.9 : 0.45)
        inner.shadowBlurRadius = 3
        inner.shadowOffset = NSSize(width: 0, height: -1.5)   // down, in either orientation
        inner.set()
        let ring = NSBezierPath(rect: outer.insetBy(dx: -20, dy: -20))
        ring.append(well.reversed)
        ring.windingRule = .evenOdd
        NSColor.black.setFill()
        ring.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(dark ? 0.7 : 0.25).setStroke()
        well.lineWidth = 1
        well.stroke()
        // The lip: a light line along the bottom edge.
        NSGraphicsContext.saveGraphicsState()
        let half = NSRect(x: bounds.minX, y: isFlipped ? bounds.midY : bounds.minY, width: bounds.width, height: bounds.height / 2)
        NSBezierPath(rect: half).addClip()
        NSColor.white.withAlphaComponent(dark ? 0.14 : 0.7).setStroke()
        NSBezierPath(roundedRect: outer.offsetBy(dx: 0, dy: isFlipped ? 0.5 : -0.5), xRadius: r, yRadius: r).stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A small upright switch for a tray, like a hardware toggle: a dark capsule with a symbol on it, and an LED under it
/// that glows in the accent colour while it is on. A click flips `state` and sends the action.
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
        widthAnchor.constraint(equalToConstant: 18).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // From the top: the capsule (20 pt), a gap, the LED (4 pt).
        func y(_ fromTop: CGFloat, _ height: CGFloat) -> CGFloat { isFlipped ? fromTop : bounds.height - fromTop - height }
        let body = NSRect(x: 1, y: y(0.5, 20), width: bounds.width - 2, height: 20)
        let capsule = NSBezierPath(roundedRect: body, xRadius: body.width / 2, yRadius: body.width / 2)
        let top = NSColor(white: dark ? 0.30 : 0.36, alpha: 1), bottom = NSColor(white: dark ? 0.10 : 0.16, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: capsule, angle: isFlipped ? -90 : 90)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        // A glint along the upper edge.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: body.minX, y: isFlipped ? body.minY : body.midY, width: body.width, height: body.height / 2)).addClip()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: body.width / 2 - 1, yRadius: body.width / 2 - 1).stroke()
        NSGraphicsContext.restoreGraphicsState()

        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(.init(paletteColors: [on ? .white : NSColor(white: 0.75, alpha: 1)]))
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = image.size
            image.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
        }

        let led = NSRect(x: bounds.midX - 2, y: y(22.5, 4), width: 4, height: 4)
        let dot = NSBezierPath(ovalIn: led)
        if on {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = .controlAccentColor
            glow.shadowBlurRadius = 4
            glow.set()
            NSColor.controlAccentColor.setFill()
            dot.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: led.insetBy(dx: 1.2, dy: 1.2)).fill()
        } else {
            NSColor(white: dark ? 0.22 : 0.55, alpha: 1).setFill()
            dot.fill()
        }
    }
}

/// A raised pill showing the current colour as a dot, with a ▾. Clicking it offers a few colours and More Colors… (the
/// colour panel); a change goes to its target/action.
final class ColorPill: PillButton {
    var color: NSColor = .systemRed { didSet { setContent(title: nil, image: Self.dot(color)) } }
    private static let presets: [(String, NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen),
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink), ("Black", .black), ("White", .white),
    ]

    init(size: CGFloat = 26) {
        super.init(title: nil, symbol: nil, style: .raised, height: size)
        showsChevron = true
        setContent(title: nil, image: Self.dot(color))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A filled circle with a hairline edge (so white shows on white).
    private static func dot(_ c: NSColor, size: CGFloat = 14) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            c.setFill(); p.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke(); p.lineWidth = 1; p.stroke()
            return true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSMenu()
        for (name, c) in Self.presets {
            let item = NSMenuItem(title: name, action: #selector(presetPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c
            item.image = Self.dot(c)
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
