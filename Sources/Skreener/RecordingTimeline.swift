import CoreGraphics
import Foundation

/// Maps host-clock times (what ScreenCaptureKit stamps frames with, and `CMClockGetHostTimeClock` reads) to the
/// recording's video timeline: seconds from the first video frame, with time spent paused left out. This mirrors how
/// `ScreenRecorder` shifts samples back by the time paused (#380).
struct RecordingClock: Equatable {
    /// Host time of the first frame, shifted back by the time paused before it: video time 0.
    private(set) var start: Double?
    private(set) var pausedTotal: Double = 0
    private(set) var pauseStart: Double?

    var isPaused: Bool { pauseStart != nil }

    mutating func pause(at host: Double) {
        guard pauseStart == nil else { return }
        pauseStart = host
    }

    mutating func resume(at host: Double) {
        guard let p = pauseStart else { return }
        pausedTotal += max(0, host - p)
        pauseStart = nil
    }

    /// The first video frame, with its original (not yet shifted) host time.
    mutating func firstFrame(at host: Double) {
        guard start == nil else { return }
        start = host - pausedTotal
    }

    /// Where `host` falls in the video; nil before the first frame, while paused (events then are dropped), and for
    /// times before the video starts. With `holdWhilePaused`, a time while paused maps to the moment the pause began
    /// instead (for state changes, like the spotlight, that must not be lost).
    func videoTime(host: Double, holdWhilePaused: Bool = false) -> Double? {
        guard let start else { return nil }
        var h = host
        if let p = pauseStart, host >= p {
            guard holdWhilePaused else { return nil }
            h = p
        }
        let t = h - pausedTotal - start
        return t >= 0 ? t : (holdWhilePaused ? 0 : nil)
    }
}

/// Converting between the recorded area (screen points) and the video's pixels.
enum RecordingGeometry {
    /// The video size for an area of `area` points on a screen with `backingScale`: scaled down to fit `maxPixels`
    /// when bigger (H.264's limit), and rounded down to even numbers (the encoder wants them), at least 2.
    static func videoSize(area: CGSize, backingScale: CGFloat, maxPixels: Int) -> CGSize {
        var scale = backingScale
        let px = area.width * scale * area.height * scale
        if px > CGFloat(maxPixels) { scale *= sqrt(CGFloat(maxPixels) / px) }
        let width = max(2, Int(area.width * scale) & ~1), height = max(2, Int(area.height * scale) & ~1)
        return CGSize(width: width, height: height)
    }

    /// Video pixels per screen point.
    static func pixelsPerPoint(area: CGSize, videoSize: CGSize) -> CGFloat {
        area.width > 0 ? videoSize.width / area.width : 1
    }

    /// A global point (points, bottom-left origin) in video pixels with a top-left origin. It may lie outside the video.
    static func videoPoint(global p: CGPoint, area: CGRect, videoSize: CGSize) -> CGPoint {
        let sx = area.width > 0 ? videoSize.width / area.width : 1
        let sy = area.height > 0 ? videoSize.height / area.height : 1
        return CGPoint(x: (p.x - area.minX) * sx, y: (area.maxY - p.y) * sy)
    }

    /// A Quartz global point (top-left origin of the main display, as `CGEvent` has it) in AppKit's global
    /// coordinates (bottom-left origin); `mainHeight` is the main display's height in points.
    static func appKitPoint(quartz p: CGPoint, mainHeight: CGFloat) -> CGPoint { CGPoint(x: p.x, y: mainHeight - p.y) }

    static func contains(_ p: CGPoint, videoSize: CGSize) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < videoSize.width && p.y < videoSize.height
    }
}

/// The look of the recording effects, shared by the live overlay (`RecordingEffects`) and the renderer, so the
/// finished video matches what was shown while recording. Sizes are in screen points.
enum EffectsLook {
    static let ringDuration = 0.5
    static let ringStartScale = 0.4
    static let ringFillAlpha: CGFloat = 0.3
    static let ringLineWidth: CGFloat = 3
    /// The keystroke pill hides this long after the last key.
    static let pillHold = 1.4
    static let pillMaxCharacters = 40
    static let pillAlpha: CGFloat = 0.72
    static let pillCornerRadius: CGFloat = 10
    /// Distance from the bottom (or top) of the area.
    static let pillEdgeInset: CGFloat = 24

    static func pillPadding(fontSize: CGFloat) -> CGFloat { fontSize * 0.6 }

    /// The pill around text of `textSize`, centered horizontally, `edgeInset` from the bottom of `bounds` (or the
    /// top), in bottom-left-origin coordinates. The text sits `padding` in from the sides and `padding / 2` from the
    /// bottom.
    static func pillFrame(textSize: CGSize, padding: CGFloat, edgeInset: CGFloat, in bounds: CGRect, atTop: Bool) -> CGRect {
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding)
        let y = atTop ? bounds.maxY - size.height - edgeInset : bounds.minY + edgeInset
        return CGRect(x: bounds.minX + (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
    }

    /// Core Animation's ease-out curve (cubic Bézier 0, 0, 0.58, 1), which the click ring animates with.
    static func easeOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        // x(s) = 3(1-s)s²·0.58 + s³ rises with s: bisect for s, then y(s) = 3(1-s)s² + s³.
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let s = (lo + hi) / 2
            let xs = 3 * (1 - s) * s * s * 0.58 + s * s * s
            if xs < x { lo = s } else { hi = s }
        }
        let s = (lo + hi) / 2
        return 3 * (1 - s) * s * s + s * s * s
    }
}

/// A click ring at one moment of its animation: it grows from `ringStartScale` to full size and fades out.
struct RingState: Equatable {
    var center: CGPoint
    /// 0 at the click, 1 when the ring is gone (linear in time).
    var progress: Double
    var scale: Double
    var opacity: Double
}

struct CursorState: Equatable {
    /// Video pixels, top-left origin.
    var point: CGPoint
    /// Over the recorded area.
    var visible: Bool
    /// Index into `cursorImages`; nil when no image was recorded.
    var image: Int?
}

/// One showing of the keystroke pill: `text` from `start` until `end`.
struct KeystrokePill: Equatable {
    var start: Double
    var end: Double
    var text: String
}

/// "State at time t": what the effects look like at a moment of the video. Pure, so the renderer and the
/// recording editor (#24) agree on it.
extension RecordingEvents {
    /// The pointer at `t`, moving in a straight line between samples (where both are over the area; off it, it jumps).
    /// Before the first sample it is at the first, after the last at the last. Nil without samples.
    func cursorState(at t: Double) -> CursorState? {
        guard let first = cursor.first else { return nil }
        let image = cursorImage(at: t)
        let i = lastIndex(of: cursor, atOrBefore: t) { $0.t }
        guard let i else { return CursorState(point: CGPoint(x: first.x, y: first.y), visible: first.visible, image: image) }
        let a = cursor[i]
        var p = CGPoint(x: a.x, y: a.y)
        if i + 1 < cursor.count {
            let b = cursor[i + 1]
            if a.visible, b.visible, b.t > a.t {
                let f = (t - a.t) / (b.t - a.t)
                p = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            }
        }
        return CursorState(point: p, visible: a.visible, image: image)
    }

    /// The cursor image showing at `t` (the first one recorded before any change).
    func cursorImage(at t: Double) -> Int? {
        let valid = { (i: Int) in cursorImages.indices.contains(i) ? i : nil }
        guard let first = cursorChanges.first else { return cursorImages.isEmpty ? nil : 0 }
        guard let i = lastIndex(of: cursorChanges, atOrBefore: t, { $0.t }) else { return valid(first.image) }
        return valid(cursorChanges[i].image)
    }

    /// The click rings animating at `t`: one per button press inside `videoSize`, for `EffectsLook.ringDuration`.
    func rings(at t: Double, videoSize: CGSize) -> [RingState] {
        clicks.compactMap { c in
            let age = t - c.t
            guard c.down, age >= 0, age < EffectsLook.ringDuration else { return nil }
            let center = CGPoint(x: c.x, y: c.y)
            guard RecordingGeometry.contains(center, videoSize: videoSize) else { return nil }
            let progress = age / EffectsLook.ringDuration
            let e = EffectsLook.easeOut(progress)
            return RingState(center: center, progress: progress,
                             scale: EffectsLook.ringStartScale + (1 - EffectsLook.ringStartScale) * e, opacity: 1 - e)
        }
    }

    /// The keystroke pill's showings, as the live overlay builds them: a key replaces the text (or, with `append`,
    /// adds to it while the pill is still up), the last `pillMaxCharacters` are kept, and the pill hides
    /// `pillHold` seconds after the last key.
    func keystrokePills() -> [KeystrokePill] {
        var pills: [KeystrokePill] = []
        for k in keys {
            var text = k.text
            if let last = pills.last, k.t < last.end {
                if k.append { text = last.text + k.text }
                pills[pills.count - 1].end = max(last.start, k.t)
            }
            if text.count > EffectsLook.pillMaxCharacters { text = String(text.suffix(EffectsLook.pillMaxCharacters)) }
            pills.append(KeystrokePill(start: k.t, end: k.t + EffectsLook.pillHold, text: text))
        }
        return pills
    }

    /// The pill text showing at `t`, if any; `pills` from `keystrokePills()`.
    func keystroke(at t: Double, pills: [KeystrokePill]) -> String? {
        guard let i = lastIndex(of: pills, atOrBefore: t, { $0.start }), t < pills[i].end else { return nil }
        return pills[i].text
    }

    func keystroke(at t: Double) -> String? { keystroke(at: t, pills: keystrokePills()) }

    /// Whether the spotlight is on at `t`.
    func isSpotlightOn(at t: Double) -> Bool {
        guard let i = lastIndex(of: spotlight, atOrBefore: t, { $0.t }) else { return spotlightAtStart }
        return spotlight[i].on
    }

    /// The last index in `items` (sorted by `time`) whose time is at or before `t`; nil if none.
    private func lastIndex<T>(of items: [T], atOrBefore t: Double, _ time: (T) -> Double) -> Int? {
        var lo = 0, hi = items.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if time(items[mid]) <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? lo - 1 : nil
    }
}
