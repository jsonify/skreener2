import CoreGraphics
import Foundation

/// Snapping boxes to what's in the screenshot (#123): a box drawn roughly around a button, a field or a card gets that
/// element's exact edges; Repeat on Similar Objects finds the other places in the screenshot that look like the inside
/// of a box (every avatar in a list, every price in a table). All in pixels, top-left origin.
enum ObjectSnap {
    /// Largest channel difference (0–255) between neighboring pixels still counted as the same color.
    static let tolerance = 16
    /// An edge has to run along at least this share of the box's side.
    static let minCoverage = 0.45

    /// Which sides of a box were moved onto an edge.
    struct Sides: Equatable {
        var left = false, right = false, top = false, bottom = false
        var any: Bool { left || right || top || bottom }
    }

    /// `box` with each side moved to the strongest edge within `reach` pixels of it, where there is one: a line
    /// between two neighboring columns (for the left and right sides) or rows (top and bottom) along which the color
    /// changes for at least `minCoverage` of the box's height (or width). Of edges about as strong, the nearest wins.
    static func snap(_ box: CGRect, in buf: PixelBuffer, reach: Int) -> (rect: CGRect, sides: Sides) {
        let x0 = Int(box.minX.rounded()), x1 = Int(box.maxX.rounded())
        let y0 = Int(box.minY.rounded()), y1 = Int(box.maxY.rounded())
        guard x1 - x0 >= 2, y1 - y0 >= 2, reach > 0 else { return (box, Sides()) }
        let rows = max(y0, 0)..<min(y1, buf.height), cols = max(x0, 0)..<min(x1, buf.width)

        /// The best boundary near `at`: `count` lines across, `along` the pixels each is measured over, `changes(b, i)`
        /// whether the color changes at boundary `b` on pixel `i` along it.
        func edge(near at: Int, count: Int, along: Range<Int>, _ changes: (Int, Int) -> Bool) -> Int? {
            guard !along.isEmpty else { return nil }
            var best: (b: Int, score: Double)?
            for b in stride(from: max(at - reach, 1), through: min(at + reach, count - 1), by: 1) {
                var n = 0
                for i in along where changes(b, i) { n += 1 }
                let score = Double(n) / Double(along.count)
                guard score >= minCoverage else { continue }
                if let cur = best {
                    let clearlyStronger = score > cur.score + 0.1
                    let asStrongAndNearer = abs(score - cur.score) <= 0.1 && abs(b - at) < abs(cur.b - at)
                    if !clearlyStronger && !asStrongAndNearer { continue }
                }
                best = (b, score)
            }
            return best?.b
        }
        func columnEdge(_ x: Int) -> Int? {
            edge(near: x, count: buf.width, along: rows) { b, y in differs(buf.rgba(x: b - 1, y: y), buf.rgba(x: b, y: y)) }
        }
        func rowEdge(_ y: Int) -> Int? {
            edge(near: y, count: buf.height, along: cols) { b, x in differs(buf.rgba(x: x, y: b - 1), buf.rgba(x: x, y: b)) }
        }

        var sides = Sides()
        var l = x0, r = x1, t = y0, btm = y1
        if let e = columnEdge(x0) { l = e; sides.left = true }
        if let e = columnEdge(x1) { r = e; sides.right = true }
        if let e = rowEdge(y0) { t = e; sides.top = true }
        if let e = rowEdge(y1) { btm = e; sides.bottom = true }
        // Both sides on the same edge (a thin box near a line): leave that pair alone.
        if r - l < 2 { l = x0; r = x1; sides.left = false; sides.right = false }
        if btm - t < 2 { t = y0; btm = y1; sides.top = false; sides.bottom = false }
        let minX = sides.left ? CGFloat(l) : box.minX, maxX = sides.right ? CGFloat(r) : box.maxX
        let minY = sides.top ? CGFloat(t) : box.minY, maxY = sides.bottom ? CGFloat(btm) : box.maxY
        return (CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), sides)
    }

    private static func differs(_ p: (r: Int, g: Int, b: Int, a: Int), _ q: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
        max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a)) > tolerance
    }

    // MARK: Similar objects

    /// Largest mean brightness difference (0–255) between the box and a place that counts as looking the same.
    static let maxMeanDifference = 10
    /// At most this many places are returned.
    static let maxMatches = 60

    /// The other places in the screenshot that look like the inside of `box` (same size), best first, none overlapping
    /// `box` or each other. A box of one flat color matches nothing (it would match every empty area).
    static func similar(to box: CGRect, in buf: PixelBuffer) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) { ObjectSnap.similarNow(to: box, in: buf) }.value
    }

    static func similarNow(to box: CGRect, in buf: PixelBuffer) -> [CGRect] {
        let tx = Int(box.minX.rounded()), ty = Int(box.minY.rounded())
        let tw = Int(box.width.rounded()), th = Int(box.height.rounded())
        guard tw >= 4, th >= 4, tx >= 0, ty >= 0, tx + tw <= buf.width, ty + th <= buf.height else { return [] }
        let full = Gray(buf, factor: 1)
        // Searched at a lower resolution (about 10 pixels across the box's short side), then placed exactly.
        let f = max(1, min(tw, th) / 10)
        let small = f == 1 ? full : Gray(buf, factor: f)
        let sw = tw / f, sh = th / f, sx = tx / f, sy = ty / f
        guard sw >= 2, sh >= 2 else { return [] }
        let template = (0..<sh).flatMap { y in (0..<sw).map { x in small[sx + x, sy + y] } }
        let mean = template.reduce(0, +) / template.count
        let spread = template.reduce(0) { $0 + abs($1 - mean) } / template.count
        guard spread >= 6 else { return [] }

        // The low-resolution pass is loose (a block straddling an edge differs even where the objects are the same);
        // each candidate is then placed and checked at full resolution.
        let limit = 3 * maxMeanDifference * sw * sh
        var found: [(x: Int, y: Int, cost: Int)] = []
        if small.width >= sw, small.height >= sh {
            for y in 0...(small.height - sh) {
                for x in 0...(small.width - sw) {
                    var cost = 0
                    rows: for j in 0..<sh {
                        for i in 0..<sw {
                            cost += abs(small[x + i, y + j] - template[j * sw + i])
                        }
                        if cost > limit { break rows }
                    }
                    if cost <= limit { found.append((x, y, cost)) }
                }
            }
        }

        let original = CGRect(x: tx, y: ty, width: tw, height: th)
        var kept: [CGRect] = []
        /// A neighbor of a place already kept (or of the box itself) is the same object again.
        func taken(_ r: CGRect) -> Bool {
            let core = r.insetBy(dx: CGFloat(tw) * 0.2, dy: CGFloat(th) * 0.2)
            return core.intersects(original) || kept.contains { core.intersects($0) }
        }
        let samples = ((tw + 1) / 2) * ((th + 1) / 2)
        for m in found.sorted(by: { $0.cost < $1.cost }).prefix(2000) {
            guard !taken(CGRect(x: m.x * f, y: m.y * f, width: tw, height: th)) else { continue }
            let at = refine(x: m.x * f, y: m.y * f, search: f == 1 ? 0 : f, box: (tx, ty, tw, th), in: full)
            guard at.cost <= maxMeanDifference * samples else { continue }
            let r = CGRect(x: at.x, y: at.y, width: tw, height: th)
            guard !taken(r) else { continue }
            kept.append(r)
            if kept.count == maxMatches { break }
        }
        return kept
    }

    /// The best place for the box within `search` pixels of (x, y), at full resolution, and how much it differs there
    /// (summed over every other pixel each way).
    private static func refine(x: Int, y: Int, search: Int, box: (x: Int, y: Int, w: Int, h: Int),
                               in g: Gray) -> (x: Int, y: Int, cost: Int) {
        var best = (x: x, y: y, cost: Int.max)
        for dy in -search...search {
            for dx in -search...search {
                let px = x + dx, py = y + dy
                guard px >= 0, py >= 0, px + box.w <= g.width, py + box.h <= g.height else { continue }
                var cost = 0
                for j in stride(from: 0, to: box.h, by: 2) {
                    for i in stride(from: 0, to: box.w, by: 2) {
                        cost += abs(g[px + i, py + j] - g[box.x + i, box.y + j])
                    }
                    if cost >= best.cost { break }
                }
                if cost < best.cost { best = (px, py, cost) }
            }
        }
        return best
    }

    /// Brightness (0–255), each value the mean of a `factor` × `factor` block of pixels.
    private struct Gray {
        let width: Int, height: Int
        private let values: [Int]

        init(_ buf: PixelBuffer, factor f: Int) {
            width = buf.width / f; height = buf.height / f
            var v = [Int](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    var sum = 0
                    for j in 0..<f {
                        for i in 0..<f {
                            let p = buf.rgba(x: x * f + i, y: y * f + j)
                            sum += (p.r * 299 + p.g * 587 + p.b * 114) / 1000
                        }
                    }
                    v[y * width + x] = sum / (f * f)
                }
            }
            values = v
        }

        subscript(x: Int, y: Int) -> Int { values[y * width + x] }
    }
}
