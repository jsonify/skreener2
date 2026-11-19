import CoreGraphics
import Foundation

/// How much the recording editor smooths the cursor's path (#382).
enum CursorSmoothing: String, Codable, CaseIterable {
    case off, low, high

    var name: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .high: return "High"
        }
    }

    /// The smoothing filter's width (a Gaussian's standard deviation), in seconds.
    var sigma: Double {
        switch self {
        case .off: return 0
        case .low: return 0.04
        case .high: return 0.1
        }
    }
}

/// The recording editor's cursor options (#382), for the whole recording: smoothing, size, and hiding it when idle.
struct CursorSettings: Codable, Equatable {
    static let minSize = 1.0, maxSize = 3.0
    /// The delays the editor offers for hiding an idle cursor, in seconds.
    static let idleDelays: [Double] = [1, 2, 3, 5]

    var smoothing = CursorSmoothing.off
    /// 1 is the size it was recorded at.
    var size = 1.0
    var hideWhenIdle = false
    /// How long the cursor stays after it stops moving, in seconds.
    var idleDelay = 2.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .smoothing)
        smoothing = raw.flatMap(CursorSmoothing.init(rawValue:)) ?? .off
        size = Self.clampedSize(try c.decodeIfPresent(Double.self, forKey: .size) ?? 1)
        hideWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .hideWhenIdle) ?? false
        let delay = try c.decodeIfPresent(Double.self, forKey: .idleDelay) ?? 2
        idleDelay = delay.isFinite ? min(max(delay, 0.5), 10) : 2
    }

    static func clampedSize(_ size: Double) -> Double {
        size.isFinite ? min(max(size, minSize), maxSize) : 1
    }

    /// "1.5×"
    static func sizeText(_ size: Double) -> String {
        let s = (size * 100).rounded() / 100
        return (s == s.rounded() ? String(Int(s)) : String(format: "%g", s)) + "×"
    }
}

/// The cursor's path and visibility as the recording editor draws it (#382). Pure, so it can be tested.
enum CursorMotion {
    /// Samples further apart than this are not smoothed across (the pointer was off the area, or recording paused).
    static let maxGap = 0.25
    /// Moving less than this, in video pixels, isn't moving.
    static let moveThreshold = 0.5
    static let fadeOut = 0.3
    static let fadeIn = 0.15

    /// `events` with the cursor's path smoothed by `smoothing`. The smoothed path goes exactly through the pointer's
    /// position at every click (press and release): a sample is put there, and the path between two clicks is
    /// smoothed with a Gaussian over time, then shifted back onto both ends.
    static func smoothed(_ events: RecordingEvents, _ smoothing: CursorSmoothing) -> RecordingEvents {
        let sigma = smoothing.sigma
        guard sigma > 0, events.cursor.count > 2 else { return events }
        let (samples, anchors) = anchored(events)
        var out = samples
        for range in segments(samples, anchors: anchors) where range.count > 2 {
            smooth(samples, range, sigma: sigma, into: &out)
        }
        var e = events
        e.cursor = out
        return e
    }

    /// The cursor samples with one added at each click, at the click's position (any sample within half a
    /// millisecond of it is replaced), and which samples are those clicks.
    static func anchored(_ events: RecordingEvents) -> (samples: [RecordingEvents.CursorSample], anchors: [Bool]) {
        let clicks = events.clicks.sorted { $0.t < $1.t }
        var items = events.cursor.map { (sample: $0, anchor: false) }
        guard !clicks.isEmpty else { return (events.cursor, events.cursor.map { _ in false }) }
        let near = { (t: Double) in clicks.contains { abs($0.t - t) < 0.0005 } }
        items.removeAll { near($0.sample.t) }
        for c in clicks {
            let visible = events.cursorState(at: c.t)?.visible ?? true
            items.append((sample: RecordingEvents.CursorSample(t: c.t, x: c.x, y: c.y, visible: visible), anchor: true))
        }
        // Stable, so a press and its release at the same moment keep their order.
        items = items.enumerated().sorted { ($0.element.sample.t, $0.offset) < ($1.element.sample.t, $1.offset) }.map { $0.element }
        return (items.map { $0.sample }, items.map { $0.anchor })
    }

    /// The stretches smoothed on their own: split at every click (which ends one stretch and starts the next), and
    /// between samples where the pointer goes on or off the area or that are more than `maxGap` apart.
    static func segments(_ s: [RecordingEvents.CursorSample], anchors: [Bool]) -> [ClosedRange<Int>] {
        guard !s.isEmpty else { return [] }
        var result: [ClosedRange<Int>] = []
        var start = 0
        for k in s.indices.dropFirst() {
            if s[k].visible != s[k - 1].visible || s[k].t - s[k - 1].t > maxGap {
                result.append(start...(k - 1))
                start = k
            } else if anchors[k] {
                result.append(start...k)
                start = k
            }
        }
        if start < s.count - 1 || result.last?.upperBound != start { result.append(start...(s.count - 1)) }
        return result
    }

    private static func smooth(_ s: [RecordingEvents.CursorSample], _ range: ClosedRange<Int>, sigma: Double,
                               into out: inout [RecordingEvents.CursorSample]) {
        let reach = 3 * sigma
        var sx = [Double](repeating: 0, count: range.count), sy = sx
        var lo = range.lowerBound, hi = range.lowerBound
        for k in range {
            let t = s[k].t
            while s[lo].t < t - reach { lo += 1 }
            while hi < range.upperBound, s[hi + 1].t <= t + reach { hi += 1 }
            var wx = 0.0, wy = 0.0, w = 0.0
            for j in lo...hi {
                let d = (s[j].t - t) / sigma
                let weight = exp(-0.5 * d * d)
                wx += weight * s[j].x; wy += weight * s[j].y; w += weight
            }
            sx[k - range.lowerBound] = wx / w
            sy[k - range.lowerBound] = wy / w
        }
        // Shift the smoothed stretch so it starts and ends exactly where the samples do.
        let a = range.lowerBound, b = range.upperBound, n = range.count - 1
        let dxA = s[a].x - sx[0], dyA = s[a].y - sy[0], dxB = s[b].x - sx[n], dyB = s[b].y - sy[n]
        let span = s[b].t - s[a].t
        for k in (a + 1)..<b {
            let f = span > 0 ? (s[k].t - s[a].t) / span : 0
            out[k].x = sx[k - a] + dxA + (dxB - dxA) * f
            out[k].y = sy[k - a] + dyA + (dyB - dyA) * f
        }
    }
}

/// When an idle cursor is hidden (#382): it fades out `delay` seconds after it last moved or clicked, and fades back
/// in when it moves again.
struct CursorVisibility: Equatable {
    /// Stretches of activity: moves or clicks less than `delay` apart.
    struct Run: Equatable {
        var start: Double
        var end: Double
    }

    let runs: [Run]
    let delay: Double

    init(events: RecordingEvents, delay: Double) {
        self.delay = delay
        var moves: [Double] = []
        let s = events.cursor
        if let first = s.first { moves.append(first.t) }
        for k in s.indices.dropFirst() {
            let dx = s[k].x - s[k - 1].x, dy = s[k].y - s[k - 1].y
            if s[k].visible != s[k - 1].visible || dx * dx + dy * dy > CursorMotion.moveThreshold * CursorMotion.moveThreshold {
                moves.append(s[k].t)
            }
        }
        moves += events.clicks.map { $0.t }
        moves.sort()
        var runs: [Run] = []
        for t in moves {
            if let last = runs.last, t - last.end < delay {
                runs[runs.count - 1].end = max(last.end, t)
            } else {
                runs.append(Run(start: t, end: t))
            }
        }
        self.runs = runs
    }

    /// How visible the cursor is at `t`, from 0 (hidden) to 1.
    func opacity(at t: Double) -> Double {
        var lo = 0, hi = runs.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if runs[mid].start <= t { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return 1 }
        let i = lo - 1
        var o = opacity(of: i, at: t)
        if i > 0 { o = max(o, opacity(of: i - 1, at: t)) }
        return o
    }

    private func opacity(of i: Int, at t: Double) -> Double {
        let r = runs[i]
        let fadingIn = i == 0 ? 1 : min(1, max(0, (t - r.start) / CursorMotion.fadeIn))
        let idle = t - r.end - delay
        let fadingOut = idle <= 0 ? 1 : max(0, 1 - idle / CursorMotion.fadeOut)
        return fadingIn * fadingOut
    }
}
