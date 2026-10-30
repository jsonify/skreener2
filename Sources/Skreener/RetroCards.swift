import AppKit

/// SK-1 pieces for the surfaces that float on their own (Quick Access, pins, the menu launcher; #344), on top of the
/// kit in `Retro.swift`. Anything here that other bars could use belongs in the kit.
enum RetroPlate {
    /// The teal lamp of a key that is under the pointer.
    static let teal: UInt32 = 0x1f9e86

    /// A chassis plate filling `rect`: the chassis colour with its glow across the top, and a groove-coloured hairline
    /// round the edge. The caller clips to the corners if the view is bigger than the plate.
    static func draw(_ rect: NSRect, radius: CGFloat, palette p: Retro.Palette, flipped: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        Retro.color(p.chassis).setFill()
        path.fill()
        Retro.fill(path, top: NSColor.white.withAlphaComponent(p.chassisGlow * 0.6), bottom: NSColor.white.withAlphaComponent(0),
                   flipped: flipped)
        Retro.color(p.groove).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// A tiny lamp: dark when off, `color` and glowing when on.
    static func drawLamp(in rect: NSRect, on: Bool, color: UInt32 = teal) {
        let dot = NSBezierPath(ovalIn: rect)
        if on {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = Retro.color(color)
            glow.shadowBlurRadius = 4
            glow.set()
            Retro.color(color).setFill()
            dot.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.black.withAlphaComponent(0.14).setFill()
            dot.fill()
        }
    }
}

/// A small olive LCD chip with mono text (a pin's zoom). `text` is spoken as its value.
final class RetroGlassChip: NSView {
    private let label = NSTextField(labelWithString: "")
    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            setAccessibilityValue(newValue)
        }
    }

    init(minWidth: CGFloat = 44, height: CGFloat = 20) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = Retro.mono(10, weight: .bold)
        label.textColor = Retro.color(Retro.lcdInk)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.drawGlass(bounds, radius: 3, top: Retro.chipTop, middle: 0xc7cdb1, bottom: Retro.chipBottom,
                        brightness: p.lcdBrightness, grid: false, shadowBlur: 2, shadowOffset: 1, flipped: isFlipped)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
