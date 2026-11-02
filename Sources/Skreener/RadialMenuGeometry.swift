import Foundation

/// The radial menu's logic that needs no screen (#359): which slice the pointer or a key picks, where the ring goes on
/// the screen, and what its hub says. Points are relative to the ring's centre, y up (AppKit's unflipped coordinates);
/// angles are in radians, clockwise from the top, the way the slices are numbered.
enum RadialMenuGeometry {
    struct Slice: Equatable {
        let action: HotKeyAction
        /// The name on the hub's LCD.
        let title: String
        let symbol: String
    }

    /// The ring's slices, clockwise from the top. Record is the one orange key.
    static let slices = [
        Slice(action: .captureArea, title: "Area", symbol: "viewfinder"),
        Slice(action: .captureWindow, title: "Window", symbol: "macwindow"),
        Slice(action: .timedArea, title: "Self-Timer", symbol: "timer"),
        Slice(action: .captureScrolling, title: "Scrolling", symbol: "arrow.up.and.down.text.horizontal"),
        Slice(action: .captureText, title: "Text", symbol: "text.viewfinder"),
        Slice(action: .recordScreen, title: "Record", symbol: "record.circle"),
    ]

    /// The slices' outer and inner edges, and the hub inside them: nearer the centre than `hubRadius` picks nothing.
    static let outerRadius: CGFloat = 118
    static let innerRadius: CGFloat = 58
    static let hubRadius: CGFloat = 50
    /// The round chassis the ring sits in, and the ring's window: the chassis with room round it for its shadow.
    static let chassisRadius = outerRadius + 10
    static let windowSize = CGSize(width: (chassisRadius + 20) * 2, height: (chassisRadius + 20) * 2)
    /// How far from the centre a click still lands on the ring; beyond it a click closes the ring.
    static let clickReach = outerRadius + 6

    /// The angle of `point` from the centre, clockwise from the top, in 0..<2π.
    static func angle(of point: CGPoint) -> CGFloat {
        let a = atan2(point.x, point.y)   // x and y swapped: 0 at the top, growing clockwise
        return a < 0 ? a + 2 * .pi : a
    }

    /// The angle at the middle of slice `index` of `count`.
    static func centerAngle(of index: Int, count: Int) -> CGFloat {
        CGFloat(index) * 2 * .pi / CGFloat(count)
    }

    /// The point `radius` from the centre at `angle` (clockwise from the top).
    static func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: sin(angle) * radius, y: cos(angle) * radius)
    }

    /// The slice in the direction of `point`, or nil in the hub (`deadZone`) or beyond `reach`. The direction counts,
    /// not the wedge's edge, so a fast flick past the ring still picks; nil `reach` has no limit.
    static func slice(at point: CGPoint, count: Int, deadZone: CGFloat = hubRadius, reach: CGFloat? = nil) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(point.x, point.y)
        guard distance >= deadZone else { return nil }
        if let reach, distance > reach { return nil }
        let step = 2 * .pi / CGFloat(count)
        let shifted = (angle(of: point) + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return min(Int(shifted / step), count - 1)
    }

    /// The ring's window, `size` big, centred on `point` but moved (not cut off) to stay inside `visible`.
    static func frame(size: CGSize, centeredAt point: CGPoint, in visible: CGRect) -> CGRect {
        var r = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        r.origin.x = min(max(r.minX, visible.minX), max(visible.maxX - size.width, visible.minX))
        r.origin.y = min(max(r.minY, visible.minY), max(visible.maxY - size.height, visible.minY))
        return r
    }

    /// What letting go of the shortcut does: runs the slice under the pointer if the pointer moved onto one while it
    /// was held (a hold), else nothing, and the ring stays open for a click (a tap, or let go in the hub).
    static func pickOnRelease(highlight: Int?, pointerMoved: Bool) -> Int? {
        pointerMoved ? highlight : nil
    }

    /// The slice a number key picks: 1 is the top one, then clockwise.
    static func slice(forKey characters: String, count: Int) -> Int? {
        guard let n = Int(characters), (1...count).contains(n) else { return nil }
        return n - 1
    }

    /// The highlight after an arrow key: → and ↓ go clockwise, ← and ↑ back; from none, the first or last slice.
    static func step(_ highlight: Int?, clockwise: Bool, count: Int) -> Int {
        guard let highlight else { return clockwise ? 0 : count - 1 }
        return (highlight + (clockwise ? 1 : count - 1)) % count
    }

    struct HubText: Equatable {
        let title: String
        let detail: String
    }

    /// The hub's LCD: the highlighted slice's name and its shortcut (the self-timer its delay), or the resting text.
    static func hubText(for slice: Slice?, shortcut: String?, timerSeconds: Int) -> HubText {
        guard let slice else { return HubText(title: "Skreener", detail: "Pick a mode") }
        if slice.action == .timedArea { return HubText(title: slice.title, detail: "Area · \(timerSeconds) s") }
        return HubText(title: slice.title, detail: shortcut ?? "")
    }
}
