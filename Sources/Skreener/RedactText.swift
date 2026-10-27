import AppKit

/// The Redact Text tool's matches as boxes on the screenshot (#295): the canvas highlights them, a click takes one
/// out (or back in), and Redact Selected / Redact All cover them with annotations.
enum RedactText {
    /// One match: a box per line it covers (image points, padded), and whether Redact Selected takes it.
    struct Hit: Equatable {
        var boxes: [CGRect]
        var selected = true
    }

    /// How the matches are covered. Only a solid fill really removes the text.
    enum Cover: Int, CaseIterable {
        case solid, pixelate, blur, erase

        var title: String {
            switch self {
            case .solid: return "Solid"
            case .pixelate: return "Pixelate"
            case .blur: return "Blur"
            case .erase: return "Erase"
            }
        }
    }

    /// A box per span of `match`, padded like Redact's; a span `box` can't place is left out.
    static func boxes(for match: TextMatcher.Match, box: (TextMatcher.Span) -> CGRect?) -> [CGRect] {
        match.spans.compactMap(box).map { $0.insetBy(dx: -3, dy: -2) }
    }

    /// Hits for freshly found matches (their boxes), all selected except those whose boxes are the same as a match
    /// taken out before, so typing on doesn't bring back what was clicked away.
    static func hits(_ found: [[CGRect]], keeping old: [Hit]) -> [Hit] {
        let off = old.filter { !$0.selected }.map(\.boxes)
        return found.filter { !$0.isEmpty }.map { Hit(boxes: $0, selected: !off.contains($0)) }
    }

    /// `hits` with the one under `p` (the topmost, all its boxes together) toggled; nil when `p` is on none.
    static func toggling(_ hits: [Hit], at p: CGPoint) -> [Hit]? {
        guard let i = hits.lastIndex(where: { $0.boxes.contains { $0.contains(p) } }) else { return nil }
        var out = hits
        out[i].selected.toggle()
        return out
    }

    /// Whether Regex is on and a term doesn't compile (the bar then says so instead of just finding nothing).
    static func hasInvalidPattern(_ terms: [String], options: TextMatcher.Options) -> Bool {
        options.regex && terms.contains { term in
            let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !TextMatcher.isValidPattern(t)
        }
    }

    /// The find bar's count: OCR still reading, a bad pattern, nothing found, or "12 matches · 10 selected"; empty
    /// before anything is typed.
    static func status(_ hits: [Hit], reading: Bool, invalidPattern: Bool, searching: Bool) -> String {
        if reading { return "Reading text…" }
        if invalidPattern { return "Invalid pattern" }
        guard searching else { return "" }
        guard !hits.isEmpty else { return "No matches" }
        let n = hits.count, selected = hits.filter(\.selected).count
        return "\(n) \(n == 1 ? "match" : "matches") · \(selected) selected"
    }

    /// One annotation per box, covering it as `cover` says, in `style` otherwise (strength, shadow). Solid is an
    /// opaque black filled rectangle with square corners; pixelate is never too fine to hide the text.
    static func annotations(_ boxes: [CGRect], cover: Cover, style: Style) -> [Annotation] {
        var s = style
        s.textOnly = false   // the whole box: it is already just the text
        let tool: Tool
        switch cover {
        case .solid:
            tool = .filledRect
            s.color = .black
            s.cornerRadius = 0
        case .pixelate:
            tool = .pixelate
            s.pixelSize = max(s.pixelSize, 8)
        case .blur: tool = .blur
        case .erase: tool = .erase
        }
        return boxes.map { Annotation(tool: tool, start: $0.origin, end: NSPoint(x: $0.maxX, y: $0.maxY), style: s) }
    }
}
