import AppKit

/// The recording editor's cut and speed track (#381), under the zoom track and on the same time scale: the recording's
/// waveform (#385), a hatched bar for every cut, a teal bar with its speed for every sped-up range, a violet one for
/// every muted range, and the In–Out selection the next edit applies to. Click a bar to select it, Delete removes it,
/// click an empty spot to deselect.
@MainActor final class EditTrackView: NSView {
    var edits: [TimelineEdit] = [] { didSet { if edits != oldValue { needsDisplay = true } } }
    /// The sound's loudest samples across the recording (`WaveformPeaks`), drawn behind the edits.
    var waveform: [Float] = [] { didSet { if waveform != oldValue { needsDisplay = true } } }
    private static let violet: UInt32 = 0x7a5cc8
    var selected: Int? { didSet { if selected != oldValue { needsDisplay = true } } }
    /// The In and Out marks, either of which may be missing.
    var markIn: Double? { didSet { if markIn != oldValue { needsDisplay = true } } }
    var markOut: Double? { didSet { if markOut != oldValue { needsDisplay = true } } }
    var duration: Double = 0 { didSet { if duration != oldValue { needsDisplay = true } } }
    var time: Double = 0 { didSet { if time != oldValue { needsDisplay = true } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { needsDisplay = true } } }
    /// Space left and right of the time scale, to line up with the scrubber's track.
    var inset: CGFloat = 0 { didSet { if inset != oldValue { needsDisplay = true } } }

    var onSelect: ((Int?) -> Void)?
    var onDelete: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Cuts, mutes and speed changes")
        toolTip = "The sound, with cuts, mutes and speed changes: click one to select it, Delete removes it"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    private var track: CGRect { bounds.insetBy(dx: inset, dy: 0) }

    private func x(_ t: Double) -> CGFloat {
        guard duration > 0 else { return track.minX }
        return track.minX + CGFloat(min(max(t, 0), duration) / duration) * track.width
    }

    private func rect(_ start: Double, _ end: Double) -> CGRect {
        CGRect(x: x(start), y: bounds.minY + 3, width: max(3, x(end) - x(start)), height: bounds.height - 6)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.color(p.track).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let alpha: CGFloat = isEnabled ? 1 : 0.35

        // The waveform: one bar per pixel column, the loudest of the buckets under it.
        if !waveform.isEmpty, track.width >= 1 {
            Retro.color(p.ink, alpha: 0.28 * alpha).setFill()
            let n = waveform.count
            let columns = Int(track.width)
            let maxHeight = bounds.height - 4
            for c in 0..<columns {
                let from = c * n / columns, to = max(from + 1, (c + 1) * n / columns)
                var peak: Float = 0
                for i in from..<min(to, n) { peak = max(peak, waveform[i]) }
                let h = CGFloat(WaveformPeaks.height(peak)) * maxHeight
                guard h >= 0.5 else { continue }
                CGRect(x: track.minX + CGFloat(c), y: bounds.midY - h / 2, width: 1, height: h).fill()
            }
        }

        // The In–Out selection, behind the edits.
        if let a = markIn ?? markOut {
            let b = markOut ?? markIn ?? a
            let r = rect(min(a, b), max(a, b)).insetBy(dx: 0, dy: -2)
            Retro.color(Retro.orange, alpha: 0.18 * alpha).setFill()
            r.fill()
            Retro.color(Retro.orange, alpha: alpha).setFill()
            for t in [markIn, markOut].compactMap({ $0 }) { CGRect(x: x(t) - 1, y: bounds.minY, width: 2, height: bounds.height).fill() }
        }

        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        for (i, e) in edits.enumerated() {
            let r = rect(e.start, e.end)
            let bar = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            let color = e.isCut ? Retro.recRed : e.isMute ? Self.violet : Retro.teal
            Retro.color(color, alpha: alpha * (i == selected ? 1 : 0.75)).setFill()
            bar.fill()
            if e.isCut {
                // Hatching: this part is left out.
                NSGraphicsContext.saveGraphicsState()
                bar.addClip()
                NSColor.white.withAlphaComponent(0.3 * alpha).setStroke()
                let hatch = NSBezierPath()
                var hx = r.minX - r.height
                while hx < r.maxX {
                    hatch.move(to: CGPoint(x: hx, y: r.minY))
                    hatch.line(to: CGPoint(x: hx + r.height, y: r.maxY))
                    hx += 6
                }
                hatch.lineWidth = 1.5
                hatch.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            if i == selected {
                Retro.color(p.ink, alpha: alpha).setStroke()
                bar.lineWidth = 2
                bar.stroke()
            }
            let size = (e.label as NSString).size(withAttributes: label)
            if size.width + 10 < r.width {
                (e.label as NSString).draw(at: CGPoint(x: r.minX + 5, y: r.midY - size.height / 2), withAttributes: label)
            }
        }

        if duration > 0 {
            let px = x(time).rounded() + 0.5
            Retro.color(p.ink).setStroke()
            let line = NSBezierPath()
            line.move(to: CGPoint(x: px, y: bounds.minY))
            line.line(to: CGPoint(x: px, y: bounds.maxY))
            line.lineWidth = 1
            line.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        onSelect?(edits.indices.last { rect(edits[$0].start, edits[$0].end).insetBy(dx: -2, dy: -3).contains(p) })
    }

    override func keyDown(with event: NSEvent) {
        // Delete and forward delete.
        if isEnabled, event.keyCode == 51 || event.keyCode == 117, selected != nil {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
