import AppKit

/// The recording HUD's mic meter (#469), in the SK-1 look: a row of small segments in a sunken strip, green, then
/// amber, then red, with the peak marker and the clip light from `MicMeter`; "NO SOUND" instead when the microphone
/// delivers only silence. The tooltip and VoiceOver give `MicMeter.Advice`.
final class MicLevelMeterView: NSView {
    var meter = MicMeter() {
        didSet {
            guard meter != oldValue else { return }
            needsDisplay = true
            if meter.advice != oldValue.advice { refreshAdvice() }
        }
    }

    private static let segmentWidth: CGFloat = 4, segmentHeight: CGFloat = 9, gap: CGFloat = 2, inset: CGFloat = 2
    private static let green: UInt32 = 0x3aa655, amber: UInt32 = 0xf0a81c

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel("Microphone level")
        refreshAdvice()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let n = CGFloat(MicMeter.segments.count)
        return NSSize(width: n * Self.segmentWidth + (n - 1) * Self.gap + 2 * Self.inset,
                      height: Self.segmentHeight + 2 * Self.inset)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func refreshAdvice() {
        toolTip = meter.advice.text
        setAccessibilityValue(meter.advice.text)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let well = NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5)
        Retro.color(p.wellTop).setFill()
        well.fill()
        NSColor.black.withAlphaComponent(p.dark ? 0.5 : 0.18).setStroke()
        well.lineWidth = 0.5
        well.stroke()

        if meter.advice == .noSound {
            let text = NSAttributedString(string: "NO SOUND", attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .heavy), .foregroundColor: Retro.color(Retro.recRed), .kern: 0.6,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
            return
        }

        let lit = meter.litSegments
        for i in MicMeter.segments.indices {
            let x = Self.inset + CGFloat(i) * (Self.segmentWidth + Self.gap)
            let rect = NSRect(x: x, y: Self.inset, width: Self.segmentWidth, height: Self.segmentHeight)
            let isLast = i == MicMeter.segments.count - 1
            let on = i < lit || i == meter.heldSegment || (isLast && meter.isClipping)
            let color: UInt32
            switch MicMeter.zone(ofSegment: i) {
            case .good: color = Self.green
            case .hot: color = Self.amber
            case .clipping: color = Retro.recRed
            }
            (on ? Retro.color(color) : Retro.color(p.toggleOff)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
