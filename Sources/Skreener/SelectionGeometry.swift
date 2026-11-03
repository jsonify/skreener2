import Foundation

/// Rect math for the area selection (#102, #103), kept free of AppKit so `swift test` covers it. Rects are in
/// view coordinates (bottom-left origin, points).
enum SelectionGeometry {
    enum Key: Equatable { case left, right, down, up }

    /// Smallest selection the keys and the scroll wheel shrink to.
    static let minSide: CGFloat = 1

    /// The selection key for an arrow key code.
    static func key(keyCode: UInt16) -> Key? {
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }

    /// Arrows move the selection; ⌘ + arrows move its right or bottom edge (→ / ↓ grow, ← / ↑ shrink). One point per
    /// press, ten with Shift. The result stays inside `bounds`.
    static func apply(_ key: Key, command: Bool, shift: Bool, to rect: CGRect, in bounds: CGRect) -> CGRect {
        let step: CGFloat = shift ? 10 : 1
        var r = rect
        switch (key, command) {
        case (.left, false): r.origin.x -= step
        case (.right, false): r.origin.x += step
        case (.down, false): r.origin.y -= step
        case (.up, false): r.origin.y += step
        case (.right, true):
            r.size.width = min(r.width + step, bounds.maxX - r.minX)
        case (.left, true):
            r.size.width = max(r.width - step, minSide)
        case (.down, true):
            // The top edge stays put; the bottom one moves down.
            let h = min(r.height + step, r.maxY - bounds.minY)
            r = CGRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
        case (.up, true):
            let h = max(r.height - step, minSide)
            r = CGRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
        }
        // A move slides the whole rect back inside the bounds.
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    /// Grows (positive `points`) or shrinks every side of `rect` by `points`, for the scroll wheel. A grown rect stays
    /// inside `bounds`; a shrunk one keeps at least `minSide` each way.
    static func resizeAllSides(_ rect: CGRect, by points: CGFloat, in bounds: CGRect) -> CGRect {
        if points >= 0 { return rect.insetBy(dx: -points, dy: -points).intersection(bounds) }
        let dx = min(-points, max((rect.width - minSide) / 2, 0)), dy = min(-points, max((rect.height - minSide) / 2, 0))
        return rect.insetBy(dx: dx, dy: dy)
    }

    /// `rect` with each edge on the nearest whole point. Unlike `integral`, which rounds outwards, this keeps the size
    /// when only the position is fractional, so moving a selection never grows it.
    static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }

    /// The rect being dragged from `start` to `current`. `square` (Shift) makes it a square on the longer side;
    /// `fromCenter` (⌥) grows it around `start`. It stays inside `bounds` (a square stays square).
    static func dragRect(from start: CGPoint, to current: CGPoint, square: Bool, fromCenter: Bool, in bounds: CGRect) -> CGRect {
        var dx = current.x - start.x, dy = current.y - start.y
        // Room from `start` to the bounds in the direction of the drag (on both sides from the center).
        func room(_ d: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ s: CGFloat) -> CGFloat {
            fromCenter ? min(s - lo, hi - s) : (d < 0 ? s - lo : hi - s)
        }
        let roomX = max(room(dx, bounds.minX, bounds.maxX, start.x), 0)
        let roomY = max(room(dy, bounds.minY, bounds.maxY, start.y), 0)
        if square {
            let side = min(max(abs(dx), abs(dy)), roomX, roomY)
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        } else {
            dx = max(min(dx, roomX), -roomX)
            dy = max(min(dy, roomY), -roomY)
        }
        let a = fromCenter ? CGPoint(x: start.x - dx, y: start.y - dy) : start
        let b = CGPoint(x: start.x + dx, y: start.y + dy)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Resizes `rect` by dragging handle `index` (counter-clockwise from bottom-left: corners at even indexes, edge
    /// midpoints at odd ones) to `point`, clamped to `bounds`. Dragging past the opposite side flips the rect.
    static func resize(_ rect: CGRect, handle index: Int, to point: CGPoint, in bounds: CGRect) -> CGRect {
        let q = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if [0, 6, 7].contains(index) { minX = q.x }
        if [2, 3, 4].contains(index) { maxX = q.x }
        if [0, 1, 2].contains(index) { minY = q.y }
        if [4, 5, 6].contains(index) { maxY = q.y }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// How far the grab zones of `handleZones` reach: outside the selection, inside it along an edge, and along
    /// the edges from a corner (the drawn corner arms are 16 pt long).
    static let grabOutside: CGFloat = 12, grabInside: CGFloat = 10, grabCorner: CGFloat = 24

    /// Generous, non-overlapping grab zones for the eight handles of `rect`, indexed like `resize` (counter-clockwise
    /// from bottom-left: corners at even indexes, edges at odd ones). A corner takes a square around it, an edge
    /// the whole band along it between the corners, so the selection can be resized without hitting a handle
    /// exactly. Inside a small selection the zones shrink, leaving its middle to move it.
    static func handleZones(of rect: CGRect) -> [(index: Int, zone: CGRect)] {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return [] }
        let out = grabOutside
        let inX = min(grabInside, rect.width / 4), inY = min(grabInside, rect.height / 4)
        let cX = min(grabCorner, rect.width / 3), cY = min(grabCorner, rect.height / 3)
        let r = rect
        func zone(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
        }
        return [
            (0, zone(r.minX - out, r.minX + cX, r.minY - out, r.minY + cY)),
            (1, zone(r.minX + cX, r.maxX - cX, r.minY - out, r.minY + inY)),
            (2, zone(r.maxX - cX, r.maxX + out, r.minY - out, r.minY + cY)),
            (3, zone(r.maxX - inX, r.maxX + out, r.minY + cY, r.maxY - cY)),
            (4, zone(r.maxX - cX, r.maxX + out, r.maxY - cY, r.maxY + out)),
            (5, zone(r.minX + cX, r.maxX - cX, r.maxY - inY, r.maxY + out)),
            (6, zone(r.minX - out, r.minX + cX, r.maxY - cY, r.maxY + out)),
            (7, zone(r.minX - out, r.minX + inX, r.minY + cY, r.maxY - cY)),
        ]
    }

    /// The handle of `rect` whose grab zone holds `point`, or nil (inside the selection that means a move).
    static func handle(at point: CGPoint, of rect: CGRect) -> Int? {
        handleZones(of: rect).first { $0.zone.contains(point) }?.index
    }

    /// Moves `rect` so its origin is at `origin`, kept inside `bounds`.
    static func move(_ rect: CGRect, to origin: CGPoint, in bounds: CGRect) -> CGRect {
        CGRect(x: min(max(origin.x, bounds.minX), bounds.maxX - rect.width),
               y: min(max(origin.y, bounds.minY), bounds.maxY - rect.height),
               width: rect.width, height: rect.height)
    }
}
