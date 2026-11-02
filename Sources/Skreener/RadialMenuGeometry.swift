import Foundation

/// The radial menu's logic that needs no screen (#359): which slice or option the pointer or a key picks, where the ring
/// goes on the screen, and what its hub says. Points are relative to the ring's centre, y up (AppKit's unflipped
/// coordinates); angles are in radians, clockwise from the top, the way the slices are numbered.
///
/// A slice may have options. While it is pointed at they fan out in a band just past it; pointing at one there picks
/// the option instead of the slice.
enum RadialMenuGeometry {
    /// Another capture mode a slice offers.
    struct Option: Equatable {
        let action: HotKeyAction
        let title: String
        let symbol: String
    }

    struct Slice: Equatable {
        let action: HotKeyAction
        /// The name on the hub's LCD.
        let title: String
        let symbol: String
        /// Fanned out past the slice while it is pointed at, in clockwise order.
        var options: [Option] = []

        /// The self-timer's slice: its hub also picks the delay.
        var hasDelay: Bool { action == .timedArea }
    }

    /// The ring's slices, clockwise from the top. Record is the one orange key.
    static let slices = [
        Slice(action: .captureArea, title: "Area", symbol: "viewfinder", options: [
            Option(action: .capturePreviousArea, title: "Previous Area", symbol: "arrow.counterclockwise"),
            Option(action: .captureAreaAndPin, title: "Area & Pin", symbol: "pin"),
            Option(action: .captureAreaAndLivePin, title: "Live Pin", symbol: "pin.fill"),
        ]),
        Slice(action: .captureWindow, title: "Window", symbol: "macwindow", options: [
            Option(action: .captureActiveWindow, title: "Active Window", symbol: "macwindow.on.rectangle"),
            Option(action: .livePinWindow, title: "Live Pin Window", symbol: "pin.square"),
        ]),
        Slice(action: .timedArea, title: "Self-Timer", symbol: "timer", options: [
            Option(action: .timedArea, title: "Area", symbol: "viewfinder"),
            Option(action: .timedWindow, title: "Window", symbol: "macwindow"),
            Option(action: .timedFullscreen, title: "Fullscreen", symbol: "display"),
        ]),
        Slice(action: .captureScrolling, title: "Scrolling", symbol: "arrow.up.and.down.text.horizontal"),
        Slice(action: .captureText, title: "Text", symbol: "text.viewfinder", options: [
            Option(action: .captureCode, title: "Code", symbol: "chevron.left.forwardslash.chevron.right"),
            Option(action: .scanQRCode, title: "QR Code", symbol: "qrcode"),
        ]),
        Slice(action: .recordScreen, title: "Record", symbol: "record.circle", options: [
            Option(action: .stepRecorder, title: "Step Recorder", symbol: "list.number"),
            Option(action: .presenter, title: "Zoom & Draw", symbol: "pencil.tip"),
        ]),
    ]

    /// The self-timer delays its hub offers, as in the menu's Self-Timer submenu.
    static let delays = [3, 5, 10]

    /// The slices' outer and inner edges, and the hub inside them: nearer the centre than `hubRadius` picks nothing.
    static let outerRadius: CGFloat = 118
    static let innerRadius: CGFloat = 58
    static let hubRadius: CGFloat = 50
    /// The round chassis the ring sits in.
    static let chassisRadius = outerRadius + 10
    /// The options' band past the chassis: its keys' inner and outer edges, and the plate they sit on.
    static let bandInner = chassisRadius + 8
    static let bandOuter = bandInner + 42
    static let bandPlateRadius = bandOuter + 7
    /// How much of the circle each option takes in the band.
    static let optionWidth: CGFloat = 0.34
    /// The ring's window: room for the band and the shadows round it.
    static let windowSize = CGSize(width: (bandPlateRadius + 18) * 2, height: (bandPlateRadius + 18) * 2)
    /// How far from the centre a click still lands on the ring; beyond it (outside a band) a click closes the ring.
    static let clickReach = outerRadius + 6

    /// What the pointer, a click or a key points at: a slice, or one of a slice's options.
    enum Target: Equatable {
        case slice(Int)
        case option(slice: Int, option: Int)

        var sliceIndex: Int {
            switch self {
            case .slice(let s), .option(let s, _): return s
            }
        }
        var optionIndex: Int? {
            if case .option(_, let o) = self { return o }
            return nil
        }
    }

    /// The angle of `point` from the centre, clockwise from the top, in 0..<2π.
    static func angle(of point: CGPoint) -> CGFloat {
        let a = atan2(point.x, point.y)   // x and y swapped: 0 at the top, growing clockwise
        return a < 0 ? a + 2 * .pi : a
    }

    /// How far `angle` is clockwise from `reference`, in -π...π.
    static func delta(_ angle: CGFloat, from reference: CGFloat) -> CGFloat {
        var d = (angle - reference).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d <= -.pi { d += 2 * .pi }
        return d
    }

    /// The angle at the middle of slice `index` of `count`.
    static func centerAngle(of index: Int, count: Int) -> CGFloat {
        CGFloat(index) * 2 * .pi / CGFloat(count)
    }

    /// How much of the circle a band of `options` takes, centred on its slice.
    static func bandSpan(options: Int) -> CGFloat { optionWidth * CGFloat(options) }

    /// The angle at the middle of option `option` of `options`, fanned out round slice `slice` of `count`.
    static func optionAngle(slice: Int, count: Int, option: Int, options: Int) -> CGFloat {
        centerAngle(of: slice, count: count) - bandSpan(options: options) / 2 + (CGFloat(option) + 0.5) * optionWidth
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

    /// What `point` points at, with slice `active` pointed at until now (its options are fanned out). Past the ring in
    /// the direction of the band: the gap before it keeps the slice, the band picks the option in that direction. While
    /// the shortcut is `held` the direction alone counts (a flick past the band still picks); otherwise only a pointer on
    /// the ring or the band does. Nil in the hub and, unless held, off the ring.
    static func target(at point: CGPoint, active: Int?, held: Bool, slices: [Slice] = slices) -> Target? {
        let distance = hypot(point.x, point.y)
        guard distance >= hubRadius else { return nil }
        if let a = active, slices.indices.contains(a), !slices[a].options.isEmpty, distance > outerRadius {
            let k = slices[a].options.count
            let span = bandSpan(options: k)
            let d = delta(angle(of: point), from: centerAngle(of: a, count: slices.count))
            // A little either side of the band still counts, so a pointer at its edge doesn't flicker off it.
            if abs(d) <= span / 2 + 0.06 {
                if distance < bandInner - 4 { return .slice(a) }
                if !held && distance > bandPlateRadius + 6 { return nil }
                let o = Int(((d + span / 2) / optionWidth).rounded(.down))
                return .option(slice: a, option: min(max(o, 0), k - 1))
            }
        }
        guard let s = slice(at: point, count: slices.count, reach: held ? nil : clickReach) else { return nil }
        return .slice(s)
    }

    /// The ring's window, `size` big, centred on `point` but moved (not cut off) to stay inside `visible`.
    static func frame(size: CGSize, centeredAt point: CGPoint, in visible: CGRect) -> CGRect {
        var r = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        r.origin.x = min(max(r.minX, visible.minX), max(visible.maxX - size.width, visible.minX))
        r.origin.y = min(max(r.minY, visible.minY), max(visible.maxY - size.height, visible.minY))
        return r
    }

    /// What letting go of the shortcut does: runs what the pointer points at if it moved there while the shortcut was
    /// held (a hold), else nothing, and the ring stays open for a click (a tap, or let go in the hub).
    static func pickOnRelease(_ target: Target?, pointerMoved: Bool) -> Target? {
        pointerMoved ? target : nil
    }

    /// The capture mode `target` runs.
    static func action(for target: Target, slices: [Slice] = slices) -> HotKeyAction? {
        guard slices.indices.contains(target.sliceIndex) else { return nil }
        let slice = slices[target.sliceIndex]
        guard let o = target.optionIndex else { return slice.action }
        return slice.options.indices.contains(o) ? slice.options[o].action : nil
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

    /// Tab (or ⇧Tab, `forward` false) through the highlighted slice's options: after the last (or before the first)
    /// comes the slice itself (nil).
    static func stepOption(_ option: Int?, forward: Bool, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let option else { return forward ? 0 : count - 1 }
        let next = option + (forward ? 1 : -1)
        return (0..<count).contains(next) ? next : nil
    }

    /// The self-timer delays on the hub, side by side under its title: each one's rect, from the centre.
    static func delayRects() -> [CGRect] {
        let w: CGFloat = 24, h: CGFloat = 15, gap: CGFloat = 3
        let total = w * CGFloat(delays.count) + gap * CGFloat(delays.count - 1)
        return delays.indices.map { CGRect(x: -total / 2 + CGFloat($0) * (w + gap), y: -18, width: w, height: h) }
    }

    /// The delay a click at `point` picks on the hub, if any.
    static func delay(at point: CGPoint) -> Int? {
        zip(delays, delayRects()).first { $0.1.insetBy(dx: -1, dy: -3).contains(point) }?.0
    }

    struct HubText: Equatable {
        let title: String
        let detail: String
        /// The self-timer's delays are shown (and picked) under the title instead of `detail`.
        var showsDelays = false
    }

    /// The hub's LCD: the name of what is pointed at and its shortcut (for the self-timer, its delays), or the resting
    /// text.
    static func hubText(for target: Target?, shortcut: String?, slices: [Slice] = slices) -> HubText {
        guard let target, slices.indices.contains(target.sliceIndex) else { return HubText(title: "Skreener", detail: "Pick a mode") }
        let slice = slices[target.sliceIndex]
        let option = target.optionIndex.flatMap { slice.options.indices.contains($0) ? slice.options[$0] : nil }
        let title = option?.title ?? slice.title
        if slice.hasDelay { return HubText(title: title, detail: "", showsDelays: true) }
        return HubText(title: title, detail: shortcut ?? "")
    }
}
