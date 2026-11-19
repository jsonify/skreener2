import AppKit

/// The recording editor's callout track (#383), under the edit track and on the scrubber's time scale: a bar per
/// callout, stacked in rows where they overlap. Click a bar to select it, drag it to move it, drag its ends to make it
/// longer or shorter, and Delete removes it. The track only reports what is done; the editor changes the callouts.
@MainActor final class CalloutTrackView: NSView {
    enum Drag {
        case move(grab: Double)
        case resize(start: Bool)
    }

    var callouts: [Callout] = [] { didSet { if callouts != oldValue { changed() } } }
    var selected: UUID? { didSet { if selected != oldValue { needsDisplay = true } } }
    var duration: Double = 0 { didSet { if duration != oldValue { changed() } } }
    var time: Double = 0 { didSet { if time != oldValue { needsDisplay = true } } }
    var isEnabled = true { didSet { if isEnabled != oldValue { needsDisplay = true } } }
    /// Space left and right of the time scale, to line up with the scrubber's track.
    var inset: CGFloat = 0 { didSet { if inset != oldValue { changed() } } }

    var onSelect: ((UUID?) -> Void)?
    var onDragBegan: ((UUID) -> Void)?
    /// The callout was dragged: moved so it starts at the time, or its edge dragged to the time.
    var onDrag: ((UUID, Drag, Double) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDelete: (() -> Void)?

    private var dragging: (id: UUID, kind: Drag)?
    private static let handle: CGFloat = 6
    /// The most rows of bars; more overlapping callouts share the last one.
    private static let maxRows = 3

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Callouts")
        toolTip = "Callouts: drag to move, drag an end to change when it starts or ends, Delete removes"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }

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

    /// Each callout's row: the first one free when it starts.
    nonisolated static func rows(_ callouts: [Callout], maxRows: Int) -> [Int] {
        var ends = [Double](repeating: -.infinity, count: max(1, maxRows))
        var rows = [Int](repeating: 0, count: callouts.count)
        for i in callouts.indices.sorted(by: { callouts[$0].start < callouts[$1].start }) {
            let row = ends.firstIndex { $0 <= callouts[i].start } ?? ends.count - 1
            rows[i] = row
            ends[row] = max(ends[row], callouts[i].end)
        }
        return rows
    }

    private func barRects() -> [CGRect] {
        let rows = Self.rows(callouts, maxRows: Self.maxRows)
        let used = (rows.max() ?? 0) + 1
        let height = (bounds.height - 4) / CGFloat(used)
        return callouts.indices.map { i in
            let a = x(callouts[i].start), b = x(callouts[i].end)
            // Row 0 at the top.
            let y = bounds.maxY - 2 - height * CGFloat(rows[i] + 1)
            return CGRect(x: a, y: y + 1, width: max(b - a, 2), height: height - 2)
        }
    }

    private func hit(_ p: CGPoint) -> (index: Int, start: Bool?)? {
        let rects = barRects()
        for i in rects.indices.reversed() {
            let r = rects[i]
            guard r.insetBy(dx: -2, dy: 0).contains(p) else { continue }
            let handle = min(Self.handle, r.width / 3)
            if p.x <= r.minX + handle { return (i, true) }
            if p.x >= r.maxX - handle { return (i, false) }
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
        let alpha: CGFloat = isEnabled ? 1 : 0.35
        let rects = barRects()
        for (i, c) in callouts.enumerated() {
            let r = rects[i]
            let bar = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            let color = NSColor(srgbRed: c.color[0], green: c.color[1], blue: c.color[2], alpha: 1)
            color.withAlphaComponent(alpha * (c.id == selected ? 1 : 0.7)).setFill()
            bar.fill()
            if c.id == selected {
                Retro.color(p.ink, alpha: alpha).setStroke()
                bar.lineWidth = 2
                bar.stroke()
            }
            let text = c.kind == .text && !c.text.isEmpty ? c.text : c.kind.name
            let label: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor(cgColor: Callouts.labelColor(on: c.color))?.withAlphaComponent(alpha) ?? .white,
            ]
            let size = (text as NSString).size(withAttributes: label)
            if size.height <= r.height + 2, r.width > 24 {
                (text as NSString).draw(with: CGRect(x: r.minX + 4, y: r.midY - size.height / 2, width: r.width - 8, height: size.height),
                                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: label)
            }
        }
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

    override func resetCursorRects() {
        guard isEnabled else { return }
        for r in barRects() {
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
            return
        }
        let c = callouts[h.index]
        onSelect?(c.id)
        let kind: Drag = h.start.map { Drag.resize(start: $0) } ?? .move(grab: timeAt(p.x) - c.start)
        dragging = (c.id, kind)
        onDragBegan?(c.id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging else { return }
        let t = timeAt(convert(event.locationInWindow, from: nil).x)
        switch d.kind {
        case .move(let grab): onDrag?(d.id, d.kind, t - grab)
        case .resize: onDrag?(d.id, d.kind, t)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging = nil
        onDragEnded?()
    }

    override func keyDown(with event: NSEvent) {
        if isEnabled, event.keyCode == 51 || event.keyCode == 117, selected != nil {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
