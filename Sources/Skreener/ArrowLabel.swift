import Foundation

/// Where the label typed after drawing an arrow goes (#174), kept free of AppKit so `swift test` covers it. Points are in
/// image coordinates (bottom-left origin).
enum ArrowLabel {
    /// The frame for a label box of `size` just past `tail` (the arrow's end without a head), on the side away from
    /// `head`, `gap` points from it. The side of the box nearest the arrow faces the tail, so the box never covers it.
    static func frame(size: CGSize, tail: CGPoint, head: CGPoint, gap: CGFloat) -> CGRect {
        var dx = tail.x - head.x, dy = tail.y - head.y
        let length = hypot(dx, dy)
        if length > 0 { dx /= length; dy /= length } else { dx = -1; dy = 0 }
        let c = CGPoint(x: tail.x + dx * gap, y: tail.y + dy * gap)
        // Within about 22° of straight up or down the box is centered across the arrow; likewise sideways.
        let lean: CGFloat = 0.38
        let x = dx > lean ? c.x : dx < -lean ? c.x - size.width : c.x - size.width / 2
        let y = dy > lean ? c.y : dy < -lean ? c.y - size.height : c.y - size.height / 2
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
