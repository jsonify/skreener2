import CoreGraphics
import Foundation

/// The Redact Text tool's matches as boxes on the screenshot (#295): the canvas highlights them, a click takes one
/// out (or back in), and Redact Selected / Redact All cover them with annotations.
public enum RedactText {
    /// One match: a box per line it covers (image points, padded), and whether Redact Selected takes it.
    public struct Hit: Equatable {
        public var boxes: [CGRect]
        public var selected = true

        public init(boxes: [CGRect], selected: Bool = true) {
            self.boxes = boxes
            self.selected = selected
        }
    }

    /// How the matches are covered. Only a solid fill really removes the text.
    public enum Cover: Int, CaseIterable {
        case solid, pixelate, blur, erase

        public var title: String {
            switch self {
            case .solid: return "Solid"
            case .pixelate: return "Pixelate"
            case .blur: return "Blur"
            case .erase: return "Erase"
            }
        }
    }

    /// A box per span of `match`, padded like Redact's; a span `box` can't place is left out.
    public static func boxes(for match: TextMatcher.Match, box: (TextMatcher.Span) -> CGRect?) -> [CGRect] {
        match.spans.compactMap(box).map { $0.insetBy(dx: -3, dy: -2) }
    }

    /// Hits for freshly found matches (their boxes), all selected except those whose boxes are the same as a match
    /// taken out before, so typing on doesn't bring back what was clicked away.
    public static func hits(_ found: [[CGRect]], keeping old: [Hit]) -> [Hit] {
        let off = old.filter { !$0.selected }.map(\.boxes)
        return found.filter { !$0.isEmpty }.map { Hit(boxes: $0, selected: !off.contains($0)) }
    }

    /// `hits` with the one under `p` (the topmost, all its boxes together) toggled; nil when `p` is on none.
    public static func toggling(_ hits: [Hit], at p: CGPoint) -> [Hit]? {
        guard let i = hits.lastIndex(where: { $0.boxes.contains { $0.contains(p) } }) else { return nil }
        var out = hits
        out[i].selected.toggle()
        return out
    }

    /// Whether Regex is on and a term doesn't compile (the bar then says so instead of just finding nothing).
    public static func hasInvalidPattern(_ terms: [String], options: TextMatcher.Options) -> Bool {
        options.regex && terms.contains { term in
            let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !TextMatcher.isValidPattern(t)
        }
    }

    /// The find bar's count: OCR still reading, a bad pattern, nothing found, or "12 matches · 10 selected"; empty
    /// before anything is typed.
    public static func status(_ hits: [Hit], reading: Bool, invalidPattern: Bool, searching: Bool) -> String {
        if reading { return "Reading text…" }
        if invalidPattern { return "Invalid pattern" }
        guard searching else { return "" }
        guard !hits.isEmpty else { return "No matches" }
        let n = hits.count, selected = hits.filter(\.selected).count
        return "\(n) \(n == 1 ? "match" : "matches") · \(selected) selected"
    }
}
