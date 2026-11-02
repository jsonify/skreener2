import AppKit

private final class RadialPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The radial menu (#359): its shortcut opens a ring of capture modes at the pointer. A tap leaves it open to click a
/// slice (or press 1–6, or the arrows and Return); holding the shortcut, pointing at a slice and letting go runs that
/// slice. Esc, a click outside or the shortcut again closes it. The math is `RadialMenuGeometry`'s.
final class RadialMenu {
    /// Runs the picked capture mode; set by the app delegate.
    var onPick: ((HotKeyAction) -> Void)?

    private var panel: RadialPanel?
    private var view: RadialMenuView?
    private var monitors: [Any] = []
    /// The shortcut is down: between its press and its release.
    private var keyHeld = false
    /// The pointer moved since the ring opened, so a highlight is where the user aimed, not where the ring landed.
    private var pointerMoved = false
    private var openedAt = NSPoint.zero
    /// A slice was picked and the ring is on its way out.
    private var choosing = false

    var isOpen: Bool { panel != nil }

    /// The shortcut went down: opens the ring at the pointer, or closes it if it is open.
    func pressed() {
        // A key held down may repeat; a release that never came (the shortcut was being re-recorded) must not stick.
        if keyHeld && shortcutKeyIsDown() { return }
        keyHeld = true
        if isOpen { close() } else { open() }
    }

    /// The shortcut was let go: after a hold onto a slice, runs it; after a tap (or let go in the hub), the ring stays
    /// open for a click.
    func released() {
        let wasHeld = keyHeld
        keyHeld = false
        guard wasHeld, isOpen, !choosing, let view else { return }
        if let index = RadialMenuGeometry.pickOnRelease(highlight: view.highlight, pointerMoved: pointerMoved) {
            choose(index)
        } else if pointerMoved {
            updateHighlight()   // the ring's reach applies once the shortcut is up
        }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        view = nil
        choosing = false
    }

    private func shortcutKeyIsDown() -> Bool {
        guard let combo = ShortcutStore.combo(for: .radialMenu) else { return false }
        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(combo.keyCode))
    }

    private func open() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = RadialMenuGeometry.windowSize
        let frame = RadialMenuGeometry.frame(size: size, centeredAt: mouse, in: screen.visibleFrame)
        let p = RadialPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let v = RadialMenuView(frame: NSRect(origin: .zero, size: size))
        v.shortcuts = RadialMenuGeometry.slices.map { ShortcutStore.combo(for: $0.action)?.displayString }
        v.timerSeconds = Preferences.selfTimerSeconds
        v.onChoose = { [weak self] index in self?.choose(index) }
        v.onDismiss = { [weak self] in self?.close() }
        p.contentView = v
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            p.animator().alphaValue = 1
        }
        panel = p
        view = v
        openedAt = mouse
        pointerMoved = false
        choosing = false

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in self?.close() }) {
            monitors.append(m)
        }
        // A click in another of Skreener's windows closes it too; the ring's own clicks are its view's.
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] e in
            if let self, e.window !== self.panel { self.close() }
            return e
        }) { monitors.append(m) }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.pointerDidMove() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in
            self?.pointerDidMove()
            return e
        }) { monitors.append(m) }
    }

    private func pointerDidMove() {
        guard isOpen, !choosing else { return }
        let mouse = NSEvent.mouseLocation
        if !pointerMoved && hypot(mouse.x - openedAt.x, mouse.y - openedAt.y) > 3 { pointerMoved = true }
        if pointerMoved { updateHighlight() }
    }

    /// Lights the slice the pointer points at. While the shortcut is held the direction alone counts, so a flick past
    /// the ring still picks; after that, only a pointer on the ring lights a slice.
    private func updateHighlight() {
        guard let panel, let view else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.midX, y: mouse.y - panel.frame.midY)
        view.highlight = RadialMenuGeometry.slice(at: point, count: RadialMenuGeometry.slices.count,
                                                  reach: keyHeld ? nil : RadialMenuGeometry.clickReach)
    }

    /// Presses the slice's key, takes the ring off the screen, then runs the mode, so the ring is never in a capture.
    private func choose(_ index: Int) {
        guard !choosing, let view, RadialMenuGeometry.slices.indices.contains(index) else { return }
        choosing = true
        view.highlight = index
        view.pressed = index
        let action = RadialMenuGeometry.slices[index].action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self else { return }
            close()
            let pick = onPick
            // A moment for the window server to take the ring away before a capture freezes the screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pick?(action) }
        }
    }
}

/// The ring in the SK-1 look: a round cream chassis, a sunken ring-shaped tray of wedge keys (Record orange) with a
/// teal lamp and lip on the one pointed at, and an olive LCD hub naming it. Unflipped, like `RadialMenuGeometry`.
final class RadialMenuView: NSView {
    private typealias G = RadialMenuGeometry

    private static let skirt: CGFloat = 2
    /// Half the gap between two keys, in points.
    private static let halfGap: CGFloat = 2
    private static let iconRadius: CGFloat = (G.outerRadius + G.innerRadius) / 2 - 4
    private static let legendRadius = G.outerRadius - 12

    var highlight: Int? {
        didSet { if highlight != oldValue { needsDisplay = true } }
    }
    var pressed: Int? {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }
    /// Each slice's shortcut, as shown on the hub.
    var shortcuts: [String?] = [] {
        didSet { needsDisplay = true }
    }
    var timerSeconds = 5 {
        didSet { needsDisplay = true }
    }
    var onChoose: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let slices = G.slices
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Radial Menu")
        var elements: [NSAccessibilityElement] = []
        for (i, slice) in slices.enumerated() {
            let e = RadialSliceElement()
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(slice.title)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(wedge(i).bounds)
            e.onPress = { [weak self] in self?.onChoose?(i) }
            elements.append(e)
        }
        setAccessibilityChildren(elements)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: p.x - center.x, y: p.y - center.y)
        guard hypot(point.x, point.y) <= G.clickReach else { onDismiss?(); return }
        if let i = G.slice(at: point, count: slices.count) { onChoose?(i) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:   // Esc
            onDismiss?()
        case 36, 76:   // Return, Enter
            if let highlight { onChoose?(highlight) }
        default:
            if let key = SelectionGeometry.key(keyCode: event.keyCode) {
                highlight = G.step(highlight, clockwise: key == .right || key == .down, count: slices.count)
            } else if let i = G.slice(forKey: event.charactersIgnoringModifiers ?? "", count: slices.count) {
                onChoose?(i)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let c = center

        // The chassis, a cream disc casting a soft shadow.
        let r = G.chassisRadius
        let chassis = NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(p.dark ? 0.55 : 0.3)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        Retro.color(p.chassis).setFill()
        NSBezierPath(ovalIn: chassis).fill()
        NSGraphicsContext.restoreGraphicsState()
        Retro.drawPlate(chassis, radius: r, palette: p, flipped: false)

        // The sunken tray round the keys, with its light lip along the bottom.
        let trayOuter = G.outerRadius + 4, trayInner = G.innerRadius - 4
        NSColor.white.withAlphaComponent(p.wellLip).setFill()
        annulus(outer: trayOuter, inner: trayInner, dy: -1).fill()
        let tray = annulus(outer: trayOuter, inner: trayInner)
        Retro.fill(tray, top: Retro.color(p.wellTop), bottom: Retro.color(p.wellBottom), flipped: false)
        Retro.innerShadow(tray, alpha: p.wellShadow, blur: 2)

        if let highlight { drawLip(highlight) }
        for (i, slice) in slices.enumerated() { drawSlice(i, slice, palette: p) }
        drawHub(palette: p)
    }

    /// The ring between `outer` and `inner` round the centre, `dy` lower or higher.
    private func annulus(outer: CGFloat, inner: CGFloat, dy: CGFloat = 0) -> NSBezierPath {
        let c = NSPoint(x: center.x, y: center.y + dy)
        let path = NSBezierPath(ovalIn: NSRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
        path.append(NSBezierPath(ovalIn: NSRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)).reversed)
        path.windingRule = .evenOdd
        return path
    }

    /// An angle from `RadialMenuGeometry` (radians, clockwise from the top) as `NSBezierPath` wants it (degrees,
    /// anticlockwise from the right).
    private static func degrees(_ angle: CGFloat) -> CGFloat { 90 - angle * 180 / .pi }

    /// Slice `i`'s key: a wedge between the slices' radii with a gap to its neighbours, `dy` lower or higher.
    private func wedge(_ i: Int, dy: CGFloat = 0) -> NSBezierPath {
        let half = .pi / CGFloat(slices.count)
        let mid = G.centerAngle(of: i, count: slices.count)
        let outer = G.outerRadius, inner = G.innerRadius
        let c = NSPoint(x: center.x, y: center.y + dy)
        let path = NSBezierPath()
        path.appendArc(withCenter: c, radius: outer, startAngle: Self.degrees(mid - half + Self.halfGap / outer),
                       endAngle: Self.degrees(mid + half - Self.halfGap / outer), clockwise: true)
        path.appendArc(withCenter: c, radius: inner, startAngle: Self.degrees(mid + half - Self.halfGap / inner),
                       endAngle: Self.degrees(mid - half + Self.halfGap / inner), clockwise: false)
        path.close()
        return path
    }

    /// A raised key, as `Retro.drawKey` draws one but wedge-shaped: a face on a darker skirt, lit along its top
    /// edge; pressed, the face sits on the skirt.
    private func drawSlice(_ i: Int, _ slice: G.Slice, palette p: Retro.Palette) {
        let colors = Retro.keyColors(slice.action == .recordScreen ? .orange : .cream, p)
        let down = pressed == i
        let faceDY = down ? -Self.skirt : 0
        if !down {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = colors.shadow.withAlphaComponent(CGFloat(colors.shadowAlpha))
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            colors.skirt.setFill()
            wedge(i, dy: -Self.skirt).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let face = wedge(i, dy: faceDY)
        NSGraphicsContext.saveGraphicsState()
        face.addClip()
        colors.highlight.setFill()
        face.fill()
        Retro.fill(wedge(i, dy: faceDY - 1), top: down ? colors.downTop : colors.top,
                   bottom: down ? colors.downBottom : colors.bottom, flipped: false)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        face.lineWidth = 0.5
        face.stroke()

        let mid = G.centerAngle(of: i, count: slices.count)
        let c = NSPoint(x: center.x, y: center.y + faceDY)
        // The symbol.
        let at = G.point(angle: mid, radius: Self.iconRadius)
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colors.ink]))
        if let image = NSImage(systemSymbolName: slice.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = image.size
            image.draw(in: NSRect(x: c.x + at.x - s.width / 2, y: c.y + at.y - s.height / 2, width: s.width, height: s.height))
        }
        // Its number key, near the outer edge.
        let number = NSAttributedString(string: "\(i + 1)", attributes: [.font: Retro.mono(8), .foregroundColor: colors.legend])
        let ns = number.size()
        let legend = G.point(angle: mid, radius: Self.legendRadius)
        number.draw(at: NSPoint(x: c.x + legend.x - ns.width / 2, y: c.y + legend.y - ns.height / 2))
        // The lamp, near the inner edge: teal (white on the orange key) while pointed at.
        let lamp = G.point(angle: mid, radius: G.innerRadius + 8)
        Retro.drawLamp(in: NSRect(x: c.x + lamp.x - 2, y: c.y + lamp.y - 2, width: 4, height: 4),
                       color: Retro.color(slice.action == .recordScreen ? 0xffffff : Retro.teal), lit: highlight == i)
    }

    /// The teal lip on the chassis along the outside of the slice pointed at.
    private func drawLip(_ i: Int) {
        let half = .pi / CGFloat(slices.count)
        let mid = G.centerAngle(of: i, count: slices.count)
        let radius = G.outerRadius + 7
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: Self.degrees(mid - half + Self.halfGap / radius),
                      endAngle: Self.degrees(mid + half - Self.halfGap / radius), clockwise: true)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = Retro.color(Retro.teal)
        glow.shadowBlurRadius = 4
        glow.set()
        Retro.color(Retro.teal).setStroke()
        arc.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The olive LCD in the middle: the name of the slice pointed at and its shortcut, or the resting text.
    private func drawHub(palette p: Retro.Palette) {
        let r = G.hubRadius
        let rect = NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let glass = Retro.drawLCD(in: rect, radius: r, inset: 4, palette: p, flipped: false)
        let text = G.hubText(for: highlight.map { slices[$0] },
                             shortcut: highlight.flatMap { $0 < shortcuts.count ? shortcuts[$0] : nil },
                             timerSeconds: timerSeconds)
        let ink = Retro.color(Retro.lcdInk)
        let title = Retro.caption(text.title, color: ink, font: .systemFont(ofSize: 10.5, weight: .heavy), kern: 1.1)
        let detail = NSAttributedString(string: text.detail,
                                        attributes: [.font: Retro.mono(10), .foregroundColor: ink.withAlphaComponent(0.8)])
        let ts = title.size(), ds = detail.size()
        let gap: CGFloat = 2
        let height = text.detail.isEmpty ? ts.height : ts.height + gap + ds.height
        let top = glass.midY + height / 2
        title.draw(at: NSPoint(x: glass.midX - ts.width / 2, y: top - ts.height))
        if !text.detail.isEmpty {
            detail.draw(at: NSPoint(x: glass.midX - ds.width / 2, y: top - ts.height - gap - ds.height))
        }
    }
}

/// One slice for VoiceOver: a button that picks it.
private final class RadialSliceElement: NSAccessibilityElement {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
