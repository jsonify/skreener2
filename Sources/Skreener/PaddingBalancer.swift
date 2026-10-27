import CoreGraphics

/// Auto-balance padding (#272): finds the content inside a screenshot's empty margins so the editor can crop to it with
/// the same margin on every side. All rects are in pixels with a top-left origin, like `PixelBuffer`.
enum PaddingBalancer {
    /// Largest channel difference (0–255) from the edge color still counted as empty margin.
    static let defaultTolerance = 12

    /// The margin color: the corner color that most other corners share, the top-left one on a tie.
    static func edgeColor(of buf: PixelBuffer, in r: (x0: Int, y0: Int, x1: Int, y1: Int),
                          tolerance: Int = defaultTolerance) -> (r: Int, g: Int, b: Int, a: Int) {
        let corners = [buf.rgba(x: r.x0, y: r.y0), buf.rgba(x: r.x1 - 1, y: r.y0),
                       buf.rgba(x: r.x0, y: r.y1 - 1), buf.rgba(x: r.x1 - 1, y: r.y1 - 1)]
        let votes = corners.map { c in corners.filter { differs($0, c, tolerance) == false }.count }
        return corners[votes.firstIndex(of: votes.max() ?? 0) ?? 0]
    }

    private static func differs(_ p: (r: Int, g: Int, b: Int, a: Int), _ q: (r: Int, g: Int, b: Int, a: Int),
                                _ tolerance: Int) -> Bool {
        max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a)) > tolerance
    }

    /// The pixel `region` (the whole image when nil) clipped to the image as integer bounds; nil when empty.
    private static func clip(_ buf: PixelBuffer, _ region: CGRect?) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let full = CGRect(x: 0, y: 0, width: buf.width, height: buf.height)
        let r = (region?.integral ?? full).intersection(full)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return (Int(r.minX), Int(r.minY), Int(r.maxX), Int(r.maxY))
    }

    /// The smallest rect holding every pixel that differs from the edge color by more than `tolerance`, or nil when
    /// the region is one flat color.
    static func contentBox(in buf: PixelBuffer, region: CGRect? = nil, tolerance: Int = defaultTolerance) -> CGRect? {
        guard let r = clip(buf, region) else { return nil }
        let edge = edgeColor(of: buf, in: r, tolerance: tolerance)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in r.y0..<r.y1 {
            for x in r.x0..<r.x1 where differs(buf.rgba(x: x, y: y), edge, tolerance) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// `content` grown by the smallest of its four margins inside `region`, so all four margins are equal and nothing
    /// is added. Nil when that is `region` itself (the content already fills it, or is already centered).
    static func balanced(content: CGRect, in region: CGRect) -> CGRect? {
        let c = content.intersection(region)
        guard !c.isNull, c.width > 0, c.height > 0 else { return nil }
        let m = min(c.minX - region.minX, region.maxX - c.maxX, c.minY - region.minY, region.maxY - c.maxY)
        let out = c.insetBy(dx: -m, dy: -m)
        return out == region ? nil : out
    }

    /// The balanced rect for the pixels in `region` (the whole image when nil), or nil when there is nothing to do.
    /// `keeping` are other rects (annotations) that must stay inside the result.
    static func balance(in buf: PixelBuffer, region: CGRect? = nil, keeping extra: [CGRect] = [],
                        tolerance: Int = defaultTolerance) -> CGRect? {
        guard let r = clip(buf, region), var box = contentBox(in: buf, region: region, tolerance: tolerance) else { return nil }
        let bounds = CGRect(x: r.x0, y: r.y0, width: r.x1 - r.x0, height: r.y1 - r.y0)
        for e in extra.map({ $0.integral.intersection(bounds) }) where !e.isNull && e.width > 0 && e.height > 0 {
            box = box.union(e)
        }
        return balanced(content: box, in: bounds)
    }
}
