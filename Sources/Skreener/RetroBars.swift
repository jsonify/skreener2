import AppKit

/// SK-1 pieces for the floating capture bars and overlays (#344): the recording bar, the scrolling-capture bar, the
/// record options panel, the self-timer, the toast and the readouts on a selection. They build on `Retro`:
/// - `RetroBarPlate`: a floating bar's chassis with rounded corners (a window's `ChassisView` is square), which drags
///   its window, swallows clicks or runs an action. `RetroBars.drawPlate` draws the same in a custom view.
/// - `RetroBars.drawLCD`: a sunken bezel with olive glass in it. `ElapsedLCD`: the recording bar's LCD (a REC lamp,
///   the format and the elapsed time in seven-segment digits). `LCDReadout`: one line of mono text on LCD glass.
/// - `RetroBars.drawChip`: text on a small LCD chip, for readouts drawn straight on the screen (a selection's size).
/// - `RetroIndicator`: a toggle's orange square and caption that only shows a state (what a recording records).
enum RetroBars {
    /// The recording bar's elapsed time, "MM:SS" (minutes go past 99 rather than wrap).
    static func elapsed(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// What the recording bar's LCD says it records: "GIF", or "MP4" and the frame rate.
    static func formatLabel(gif: Bool, fps: Int) -> String { gif ? "GIF" : "MP4 \(fps)" }

    /// The REC lamp's red (the timer's), and how far it dims between blinks.
    static let recRed: UInt32 = 0xe0402f
    static let lampDimmed: CGFloat = 0.2

    /// The chassis in `rect` with rounded corners: cream (charcoal in Dark Mode) with the white glow across its top
    /// and a hairline edge.
    static func drawPlate(_ rect: NSRect, radius: CGFloat, palette p: Retro.Palette, flipped: Bool) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        Retro.color(p.chassis).setFill()
        rect.fill()
        // The glow: an ellipse 1.6 times as wide as the plate, centred on its top edge (as `ChassisView`'s).
        let glow = NSGradient(starting: NSColor.white.withAlphaComponent(p.chassisGlow), ending: NSColor.white.withAlphaComponent(0))
        let t = NSAffineTransform()
        t.translateX(by: rect.midX, yBy: flipped ? rect.minY : rect.maxY)
        t.scaleX(by: rect.width * 0.8, yBy: max(min(rect.height, 600), 1) * 0.8)
        t.concat()
        glow?.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 1, options: [])
        NSGraphicsContext.restoreGraphicsState()
        guard radius > 0 else { return }   // a square plate fills a window (or a popover), which has its own edge
        NSColor.black.withAlphaComponent(p.dark ? 0.55 : 0.25).setStroke()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        edge.stroke()
    }

    /// An LCD in `rect`: the sunken bezel (its light lip drawn 1 pt below `rect`) and the olive glass `inset` inside
    /// it. Returns the glass.
    @discardableResult
    static func drawLCD(in rect: NSRect, radius: CGFloat = 9, inset: CGFloat = 4, palette p: Retro.Palette, flipped: Bool) -> NSRect {
        Retro.drawWell(rect, radius: radius, top: Retro.color(p.bezelTop), bottom: Retro.color(p.bezelBottom), shadow: 0.18,
                       lip: p.wellLip, flipped: flipped)
        let glass = rect.insetBy(dx: inset, dy: inset)
        Retro.drawGlass(glass, radius: max(radius - inset + 1, 3), brightness: p.lcdBrightness, flipped: flipped)
        return glass
    }

    /// The type for an LCD chip's text.
    static func chipAttributes(size: CGFloat = 11, alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        [.font: Retro.mono(size, weight: .semibold), .foregroundColor: Retro.color(Retro.lcdInk, alpha: alpha), .kern: 0.3]
    }

    /// `text` on a small LCD chip at `origin` (its lower left corner, unflipped): the olive glass with a dark rim,
    /// the text in mono ink. `alpha` fades the whole chip. Returns the chip's rect.
    @discardableResult
    static func drawChip(_ text: String, at origin: NSPoint, size: CGFloat = 11, padding: NSSize = NSSize(width: 6, height: 3),
                         alpha: CGFloat = 1, brightness: CGFloat = 1) -> NSRect {
        let s = NSAttributedString(string: text, attributes: chipAttributes(size: size))
        let textSize = s.size()
        let box = NSRect(x: origin.x, y: origin.y, width: ceil(textSize.width) + padding.width * 2,
                         height: ceil(textSize.height) + padding.height * 2)
        drawChip(s, in: box, alpha: alpha, brightness: brightness)
        return box
    }

    /// How big `drawChip` draws `text`.
    static func chipSize(_ text: String, size: CGFloat = 11, padding: NSSize = NSSize(width: 6, height: 3)) -> NSSize {
        let t = NSAttributedString(string: text, attributes: chipAttributes(size: size)).size()
        return NSSize(width: ceil(t.width) + padding.width * 2, height: ceil(t.height) + padding.height * 2)
    }

    private static func drawChip(_ s: NSAttributedString, in box: NSRect, alpha: CGFloat, brightness: CGFloat) {
        guard alpha > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // A soft shadow lifts it off whatever is under it; a dark rim keeps it apart from light screens.
        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow()
        lift.shadowColor = NSColor.black.withAlphaComponent(0.45)
        lift.shadowBlurRadius = 3
        lift.shadowOffset = NSSize(width: 0, height: -1)
        lift.set()
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box.insetBy(dx: -1, dy: -1), xRadius: 5, yRadius: 5).fill()
        NSGraphicsContext.restoreGraphicsState()
        Retro.drawGlass(box, radius: 4, top: Retro.chipTop, middle: 0xc7cdb1, bottom: Retro.chipBottom, brightness: brightness,
                        grid: false, shadowBlur: 2, shadowOffset: 1, flipped: false)
        let t = s.size()
        s.draw(at: NSPoint(x: box.midX - t.width / 2, y: box.midY - t.height / 2))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

/// A floating bar's chassis: `RetroBars.drawPlate` filling the view, in the appearance's palette. What a click on
/// bare chassis does is `click`: drag the window (a bar), swallow it (a panel over a selection, which must not start
/// a new selection underneath) or run something (a toast that a click dismisses).
final class RetroBarPlate: NSView {
    enum Click {
        case drag, swallow
        case run(() -> Void)
    }

    var click: Click
    let radius: CGFloat
    /// Called after the appearance changes, for colours that aren't drawn here (e.g. a label's).
    var onAppearanceChange: (() -> Void)?

    init(radius: CGFloat = 14, click: Click = .drag) {
        self.radius = radius
        self.click = click
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RetroBars.drawPlate(bounds, radius: radius, palette: Retro.palette(for: self), flipped: isFlipped)
    }

    /// Whether a click moves the window is `click`'s to decide, even in a window movable by its background.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onAppearanceChange?()
    }

    override func mouseDown(with event: NSEvent) {
        switch click {
        case .drag: window?.performDrag(with: event)
        case .swallow: break
        case .run(let action): action()
        }
    }
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

/// The recording bar's LCD, after the timer's: a REC lamp that blinks (steady and "PAUSED" while paused) and what is
/// recorded ("MP4 60") along the top, the elapsed time in seven-segment digits under them.
final class ElapsedLCD: NSView {
    var time = "00:00" { didSet { if time != oldValue { needsDisplay = true } } }
    var detail = "" { didSet { if detail != oldValue { needsDisplay = true } } }
    var isPaused = false { didSet { if isPaused != oldValue { needsDisplay = true } } }
    /// The blink: lit or dimmed (ignored while paused).
    var lampLit = true { didSet { if lampLit != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Elapsed time")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 142, height: 62) }
    override func accessibilityValue() -> Any? { isPaused ? "\(time), paused" : time }
    /// Clicks go through to the chassis, which drags the bar.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let outer = NSRect(x: bounds.minX, y: bounds.minY + (isFlipped ? 0 : 1), width: bounds.width, height: bounds.height - 1)
        let glass = RetroBars.drawLCD(in: outer, palette: p, flipped: isFlipped)
        let ink = Retro.color(Retro.lcdInk)
        let inner = glass.insetBy(dx: 9, dy: 5)
        let rowHeight: CGFloat = 10
        let row = NSRect(x: inner.minX, y: isFlipped ? inner.minY : inner.maxY - rowHeight, width: inner.width, height: rowHeight)

        let type: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .heavy), .foregroundColor: ink, .kern: 1]
        let lamp = NSRect(x: row.minX, y: row.midY - 3, width: 6, height: 6)
        if isPaused {
            ink.withAlphaComponent(0.4).setFill()
            NSBezierPath(ovalIn: lamp).fill()
        } else {
            let red = Retro.color(RetroBars.recRed, alpha: lampLit ? 1 : RetroBars.lampDimmed)
            NSGraphicsContext.saveGraphicsState()
            if lampLit {
                let glow = NSShadow()
                glow.shadowColor = Retro.color(RetroBars.recRed)
                glow.shadowBlurRadius = 4
                glow.set()
            }
            red.setFill()
            NSBezierPath(ovalIn: lamp).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let state = NSAttributedString(string: isPaused ? "PAUSED" : "REC", attributes: type)
        state.draw(at: NSPoint(x: lamp.maxX + 4, y: row.midY - state.size().height / 2))
        var soft = type
        soft[.foregroundColor] = ink.withAlphaComponent(0.75)
        soft[.font] = NSFont.systemFont(ofSize: 8, weight: .semibold)
        let format = NSAttributedString(string: detail.uppercased(), attributes: soft)
        let formatSize = format.size()
        format.draw(at: NSPoint(x: row.maxX - formatSize.width, y: row.midY - formatSize.height / 2))

        // The digits fill what is left under the top row.
        let gap: CGFloat = 3
        let digitsArea = NSRect(x: inner.minX, y: isFlipped ? row.maxY + gap : inner.minY, width: inner.width,
                                height: inner.height - rowHeight - gap)
        let digitHeight = max(min(26, digitsArea.height), 8), spacing: CGFloat = 3
        let width = SevenSegment.textWidth(time, digitHeight: digitHeight, spacing: spacing)
        SevenSegment.draw(time, in: NSRect(x: digitsArea.midX - width / 2, y: digitsArea.midY - digitHeight / 2, width: width,
                                           height: digitHeight), color: ink, spacing: spacing, flipped: isFlipped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// One line of mono text on LCD glass in a small bezel, cut short at the end when it doesn't fit (a status line).
final class LCDReadout: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    private let height: CGFloat

    init(height: CGFloat = 30) {
        self.height = height
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityValue() -> Any? { text }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let outer = NSRect(x: bounds.minX, y: bounds.minY + (isFlipped ? 0 : 1), width: bounds.width, height: bounds.height - 1)
        let glass = RetroBars.drawLCD(in: outer, radius: 7, inset: 3, palette: p, flipped: isFlipped)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var attrs = RetroBars.chipAttributes(size: 11)
        attrs[.paragraphStyle] = para
        let s = NSAttributedString(string: text, attributes: attrs)
        let h = s.size().height
        let rect = NSRect(x: glass.minX + 8, y: glass.midY - h / 2, width: max(glass.width - 16, 0), height: h)
        guard rect.width > 0 else { return }
        s.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A toggle's look without the button: an orange square while `isOn` (the palette's off colour otherwise) and the
/// title in capitals. It shows a state that can't be changed here, e.g. that a recording takes in the microphone.
final class RetroIndicator: NSView {
    var isOn: Bool { didSet { needsDisplay = true; refreshAccessibility() } }
    private let title: String

    init(_ title: String, isOn: Bool) {
        self.title = title
        self.isOn = isOn
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        refreshAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func label(_ p: Retro.Palette) -> NSAttributedString {
        NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .bold), .foregroundColor: Retro.color(isOn ? p.ink : p.inkSoft), .kern: 0.6,
        ])
    }

    override var intrinsicContentSize: NSSize {
        let s = label(Retro.light).size()
        return NSSize(width: 9 + 5 + ceil(s.width) + 1, height: max(ceil(s.height), 12))
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func refreshAccessibility() { setAccessibilityLabel("\(title): \(isOn ? "on" : "off")") }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let square = NSRect(x: 0, y: (bounds.height - 9) / 2, width: 9, height: 9)
        let path = NSBezierPath(roundedRect: square, xRadius: 2, yRadius: 2)
        Retro.color(isOn ? Retro.orange : p.toggleOff).setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: NSRect(x: square.minX, y: isFlipped ? square.minY : square.maxY - 1, width: square.width, height: 1)).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        let s = label(p)
        s.draw(at: NSPoint(x: square.maxX + 5, y: (bounds.height - s.size().height) / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
