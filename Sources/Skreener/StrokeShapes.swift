import AppKit

/// Geometry for freehand strokes and the hand-drawn look (#119): simplifying and smoothing strokes, recognising a
/// stroke that was meant as a line, ellipse or rectangle, and a stable wobble.
enum StrokeShapes {
    /// What a freehand stroke was most likely meant to be.
    enum Fitted: Equatable {
        case line(CGPoint, CGPoint)
        case ellipse(CGRect)
        case rect(CGRect)
    }

    /// Ramer–Douglas–Peucker: the fewest points that stay within `epsilon` of the stroke. Keeps the first and last.
    static func simplify(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            var worst = lo, worstD: CGFloat = 0
            for i in (lo + 1)..<hi {
                let d = distance(pts[i], toSegment: pts[lo], pts[hi])
                if d > worstD { worstD = d; worst = i }
            }
            if worstD > epsilon {
                keep[worst] = true
                stack.append((lo, worst)); stack.append((worst, hi))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    /// A smooth curve through every point (Catmull–Rom), or straight segments for two points.
    static func smoothPath(_ pts: [CGPoint], closed: Bool = false) -> NSBezierPath {
        let p = NSBezierPath()
        guard let first = pts.first else { return p }
        p.move(to: first)
        guard pts.count > 2 else {
            pts.dropFirst().forEach { p.line(to: $0) }
            return p
        }
        let n = pts.count
        let segments = closed ? n : n - 1
        func at(_ i: Int) -> CGPoint {
            if closed { return pts[(i % n + n) % n] }
            return pts[min(max(i, 0), n - 1)]
        }
        for i in 0..<segments {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
        }
        if closed { p.close() }
        return p
    }

    /// The shape a stroke was meant as, when it is within `tolerance` (mean distance over the stroke's diagonal) of a
    /// straight line, or, for a closed stroke, of an ellipse or rectangle; nil for anything else.
    static func fit(_ pts: [CGPoint], tolerance: CGFloat = 0.06) -> Fitted? {
        guard pts.count >= 3, let first = pts.first, let last = pts.last else { return nil }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let box = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        let diag = hypot(box.width, box.height)
        guard diag > 10 else { return nil }
        let count = CGFloat(pts.count)

        if hypot(last.x - first.x, last.y - first.y) > diag * 0.25 {
            let err = pts.reduce(0) { $0 + distance($1, toSegment: first, last) } / count / diag
            return err < tolerance ? .line(first, last) : nil
        }
        guard box.width > 4, box.height > 4 else { return nil }
        let a = box.width / 2, b = box.height / 2, cx = box.midX, cy = box.midY
        let ellipseErr = pts.reduce(0) { sum, p in
            sum + abs(hypot((p.x - cx) / a, (p.y - cy) / b) - 1) * (a + b) / 2
        } / count / diag
        let rectErr = pts.reduce(0) { sum, p in
            sum + min(abs(p.x - box.minX), abs(p.x - box.maxX), abs(p.y - box.minY), abs(p.y - box.maxY))
        } / count / diag
        guard min(ellipseErr, rectErr) < tolerance else { return nil }
        return ellipseErr <= rectErr ? .ellipse(box) : .rect(box)
    }

    /// `path` redrawn as if by hand: walked at even steps, each point nudged across the line by a seeded random amount
    /// (the same seed gives the same wobble every time), and joined smoothly.
    static func handDrawn(_ path: NSBezierPath, seed: UInt64, amplitude: CGFloat) -> NSBezierPath {
        var rng = SeededRandom(seed: seed)
        let out = NSBezierPath()
        for (pts, closed) in polylines(path.flattened) {
            let even = resample(pts, step: max(amplitude * 8, 14))
            guard even.count >= 2 else { continue }
            let wobbly = even.enumerated().map { i, p -> CGPoint in
                // The ends of an open line stay put so arrowheads still meet it.
                if !closed && (i == 0 || i == even.count - 1) { return p }
                return CGPoint(x: p.x + rng.next(in: -amplitude...amplitude), y: p.y + rng.next(in: -amplitude...amplitude))
            }
            out.append(smoothPath(closed ? Array(wobbly.dropLast()) : wobbly, closed: closed))
        }
        return out
    }

    // MARK: Helpers

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The subpaths of a flattened path as point lists, and whether each is closed.
    private static func polylines(_ path: NSBezierPath) -> [([CGPoint], Bool)] {
        var out: [([CGPoint], Bool)] = []
        var current: [CGPoint] = []
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<path.elementCount {
            switch path.element(at: i, associatedPoints: &pts) {
            case .moveTo:
                if current.count > 1 { out.append((current, false)) }
                current = [pts[0]]
            case .closePath:
                if let f = current.first { current.append(f) }
                if current.count > 1 { out.append((current, true)) }
                current = []
            default:
                // A flattened path has only straight segments.
                current.append(pts[0])
            }
        }
        if current.count > 1 { out.append((current, false)) }
        return out
    }

    /// Points every `step` along a polyline (its ends included).
    private static func resample(_ pts: [CGPoint], step: CGFloat) -> [CGPoint] {
        guard var prev = pts.first else { return [] }
        var out = [prev], carried: CGFloat = 0
        for p in pts.dropFirst() {
            var seg = hypot(p.x - prev.x, p.y - prev.y)
            var from = prev
            while carried + seg >= step {
                let t = (step - carried) / seg
                from = CGPoint(x: from.x + (p.x - from.x) * t, y: from.y + (p.y - from.y) * t)
                out.append(from)
                seg = hypot(p.x - from.x, p.y - from.y)
                carried = 0
            }
            carried += seg
            prev = p
        }
        if let last = pts.last, out.last != last { out.append(last) }
        return out
    }
}

/// SplitMix64: a small, fast generator that always gives the same numbers for the same seed.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(next() >> 11) / CGFloat(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
