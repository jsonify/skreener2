import AppKit

/// The SK-1 look (#344), after the MT-1 Menu Timer panel: a cream chassis (charcoal in Dark Mode) with sunken trays
/// of raised keys, an olive LCD with seven-segment digits, and orange for what is on and for the main action.
///
/// The kit, for every surface that takes the look (Settings keeps the standard macOS controls):
///
/// Colours and type (`Retro`)
/// - `Retro.palette(for:)` / `Retro.Palette` (`Retro.light`, `Retro.dark`): the colours that change with the appearance;
///   `Retro.color(_:)` turns a token into an `NSColor`. The fixed ones: `Retro.orange` (what is on, the main action),
///   the orange and charcoal keys', the LCD's (`glassTop`…, `chipTop`…, `lcdInk`) and the lamps' (`teal`, `recRed`).
/// - `Retro.captionFont`, `Retro.mono(_:weight:)`, `Retro.caption(_:color:)`: the type. `Retro.chipAttributes`: an
///   LCD chip's mono text.
/// - `Retro.blinkLit(_:)`: whether a blinking lamp is lit (1 s, lit for the first half).
///
/// Drawing, for a custom view's `draw(_:)` (`Retro`)
/// - `drawPlate`: a chassis plate with rounded corners (cream or charcoal with its glow, a hairline edge).
/// - `drawWell`: a sunken tray. `drawKey` (with `keyColors`, `keyFace`) and `drawOnBar`: a raised key and the
///   selected key's orange bar. `drawToggleSquare`: a toggle's square. `drawLamp`: a small round lamp.
/// - `drawGlass`: olive LCD glass. `drawLCD`: glass in its sunken bezel. `drawChipGlass`: a small LCD chip's glass.
///   `drawChip` / `chipSize`: text on an LCD chip drawn straight on the screen (a selection's size).
///
/// Views
/// - `ChassisView`: a window's background (a drag moves the window). `ChassisPlate`: a floating bar's or card's
///   rounded chassis, which drags its window, swallows clicks or runs an action. `SpeakerGrille`: a decoration.
/// - `RetroLabel`: a caption or plain secondary text in the palette's ink.
/// - `PillButton` styles: `.keycap` (with `keyVariant` cream, orange or charcoal, `legend`, `isOn` pressed with an
///   orange bar), `.toggle` (an orange square and a label), `.round` (a small round key, e.g. a stepper's arrow) and
///   `.lcd` (a small olive readout). Any of them can carry a `caption` to its left.
/// - `PillPopUp(…, style: .lcd, stepper: true)`: an LCD chip between ◀ ▶ that steps through its items; a click on the
///   chip still opens the menu. `onStep` for a pull-down's own steps (the editor's zoom).
/// - `KeycapTray(keys, caption:)`: keys in a sunken tray with a caption under it. `KeySwitch`: an upright switch
///   with an LED. `RetroIndicator`: a toggle's square and caption that only shows a state.
/// - `RetroSegmented`: a few choices in a track, the chosen one charcoal. `SwatchRow` / `RoundSwatch`: round colour
///   swatches. `ColorPill`: one round swatch with a menu.
/// - `RetroUI`: builders for the windows (`key`, `toggle`, `menuKey`, `stepper`, `tray`, `hint`, `useChassis`,
///   `contentTop`). `RetroDialog`: a small modal dialog or sheet with an orange main key, for a form.
/// - LCDs (`LCDDisplay.swift`): `LCDDisplay` (the editor's status display), `ElapsedLCD` (the recording bar's),
///   `LCDReadout` (one line of mono text), `LCDChip` (a small readout), `SevenSegmentView` and `SevenSegment` (the
///   digits and their geometry).
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
    static let chipTop: UInt32 = 0xcfd5ba, chipMiddle: UInt32 = 0xc7cdb1, chipBottom: UInt32 = 0xbfc6a9
    /// A lamp's teal (a key under the pointer) and the REC lamp's red (the timer's).
    static let teal: UInt32 = 0x1f9e86, recRed: UInt32 = 0xe0402f
    /// How far a blinking lamp dims between blinks.
    static let lampDimmed: CGFloat = 0.2

    /// Whether a lamp that has blinked for `elapsed` seconds is lit: once a second, lit for the first half of it.
    static func blinkLit(_ elapsed: TimeInterval) -> Bool { Int((max(elapsed, 0) * 2).rounded(.down)) % 2 == 0 }

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

    /// A small LCD chip's glass in `rect`: lighter than the display's, with no pixel grid and a shallower shadow.
    static func drawChipGlass(_ rect: NSRect, radius: CGFloat, brightness: CGFloat, flipped: Bool) {
        drawGlass(rect, radius: radius, top: chipTop, middle: chipMiddle, bottom: chipBottom, brightness: brightness, grid: false,
                  shadowBlur: 2, shadowOffset: 1, flipped: flipped)
    }

    /// An LCD in `rect`: the sunken bezel (its light lip drawn 1 pt below `rect`) and the olive glass `inset` inside
    /// it. Returns the glass.
    @discardableResult
    static func drawLCD(in rect: NSRect, radius: CGFloat = 9, inset: CGFloat = 4, palette p: Palette, flipped: Bool) -> NSRect {
        drawWell(rect, radius: radius, top: color(p.bezelTop), bottom: color(p.bezelBottom), shadow: 0.18, lip: p.wellLip,
                 flipped: flipped)
        let glass = rect.insetBy(dx: inset, dy: inset)
        drawGlass(glass, radius: max(radius - inset + 1, 3), brightness: p.lcdBrightness, flipped: flipped)
        return glass
    }

    /// A chassis plate in `rect` with rounded corners: cream (charcoal in Dark Mode) with the white glow across its top,
    /// as `ChassisView`'s, and a hairline edge. A square plate (`radius` 0) fills a window or a menu, which has its own
    /// edge, so it gets none.
    static func drawPlate(_ rect: NSRect, radius: CGFloat, palette p: Palette, flipped: Bool) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        color(p.chassis).setFill()
        rect.fill()
        // The glow: an ellipse 1.6 times as wide as the plate, centred on its top edge.
        let glow = NSGradient(starting: NSColor.white.withAlphaComponent(p.chassisGlow), ending: NSColor.white.withAlphaComponent(0))
        let t = NSAffineTransform()
        t.translateX(by: rect.midX, yBy: flipped ? rect.minY : rect.maxY)
        t.scaleX(by: rect.width * 0.8, yBy: max(min(rect.height, 600), 1) * 0.8)
        t.concat()
        glow?.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 1, options: [])
        NSGraphicsContext.restoreGraphicsState()
        guard radius > 0 else { return }
        NSColor.black.withAlphaComponent(p.dark ? 0.55 : 0.25).setStroke()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        edge.stroke()
    }

    /// A small round lamp in `rect`: lit, `color` with a glow `glow` wide (0 for none, e.g. on the LCD's glass);
    /// unlit, `unlit` (by default a faint dark dot).
    static func drawLamp(in rect: NSRect, color: NSColor, lit: Bool, unlit: NSColor? = nil, glow: CGFloat = 4) {
        let dot = NSBezierPath(ovalIn: rect)
        guard lit else {
            (unlit ?? NSColor.black.withAlphaComponent(0.14)).setFill()
            dot.fill()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        if glow > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = color
            shadow.shadowBlurRadius = glow
            shadow.set()
        }
        color.setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A toggle's square in `square` (9 pt): orange while `on`, the palette's off colour otherwise, with a light top
    /// edge and a hairline.
    static func drawToggleSquare(_ square: NSRect, on: Bool, palette p: Palette, flipped: Bool) {
        let path = NSBezierPath(roundedRect: square, xRadius: 2, yRadius: 2)
        color(on ? orange : p.toggleOff).setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: NSRect(x: square.minX, y: flipped ? square.minY : square.maxY - 1, width: square.width, height: 1)).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// The type for an LCD chip's text.
    static func chipAttributes(size: CGFloat = 11, alpha: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        [.font: mono(size, weight: .semibold), .foregroundColor: color(lcdInk, alpha: alpha), .kern: 0.3]
    }

    /// `text` on a small LCD chip at `origin` (its lower left corner, unflipped), for readouts drawn straight on the
    /// screen: the chip's glass with a dark rim and a soft shadow, the text in mono ink. `alpha` fades the whole chip.
    /// Returns the chip's rect.
    @discardableResult
    static func drawChip(_ text: String, at origin: NSPoint, size: CGFloat = 11, padding: NSSize = NSSize(width: 6, height: 3),
                         alpha: CGFloat = 1, brightness: CGFloat = 1) -> NSRect {
        let s = NSAttributedString(string: text, attributes: chipAttributes(size: size))
        let box = NSRect(origin: origin, size: chipSize(text, size: size, padding: padding))
        guard alpha > 0, let ctx = NSGraphicsContext.current?.cgContext else { return box }
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
        drawChipGlass(box, radius: 4, brightness: brightness, flipped: false)
        let t = s.size()
        s.draw(at: NSPoint(x: box.midX - t.width / 2, y: box.midY - t.height / 2))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        return box
    }

    /// How big `drawChip` draws `text`.
    static func chipSize(_ text: String, size: CGFloat = 11, padding: NSSize = NSSize(width: 6, height: 3)) -> NSSize {
        let t = NSAttributedString(string: text, attributes: chipAttributes(size: size)).size()
        return NSSize(width: ceil(t.width) + padding.width * 2, height: ceil(t.height) + padding.height * 2)
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

/// A floating bar's or card's chassis: `Retro.drawPlate` filling the view, in the appearance's palette (a window's
/// `ChassisView` is square). What a click on bare chassis does is `click`: drag the window (a bar), swallow it (a
/// panel over a selection, which must not start a new selection underneath) or run something (a toast that a click
/// dismisses).
final class ChassisPlate: NSView {
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
        Retro.drawPlate(bounds, radius: radius, palette: Retro.palette(for: self), flipped: isFlipped)
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
        Retro.drawToggleSquare(square, on: isOn, palette: p, flipped: isFlipped)
        let s = label(p)
        s.draw(at: NSPoint(x: square.maxX + 5, y: (bounds.height - s.size().height) / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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

/// Esc cancels; a borderless-looking window can still become key.
private final class DialogWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override var canBecomeKey: Bool { true }
}

/// A small dialog in the SK-1 look, for what used to be an `NSAlert` with an accessory view: a heading, a line of text,
/// the form, and a Cancel key with an orange main key. Run it modally or as a sheet; the main key is
/// `primaryKey` (disable it while the form is invalid) and `validate` can refuse it with a message.
final class RetroDialog: NSObject {
    let primaryKey: PillButton
    private let cancelKey: PillButton
    private let window: DialogWindow
    private let message = RetroLabel(text: "", tone: .soft, size: 12)
    /// Returns a problem to show instead of closing, or nil when the form is fine.
    var validate: (() -> String?)?

    /// `width` is the content's width; `body` is laid out at `width` minus the margins.
    init(title: String, message text: String, body: NSView, primary: String, secondary: String = "Cancel", width: CGFloat = 380) {
        primaryKey = RetroUI.key(primary, variant: .orange, height: 28)
        cancelKey = RetroUI.key(secondary, height: 28)
        window = DialogWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.finish(.cancel) }
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
        let content = RetroUI.useChassis(window)

        let margin: CGFloat = 20
        let inner = width - margin * 2
        let heading = RetroLabel(text: title, tone: .ink, size: 14)
        heading.font = .systemFont(ofSize: 14, weight: .bold)
        message.stringValue = text
        message.lineBreakMode = .byWordWrapping
        message.maximumNumberOfLines = 0
        message.cell?.wraps = true
        message.preferredMaxLayoutWidth = inner

        primaryKey.target = self
        primaryKey.action = #selector(primaryPressed)
        primaryKey.keyEquivalent = "\r"
        cancelKey.target = self
        cancelKey.action = #selector(cancelPressed)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelKey, primaryKey])
        buttons.spacing = 10

        let stack = NSStackView(views: [heading, message, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: RetroUI.contentTop(of: window, in: content), constant: 10),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            stack.widthAnchor.constraint(equalToConstant: inner),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        content.layoutSubtreeIfNeeded()
        let titleBar = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(NSSize(width: width, height: ceil(stack.fittingSize.height) + 10 + margin + max(titleBar, 0)))
    }

    /// Text above the form (e.g. what is wrong).
    func setMessage(_ text: String) { message.stringValue = text }

    /// What has the keyboard focus when the dialog opens (e.g. the form's first field).
    var initialFirstResponder: NSView? {
        get { window.initialFirstResponder }
        set { window.initialFirstResponder = newValue }
    }

    private func focusFirstResponder() {
        if let first = window.initialFirstResponder { window.makeFirstResponder(first) }
    }

    /// Runs as a modal window; true if the main key was pressed.
    func runModal() -> Bool {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        focusFirstResponder()
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response == .OK
    }

    /// Runs as a sheet on `parent`; `done` gets true if the main key was pressed.
    func beginSheet(on parent: NSWindow, done: @escaping (Bool) -> Void) {
        // The sheet's completion keeps the dialog alive: its keys only hold it weakly.
        parent.beginSheet(window) { [self] response in
            withExtendedLifetime(self) { done(response == .OK) }
        }
        focusFirstResponder()
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: response)
        } else {
            NSApp.stopModal(withCode: response)
        }
    }

    @objc private func primaryPressed() {
        if let problem = validate?() {
            NSSound.beep()
            message.stringValue = problem
            return
        }
        finish(.OK)
    }

    @objc private func cancelPressed() { finish(.cancel) }
}
