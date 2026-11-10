import CoreGraphics
import Foundation

// Editing markups and redactions after they are drawn, for the iOS editor (#440): finding the one under a finger,
// moving it, and dragging its handles (an arrow's or line's ends, a box's corners). All in image pixels (bottom-left
// origin), like the markups themselves.

/// A box's four corners as handles, numbered counterclockwise from the bottom-left (y-up): 0 (minX, minY),
/// 1 (maxX, minY), 2 (maxX, maxY), 3 (minX, maxY).
public enum BoxHandles {
    public static func corners(of rect: CGRect) -> [CGPoint] {
        let r = rect.standardized
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    /// `rect` with corner `i` dragged to `p`; the opposite corner stays put. Dragged past it, the box flips.
    public static func rect(_ rect: CGRect, movingCorner i: Int, to p: CGPoint) -> CGRect {
        let c = corners(of: rect)
        guard c.indices.contains(i) else { return rect.standardized }
        let fixed = c[(i + 2) % 4]
        return CGRect(x: min(fixed.x, p.x), y: min(fixed.y, p.y), width: abs(fixed.x - p.x),
                      height: abs(fixed.y - p.y))
    }

    /// How far `p` is from the outline of `rect` (0 on it), inside or out.
    static func distanceToOutline(_ p: CGPoint, _ rect: CGRect) -> CGFloat {
        let r = rect.standardized
        if r.contains(p) {
            return min(p.x - r.minX, r.maxX - p.x, p.y - r.minY, r.maxY - p.y)
        }
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}

extension Markup {
    /// A point of a markup that can be dragged to reshape it.
    public enum Handle: Equatable, Sendable {
        /// An arrow's or line's tail and head.
        case start, end
        /// A rectangle's, ellipse's or highlight's corner (`BoxHandles` numbering).
        case corner(Int)
    }

    /// The handles and where they are: an arrow's or line's two ends, a box's four corners; none for a pen stroke or
    /// text (they only move).
    public var handles: [(handle: Handle, point: CGPoint)] {
        switch kind {
        case .arrow(let a, let b), .line(let a, let b):
            return [(handle: Handle.start, point: a), (handle: Handle.end, point: b)]
        case .rectangle(let r), .ellipse(let r), .highlight(let r):
            return BoxHandles.corners(of: r).enumerated().map {
                (handle: Handle.corner($0.offset), point: $0.element)
            }
        case .pen, .text:
            return []
        }
    }

    /// The markup with `handle` dragged to `p`. A handle it doesn't have changes nothing.
    public func moving(_ handle: Handle, to p: CGPoint) -> Markup {
        var m = self
        switch (kind, handle) {
        case (.arrow(_, let b), .start): m.kind = .arrow(from: p, to: b)
        case (.arrow(let a, _), .end): m.kind = .arrow(from: a, to: p)
        case (.line(_, let b), .start): m.kind = .line(from: p, to: b)
        case (.line(let a, _), .end): m.kind = .line(from: a, to: p)
        case (.rectangle(let r), .corner(let i)): m.kind = .rectangle(BoxHandles.rect(r, movingCorner: i, to: p))
        case (.ellipse(let r), .corner(let i)): m.kind = .ellipse(BoxHandles.rect(r, movingCorner: i, to: p))
        case (.highlight(let r), .corner(let i)): m.kind = .highlight(BoxHandles.rect(r, movingCorner: i, to: p))
        default: break
        }
        return m
    }

    /// The same markup moved by (`dx`, `dy`) image pixels.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Markup {
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x + dx, y: q.y + dy) }
        var m = self
        switch kind {
        case .arrow(let a, let b): m.kind = .arrow(from: p(a), to: p(b))
        case .line(let a, let b): m.kind = .line(from: p(a), to: p(b))
        case .pen(let points): m.kind = .pen(points.map(p))
        case .rectangle(let r): m.kind = .rectangle(r.offsetBy(dx: dx, dy: dy))
        case .ellipse(let r): m.kind = .ellipse(r.offsetBy(dx: dx, dy: dy))
        case .text(let s, let at): m.kind = .text(s, at: p(at))
        case .highlight(let r): m.kind = .highlight(r.offsetBy(dx: dx, dy: dy))
        }
        return m
    }

    /// The box around what the markup draws (its stroke's middle, or a label's glyphs), to outline it when selected.
    public func selectionBounds(imageWidth: Int) -> CGRect {
        switch kind {
        case .arrow(let a, let b), .line(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .pen(let points):
            guard let first = points.first else { return .null }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        case .rectangle(let r), .ellipse(let r), .highlight(let r):
            return r.standardized
        case .text(let s, let at):
            return Markup.textBounds(s, at: at, imageWidth: imageWidth, scale: width)
        }
    }

    /// True when `p` is on the markup, or within `tolerance` of it: on an arrow's, line's, pen's, rectangle's or
    /// ellipse's stroke (not inside an outline, so whatever is under it stays reachable), anywhere in a highlight or
    /// over a label. A box too small to have an inside counts everywhere.
    public func hits(_ p: CGPoint, tolerance: CGFloat, imageWidth: Int) -> Bool {
        let reach = tolerance + Markup.lineWidth(imageWidth: imageWidth, scale: width) / 2
        switch kind {
        case .arrow(let a, let b), .line(let a, let b):
            return Self.distance(p, toSegment: a, b) <= reach
        case .pen(let points):
            guard let first = points.first else { return false }
            if points.count == 1 { return hypot(p.x - first.x, p.y - first.y) <= reach }
            return zip(points, points.dropFirst()).contains { Self.distance(p, toSegment: $0, $1) <= reach }
        case .rectangle(let r):
            let r = r.standardized
            if r.width <= 2 * reach || r.height <= 2 * reach { return r.insetBy(dx: -reach, dy: -reach).contains(p) }
            return BoxHandles.distanceToOutline(p, r) <= reach
        case .ellipse(let r):
            let r = r.standardized
            if r.width <= 2 * reach || r.height <= 2 * reach { return r.insetBy(dx: -reach, dy: -reach).contains(p) }
            return Self.distance(p, toEllipseIn: r) <= reach
        case .highlight(let r):
            return r.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .text:
            return selectionBounds(imageWidth: imageWidth).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    /// The topmost (newest) of `markups` that `p` hits, or nil.
    public static func index(at p: CGPoint, in markups: [Markup], tolerance: CGFloat, imageWidth: Int) -> Int? {
        markups.indices.last { markups[$0].hits(p, tolerance: tolerance, imageWidth: imageWidth) }
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// About how far `p` is from the ellipse inscribed in `r`, along the ray from its centre (close enough to pick it
    /// with a finger).
    static func distance(_ p: CGPoint, toEllipseIn r: CGRect) -> CGFloat {
        let a = r.width / 2, b = r.height / 2
        let dx = p.x - r.midX, dy = p.y - r.midY
        let d = hypot(dx, dy)
        guard a > 0, b > 0, d > 0 else { return min(a, b) }
        let k = sqrt((dx / a) * (dx / a) + (dy / b) * (dy / b))
        return abs(d - d / k)
    }
}

extension Redaction {
    /// The same redaction moved by (`dx`, `dy`) image pixels.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Redaction {
        Redaction(rect: rect.offsetBy(dx: dx, dy: dy), style: style)
    }

    /// The redaction with corner `i` (`BoxHandles` numbering) dragged to `p`.
    public func moving(corner i: Int, to p: CGPoint) -> Redaction {
        Redaction(rect: BoxHandles.rect(rect, movingCorner: i, to: p), style: style)
    }

    /// The topmost (newest) of `redactions` whose area, grown by `tolerance`, holds `p`, or nil.
    public static func index(at p: CGPoint, in redactions: [Redaction], tolerance: CGFloat) -> Int? {
        redactions.indices.last {
            redactions[$0].rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }
}
