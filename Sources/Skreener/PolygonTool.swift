import AppKit

/// Geometry for the pen's polygonal mode: building a multi-segment line by clicking vertices, deciding when a
/// click closes the shape, and testing whether a point falls inside a closed, filled polygon.
enum PolygonTool {
    /// Whether `p` is inside the polygon with `vertices` (ray casting, even–odd rule). Fewer than three vertices
    /// enclose nothing.
    static func contains(_ vertices: [CGPoint], point p: CGPoint) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let a = vertices[i], b = vertices[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Whether a click at `p` should close the polygon: only once three or more vertices are placed and the click lands
    /// within `distance` of the first vertex (the point the shape was started from).
    static func shouldClose(_ vertices: [CGPoint], at p: CGPoint, within distance: CGFloat) -> Bool {
        guard vertices.count >= 3, let first = vertices.first else { return false }
        return hypot(p.x - first.x, p.y - first.y) <= distance
    }

    /// The vertices joined by straight edges. `closed` appends the edge back to the first vertex (a closed polygon's
    /// fill and outline); otherwise the path stays an open multi-segment line.
    static func path(_ vertices: [CGPoint], closed: Bool = true) -> NSBezierPath {
        let p = NSBezierPath()
        guard let first = vertices.first else { return p }
        p.move(to: first)
        for v in vertices.dropFirst() { p.line(to: v) }
        if closed { p.close() }
        return p
    }
}
