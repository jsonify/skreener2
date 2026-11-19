import Foundation

// Cuts and speed changes in the recording editor (#381). Edits are ranges of the clean video's own time (source time),
// so the event track, zoom sections and effects never move; `EditTimeline` maps between source time and the time in
// the exported video (output time) when exporting and while previewing.

/// A range of the recording that is cut out (`speed` 0), muted (`speed` 1, #385) or played faster.
struct TimelineEdit: Codable, Equatable {
    var start: Double
    var end: Double
    /// 0 cuts the range; 1 plays it at normal speed without sound; 2, 4 or 8 speeds it up.
    var speed: Double

    static let mute = 1.0

    static let speeds: [Double] = [2, 4, 8]
    /// Shorter edits are dropped.
    static let minLength = 0.05

    var isCut: Bool { speed == 0 }
    var isMute: Bool { speed == Self.mute }
    var length: Double { end - start }

    func contains(_ t: Double) -> Bool { t >= start && t < end }

    var label: String { isCut ? "Cut" : isMute ? "Mute" : "\(Int(speed))×" }

    /// What it is called in Undo and the Remove button's name.
    var kind: String { isCut ? "Cut" : isMute ? "Mute" : "Speed Change" }
}

/// The recording's timeline with its edits applied: which source time plays at each output time, and back.
struct EditTimeline: Equatable {
    /// A stretch of source time that plays at one speed (0: cut out).
    struct Segment: Equatable {
        var start: Double, end: Double, speed: Double
        /// Where it starts in the output.
        var outputStart: Double
        /// Played without sound.
        var muted = false
        var outputLength: Double { speed > 0 ? (end - start) / speed : 0 }
    }

    let duration: Double
    let edits: [TimelineEdit]
    let segments: [Segment]

    init(edits: [TimelineEdit], duration: Double) {
        self.duration = max(0, duration)
        self.edits = Self.tidy(edits, duration: duration)
        var segments: [Segment] = []
        var t = 0.0, out = 0.0
        func add(_ end: Double, _ speed: Double, muted: Bool = false) {
            guard end > t else { return }
            let s = Segment(start: t, end: end, speed: speed, outputStart: out, muted: muted)
            segments.append(s)
            out += s.outputLength
            t = end
        }
        for e in self.edits {
            add(e.start, 1)
            add(e.end, e.speed, muted: e.isMute)
        }
        add(self.duration, 1)
        self.segments = segments
    }

    var isEmpty: Bool { edits.isEmpty }

    /// Whether any edit changes which frames play (a cut or a speed change); mutes only change the sound.
    var changesTime: Bool { edits.contains { !$0.isMute } }

    var outputDuration: Double { segments.last.map { $0.outputStart + $0.outputLength } ?? 0 }

    /// The source time showing at output time `t` (the end of the recording past the end).
    func sourceTime(output t: Double) -> Double {
        for s in segments where s.speed > 0 && t < s.outputStart + s.outputLength {
            return s.start + max(0, t - s.outputStart) * s.speed
        }
        return duration
    }

    /// Where source time `t` plays in the output; a time inside a cut maps to where the cut is.
    func outputTime(source t: Double) -> Double {
        for s in segments where t < s.end {
            return s.outputStart + (s.speed > 0 ? max(0, t - s.start) / s.speed : 0)
        }
        return outputDuration
    }

    /// The edit at source time `t`, if any.
    func edit(at t: Double) -> TimelineEdit? { edits.first { $0.contains(t) } }

    /// Sorted, inside the recording, no shorter than `TimelineEdit.minLength`, never overlapping (a later edit in the
    /// list wins where two overlap), with a speed that is 0 or one of `TimelineEdit.speeds`.
    static func tidy(_ edits: [TimelineEdit], duration: Double) -> [TimelineEdit] {
        var result: [TimelineEdit] = []
        for var e in edits {
            e.start = max(0, e.start)
            e.end = min(duration, e.end)
            if e.speed != 0, e.speed != TimelineEdit.mute { e.speed = TimelineEdit.speeds.min { abs($0 - e.speed) < abs($1 - e.speed) } ?? 2 }
            guard e.end - e.start >= TimelineEdit.minLength else { continue }
            result = adding(e, to: result)
        }
        return result.sorted { $0.start < $1.start }
    }

    /// `edits` with `new` added: whatever it overlaps is trimmed or split around it.
    static func adding(_ new: TimelineEdit, to edits: [TimelineEdit]) -> [TimelineEdit] {
        var result: [TimelineEdit] = []
        for e in edits {
            if e.end <= new.start || e.start >= new.end { result.append(e); continue }
            if e.start < new.start {
                var before = e
                before.end = new.start
                if before.length >= TimelineEdit.minLength { result.append(before) }
            }
            if e.end > new.end {
                var after = e
                after.start = new.end
                if after.length >= TimelineEdit.minLength { result.append(after) }
            }
        }
        result.append(new)
        return result.sorted { $0.start < $1.start }
    }

    /// Lays `source` (samples of the recording at `sampleRate`) out on the output timeline: cut ranges are left out,
    /// muted and sped-up ranges are silent (a sped-up range's sound would be a chipmunk), with a short fade at every
    /// join so it doesn't click.
    func remap(_ source: [Float], sampleRate: Double) -> [Float] {
        guard !isEmpty else { return source }
        let frames = Int((outputDuration * sampleRate).rounded())
        var out = [Float](repeating: 0, count: frames)
        let fade = max(1, Int(0.01 * sampleRate))
        for s in segments where s.speed == 1 && !s.muted {
            let from = Int((s.start * sampleRate).rounded()), to = min(source.count, Int((s.end * sampleRate).rounded()))
            let at = Int((s.outputStart * sampleRate).rounded())
            guard to > from else { continue }
            let count = min(to - from, frames - at)
            guard count > 0 else { continue }
            for i in 0..<count {
                var g: Float = 1
                // Fade in after a join, fade out before one (not at the very start or end of the recording).
                if s.start > 0, i < fade { g = Float(i) / Float(fade) }
                if s.end < duration, count - i <= fade { g = min(g, Float(count - i - 1) / Float(fade)) }
                out[at + i] = source[from + i] * g
            }
        }
        return out
    }

    /// Stretches of at least `minimum` seconds in which nothing happens in `events`: the pointer doesn't move more
    /// than a couple of pixels, and there are no clicks or keystrokes. Each is shortened by `margin` at both ends, so
    /// what led into it and out of it stays at normal speed.
    static func idleRanges(_ events: RecordingEvents, duration: Double, minimum: Double = 3, margin: Double = 0.5) -> [(start: Double, end: Double)] {
        var activity: [Double] = events.clicks.map(\.t) + events.keys.map(\.t)
        var last: RecordingEvents.CursorSample?
        for s in events.cursor {
            // Measured from where the pointer last came to rest, so slow drift adds up.
            guard let p = last else { last = s; continue }
            if hypot(s.x - p.x, s.y - p.y) > 2 {
                activity.append(s.t)
                last = s
            }
        }
        activity = ([0] + activity.filter { $0 >= 0 && $0 <= duration } + [duration]).sorted()
        var ranges: [(start: Double, end: Double)] = []
        for (a, b) in zip(activity, activity.dropFirst()) where b - a >= minimum {
            let start = a + margin, end = b - margin
            if end - start >= minimum - 2 * margin { ranges.append((start, end)) }
        }
        return ranges
    }
}
