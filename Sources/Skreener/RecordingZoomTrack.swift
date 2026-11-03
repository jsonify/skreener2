import AppKit

/// The recording editor's zoom track (#24), under the scrubber and on its time scale: a bar per zoom section. Click a
/// bar to select it, drag it to move it, drag its ends to make it longer or shorter, Delete removes it, and a double
/// click on an empty spot adds one. The track only reports what is done; the editor changes the sections
/// (`AutoZoom.move` and the like, which keep them apart) and sets them back here.
@MainActor final class ZoomTrackView: NSView {
    enum Drag {
        case move(grab: Double)
        case resize(AutoZoom.Edge)
    }

    var sections: [ZoomSection] = [] { didSet { if sections != oldValue { changed() } } }
    var selected: Int? { didSet { if selected != oldValue { needsDisplay = true } } }
    var duration: Double = 0 { didSet { if duration != oldValue { changed() } } }
    var time: Double = 0 { didSet { if time != oldValue { needsDisplay = true } } }
    /// Auto-zoom is off: the bars are drawn faded.
    var dimmed = false { didSet { if dimmed != oldValue { needsDisplay = true } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { needsDisplay = true } } }
    /// Space left and right of the time scale, to line up with the scrubber's track.
    var inset: CGFloat = 0 { didSet { if inset != oldValue { changed() } } }

    var onSelect: ((Int?) -> Void)?
    /// A drag of the section at the index began.
    var onDragBegan: ((Int) -> Void)?
    /// The section at the index was dragged: moved so it starts at the time, or its edge dragged to the time.
    var onDrag: ((Int, Drag, Double) -> Void)?
    var onDragEnded: (() -> Void)?
    /// A double click on an empty spot, at that time.
    var onAdd: ((Double) -> Void)?
    var onDelete: (() -> Void)?

    private var dragging: (index: Int, kind: Drag)?
    /// How close (points) to a bar's end a press resizes it.
    private static let handle: CGFloat = 6

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Zoom sections")
        toolTip = "Zoom sections: drag to move, drag an end to resize, Delete removes, double-click adds"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 26) }

    private func changed() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Geometry

    private var track: CGRect { bounds.insetBy(dx: inset, dy: 0) }

    private func x(_ t: Double) -> CGFloat {
        guard duration > 0 else { return track.minX }
        return track.minX + CGFloat(t / duration) * track.width
    }

    private func timeAt(_ x: CGFloat) -> Double {
        guard track.width > 0 else { return 0 }
        return Double((x - track.minX) / track.width) * duration
    }

    private func barRect(_ s: ZoomSection) -> CGRect {
        let a = x(s.start), b = x(s.end)
        return CGRect(x: a, y: bounds.minY + 3, width: max(b - a, 2), height: bounds.height - 6)
    }

    /// The section under `p`, and whether the press is on one of its ends.
    private func hit(_ p: CGPoint) -> (index: Int, edge: AutoZoom.Edge?)? {
        for (i, s) in sections.enumerated() {
            let r = barRect(s)
            let handle = min(Self.handle, r.width / 3)
            guard r.insetBy(dx: -2, dy: 0).contains(p) else { continue }
            if p.x <= r.minX + handle { return (i, .start) }
            if p.x >= r.maxX - handle { return (i, .end) }
            return (i, nil)
        }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let well = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        Retro.color(p.track).setFill()
        well.fill()
        let alpha: CGFloat = (dimmed || !isEnabled) ? 0.35 : 1
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        for (i, s) in sections.enumerated() {
            let r = barRect(s)
            let bar = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            Retro.color(Retro.orange, alpha: alpha * (i == selected ? 1 : 0.75)).setFill()
            bar.fill()
            if i == selected {
                Retro.color(p.ink, alpha: alpha).setStroke()
                bar.lineWidth = 2
                bar.stroke()
                // Grips at the ends.
                Retro.color(p.ink, alpha: alpha).setFill()
                for gx in [r.minX + 2, r.maxX - 4] where r.width > 12 {
                    NSBezierPath(rect: CGRect(x: gx, y: r.midY - 5, width: 2, height: 10)).fill()
                }
            }
            let text = Self.levelText(s.level) + (s.mode == .fixed ? " fixed" : "")
            let size = (text as NSString).size(withAttributes: label)
            if size.width + 12 < r.width {
                (text as NSString).draw(at: CGPoint(x: r.minX + 6, y: r.midY - size.height / 2), withAttributes: label)
            }
        }
        // The playhead.
        if duration > 0 {
            let px = x(min(max(time, 0), duration)).rounded() + 0.5
            Retro.color(p.ink).setStroke()
            let line = NSBezierPath()
            line.move(to: CGPoint(x: px, y: bounds.minY))
            line.line(to: CGPoint(x: px, y: bounds.maxY))
            line.lineWidth = 1
            line.stroke()
        }
    }

    /// "2×", "1.25×".
    nonisolated static func levelText(_ level: Double) -> String {
        let s = String(format: "%.2f", level).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        return s + "×"
    }

    override func resetCursorRects() {
        guard isEnabled else { return }
        for s in sections {
            let r = barRect(s)
            let handle = min(Self.handle, r.width / 3)
            addCursorRect(CGRect(x: r.minX - 2, y: r.minY, width: handle + 2, height: r.height), cursor: .resizeLeftRight)
            addCursorRect(CGRect(x: r.maxX - handle, y: r.minY, width: handle + 2, height: r.height), cursor: .resizeLeftRight)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Mouse and keys

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        guard let h = hit(p) else {
            onSelect?(nil)
            if event.clickCount == 2 { onAdd?(min(max(timeAt(p.x), 0), duration)) }
            return
        }
        onSelect?(h.index)
        let kind: Drag = h.edge.map { Drag.resize($0) } ?? .move(grab: timeAt(p.x) - sections[h.index].start)
        dragging = (h.index, kind)
        onDragBegan?(h.index)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging else { return }
        let t = timeAt(convert(event.locationInWindow, from: nil).x)
        switch d.kind {
        case .move(let grab): onDrag?(d.index, d.kind, t - grab)
        case .resize: onDrag?(d.index, d.kind, t)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging = nil
        onDragEnded?()
    }

    override func keyDown(with event: NSEvent) {
        // Delete and forward delete.
        if isEnabled, event.keyCode == 51 || event.keyCode == 117, selected != nil {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
