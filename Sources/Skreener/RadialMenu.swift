import AppKit

private final class RadialPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The radial menu (#359): its shortcut opens a ring of capture modes at the pointer. A tap leaves it open to click a
/// slice (or press 1–6, or the arrows and Return); holding the shortcut, pointing at a slice and letting go runs that
/// slice. A slice with options fans them out past it while it is pointed at: move on out to one (or Tab to it) to pick
/// it instead. Self-Timer's hub also sets the delay. Esc, a click outside or the shortcut again closes the ring. The
/// math is `RadialMenuGeometry`'s.
final class RadialMenu {
    private typealias G = RadialMenuGeometry

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
    /// Something was picked and the ring is on its way out.
    private var choosing = false

    var isOpen: Bool { panel != nil }

    /// The shortcut went down: opens the ring at the pointer, or closes it if it is open.
    func pressed() {
        // A key held down may repeat; a release that never came (the shortcut was being re-recorded) must not stick.
        if keyHeld && shortcutKeyIsDown() { return }
        keyHeld = true
        if isOpen { close() } else { open() }
    }

    /// The shortcut was let go: after a hold onto a slice or option, runs it; after a tap (or let go in the hub), the
    /// ring stays open for a click.
    func released() {
        let wasHeld = keyHeld
        keyHeld = false
        guard wasHeld, isOpen, !choosing, let view else { return }
        let under = G.target(at: pointer(), active: view.target?.sliceIndex, held: true)
        if let target = G.pickOnRelease(under, pointerMoved: pointerMoved) {
            choose(target)
        } else if pointerMoved {
            updateHighlight()   // the ring's reach applies once the shortcut is up
        }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        MainActor.assumeIsolated { CapturePanelHandOff.closing { panel?.orderOut(nil) } }
        panel = nil
        view = nil
        choosing = false
    }

    private func shortcutKeyIsDown() -> Bool {
        guard let combo = ShortcutStore.combo(for: .radialMenu) else { return false }
        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(combo.keyCode))
    }

    /// The pointer, from the ring's centre.
    private func pointer() -> CGPoint {
        guard let panel else { return .zero }
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - panel.frame.midX, y: mouse.y - panel.frame.midY)
    }

    private func open() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = G.windowSize
        let frame = G.frame(size: size, centeredAt: mouse, in: screen.visibleFrame)
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
        var shortcuts: [HotKeyAction: String] = [:]
        for slice in G.slices {
            for action in [slice.action] + slice.options.map(\.action) {
                shortcuts[action] = ShortcutStore.combo(for: action)?.displayString
            }
        }
        v.shortcuts = shortcuts
        v.timerSeconds = Preferences.selfTimerSeconds
        v.onChoose = { [weak self] target in self?.choose(target) }
        v.onDelay = { seconds in Preferences.selfTimerSeconds = seconds }
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

    /// Lights what the pointer points at. While the shortcut is held the direction alone counts, so a flick past the
    /// ring still picks; after that, only a pointer on the ring or a band lights something. In the hub the highlight
    /// stays, so the self-timer's delays there can be reached.
    private func updateHighlight() {
        guard let view else { return }
        let point = pointer()
        if hypot(point.x, point.y) < G.hubRadius { return }
        view.target = G.target(at: point, active: view.target?.sliceIndex, held: keyHeld)
    }

    /// Presses the key, takes the ring off the screen, then runs the mode, so the ring is never in a capture.
    private func choose(_ target: RadialMenuGeometry.Target) {
        guard !choosing, let view, let action = G.action(for: target) else { return }
        choosing = true
        view.target = target
        view.pressed = target
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
/// teal lamp and lip on the one pointed at, its options fanned out on a plate past it, and an olive LCD hub naming what
/// is pointed at. Unflipped, like `RadialMenuGeometry`.
final class RadialMenuView: NSView {
    private typealias G = RadialMenuGeometry

    private static let skirt: CGFloat = 2
    /// Half the gap between two keys, in points.
    private static let halfGap: CGFloat = 2
    private static let iconRadius: CGFloat = (G.outerRadius + G.innerRadius) / 2 - 4
    private static let legendRadius = G.outerRadius - 12

    /// What is pointed at (its slice lit, its options fanned out).
    var target: RadialMenuGeometry.Target? {
        didSet { if target != oldValue { needsDisplay = true } }
    }
    var pressed: RadialMenuGeometry.Target? {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }
    /// The shortcut of each mode on the ring, as shown on the hub.
    var shortcuts: [HotKeyAction: String] = [:] {
        didSet { needsDisplay = true }
    }
    var timerSeconds = 5 {
        didSet { needsDisplay = true }
    }
    var onChoose: ((RadialMenuGeometry.Target) -> Void)?
    /// A self-timer delay was picked on the hub.
    var onDelay: ((Int) -> Void)?
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
            elements.append(element(slice.title, frame: sliceWedge(i).bounds, target: .slice(i)))
            for (j, option) in slice.options.enumerated() {
                elements.append(element("\(slice.title): \(option.title)", frame: optionWedge(i, j).bounds,
                                        target: .option(slice: i, option: j)))
            }
        }
        setAccessibilityChildren(elements)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func element(_ label: String, frame: NSRect, target: RadialMenuGeometry.Target) -> NSAccessibilityElement {
        let e = RadialSliceElement()
        e.setAccessibilityRole(.button)
        e.setAccessibilityLabel(label)
        e.setAccessibilityParent(self)
        e.setAccessibilityFrameInParentSpace(frame)
        e.onPress = { [weak self] in self?.onChoose?(target) }
        return e
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: p.x - center.x, y: p.y - center.y)
        if hypot(point.x, point.y) < G.hubRadius {
            if let target, slices[target.sliceIndex].hasDelay, let seconds = G.delay(at: point) {
                timerSeconds = seconds
                onDelay?(seconds)
            }
            return
        }
        if let t = G.target(at: point, active: target?.sliceIndex, held: false) { onChoose?(t) } else { onDismiss?() }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:   // Esc
            onDismiss?()
        case 36, 76:   // Return, Enter
            if let target { onChoose?(target) }
        case 48:   // Tab, ⇧Tab: through the lit slice's options
            guard let target else { return }
            let count = slices[target.sliceIndex].options.count
            let forward = !event.modifierFlags.contains(.shift)
            if let o = G.stepOption(target.optionIndex, forward: forward, count: count) {
                self.target = .option(slice: target.sliceIndex, option: o)
            } else {
                self.target = .slice(target.sliceIndex)
            }
        default:
            if let key = SelectionGeometry.key(keyCode: event.keyCode) {
                target = .slice(G.step(target?.sliceIndex, clockwise: key == .right || key == .down, count: slices.count))
            } else if let i = G.slice(forKey: event.charactersIgnoringModifiers ?? "", count: slices.count) {
                onChoose?(.slice(i))
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

        // The options' plate comes out from under the chassis, so it goes first.
        if let target, !slices[target.sliceIndex].options.isEmpty { drawBand(target, palette: p) }

        // The chassis, a cream disc casting a soft shadow.
        let r = G.chassisRadius
        let chassis = NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        withShadow(alpha: p.dark ? 0.55 : 0.3, blur: 14, offset: 4) {
            Retro.color(p.chassis).setFill()
            NSBezierPath(ovalIn: chassis).fill()
        }
        Retro.drawPlate(chassis, radius: r, palette: p, flipped: false)

        // The sunken tray round the keys, with its light lip along the bottom.
        drawTray(sector(inner: G.innerRadius - 4, outer: G.outerRadius + 4, from: 0, to: 2 * .pi), palette: p)

        if let target { drawLip(target.sliceIndex) }
        for (i, slice) in slices.enumerated() {
            let down = pressed == .slice(i)
            drawKey(sliceWedge(i, dy: down ? -Self.skirt : 0), sliceWedge(i, dy: -Self.skirt),
                    variant: slice.action == .recordScreen ? .orange : .cream, down: down, palette: p) { colors, dy in
                let mid = G.centerAngle(of: i, count: slices.count)
                drawSymbol(slice.symbol, size: 17, color: colors.ink, at: G.point(angle: mid, radius: Self.iconRadius), dy: dy)
                drawText("\(i + 1)", font: Retro.mono(8), color: colors.legend,
                         at: G.point(angle: mid, radius: Self.legendRadius), dy: dy)
                drawLamp(at: G.point(angle: mid, radius: G.innerRadius + 8), dy: dy,
                         lit: target?.sliceIndex == i && target?.optionIndex == nil,
                         color: slice.action == .recordScreen ? 0xffffff : Retro.teal)
            }
        }
        drawHub(palette: p)
    }

    /// The options of `target`'s slice on a plate past the chassis: a tray of small keys, the one pointed at lit.
    private func drawBand(_ target: RadialMenuGeometry.Target, palette p: Retro.Palette) {
        let s = target.sliceIndex
        let options = slices[s].options
        let mid = G.centerAngle(of: s, count: slices.count)
        let half = G.bandSpan(options: options.count) / 2
        let plateHalf = half + 8 / G.bandPlateRadius
        let plate = sector(inner: G.chassisRadius - 8, outer: G.bandPlateRadius, from: mid - plateHalf, to: mid + plateHalf)
        withShadow(alpha: p.dark ? 0.5 : 0.25, blur: 10, offset: 3) {
            Retro.color(p.chassis).setFill()
            plate.fill()
        }
        NSColor.black.withAlphaComponent(p.dark ? 0.55 : 0.25).setStroke()
        plate.lineWidth = 0.5
        plate.stroke()
        let trayHalf = half + 4 / G.bandOuter
        drawTray(sector(inner: G.bandInner - 4, outer: G.bandOuter + 4, from: mid - trayHalf, to: mid + trayHalf), palette: p)
        for (j, option) in options.enumerated() {
            let down = pressed == .option(slice: s, option: j)
            drawKey(optionWedge(s, j, dy: down ? -Self.skirt : 0), optionWedge(s, j, dy: -Self.skirt), variant: .cream,
                    down: down, palette: p) { colors, dy in
                let a = G.optionAngle(slice: s, count: slices.count, option: j, options: options.count)
                drawSymbol(option.symbol, size: 14, color: colors.ink, at: G.point(angle: a, radius: G.bandOuter - 18), dy: dy)
                drawLamp(at: G.point(angle: a, radius: G.bandInner + 6), dy: dy, lit: target.optionIndex == j, color: Retro.teal)
            }
        }
    }

    // MARK: Shapes

    /// An angle from `RadialMenuGeometry` (radians, clockwise from the top) as `NSBezierPath` wants it (degrees,
    /// anticlockwise from the right).
    private static func degrees(_ angle: CGFloat) -> CGFloat { 90 - angle * 180 / .pi }

    /// The part of the ring between `inner` and `outer` from angle `start` clockwise to `end`, `dy` lower or higher;
    /// a whole ring when it goes all the way round.
    private func sector(inner: CGFloat, outer: CGFloat, from start: CGFloat, to end: CGFloat, dy: CGFloat = 0) -> NSBezierPath {
        let c = NSPoint(x: center.x, y: center.y + dy)
        guard end - start < 2 * .pi else {
            let path = NSBezierPath(ovalIn: NSRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            path.append(NSBezierPath(ovalIn: NSRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)).reversed)
            path.windingRule = .evenOdd
            return path
        }
        let path = NSBezierPath()
        path.appendArc(withCenter: c, radius: outer, startAngle: Self.degrees(start), endAngle: Self.degrees(end), clockwise: true)
        path.appendArc(withCenter: c, radius: inner, startAngle: Self.degrees(end), endAngle: Self.degrees(start), clockwise: false)
        path.close()
        return path
    }

    /// A key between `inner` and `outer` from `start` to `end`, with half a gap taken off each side.
    private func keyShape(inner: CGFloat, outer: CGFloat, from start: CGFloat, to end: CGFloat, dy: CGFloat) -> NSBezierPath {
        let c = NSPoint(x: center.x, y: center.y + dy)
        let g = Self.halfGap
        let path = NSBezierPath()
        path.appendArc(withCenter: c, radius: outer, startAngle: Self.degrees(start + g / outer),
                       endAngle: Self.degrees(end - g / outer), clockwise: true)
        path.appendArc(withCenter: c, radius: inner, startAngle: Self.degrees(end - g / inner),
                       endAngle: Self.degrees(start + g / inner), clockwise: false)
        path.close()
        return path
    }

    /// Slice `i`'s key, `dy` lower or higher.
    private func sliceWedge(_ i: Int, dy: CGFloat = 0) -> NSBezierPath {
        let half = .pi / CGFloat(slices.count)
        let mid = G.centerAngle(of: i, count: slices.count)
        return keyShape(inner: G.innerRadius, outer: G.outerRadius, from: mid - half, to: mid + half, dy: dy)
    }

    /// Option `j` of slice `i`'s key in its band, `dy` lower or higher.
    private func optionWedge(_ i: Int, _ j: Int, dy: CGFloat = 0) -> NSBezierPath {
        let a = G.optionAngle(slice: i, count: slices.count, option: j, options: slices[i].options.count)
        return keyShape(inner: G.bandInner, outer: G.bandOuter, from: a - G.optionWidth / 2, to: a + G.optionWidth / 2, dy: dy)
    }

    // MARK: Parts

    private func withShadow(alpha: CGFloat, blur: CGFloat, offset: CGFloat, color: NSColor = .black, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(alpha)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -offset)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A sunken tray in `shape`, with its light lip along the bottom.
    private func drawTray(_ shape: NSBezierPath, palette p: Retro.Palette) {
        let lip = shape.copy() as? NSBezierPath ?? shape
        let down = AffineTransform(translationByX: 0, byY: -1)
        lip.transform(using: down)
        NSColor.white.withAlphaComponent(p.wellLip).setFill()
        lip.fill()
        Retro.fill(shape, top: Retro.color(p.wellTop), bottom: Retro.color(p.wellBottom), flipped: false)
        Retro.innerShadow(shape, alpha: p.wellShadow, blur: 2)
    }

    /// A raised key, as `Retro.drawKey` draws one but in `face`'s shape: a face on a darker `skirt`, lit along its top
    /// edge; pressed, the face sits on the skirt. `legend` draws what is on it, given how far the face sank.
    private func drawKey(_ face: NSBezierPath, _ skirt: NSBezierPath, variant: Retro.KeyVariant, down: Bool,
                         palette p: Retro.Palette, legend: (Retro.KeyColors, CGFloat) -> Void) {
        let colors = Retro.keyColors(variant, p)
        if !down {
            withShadow(alpha: CGFloat(colors.shadowAlpha), blur: 2, offset: 1, color: colors.shadow) {
                colors.skirt.setFill()
                skirt.fill()
            }
        }
        let lower = face.copy() as? NSBezierPath ?? face
        lower.transform(using: AffineTransform(translationByX: 0, byY: -1))
        NSGraphicsContext.saveGraphicsState()
        face.addClip()
        colors.highlight.setFill()
        face.fill()
        Retro.fill(lower, top: down ? colors.downTop : colors.top, bottom: down ? colors.downBottom : colors.bottom, flipped: false)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        face.lineWidth = 0.5
        face.stroke()
        legend(colors, down ? -Self.skirt : 0)
    }

    private func drawSymbol(_ name: String, size: CGFloat, color: NSColor, at point: CGPoint, dy: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: NSRect(x: center.x + point.x - s.width / 2, y: center.y + dy + point.y - s.height / 2,
                              width: s.width, height: s.height))
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, dy: CGFloat) {
        let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = s.size()
        s.draw(at: NSPoint(x: center.x + point.x - size.width / 2, y: center.y + dy + point.y - size.height / 2))
    }

    private func drawLamp(at point: CGPoint, dy: CGFloat, lit: Bool, color: UInt32) {
        Retro.drawLamp(in: NSRect(x: center.x + point.x - 2, y: center.y + dy + point.y - 2, width: 4, height: 4),
                       color: Retro.color(color), lit: lit)
    }

    /// The teal lip on the chassis along the outside of slice `i`.
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

    /// The olive LCD in the middle: the name of what is pointed at and its shortcut (for the self-timer, its delays to
    /// pick from), or the resting text.
    private func drawHub(palette p: Retro.Palette) {
        let r = G.hubRadius
        let rect = NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let glass = Retro.drawLCD(in: rect, radius: r, inset: 4, palette: p, flipped: false)
        let action = target.flatMap { G.action(for: $0) }
        let text = G.hubText(for: target, shortcut: action.flatMap { shortcuts[$0] })
        let ink = Retro.color(Retro.lcdInk)
        let radius = glass.width / 2 - 5   // the glass's radius, less a margin inside its rim
        if text.showsDelays {
            // One line just above the delay chips.
            let chipsTop = (G.delayRects().map(\.maxY).max() ?? 0) + 5
            let lines = Self.fitTitle(text.title, ink: ink, radius: radius) { heights in
                heights.count == 1 ? [(chipsTop + heights[0], chipsTop)] : nil
            }
            for line in lines {
                line.draw(at: NSPoint(x: glass.midX - line.size().width / 2, y: glass.midY + chipsTop))
            }
            for (seconds, box) in zip(G.delays, G.delayRects()) {
                let chip = box.offsetBy(dx: center.x, dy: center.y)
                let on = seconds == timerSeconds
                let path = NSBezierPath(roundedRect: chip, xRadius: 3, yRadius: 3)
                if on {
                    ink.setFill()
                    path.fill()
                } else {
                    ink.withAlphaComponent(0.35).setStroke()
                    path.lineWidth = 0.75
                    path.stroke()
                }
                let label = NSAttributedString(string: "\(seconds)s", attributes: [
                    .font: Retro.mono(9), .foregroundColor: on ? Retro.color(Retro.glassMiddle) : ink.withAlphaComponent(0.8),
                ])
                let ls = label.size()
                label.draw(at: NSPoint(x: chip.midX - ls.width / 2, y: chip.midY - ls.height / 2))
            }
            return
        }
        let detail = NSAttributedString(string: text.detail,
                                        attributes: [.font: Retro.mono(10), .foregroundColor: ink.withAlphaComponent(0.8)])
        let below = text.detail.isEmpty ? 0 : 2 + detail.size().height   // the gap and the detail under the title
        // The title's lines and the detail, centred as one block.
        let lines = Self.fitTitle(text.title, ink: ink, radius: radius) { heights in
            var top = (heights.reduce(0, +) + below) / 2
            return heights.map { h in
                defer { top -= h }
                return (top, top - h)
            }
        }
        var y = glass.midY + (lines.map { $0.size().height }.reduce(0, +) + below) / 2
        for line in lines {
            y -= line.size().height
            line.draw(at: NSPoint(x: glass.midX - line.size().width / 2, y: y))
        }
        if !text.detail.isEmpty {
            let ds = detail.size()
            detail.draw(at: NSPoint(x: glass.midX - ds.width / 2, y: y - 2 - ds.height))
        }
    }

    /// The hub title's sizes to try, biggest first; one line is only shrunk to `minOneLine` before trying two.
    private static let titleSizes: [CGFloat] = Array(stride(from: 10.5, through: 6.5, by: -0.5))
    private static let minOneLine: CGFloat = 8.5

    private static func titleLine(_ text: String, size: CGFloat, ink: NSColor) -> NSAttributedString {
        Retro.caption(text, color: ink, font: .systemFont(ofSize: size, weight: .heavy), kern: 1.1 * size / 10.5)
    }

    /// The hub's title as lines that each fit inside the round glass (`radius`, from its centre), in the biggest size
    /// that works: one line first, then two. `place` puts lines of the given heights (top first) as top and
    /// bottom offsets from the centre, or says nil when that many lines can't go there. Nothing fits at all: two
    /// lines (or one, for a single word) at the smallest size.
    private static func fitTitle(_ title: String, ink: NSColor, radius: CGFloat,
                                 place: ([CGFloat]) -> [(top: CGFloat, bottom: CGFloat)]?) -> [NSAttributedString] {
        let layouts = G.hubTitleLayouts(title)
        for layout in layouts {
            let oneLineFirst = layout.count == 1 && layouts.count > 1
            for size in titleSizes where !oneLineFirst || size >= minOneLine {
                let lines = layout.map { titleLine($0, size: size, ink: ink) }
                guard let spots = place(lines.map { $0.size().height }) else { break }
                let fits = zip(lines, spots).allSatisfy { line, spot in
                    line.size().width <= G.hubLineWidth(radius: radius, top: spot.top, bottom: spot.bottom)
                }
                if fits { return lines }
            }
        }
        let fallback = layouts.last { place(Array(repeating: 0, count: $0.count)) != nil } ?? [title]
        return fallback.map { titleLine($0, size: titleSizes.last ?? 6.5, ink: ink) }
    }
}

/// One slice or option for VoiceOver: a button that picks it.
private final class RadialSliceElement: NSAccessibilityElement {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
