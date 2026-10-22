/// The editor's pixel ruler (#107): from a pixel, how far the same color runs left and right (or up and down), so
/// holding the ruler over a button measures the button and over a gap measures the gap.
enum RulerScanner {
    enum Axis { case horizontal, vertical }

    /// Largest channel difference (0–255) still counted as the same color.
    static let defaultTolerance = 10
    /// With `outer`, a run of another color past an edge counts as that element's border only up to this many pixels;
    /// a longer one is the background.
    static let maxBorder = 16

    /// The pixels (inclusive, along `axis`) that share the color at (x, y) (top-left origin), or nil outside the image.
    /// `outer` also takes in a border on each side: the run of the next color, when it is at most `maxBorder` long.
    static func span(in buf: PixelBuffer, x: Int, y: Int, axis: Axis, tolerance: Int = defaultTolerance,
                     outer: Bool = false) -> ClosedRange<Int>? {
        guard buf.contains(x: x, y: y) else { return nil }
        let count = axis == .horizontal ? buf.width : buf.height
        let start = axis == .horizontal ? x : y
        func at(_ i: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            axis == .horizontal ? buf.rgba(x: i, y: y) : buf.rgba(x: x, y: i)
        }
        func same(_ p: (r: Int, g: Int, b: Int, a: Int), _ q: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
            max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a)) <= tolerance
        }
        let origin = at(start)
        /// The last index of the run of `color` from `i` (exclusive) in direction `step`, at most `limit` pixels on.
        func runEnd(from i: Int, step: Int, matching color: (r: Int, g: Int, b: Int, a: Int), limit: Int = .max) -> Int {
            var j = i, n = 0
            while j + step >= 0, j + step < count, n < limit, same(at(j + step), color) { j += step; n += 1 }
            return j
        }
        /// Past the edge at `edge`: the end of the next color's run, when that run is a border (short enough).
        func borderEnd(from edge: Int, step: Int) -> Int {
            let first = edge + step
            guard first >= 0, first < count else { return edge }
            let end = runEnd(from: first, step: step, matching: at(first), limit: maxBorder)
            // Longer than a border: it's the background around the element.
            return abs(end - first) + 1 > maxBorder ? edge : end
        }
        var lo = runEnd(from: start, step: -1, matching: origin)
        var hi = runEnd(from: start, step: 1, matching: origin)
        if outer {
            lo = borderEnd(from: lo, step: -1)
            hi = borderEnd(from: hi, step: 1)
        }
        return lo...hi
    }
}
