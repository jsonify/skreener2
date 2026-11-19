import Foundation

/// One caption line, in the recording's own time (source time, like the edits), so cuts never move it (#386).
struct Caption: Codable, Equatable {
    var start: Double
    var end: Double
    var text: String
}

/// The recording editor's captions (#386): made from the microphone's words, drawn into the video and/or saved as an
/// `.srt` next to it. Pure, so it can be tested.
enum Captions {
    /// A recognized word, timed in seconds from the start of the recording.
    struct Word: Equatable {
        var start: Double
        var duration: Double
        var text: String
        var end: Double { start + duration }
    }

    /// A line holds at most this many characters, as subtitles usually do.
    static let maxCharacters = 42
    static let maxDuration = 5.0
    /// A pause this long starts a new line.
    static let maxGap = 0.8
    /// Lines show for at least this long (unless the next one starts sooner).
    static let minDuration = 1.0
    /// Pieces shorter than this after cuts are left out.
    static let minPiece = 0.2

    /// `words` (in time order) grouped into caption lines: a new line after a pause, at the end of a sentence, or when
    /// the line would get too long to read.
    static func lines(_ words: [Word]) -> [Caption] {
        var result: [Caption] = []
        var current: Caption?
        var lastEnd = 0.0
        func close() {
            if let c = current { result.append(c) }
            current = nil
        }
        for w in words {
            let text = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let c = current {
                let tooLong = c.text.count + 1 + text.count > maxCharacters
                if w.start - lastEnd > maxGap || tooLong || w.end - c.start > maxDuration { close() }
            }
            if var c = current {
                c.text += " " + text
                c.end = max(c.end, w.end)
                current = c
            } else {
                current = Caption(start: w.start, end: w.end, text: text)
            }
            lastEnd = w.end
            if let last = text.last, ".?!".contains(last) { close() }
        }
        close()
        return tidy(result)
    }

    /// Sorted, without empty lines, never overlapping, each shown for at least `minDuration` when there is room.
    static func tidy(_ captions: [Caption]) -> [Caption] {
        var list = captions
            .map { Caption(start: max(0, $0.start), end: $0.end, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        for i in list.indices {
            let next = i + 1 < list.count ? list[i + 1].start : Double.infinity
            list[i].end = min(max(list[i].end, list[i].start + minDuration), next)
        }
        return list.filter { $0.end > $0.start }
    }

    /// The caption showing at `t`, if any.
    static func index(at t: Double, in captions: [Caption]) -> Int? {
        captions.firstIndex { t >= $0.start && t < $0.end }
    }

    /// `captions` on the exported video's timeline: only where the recording plays at normal speed with its sound
    /// (cut, sped-up and muted ranges have no speech to read), with times moved by the cuts and speed changes before
    /// them.
    static func laidOut(_ captions: [Caption], on timeline: EditTimeline) -> [Caption] {
        guard !timeline.isEmpty else { return captions }
        var out: [Caption] = []
        for c in captions {
            for s in timeline.segments where s.speed == 1 && !s.muted {
                let a = max(c.start, s.start), b = min(c.end, s.end)
                guard b - a >= minPiece else { continue }
                let piece = Caption(start: s.outputStart + (a - s.start), end: s.outputStart + (b - s.start), text: c.text)
                // A line split by a cut that left its pieces side by side is one line again.
                if let last = out.last, last.text == piece.text, abs(last.end - piece.start) < 1e-6 {
                    out[out.count - 1].end = piece.end
                } else {
                    out.append(piece)
                }
            }
        }
        return out
    }

    /// `captions` as a SubRip (`.srt`) file.
    static func srt(_ captions: [Caption]) -> String {
        captions.enumerated().map { i, c in
            "\(i + 1)\n\(timestamp(c.start)) --> \(timestamp(c.end))\n\(c.text)\n"
        }.joined(separator: "\n")
    }

    /// "01:02:03,456"
    static func timestamp(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    /// Where the `.srt` for an export at `video` goes: next to it, with the same name.
    static func srtURL(for video: URL) -> URL { video.deletingPathExtension().appendingPathExtension("srt") }
}
