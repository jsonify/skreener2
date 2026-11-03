import CoreGraphics
import Foundation

// Auto-zoom (#24, phase 2): zoom sections made from the clicks, edited on the recording editor's timeline, and the
// camera that turns them into a crop of the video at each moment. Everything here is pure, so the preview and the
// export (both `StudioCompositor`) show the same frame at the same time.

/// A stretch of the video shown zoomed in: from `start` to `end` (seconds), at `level`, eased in and out.
struct ZoomSection: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        /// The view follows the pointer.
        case follow
        /// The view stays on `x`, `y`.
        case fixed
    }

    var start: Double
    var end: Double
    /// How far in: 2 shows half the video's width and height.
    var level: Double = AutoZoom.defaultLevel
    var mode: Mode = .follow
    /// The fixed point (and where a follow section starts without pointer samples): video pixels, top-left origin.
    var x: Double
    var y: Double

    init(start: Double, end: Double, level: Double = AutoZoom.defaultLevel, mode: Mode = .follow, x: Double, y: Double) {
        self.start = start
        self.end = end
        self.level = AutoZoom.clampLevel(level)
        self.mode = mode
        self.x = x
        self.y = y
    }

    var duration: Double { end - start }
    var center: CGPoint { CGPoint(x: x, y: y) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        level = AutoZoom.clampLevel(try c.decodeIfPresent(Double.self, forKey: .level) ?? AutoZoom.defaultLevel)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .follow
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
    }
}

/// Auto-zoom's numbers, and making sections from the clicks and editing them.
enum AutoZoom {
    // MARK: Constants

    static let defaultLevel = 2.0
    static let minLevel = 1.25
    static let maxLevel = 4.0
    /// The levels the inspector offers.
    static let levels = [1.25, 1.5, 2, 2.5, 3, 4]
    /// Clicks closer than this (and inside the same zoomed view) make one section.
    static let clickGap = 3.0
    /// A section starts this long before its first click…
    static let leadIn = 0.4
    /// …and ends this long after its last.
    static let holdAfter = 1.5
    /// Sections closer than this are merged into one.
    static let minGap = 0.8
    /// How long zooming in (and out) takes.
    static let ease = 0.6
    /// The length of a section added by hand.
    static let addedLength = 2.0
    /// The shortest a section can be made.
    static let minLength = 0.5
    /// Follow mode: the pointer moves this far (a fraction of the zoomed view, from its middle) before the view pans.
    static let deadZone = 0.2
    /// Follow mode: how quickly the view catches up with the pointer (the time constant of the smoothing).
    static let followLag = 0.3
    /// Follow mode: the camera path's time step.
    static let followStep = 1.0 / 60

    static func clampLevel(_ level: Double) -> Double {
        level.isFinite ? min(max(level, minLevel), maxLevel) : defaultLevel
    }

    // MARK: Making sections from clicks

    /// The zoom sections for `events`' left clicks in a video of `videoSize` pixels and `duration` seconds: clicks
    /// closer than `clickGap` and inside the same view at `level` make one section, from `leadIn` before its first
    /// click to `holdAfter` after its last; sections that would overlap or sit closer than `minGap` merge.
    static func sections(from events: RecordingEvents, videoSize: CGSize, duration: Double,
                         level: Double = defaultLevel) -> [ZoomSection] {
        let clicks = events.clicks
            .filter { $0.down && $0.button == .left && RecordingGeometry.contains(CGPoint(x: $0.x, y: $0.y), videoSize: videoSize) }
            .sorted { $0.t < $1.t }
        // Groups of clicks.
        var groups: [[RecordingEvents.Click]] = []
        for c in clicks {
            if let group = groups.last, let first = group.first, let last = group.last, c.t - last.t < clickGap,
               view(at: CGPoint(x: first.x, y: first.y), level: level, videoSize: videoSize).contains(CGPoint(x: c.x, y: c.y)) {
                groups[groups.count - 1].append(c)
            } else {
                groups.append([c])
            }
        }
        let end = duration > 0 ? duration : .infinity
        var sections: [ZoomSection] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let s = ZoomSection(start: max(0, first.t - leadIn), end: min(end, last.t + holdAfter), level: level,
                                x: first.x, y: first.y)
            if let prev = sections.last, s.start - prev.end < minGap {
                sections[sections.count - 1].end = max(prev.end, s.end)
            } else {
                sections.append(s)
            }
        }
        return sections.filter { $0.end > $0.start }
    }

    /// The part of the video (pixels, top-left origin) a view at `level` centered on `center` shows, kept inside it.
    static func view(at center: CGPoint, level: Double, videoSize: CGSize) -> CGRect {
        let k = CGFloat(max(level, 1))
        let size = CGSize(width: videoSize.width / k, height: videoSize.height / k)
        let x = min(max(center.x - size.width / 2, 0), videoSize.width - size.width)
        let y = min(max(center.y - size.height / 2, 0), videoSize.height - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    // MARK: Editing sections

    /// Which end of a section is dragged.
    enum Edge { case start, end }

    /// `sections` (in time order) with the one at `index` moved to start at `start`, its length kept, stopped by its
    /// neighbours and the ends of the video.
    static func move(_ sections: [ZoomSection], index: Int, to start: Double, duration: Double) -> [ZoomSection] {
        guard sections.indices.contains(index) else { return sections }
        var out = sections
        let s = sections[index]
        let length = s.duration
        let lo = index > 0 ? sections[index - 1].end : 0
        let hi = index + 1 < sections.count ? sections[index + 1].start : max(duration, s.end)
        let t = max(lo, min(start, hi - length))
        out[index].start = t
        out[index].end = t + length
        return out
    }

    /// `sections` with one end of the section at `index` dragged to `time`, kept at least `minLength` long and
    /// stopped by its neighbours and the ends of the video.
    static func resize(_ sections: [ZoomSection], index: Int, edge: Edge, to time: Double, duration: Double) -> [ZoomSection] {
        guard sections.indices.contains(index) else { return sections }
        var out = sections
        let s = sections[index]
        switch edge {
        case .start:
            let lo = index > 0 ? sections[index - 1].end : 0
            out[index].start = min(max(time, lo), max(s.end - minLength, lo))
        case .end:
            let hi = index + 1 < sections.count ? sections[index + 1].start : max(duration, s.end)
            out[index].end = max(min(time, hi), min(s.start + minLength, hi))
        }
        return out
    }

    /// `sections` with a new `addedLength` section starting at `time` (moved back to fit the free time around it, and
    /// shortened if that is less), and its index; nil when `time` is inside a section or there is no room.
    static func add(to sections: [ZoomSection], at time: Double, duration: Double, center: CGPoint,
                    level: Double = defaultLevel) -> (sections: [ZoomSection], index: Int)? {
        let t = min(max(time, 0), max(duration, 0))
        if sections.contains(where: { t >= $0.start && t < $0.end }) { return nil }
        let index = sections.firstIndex { $0.start > t } ?? sections.count
        let lo = index > 0 ? sections[index - 1].end : 0
        let hi = index < sections.count ? sections[index].start : max(duration, 0)
        guard hi - lo >= minLength else { return nil }
        let end = min(t + addedLength, hi)
        let start = max(lo, end - addedLength)
        var out = sections
        out.insert(ZoomSection(start: start, end: end, level: level, x: Double(center.x), y: Double(center.y)), at: index)
        return (out, index)
    }

    /// Sections in time order with no overlaps (for ones read from a file): each starts no earlier than the one before ends.
    static func tidy(_ sections: [ZoomSection]) -> [ZoomSection] {
        var out: [ZoomSection] = []
        for var s in sections.sorted(by: { $0.start < $1.start }) where s.start.isFinite && s.end.isFinite {
            if let prev = out.last { s.start = max(s.start, prev.end) }
            if s.end - s.start > 0.001 { out.append(s) }
        }
        return out
    }

    // MARK: Easing

    /// Ease-in-out cubic on 0…1.
    static func easeInOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}

/// What the "camera" shows at each moment: the crop of the video (pixels, top-left origin) for `sections`. Between
/// sections it is the whole video; in one, the video's size divided by the zoom, centered on the target (the fixed
/// point, or the pointer smoothed) and kept inside the video. The zoom eases in over `AutoZoom.ease` at a section's
/// start and out at its end. Fixed at init, so `crop(at:)` gives the same answer for a time in any order.
struct ZoomCamera {
    let videoSize: CGSize
    let sections: [ZoomSection]
    /// Follow sections' view centers every `AutoZoom.followStep` from their start (empty for fixed ones).
    private let paths: [[CGPoint]]

    init(sections: [ZoomSection], events: RecordingEvents, videoSize: CGSize) {
        let tidy = AutoZoom.tidy(sections)
        self.videoSize = videoSize
        self.sections = tidy
        paths = tidy.map { s in
            s.mode == .follow ? Self.followPath(s, events: events, videoSize: videoSize) : []
        }
    }

    var fullCrop: CGRect { CGRect(origin: .zero, size: videoSize) }

    /// The section showing at `t`, if any.
    func sectionIndex(at t: Double) -> Int? {
        sections.firstIndex { t >= $0.start && t <= $0.end }
    }

    /// The zoom at `t`: 1 outside sections, eased up to the section's level at its start and back down at its end.
    func level(at t: Double) -> Double {
        guard let i = sectionIndex(at: t) else { return 1 }
        return Self.level(sections[i], at: t)
    }

    static func level(_ s: ZoomSection, at t: Double) -> Double {
        let ease = AutoZoom.ease
        let f = min(AutoZoom.easeInOut((t - s.start) / ease), AutoZoom.easeInOut((s.end - t) / ease))
        return 1 + (s.level - 1) * f
    }

    /// Where the view is aimed at `t` in the section at `index`.
    func target(section index: Int, at t: Double) -> CGPoint {
        let s = sections[index]
        let path = paths[index]
        guard s.mode == .follow, !path.isEmpty else { return s.center }
        let f = max(0, (t - s.start) / AutoZoom.followStep)
        let i = min(Int(f), path.count - 1)
        guard i + 1 < path.count else { return path[i] }
        let a = path[i], b = path[i + 1], k = CGFloat(f - Double(i))
        return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    /// The part of the video showing at `t`.
    func crop(at t: Double) -> CGRect {
        guard let i = sectionIndex(at: t) else { return fullCrop }
        let level = Self.level(sections[i], at: t)
        guard level > 1.0001 else { return fullCrop }
        return AutoZoom.view(at: target(section: i, at: t), level: level, videoSize: videoSize)
    }

    /// A follow section's view centers: the pointer, smoothed. The goal stays put while the pointer is within the dead
    /// zone around it and is pulled along when it leaves it; the view eases toward the goal (exponential smoothing).
    /// It is worked out on a fixed grid from the section's start, so it is the same however the video is played.
    private static func followPath(_ s: ZoomSection, events: RecordingEvents, videoSize: CGSize) -> [CGPoint] {
        let view = AutoZoom.view(at: .zero, level: s.level, videoSize: videoSize).size
        let dz = CGSize(width: view.width * AutoZoom.deadZone, height: view.height * AutoZoom.deadZone)
        // The goal never needs to go where the view would be pushed back inside the video anyway.
        let lo = CGPoint(x: view.width / 2, y: view.height / 2)
        let hi = CGPoint(x: videoSize.width - view.width / 2, y: videoSize.height - view.height / 2)
        func keep(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, lo.x), hi.x), y: min(max(p.y, lo.y), hi.y))
        }
        func pointer(at t: Double) -> CGPoint? {
            guard let c = events.cursorState(at: t), c.visible else { return nil }
            return CGPoint(x: min(max(c.point.x, 0), videoSize.width), y: min(max(c.point.y, 0), videoSize.height))
        }
        let step = AutoZoom.followStep
        let count = max(1, Int((s.duration / step).rounded(.up)) + 1)
        let pull = CGFloat(1 - exp(-step / AutoZoom.followLag))
        var goal = keep(pointer(at: s.start) ?? s.center)
        var center = goal
        var path: [CGPoint] = []
        path.reserveCapacity(count + 1)
        for i in 0...count {
            if let p = pointer(at: s.start + Double(i) * step) {
                if p.x > goal.x + dz.width { goal.x = p.x - dz.width } else if p.x < goal.x - dz.width { goal.x = p.x + dz.width }
                if p.y > goal.y + dz.height { goal.y = p.y - dz.height } else if p.y < goal.y - dz.height { goal.y = p.y + dz.height }
                goal = keep(goal)
            }
            if i > 0 {
                center.x += (goal.x - center.x) * pull
                center.y += (goal.y - center.y) * pull
            }
            path.append(center)
        }
        return path
    }
}
