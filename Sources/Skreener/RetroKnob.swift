import AppKit

/// The arithmetic of `RetroKnob`, apart from drawing (unit-tested): where each of its positions points and how far a
/// drag or a scroll turns it. A knob has `count` positions from 0; a click-stop knob has one per choice, a smooth one
/// one per step of its range.
struct KnobScale: Equatable {
    enum Kind: Equatable {
        /// Clicks between `count` choices.
        case stops(count: Int)
        /// Turns smoothly from `min` to `max` in steps of `step`.
        case smooth(min: Int, max: Int, step: Int)
    }

    let kind: Kind

    /// How far the pointer turns from the first position to the last, in degrees: from seven o'clock round to five.
    static let sweep: CGFloat = 270
    /// The pointer's angle at the first position, in degrees counter-clockwise from three o'clock.
    static let startAngle: CGFloat = 225
    /// How far a drag goes for one click of a click-stop knob, and for the whole sweep of a smooth one, in points.
    static let dragPerStop: CGFloat = 22
    static let dragForSweep: CGFloat = 160
    /// The ticks round a smooth knob.
    static let smoothTicks = 11

    var count: Int {
        switch kind {
        case .stops(let n): return max(n, 1)
        case .smooth(let lo, let hi, let step): return max((hi - lo) / max(step, 1), 0) + 1
        }
    }

    var isSmooth: Bool { if case .smooth = kind { return true } else { return false } }

    func clamp(_ position: Int) -> Int { min(max(position, 0), count - 1) }

    /// How far round `position` is, from 0 (the first) to 1 (the last).
    func fraction(_ position: Int) -> CGFloat {
        count > 1 ? CGFloat(clamp(position)) / CGFloat(count - 1) : 0
    }

    /// The pointer's angle at `position`, in degrees counter-clockwise from three o'clock.
    func angle(_ position: Int) -> CGFloat { Self.startAngle - Self.sweep * fraction(position) }

    /// The ticks round the knob, each as a fraction of the sweep.
    var ticks: [CGFloat] {
        let n = isSmooth ? Self.smoothTicks : count
        return n > 1 ? (0..<n).map { CGFloat($0) / CGFloat(n - 1) } : [0]
    }

    /// How far a drag goes for one position.
    var dragPerPosition: CGFloat {
        isSmooth ? Self.dragForSweep / CGFloat(max(count - 1, 1)) : Self.dragPerStop
    }

    /// The positions a drag of `distance` points (up is positive) turns the knob, carrying what is left over in
    /// `carry` for the next move of the same drag.
    func steps(forDrag distance: CGFloat, carry: inout CGFloat) -> Int {
        carry += distance
        let steps = Int((carry / dragPerPosition).rounded(.towardZero))
        carry -= CGFloat(steps) * dragPerPosition
        return steps
    }

    /// The value at `position` of a smooth knob (a click-stop knob's position is its choice's index).
    func value(at position: Int) -> Int {
        guard case .smooth(let lo, _, let step) = kind else { return clamp(position) }
        return lo + clamp(position) * step
    }

    /// The position nearest `value` on a smooth knob.
    func position(for value: Int) -> Int {
        guard case .smooth(let lo, _, let step) = kind else { return clamp(value) }
        return clamp(Int((Double(value - lo) / Double(max(step, 1))).rounded()))
    }
}

/// An SK-1 knob (#353): a round cream knob seen from above with tick marks round it, and an LCD chip beside it that
/// shows the value, with the first and last values under the knob. A click-stop knob clicks between a few choices
/// (`init(stops:…)`, like a pop-up: `selectedTag()`), a smooth one turns through a range (`init(min:max:…)`, `value`).
///
/// Drag up or down to turn it, or scroll; with the keyboard focus the arrow keys, Page Up / Down, Home and End turn it.
/// A double-click puts it back to its default. It sends its action as it turns, or with `sendsWhileTurning` off only
/// once the turn ends (the drag let go, or a moment after the last scroll or key), for a setting whose change is hard
/// to undo.
final class RetroKnob: NSControl {
    let scale: KnobScale
    private let titles: [String]
    private let tags: [Int]
    private let format: (Int) -> String
    private(set) var position: Int
    private let defaultPosition: Int
    var sendsWhileTurning = true
    /// What the action was last sent for, so a turn that ends where it started sends nothing.
    private var sentPosition: Int
    private var dragCarry: CGFloat = 0
    private var scrollCarry: CGFloat = 0

    private static let knobSize: CGFloat = 52
    private static let gap: CGFloat = 10
    private static let scaleHeight: CGFloat = 11
    private static let chipFont: CGFloat = 11

    /// A click-stop knob for `stops` (title, tag), on the one tagged `selected`; a double-click picks `defaultTag`.
    init(name: String, stops: [(title: String, tag: Int)], selected: Int, defaultTag: Int) {
        let s = KnobScale(kind: .stops(count: stops.count))
        let t = stops.map(\.tag)
        scale = s
        titles = stops.map(\.title)
        tags = t
        format = { _ in "" }
        position = s.clamp(t.firstIndex(of: selected) ?? 0)
        defaultPosition = s.clamp(t.firstIndex(of: defaultTag) ?? 0)
        sentPosition = s.clamp(t.firstIndex(of: selected) ?? 0)
        super.init(frame: .zero)
        setUp(name)
    }

    /// A smooth knob from `min` to `max` in steps of `step`, showing values with `format`.
    init(name: String, min lo: Int, max hi: Int, step: Int = 1, value: Int, defaultValue: Int, format: @escaping (Int) -> String) {
        let s = KnobScale(kind: .smooth(min: lo, max: hi, step: step))
        scale = s
        titles = []
        tags = []
        self.format = format
        position = s.position(for: value)
        defaultPosition = s.position(for: defaultValue)
        sentPosition = s.position(for: value)
        super.init(frame: .zero)
        setUp(name)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp(_ name: String) {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(name)
        toolTip = name
    }

    /// A click-stop knob's chosen tag.
    override func selectedTag() -> Int { tags.indices.contains(position) ? tags[position] : -1 }

    /// A smooth knob's value; a click-stop knob's chosen tag.
    var value: Int { scale.isSmooth ? scale.value(at: position) : selectedTag() }

    private func title(at p: Int) -> String {
        scale.isSmooth ? format(scale.value(at: p)) : (titles.indices.contains(p) ? titles[p] : "")
    }

    // MARK: Layout and drawing

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }

    /// The widest value on the chip, so the chip doesn't change size as the knob turns.
    private var chipSize: NSSize {
        let samples = scale.isSmooth ? [title(at: 0), title(at: scale.count - 1), title(at: scale.count / 2)] : titles
        let widest = samples.map { Retro.chipSize($0, size: Self.chipFont, padding: NSSize(width: 9, height: 4)) }
            .max { $0.width < $1.width } ?? .zero
        return NSSize(width: max(widest.width, 64), height: widest.height)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.knobSize + Self.gap + chipSize.width + 2, height: Self.knobSize + Self.scaleHeight)
    }

    private var knobRect: NSRect { NSRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize) }
    /// The knob's body (the part that turns), inside the ring of ticks.
    private var capRect: NSRect { knobRect.insetBy(dx: 8, dy: 8) }

    /// The point `radius` from the knob's centre at `angle` (degrees counter-clockwise from three o'clock).
    private func point(_ angle: CGFloat, _ radius: CGFloat) -> NSPoint {
        let a = angle * .pi / 180
        return NSPoint(x: knobRect.midX + cos(a) * radius, y: knobRect.midY - sin(a) * radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let f = scale.fraction(position)

        // Ticks: lit orange up to the value.
        let tickRadius: CGFloat = scale.isSmooth ? 1.4 : 2
        for t in scale.ticks {
            let c = point(KnobScale.startAngle - KnobScale.sweep * t, Self.knobSize / 2 - 2.5)
            let dot = NSBezierPath(ovalIn: NSRect(x: c.x - tickRadius, y: c.y - tickRadius, width: tickRadius * 2, height: tickRadius * 2))
            if t <= f + 0.0001 {
                Retro.drawLamp(in: dot.bounds, color: Retro.color(Retro.orange), lit: true, glow: 3)
            } else {
                Retro.color(p.inkSoft, alpha: 0.55).setFill()
                dot.fill()
            }
        }

        // The knob: the shadow it casts and its skirt, the body, and the lighter top it turns by.
        let body = capRect
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(p.keyShadow * 1.4)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        Retro.color(p.keySkirt).setFill()
        NSBezierPath(ovalIn: body.offsetBy(dx: 0, dy: 2.5)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let bodyPath = NSBezierPath(ovalIn: body)
        Retro.fill(bodyPath, top: Retro.color(p.keyTop), bottom: Retro.color(p.keyBottom), flipped: true)
        NSColor.white.withAlphaComponent(p.keyHighlight * 0.8).setStroke()
        let rim = NSBezierPath()
        rim.appendArc(withCenter: NSPoint(x: body.midX, y: body.midY), radius: body.width / 2 - 0.75, startAngle: 200, endAngle: 340)
        rim.lineWidth = 1
        rim.stroke()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        bodyPath.lineWidth = 0.5
        bodyPath.stroke()
        let top = NSBezierPath(ovalIn: body.insetBy(dx: 4, dy: 4))
        Retro.fill(top, top: Retro.color(isHighlighted ? p.keyDownBottom : p.keyDownTop),
                   bottom: Retro.color(isHighlighted ? p.keyDownTop : p.keyTop), flipped: true)
        NSColor.black.withAlphaComponent(0.06).setStroke()
        top.lineWidth = 1
        top.stroke()

        // The pointer: charcoal on a click-stop knob, orange on a smooth one.
        let angle = scale.angle(position)
        let line = NSBezierPath()
        line.move(to: point(angle, 4))
        line.line(to: point(angle, body.width / 2 - 6))
        line.lineWidth = 3
        line.lineCapStyle = .round
        Retro.color(scale.isSmooth ? Retro.orange : p.keyInk).setStroke()
        line.stroke()

        // The first and last values under the knob.
        let ends = [title(at: 0), title(at: scale.count - 1)].map {
            NSAttributedString(string: $0.uppercased(), attributes: [.font: Retro.mono(8, weight: .semibold),
                                                                   .foregroundColor: Retro.color(p.inkSoft), .kern: 0.2])
        }
        let y = Self.knobSize - 1
        ends[0].draw(at: NSPoint(x: max(knobRect.midX - 22 - ends[0].size().width / 2, 0), y: y))
        ends[1].draw(at: NSPoint(x: knobRect.midX + 22 - ends[1].size().width / 2, y: y))

        // The value on its chip, in a sunken bezel.
        let size = chipSize
        let chip = NSRect(x: knobRect.maxX + Self.gap, y: knobRect.midY - size.height / 2, width: size.width, height: size.height)
        Retro.drawWell(chip.insetBy(dx: -2, dy: -2), radius: 6, top: Retro.color(p.bezelTop), bottom: Retro.color(p.bezelBottom),
                       shadow: 0.18, lip: p.wellLip, flipped: true)
        Retro.drawChipGlass(chip, radius: 4, brightness: p.lcdBrightness, flipped: true)
        let text = NSAttributedString(string: title(at: position).uppercased(), attributes: Retro.chipAttributes(size: Self.chipFont))
        let t = text.size()
        text.draw(at: NSPoint(x: chip.midX - t.width / 2, y: chip.midY - t.height / 2))
    }

    override func drawFocusRingMask() { NSBezierPath(ovalIn: capRect.insetBy(dx: -2, dy: -2)).fill() }
    override var focusRingMaskBounds: NSRect { capRect.insetBy(dx: -2, dy: -2) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Turning

    /// Moves to `p` (clamped); sends the action now or when the turn ends (`sendsWhileTurning`).
    private func turn(to p: Int, ending: Bool) {
        let p = scale.clamp(p)
        if p != position {
            position = p
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        if sendsWhileTurning {
            send()
        } else if ending {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(send), object: nil)
            perform(#selector(send), with: nil, afterDelay: 0.6)
        }
    }

    @objc private func send() {
        guard position != sentPosition else { return }
        sentPosition = position
        sendAction(action, to: target)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            turn(to: defaultPosition, ending: true)
            return
        }
        dragCarry = 0
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let steps = scale.steps(forDrag: -event.deltaY, carry: &dragCarry)
        if steps != 0 { turn(to: position + steps, ending: false) }
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        if !sendsWhileTurning { send() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { super.scrollWheel(with: event); return }
        // Up turns it up, whichever way the system scrolls.
        let up = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let steps: Int
        if event.hasPreciseScrollingDeltas {
            steps = scale.steps(forDrag: up, carry: &scrollCarry)
        } else {
            steps = up > 0 ? 1 : up < 0 ? -1 : 0
        }
        if steps != 0 { turn(to: position + steps, ending: true) }
    }

    override func keyDown(with event: NSEvent) {
        let page = scale.isSmooth ? max(scale.count / 10, 1) : 1
        switch event.specialKey {
        case .upArrow?, .rightArrow?: turn(to: position + 1, ending: true)
        case .downArrow?, .leftArrow?: turn(to: position - 1, ending: true)
        case .pageUp?: turn(to: position + page, ending: true)
        case .pageDown?: turn(to: position - page, ending: true)
        case .home?: turn(to: 0, ending: true)
        case .end?: turn(to: scale.count - 1, ending: true)
        default: super.keyDown(with: event)
        }
    }

    // MARK: Accessibility

    override func accessibilityValue() -> Any? { title(at: position) }
    override func accessibilityPerformIncrement() -> Bool { turn(to: position + 1, ending: true); return true }
    override func accessibilityPerformDecrement() -> Bool { turn(to: position - 1, ending: true); return true }
}
