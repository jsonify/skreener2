import AppKit

/// The SK-1 look (#344), after the MT-1 Menu Timer panel: a cream chassis (charcoal in Dark Mode) with sunken trays
/// of raised keys, an olive LCD with seven-segment digits, and orange for what is on and for the main action.
///
/// The kit, for every bar that takes the look:
/// - `Retro.palette(for:)` and `Retro.Palette`: the colours, light or dark, for a view's appearance; `Retro.color(_:)`
///   turns a token into an `NSColor`. The fixed colours (orange, the olive LCD) are `Retro.orange`, `Retro.lcdInk`….
/// - `Retro.captionFont`, `Retro.mono(_:weight:)`, `Retro.caption(_:color:)`: the type. `RetroLabel`: a label in
///   the palette's ink that follows the appearance (a caption, or plain secondary text).
/// - `ChassisView`: a window's background (and a drag handle for the window). `SpeakerGrille`: a decoration.
/// - `PillButton` styles: `.keycap` (with `keyVariant` cream, orange or charcoal, `legend`, `isOn` pressed with an
///   orange bar), `.toggle` (an orange square and a label), `.round` (a small round key, e.g. a stepper's arrow) and
///   `.lcd` (a small olive readout). Any of them can carry a `caption` to its left.
/// - `PillPopUp(…, style: .lcd, stepper: true)`: an LCD chip between ◀ ▶ that steps through its items; a click on the
///   chip still opens the menu. `onStep` for a pull-down's own steps (the editor's zoom).
/// - `KeycapTray(keys, caption:)`: keys in a sunken tray with a caption under it.
/// - `RetroSegmented`: a few choices in a track, the chosen one charcoal. `SwatchRow`: round colour swatches.
///   `ColorPill`: one round swatch with a menu. `KeySwitch`: an upright switch with an LED.
/// - `LCDDisplay` (a status display), `SevenSegmentView` (digits on an LCD) and `SevenSegment` (their geometry).
/// - `Retro.drawWell`, `Retro.drawKey`, `Retro.drawGlass`: the same shapes, for a custom view's `draw(_:)`.
enum Retro {
    /// The colours that change between light and dark, as 0xRRGGBB (alphas as fractions).
    struct Palette: Equatable {
        var dark: Bool
        /// The chassis, and the white glow across its top (alpha).
        var chassis: UInt32, chassisGlow: CGFloat
        /// A groove in the chassis (a rule between groups), and the light line under it (alpha of white).
        var groove: UInt32, grooveLip: CGFloat
        /// A sunken tray: its floor from top to bottom, its inner shadow (alpha) and the light lip under it (alpha).
        var wellTop: UInt32, wellBottom: UInt32, wellShadow: CGFloat, wellLip: CGFloat
        /// A cream key: its face from top to bottom, up and pressed, the skirt under it, the light along its top edge
        /// (alpha of white), the shadow it casts (alpha), and its ink.
        var keyTop: UInt32, keyBottom: UInt32, keyDownTop: UInt32, keyDownBottom: UInt32, keySkirt: UInt32
        var keyHighlight: CGFloat, keyShadow: CGFloat, keyInk: UInt32
        /// The charcoal key (Settings): face top to bottom, skirt.
        var charcoalTop: UInt32, charcoalBottom: UInt32, charcoalSkirt: UInt32
        /// Captions and labels; secondary text and a key's legend.
        var ink: UInt32, inkSoft: UInt32
        /// The segmented control's track and its unselected text; a toggle's square when off.
        var track: UInt32, trackInk: UInt32, toggleOff: UInt32
        /// The LCD's bezel, top to bottom, and how bright its glass is (1 in light; a touch dimmer in dark).
        var bezelTop: UInt32, bezelBottom: UInt32, lcdBrightness: CGFloat
        /// The canvas well behind a screenshot, and its dots (alpha).
        var canvas: UInt32, canvasDot: CGFloat
        /// A speaker grille's holes, lit side and dark side.
        var grilleLight: UInt32, grilleDark: UInt32
    }

    static let light = Palette(
        dark: false, chassis: 0xebe8e1, chassisGlow: 0.55, groove: 0xd3cfc5, grooveLip: 0.7,
        wellTop: 0xe2ded6, wellBottom: 0xe9e6df, wellShadow: 0.16, wellLip: 0.9,
        keyTop: 0xfdfcfa, keyBottom: 0xe8e4dc, keyDownTop: 0xece9e2, keyDownBottom: 0xf6f4ef, keySkirt: 0xc7c2b7,
        keyHighlight: 1, keyShadow: 0.14, keyInk: 0x2b2a27,
        charcoalTop: 0x45433e, charcoalBottom: 0x252421, charcoalSkirt: 0x11100f,
        ink: 0x2b2a27, inkSoft: 0x67635a, track: 0xdcd8cf, trackInk: 0x57534b, toggleOff: 0xd3cfc5,
        bezelTop: 0xd2cec4, bezelBottom: 0xe2ded6, lcdBrightness: 1,
        canvas: 0xdcd8cf, canvasDot: 0.09, grilleLight: 0x8f8a80, grilleDark: 0x3d3b37)

    static let dark = Palette(
        dark: true, chassis: 0x2b2a27, chassisGlow: 0.06, groove: 0x1a1917, grooveLip: 0.06,
        wellTop: 0x1d1c1a, wellBottom: 0x242320, wellShadow: 0.5, wellLip: 0.07,
        keyTop: 0x4a4843, keyBottom: 0x36342f, keyDownTop: 0x302e2a, keyDownBottom: 0x3a3833, keySkirt: 0x1a1917,
        keyHighlight: 0.1, keyShadow: 0.45, keyInk: 0xece8df,
        charcoalTop: 0x2c2a27, charcoalBottom: 0x181715, charcoalSkirt: 0x0a0a09,
        ink: 0xece8df, inkSoft: 0xa8a397, track: 0x1f1e1c, trackInk: 0xa8a397, toggleOff: 0x4a4843,
        bezelTop: 0x1d1c1a, bezelBottom: 0x26251f, lcdBrightness: 0.86,
        canvas: 0x1f1e1c, canvasDot: 0.07, grilleLight: 0x1a1917, grilleDark: 0x0b0b0a)

    // The colours that are the same in light and dark.
    /// What is on: a toggle's square, the selected key's bar.
    static let orange: UInt32 = 0xff5c1c
    /// The orange key (the main action): face top to bottom, skirt.
    static let orangeTop: UInt32 = 0xff8045, orangeBottom: UInt32 = 0xf2520f, orangeSkirt: UInt32 = 0xb93a07
    /// The charcoal key's ink and the selected segment's.
    static let charcoalInk: UInt32 = 0xf2efe9
    /// The selected segment, top to bottom.
    static let segmentTop: UInt32 = 0x45433e, segmentBottom: UInt32 = 0x2a2926
    /// The LCD's glass, top to bottom, and its ink.
    static let glassTop: UInt32 = 0xd3d9be, glassMiddle: UInt32 = 0xc3caad, glassBottom: UInt32 = 0xb9c0a2
    static let lcdInk: UInt32 = 0x1e2318
    /// An LCD chip's glass, top to bottom.
    static let chipTop: UInt32 = 0xcfd5ba, chipBottom: UInt32 = 0xbfc6a9

    static func palette(dark: Bool) -> Palette { dark ? Self.dark : light }
    static func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    /// The palette for `view`'s appearance; call it while drawing, and redraw on `viewDidChangeEffectiveAppearance`.
    @MainActor static func palette(for view: NSView) -> Palette { palette(dark: isDark(view.effectiveAppearance)) }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
    /// `hex` scaled toward black by `brightness` (1 leaves it as it is): the LCD's glass in Dark Mode.
    static func color(_ hex: UInt32, brightness: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255 * brightness, green: CGFloat((hex >> 8) & 0xff) / 255 * brightness,
                blue: CGFloat(hex & 0xff) / 255 * brightness, alpha: 1)
    }
    static func rgb(_ hex: UInt32) -> RGBColor {
        RGBColor(r8: Int((hex >> 16) & 0xff), g8: Int((hex >> 8) & 0xff), b8: Int(hex & 0xff))
    }

    // MARK: Type

    /// Captions under trays and before controls: small, bold, upper case and tracked (with `captionKern`).
    static var captionFont: NSFont { .systemFont(ofSize: 9, weight: .semibold) }
    static let captionKern: CGFloat = 0.8
    /// The LCD's and the legends' type.
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
    /// `text` upper-cased and tracked, as a caption.
    static func caption(_ text: String, color: NSColor, font: NSFont = captionFont, kern: CGFloat = captionKern) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    // MARK: Drawing

    /// Fills `path` with a gradient from `top` to `bottom` as seen on screen, whichever way the view is flipped.
    static func fill(_ path: NSBezierPath, top: NSColor, bottom: NSColor, flipped: Bool) {
        NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: flipped ? -90 : 90)
    }

    /// A shadow inside `path`, as if its edge stood above what is in it; `offset` is how far down it falls.
    static func innerShadow(_ path: NSBezierPath, alpha: CGFloat, blur: CGFloat, offset: CGFloat = 1) {
        guard alpha > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -offset)   // down, in either orientation
        shadow.set()
        let ring = NSBezierPath(rect: path.bounds.insetBy(dx: -20, dy: -20))
        ring.append(path.reversed)
        ring.windingRule = .evenOdd
        NSColor.black.setFill()
        ring.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A sunken tray in `rect`: a floor from `top` to `bottom`, an inner shadow under its top edge, and a light lip along
    /// its bottom (drawn 1 pt below `rect`, so leave room for it).
    static func drawWell(_ rect: NSRect, radius: CGFloat, top: NSColor, bottom: NSColor, shadow: CGFloat, lip: CGFloat,
                         flipped: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if lip > 0 {
            NSColor.white.withAlphaComponent(lip).setFill()
            NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: flipped ? 1 : -1), xRadius: radius, yRadius: radius).fill()
        }
        fill(path, top: top, bottom: bottom, flipped: flipped)
        innerShadow(path, alpha: shadow, blur: 2)
    }

    /// `drawWell` in the palette's tray colours.
    static func drawWell(_ rect: NSRect, radius: CGFloat, palette p: Palette, flipped: Bool) {
        drawWell(rect, radius: radius, top: color(p.wellTop), bottom: color(p.wellBottom), shadow: p.wellShadow,
                 lip: p.wellLip, flipped: flipped)
    }

    /// The three kinds of key.
    enum KeyVariant {
        /// The usual key.
        case cream
        /// The main action (Save).
        case orange
        /// A key apart from the rest (Settings).
        case charcoal
    }

    /// What a key is drawn with.
    struct KeyColors {
        var top: NSColor, bottom: NSColor, downTop: NSColor, downBottom: NSColor, skirt: NSColor
        /// The light along the face's top edge.
        var highlight: NSColor
        /// The symbol, title and legend.
        var ink: NSColor, legend: NSColor
        /// The shadow under the key.
        var shadow: NSColor, shadowAlpha: Float
    }

    static func keyColors(_ variant: KeyVariant, _ p: Palette) -> KeyColors {
        switch variant {
        case .cream:
            return KeyColors(top: color(p.keyTop), bottom: color(p.keyBottom), downTop: color(p.keyDownTop),
                             downBottom: color(p.keyDownBottom), skirt: color(p.keySkirt),
                             highlight: NSColor.white.withAlphaComponent(p.keyHighlight), ink: color(p.keyInk),
                             legend: color(p.inkSoft), shadow: .black, shadowAlpha: Float(p.keyShadow))
        case .orange:
            let top = color(orangeTop), bottom = color(orangeBottom)
            return KeyColors(top: top, bottom: bottom, downTop: bottom, downBottom: top, skirt: color(orangeSkirt),
                             highlight: NSColor.white.withAlphaComponent(0.35), ink: .white,
                             legend: NSColor.white.withAlphaComponent(0.8), shadow: color(orangeBottom),
                             shadowAlpha: p.dark ? 0.5 : 0.35)
        case .charcoal:
            let top = color(p.charcoalTop), bottom = color(p.charcoalBottom)
            return KeyColors(top: top, bottom: bottom, downTop: bottom, downBottom: top, skirt: color(p.charcoalSkirt),
                             highlight: NSColor.white.withAlphaComponent(0.12), ink: color(charcoalInk),
                             legend: color(charcoalInk, alpha: 0.7), shadow: .black, shadowAlpha: p.dark ? 0.6 : 0.3)
        }
    }

    /// Where a key's face is in `bounds`: all but the bottom `skirt`, or (pressed) moved down onto it.
    static func keyFace(in bounds: NSRect, skirt: CGFloat = 2, down: Bool, flipped: Bool) -> NSRect {
        let raisedUp = !down
        // Up, the face is at the visual top; pressed, at the visual bottom.
        let atLowY = raisedUp == flipped
        return NSRect(x: bounds.minX, y: atLowY ? bounds.minY : bounds.minY + skirt, width: bounds.width, height: bounds.height - skirt)
    }

    /// A raised key filling `bounds`: a face from top to bottom with a light top edge and a hairline, standing on a
    /// `skirt` of darker colour; pressed (`down`), the face sits on the skirt and is lit from below. Returns the face.
    /// The shadow it casts is the caller's (a layer shadow, which may fall outside the view).
    @discardableResult
    static func drawKey(in bounds: NSRect, radius: CGFloat, colors c: KeyColors, down: Bool, skirt: CGFloat = 2,
                        flipped: Bool) -> NSRect {
        let face = keyFace(in: bounds, skirt: skirt, down: down, flipped: flipped)
        if !down {
            c.skirt.setFill()
            NSBezierPath(roundedRect: face.offsetBy(dx: 0, dy: flipped ? skirt : -skirt), xRadius: radius, yRadius: radius).fill()
        }
        let facePath = NSBezierPath(roundedRect: face, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        facePath.addClip()
        // The light edge: the highlight, with the face drawn over it 1 pt lower.
        c.highlight.setFill()
        facePath.fill()
        let lower = NSBezierPath(roundedRect: face.offsetBy(dx: 0, dy: flipped ? 1 : -1), xRadius: radius, yRadius: radius)
        fill(lower, top: down ? c.downTop : c.top, bottom: down ? c.downBottom : c.bottom, flipped: flipped)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        let edge = NSBezierPath(roundedRect: face.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        edge.stroke()
        return face
    }

    /// The short glowing orange bar at the bottom of the selected key's face.
    static func drawOnBar(in face: NSRect, flipped: Bool) {
        let w = min(10, face.width / 2), h: CGFloat = 2
        let y = flipped ? face.maxY - 3 - h : face.minY + 3
        let bar = NSBezierPath(roundedRect: NSRect(x: face.midX - w / 2, y: y, width: w, height: h), xRadius: 1, yRadius: 1)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(orange)
        glow.shadowBlurRadius = 4
        glow.set()
        color(orange).setFill()
        bar.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// LCD glass in `rect`: olive, darker toward the bottom (dimmed by `brightness`), an inner shadow and dark edge,
    /// a sheen at the top left and a faint pixel grid.
    static func drawGlass(_ rect: NSRect, radius: CGFloat, top: UInt32 = glassTop, middle: UInt32 = glassMiddle,
                          bottom: UInt32 = glassBottom, brightness: CGFloat, grid: Bool = true, shadowBlur: CGFloat = 4,
                          shadowOffset: CGFloat = 2, flipped: Bool) {
        let glass = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let stops = [color(top, brightness: brightness), color(middle, brightness: brightness), color(bottom, brightness: brightness)]
        // Bottom first: gradients run from the bottom up.
        NSGradient(colors: stops.reversed(), atLocations: [0, 0.4, 1], colorSpace: .sRGB)?.draw(in: glass, angle: flipped ? -90 : 90)
        NSGraphicsContext.saveGraphicsState()
        glass.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.2), NSColor.white.withAlphaComponent(0)], atLocations: [0, 0.4],
                   colorSpace: .sRGB)?.draw(in: glass, angle: flipped ? 80 : -80)
        if grid {
            let lines = NSBezierPath()
            var y = rect.minY
            while y < rect.maxY { lines.appendRect(NSRect(x: rect.minX, y: y, width: rect.width, height: 1)); y += 2 }
            NSColor.black.withAlphaComponent(0.025).setFill()
            lines.fill()
            let columns = NSBezierPath()
            var x = rect.minX
            while x < rect.maxX { columns.appendRect(NSRect(x: x, y: rect.minY, width: 1, height: rect.height)); x += 2 }
            NSColor.black.withAlphaComponent(0.02).setFill()
            columns.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        innerShadow(glass, alpha: 0.28, blur: shadowBlur, offset: shadowOffset)
        NSColor.black.withAlphaComponent(0.25).setStroke()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: max(radius - 0.5, 0), yRadius: max(radius - 0.5, 0))
        edge.lineWidth = 1
        edge.stroke()
    }

    /// Whether two colours look the same (within a rounding step): which swatch the current colour is.
    static func sameColor(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        let d = abs(x.redComponent - y.redComponent) + abs(x.greenComponent - y.greenComponent) + abs(x.blueComponent - y.blueComponent)
        return d < 0.02 && abs(x.alphaComponent - y.alphaComponent) < 0.02
    }
}

/// A label in the SK-1 palette's ink, which follows the appearance: a caption (upper case, tracked, `Retro.ink`) or
/// plain text in the soft ink. Set `stringValue` on a plain one; a caption's text is `caption`.
final class RetroLabel: NSTextField {
    enum Tone { case ink, soft }
    private let tone: Tone
    private let isCaption: Bool
    var caption: String { didSet { refresh() } }

    /// A caption.
    init(caption: String, tone: Tone = .ink) {
        self.caption = caption
        self.tone = tone
        isCaption = true
        super.init(frame: .zero)
        setUp()
    }

    /// Plain text, e.g. a hint.
    init(text: String, tone: Tone = .soft, size: CGFloat = 12) {
        caption = ""
        self.tone = tone
        isCaption = false
        super.init(frame: .zero)
        setUp()
        font = .systemFont(ofSize: size)
        stringValue = text
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        translatesAutoresizingMaskIntoConstraints = false
        refresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        let p = Retro.palette(for: self)
        let ink = Retro.color(tone == .ink ? p.ink : p.inkSoft)
        if isCaption {
            attributedStringValue = Retro.caption(caption, color: ink)
            setAccessibilityLabel(caption)
        } else {
            textColor = ink
        }
    }
}

/// The SK-1 chassis: cream with a soft white glow across the top, charcoal in Dark Mode. As a window's content view,
/// a drag on bare chassis moves the window, as on the timer's panel.
final class ChassisView: NSView {
    /// Called after the appearance changes, for colours that aren't drawn here (e.g. a scroll view's background).
    var onAppearanceChange: (() -> Void)?

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.color(p.chassis).setFill()
        dirtyRect.fill()
        // The glow: an ellipse 1.6 times as wide as the view (at most 300 pt deep), centred on its top edge.
        let glow = NSGradient(starting: NSColor.white.withAlphaComponent(p.chassisGlow), ending: NSColor.white.withAlphaComponent(0))
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: bounds.midX, yBy: isFlipped ? bounds.minY : bounds.maxY)
        t.scaleX(by: bounds.width * 0.8, yBy: min(bounds.height, 600) * 0.5)
        t.concat()
        glow?.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 1, options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onAppearanceChange?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Rows of small round holes, like a speaker grille: a decoration for a corner of the chassis.
final class SpeakerGrille: NSView {
    private let columns: Int, rows: Int
    private static let hole: CGFloat = 4, gap: CGFloat = 3

    init(columns: Int = 7, rows: Int = 1) {
        self.columns = columns
        self.rows = rows
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let step = Self.hole + Self.gap
        return NSSize(width: CGFloat(columns) * step - Self.gap, height: CGFloat(rows) * step - Self.gap + 1)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let gradient = NSGradient(starting: Retro.color(p.grilleLight), ending: Retro.color(p.grilleDark))
        let step = Self.hole + Self.gap
        for row in 0..<rows {
            for col in 0..<columns {
                let top = CGFloat(row) * step
                let rect = NSRect(x: CGFloat(col) * step, y: isFlipped ? top : bounds.height - top - Self.hole - 1,
                                  width: Self.hole, height: Self.hole)
                // A light lip under each hole.
                NSColor.white.withAlphaComponent(p.dark ? 0.06 : 0.8).setFill()
                NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: isFlipped ? 0.5 : -0.5)).fill()
                gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: 0, y: isFlipped ? -0.3 : 0.3))
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The seven-segment digits of the timer's LCD: each digit is a 20 × 36 box of segments 3.6 thick with 0.7 gaps, the
/// row skewed 5° to the right, and the segments that are off still faintly there.
enum SevenSegment {
    enum Segment: String, CaseIterable {
        case a, b, c, d, e, f, g
    }

    static let width: CGFloat = 20, height: CGFloat = 36, thickness: CGFloat = 3.6, gap: CGFloat = 0.7
    /// The lean, in degrees (to the right, like italics).
    static let skew: CGFloat = 5
    /// How strongly an unlit segment shows.
    static let unlitOpacity: CGFloat = 0.07

    /// The segments lit for `c`: a digit, "-" or a space (nothing lit); anything else lights nothing.
    static func lit(_ c: Character) -> Set<Segment> {
        let map: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
                                        "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g"]
        return Set((map[c] ?? "").compactMap { Segment(rawValue: String($0)) })
    }

    /// The segment's outline in a `width` × `height` box, y down (as in the timer's SVG).
    static func polygon(_ s: Segment) -> [CGPoint] {
        let h = thickness / 2, l = thickness / 2, r = width - thickness / 2, m = height / 2
        func across(_ cy: CGFloat, _ x1: CGFloat, _ x2: CGFloat) -> [CGPoint] {
            [CGPoint(x: x1, y: cy), CGPoint(x: x1 + h, y: cy - h), CGPoint(x: x2 - h, y: cy - h), CGPoint(x: x2, y: cy),
             CGPoint(x: x2 - h, y: cy + h), CGPoint(x: x1 + h, y: cy + h)]
        }
        func down(_ cx: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> [CGPoint] {
            [CGPoint(x: cx, y: y1), CGPoint(x: cx + h, y: y1 + h), CGPoint(x: cx + h, y: y2 - h), CGPoint(x: cx, y: y2),
             CGPoint(x: cx - h, y: y2 - h), CGPoint(x: cx - h, y: y1 + h)]
        }
        switch s {
        case .a: return across(h, l + gap, r - gap)
        case .g: return across(m, l + gap, r - gap)
        case .d: return across(height - h, l + gap, r - gap)
        case .f: return down(l, h + gap, m - gap)
        case .b: return down(r, h + gap, m - gap)
        case .e: return down(l, m + gap, height - h - gap)
        case .c: return down(r, m + gap, height - h - gap)
        }
    }

    /// `value` right-aligned in `cells` digits, blank cells in front (a blank shows only unlit segments); too big
    /// a value shows as dashes.
    static func cells(_ value: Int, count: Int) -> String {
        let s = String(max(value, 0))
        guard s.count <= count else { return String(repeating: "-", count: count) }
        return String(repeating: " ", count: count - s.count) + s
    }

    /// How wide `text` is drawn `digitHeight` tall with `spacing` between characters (a ":" is narrow).
    static func textWidth(_ text: String, digitHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        let scale = digitHeight / height
        let widths = text.map { $0 == ":" ? 6 * scale : width * scale }
        return widths.reduce(0, +) + spacing * CGFloat(max(text.count - 1, 0)) + tan(skew * .pi / 180) * digitHeight
    }

    /// Draws `text` in `color`, digits `rect.height` tall from `rect`'s left edge.
    static func draw(_ text: String, in rect: NSRect, color: NSColor, spacing: CGFloat, flipped: Bool) {
        let scale = rect.height / height
        let lean = tan(skew * .pi / 180)
        var x = rect.minX
        // A point of the box (y down) in the view, leaning right toward the top.
        func point(_ p: CGPoint, _ originX: CGFloat) -> NSPoint {
            let dx = lean * (height - p.y) * scale
            return NSPoint(x: originX + p.x * scale + dx, y: flipped ? rect.minY + p.y * scale : rect.maxY - p.y * scale)
        }
        for ch in text {
            if ch == ":" {
                for cy in [12.0, 25.0] as [CGFloat] {
                    let c = point(CGPoint(x: 3, y: cy), x)
                    color.setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 2 * scale, y: c.y - 2 * scale, width: 4 * scale, height: 4 * scale)).fill()
                }
                x += 6 * scale + spacing
                continue
            }
            let on = lit(ch)
            for s in Segment.allCases {
                let pts = polygon(s).map { point($0, x) }
                let path = NSBezierPath()
                path.move(to: pts[0])
                pts.dropFirst().forEach { path.line(to: $0) }
                path.close()
                (on.contains(s) ? color : color.withAlphaComponent(color.alphaComponent * unlitOpacity)).setFill()
                path.fill()
            }
            x += width * scale + spacing
        }
    }
}

/// Seven-segment digits for an LCD (`text`: digits, "-", ":" and spaces), drawn in the LCD's ink with no background,
/// `digitHeight` tall.
final class SevenSegmentView: NSView {
    var text: String { didSet { if text != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var digitHeight: CGFloat { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var spacing: CGFloat = 2

    init(text: String = "", digitHeight: CGFloat = 22) {
        self.text = text
        self.digitHeight = digitHeight
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(SevenSegment.textWidth(text, digitHeight: digitHeight, spacing: spacing)), height: digitHeight)
    }
    override func accessibilityValue() -> Any? { text.trimmingCharacters(in: .whitespaces) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: (bounds.height - digitHeight) / 2, width: bounds.width, height: digitHeight)
        SevenSegment.draw(text, in: rect, color: Retro.color(Retro.lcdInk), spacing: spacing, flipped: isFlipped)
    }
}

/// A row of choices in a sunken track; the chosen one is a charcoal key with light text. Used like a pop-up: add
/// items with tags, read `selectedTag()`, `selectItem(withTag:)`; a click on another choice sends the action to the
/// target. An optional caption sits to its left.
final class RetroSegmented: NSView {
    weak var target: AnyObject?
    var action: Selector?
    private(set) var indexOfSelectedItem = -1
    private var segments: [Segment] = []
    private let row = NSStackView()
    private let track = TrackView()
    private let height: CGFloat

    var isEnabled = true {
        didSet { alphaValue = isEnabled ? 1 : 0.4; segments.forEach { $0.isEnabled = isEnabled } }
    }

    init(caption: String? = nil, height: CGFloat = 24) {
        self.height = height
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        track.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(row)
        let outer = NSStackView()
        outer.orientation = .horizontal
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false
        if let caption { outer.addArrangedSubview(RetroLabel(caption: caption)) }
        outer.addArrangedSubview(track)
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor), outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor), outer.bottomAnchor.constraint(equalTo: bottomAnchor),
            track.heightAnchor.constraint(equalToConstant: height),
            row.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -2),
            row.topAnchor.constraint(equalTo: track.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -2),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        if let caption { setAccessibilityLabel(caption) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var toolTip: String? {
        didSet { if accessibilityLabel()?.isEmpty != false { setAccessibilityLabel(toolTip) } }
    }

    /// Adds a choice; `help` is its tooltip and spoken name (e.g. "Open Head" for "Open").
    func addItem(_ title: String, tag: Int, help: String? = nil) {
        let s = Segment(title: title, tag: tag, owner: self)
        s.toolTip = help
        s.setAccessibilityLabel(help ?? title)
        segments.append(s)
        row.addArrangedSubview(s)
        if indexOfSelectedItem < 0 { select(0) }
    }

    func selectedTag() -> Int { segments.indices.contains(indexOfSelectedItem) ? segments[indexOfSelectedItem].value : -1 }

    func selectItem(withTag tag: Int) {
        if let i = segments.firstIndex(where: { $0.value == tag }) { select(i) }
    }

    private func select(_ i: Int) {
        indexOfSelectedItem = i
        for (n, s) in segments.enumerated() { s.isSelected = n == i }
    }

    fileprivate func picked(_ s: Segment) {
        guard isEnabled, let i = segments.firstIndex(where: { $0 === s }), i != indexOfSelectedItem else { return }
        select(i)
        if let action { NSApp.sendAction(action, to: target, from: self) }
    }

    /// The track: a sunken well in the track colour.
    private final class TrackView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let p = Retro.palette(for: self)
            Retro.drawWell(bounds.insetBy(dx: 0, dy: 0.5), radius: 6, top: Retro.color(p.track), bottom: Retro.color(p.track),
                           shadow: p.wellShadow, lip: p.dark ? 0.06 : 0.8, flipped: isFlipped)
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }

    /// One choice.
    fileprivate final class Segment: NSButton {
        let value: Int
        private let segmentTitle: String
        private weak var owner: RetroSegmented?
        var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected ? 1 : 0) } }

        init(title: String, tag: Int, owner: RetroSegmented) {
            value = tag
            segmentTitle = title
            self.owner = owner
            super.init(frame: .zero)
            isBordered = false
            self.title = ""
            target = self
            action = #selector(press)
            translatesAutoresizingMaskIntoConstraints = false
            widthAnchor.constraint(equalToConstant: ceil(Retro.caption(title, color: .black, kern: 0.6).size().width) + 14).isActive = true
            setAccessibilityRole(.radioButton)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        @objc private func press() { owner?.picked(self) }

        override func draw(_ dirtyRect: NSRect) {
            let p = Retro.palette(for: self)
            let ink: NSColor
            if isSelected {
                let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.shadowBlurRadius = 1.5
                shadow.shadowOffset = NSSize(width: 0, height: -0.5)
                shadow.set()
                Retro.color(Retro.segmentBottom).setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
                Retro.fill(path, top: Retro.color(Retro.segmentTop), bottom: Retro.color(Retro.segmentBottom), flipped: isFlipped)
                ink = Retro.color(Retro.charcoalInk)
            } else {
                ink = Retro.color(p.trackInk)
            }
            let text = Retro.caption(segmentTitle, color: ink, kern: 0.6)
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        override var focusRingMaskBounds: NSRect { bounds }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }
}

/// A round colour swatch: a small raised cream button holding a dot of `color`, ringed in ink while it is the one
/// chosen. `isMore` shows a colour wheel instead (for More Colors…), with the dot in the middle when `color` is set.
final class RoundSwatch: NSButton {
    var color: NSColor? { didSet { needsDisplay = true } }
    var isChosen = false { didSet { needsDisplay = true; setAccessibilityValue(isChosen ? "selected" : nil) } }
    var isMore = false { didSet { needsDisplay = true } }
    private let run: () -> Void

    init(color: NSColor?, name: String, size: CGFloat = 20, run: @escaping () -> Void) {
        self.color = color
        self.run = run
        super.init(frame: .zero)
        isBordered = false
        title = ""
        toolTip = name
        setAccessibilityLabel(name)
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func fire() { run() }

    override func draw(_ dirtyRect: NSRect) {
        Self.drawSwatch(in: bounds, color: color, chosen: isChosen, wheel: isMore, palette: Retro.palette(for: self),
                        pressed: isHighlighted, flipped: isFlipped)
    }

    /// The swatch in `bounds` (a circle as wide as it is tall): the raised button, the wheel or nothing, the dot, the ring.
    static func drawSwatch(in bounds: NSRect, color: NSColor?, chosen: Bool, wheel: Bool, palette p: Retro.Palette,
                           pressed: Bool, flipped: Bool) {
        let d = min(bounds.width, bounds.height) - 2
        let body = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        if chosen {
            Retro.color(p.ink).setFill()
            NSBezierPath(ovalIn: body.insetBy(dx: -1, dy: -1)).fill()
            Retro.color(p.chassis).setFill()
            NSBezierPath(ovalIn: body.insetBy(dx: 0.5, dy: 0.5)).fill()
        } else {
            // The skirt under it.
            Retro.color(p.keySkirt).setFill()
            NSBezierPath(ovalIn: body.offsetBy(dx: 0, dy: flipped ? 1 : -1)).fill()
        }
        let button = NSBezierPath(ovalIn: chosen ? body.insetBy(dx: 1.5, dy: 1.5) : body)
        Retro.fill(button, top: Retro.color(pressed ? p.keyDownTop : p.keyTop), bottom: Retro.color(pressed ? p.keyDownBottom : p.keyBottom),
                   flipped: flipped)
        NSColor.black.withAlphaComponent(0.12).setStroke()
        button.lineWidth = 0.5
        button.stroke()
        let dotSize = d * 0.6
        let dotRect = NSRect(x: body.midX - dotSize / 2, y: body.midY - dotSize / 2, width: dotSize, height: dotSize)
        if wheel {
            // Six hues round the dot.
            let hues: [CGFloat] = [0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6]
            let center = NSPoint(x: body.midX, y: body.midY), r = dotSize / 2 + (color == nil ? 0 : 1.5)
            for (i, hue) in hues.enumerated() {
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: r, startAngle: CGFloat(i) * 60, endAngle: CGFloat(i + 1) * 60)
                wedge.close()
                NSColor(hue: hue, saturation: 0.75, brightness: 0.95, alpha: 1).setFill()
                wedge.fill()
            }
        }
        if let color {
            let dot = NSBezierPath(ovalIn: wheel ? dotRect.insetBy(dx: 2, dy: 2) : dotRect)
            color.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.3).setStroke()
            dot.lineWidth = 0.5
            dot.stroke()
        }
    }

    override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Round swatches for the usual colours and a colour wheel for More Colors… (the colour panel); the current colour's
/// swatch is ringed, the wheel when it is none of them. A pick sets `color` and sends the action to the target, like
/// `ColorPill`. An optional caption sits to its left.
final class SwatchRow: NSView {
    weak var target: AnyObject?
    var action: Selector?
    var color: NSColor = .systemRed { didSet { refresh() } }
    private var swatches: [(color: NSColor, view: RoundSwatch)] = []
    private var more: RoundSwatch?

    /// `colors` defaults to `ColorPill.presets`.
    init(caption: String? = nil, colors: [(String, NSColor)]? = nil, size: CGFloat = 18) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        if let caption {
            row.addArrangedSubview(RetroLabel(caption: caption))
            row.setCustomSpacing(7, after: row.arrangedSubviews[0])
        }
        for (name, c) in colors ?? ColorPill.presets {
            let s = RoundSwatch(color: c, name: name, size: size) { [weak self] in self?.pick(c) }
            swatches.append((c, s))
            row.addArrangedSubview(s)
        }
        let wheel = RoundSwatch(color: nil, name: "More Colors…", size: size) { [weak self] in self?.showPanel() }
        wheel.isMore = true
        more = wheel
        row.addArrangedSubview(wheel)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(caption ?? "Color")
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        var found = false
        for s in swatches {
            let same = !found && Retro.sameColor(s.color, color)
            s.view.isChosen = same
            found = found || same
        }
        more?.isChosen = !found
        more?.color = found ? nil : color
    }

    private func pick(_ c: NSColor) {
        color = c
        if let action { NSApp.sendAction(action, to: target, from: self) }
    }

    private func showPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(panelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func panelChanged(_ panel: NSColorPanel) { pick(panel.color) }
}
