import Foundation

/// Finds the terms to redact in the lines OCR read (#295). Pure text: the editor turns each span into a box.
enum TextMatcher {
    struct Options: Equatable {
        var caseSensitive = false
        var wholeWord = true
        var regex = false
        var fuzzy = false
    }

    /// Part of a match inside one line: the line's index and a range of that line's own string.
    struct Span: Equatable {
        let line: Int
        let range: Range<String.Index>
    }

    /// One hit: the index of the term that found it, and one span per line it covers (several when it wraps).
    struct Match: Equatable {
        let term: Int
        let spans: [Span]
    }

    /// Every match of `terms` in `lines`, in reading order (by first span's line, then position).
    static func matches(of terms: [String], in lines: [String], options: Options) -> [Match] {
        let units = makeUnits(lines)
        guard !units.isEmpty else { return [] }
        let cs = options.caseSensitive
        let joined = options.regex ? String(units.map(\.ch)) : ""
        let text: Keys? = options.regex ? nil : (options.fuzzy ? fuzzyKeys(units, cs) : plainKeys(units, cs))
        var found: [Match] = []
        for (index, raw) in terms.enumerated() {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let hits: [(Int, Int)]
            if let text {
                let termUnits = makeUnits([term])
                hits = scan(options.fuzzy ? fuzzyKeys(termUnits, cs) : plainKeys(termUnits, cs),
                            in: text, units: units, wholeWord: options.wholeWord)
            } else {
                hits = regexHits(term, in: joined, units: units, options: options)
            }
            for (a, b) in hits {
                let pieces = spans(from: a, to: b, units: units)
                if !pieces.isEmpty { found.append(Match(term: index, spans: pieces)) }
            }
        }
        found.sort { x, y in
            let p = x.spans[0], q = y.spans[0]
            if p.line != q.line { return p.line < q.line }
            if p.range.lowerBound != q.range.lowerBound { return p.range.lowerBound < q.range.lowerBound }
            return x.term < y.term
        }
        // Two terms that found the very same text mark it once, under the first term.
        var kept: [Match] = []
        for match in found {
            var duplicate = false
            for earlier in kept.reversed() {
                if earlier.spans[0].line != match.spans[0].line { break }
                if earlier.spans == match.spans { duplicate = true; break }
            }
            if !duplicate { kept.append(match) }
        }
        return kept
    }

    /// Whether `pattern` compiles as a regular expression (the bar marks a bad pattern instead of matching nothing).
    static func isValidPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    // MARK: Joined text

    /// One character of the lines joined with single spaces, remembering where it came from. `line` is -1 for the
    /// joining space.
    private struct Unit {
        let ch: Character
        let line: Int
        let start: String.Index
        let end: String.Index
        let utf16Start: Int
        let utf16End: Int
    }

    /// What gets compared: one key per comparable step, and the first and last unit each key stands for.
    private struct Keys {
        var keys: [String] = []
        var first: [Int] = []
        var last: [Int] = []
    }

    private static func makeUnits(_ lines: [String]) -> [Unit] {
        var out: [Unit] = []
        var offset = 0
        for (n, line) in lines.enumerated() where !line.isEmpty {
            if !out.isEmpty {
                out.append(Unit(ch: " ", line: -1, start: line.startIndex, end: line.startIndex,
                                utf16Start: offset, utf16End: offset + 1))
                offset += 1
            }
            var i = line.startIndex
            while i < line.endIndex {
                let next = line.index(after: i)
                let length = line[i..<next].utf16.count
                out.append(Unit(ch: line[i], line: n, start: i, end: next, utf16Start: offset, utf16End: offset + length))
                offset += length
                i = next
            }
        }
        return out
    }

    private static func fold(_ ch: Character, _ caseSensitive: Bool) -> String {
        if ch.isWhitespace { return " " }
        return caseSensitive ? String(ch) : String(ch).folding(options: .caseInsensitive, locale: nil)
    }

    private static func plainKeys(_ units: [Unit], _ caseSensitive: Bool) -> Keys {
        Keys(keys: units.map { fold($0.ch, caseSensitive) }, first: Array(units.indices), last: Array(units.indices))
    }

    // MARK: Fuzzy

    private static let lookAlikes: [String: String] = {
        var table: [String: String] = [:]
        for (key, members) in [("0", "0Oo"), ("1", "1lI|!"), ("5", "5Ss"), ("8", "8B"), ("2", "2Zz")] {
            for member in members { table[String(member)] = key }
        }
        return table
    }()

    private static func lookAlikeKey(_ ch: Character, _ caseSensitive: Bool) -> String? {
        let s = String(ch)
        if let key = lookAlikes[s] { return key }
        if !caseSensitive {
            for variant in [s.lowercased(), s.uppercased()] { if let key = lookAlikes[variant] { return key } }
        }
        return nil
    }

    /// Whitespace dropped, look-alikes collapsed, "rn" read as "m" and "vv" as "w".
    private static func fuzzyKeys(_ units: [Unit], _ caseSensitive: Bool) -> Keys {
        func base(_ ch: Character) -> String { caseSensitive ? String(ch) : fold(ch, false) }
        let ids = units.indices.filter { !units[$0].ch.isWhitespace }
        var out = Keys()
        var j = 0
        while j < ids.count {
            let a = base(units[ids[j]].ch)
            if j + 1 < ids.count {
                let b = base(units[ids[j + 1]].ch)
                if (a == "r" && b == "n") || (a == "v" && b == "v") {
                    out.keys.append(a == "r" ? "m" : "w")
                    out.first.append(ids[j])
                    out.last.append(ids[j + 1])
                    j += 2
                    continue
                }
            }
            out.keys.append(lookAlikeKey(units[ids[j]].ch, caseSensitive) ?? a)
            out.first.append(ids[j])
            out.last.append(ids[j])
            j += 1
        }
        return out
    }

    // MARK: Finding

    /// Unit ranges (first, last) of each non-overlapping hit of `term` in `text`.
    private static func scan(_ term: Keys, in text: Keys, units: [Unit], wholeWord: Bool) -> [(Int, Int)] {
        let m = term.keys.count
        var out: [(Int, Int)] = []
        var i = 0
        while m > 0, i + m <= text.keys.count {
            if text.keys[i..<(i + m)].elementsEqual(term.keys) {
                let a = text.first[i], b = text.last[i + m - 1]
                if !wholeWord || (!isWordChar(units, a - 1) && !isWordChar(units, b + 1)) {
                    out.append((a, b))
                    i += m
                    continue
                }
            }
            i += 1
        }
        return out
    }

    private static func isWordChar(_ units: [Unit], _ index: Int) -> Bool {
        guard units.indices.contains(index) else { return false }
        return units[index].ch.isLetter || units[index].ch.isNumber
    }

    private static func regexHits(_ pattern: String, in joined: String, units: [Unit], options: Options) -> [(Int, Int)] {
        let wrapped = options.wholeWord ? "\\b(?:\(pattern))\\b" : pattern
        let flags: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: wrapped, options: flags) else { return [] }
        let whole = NSRange(location: 0, length: joined.utf16.count)
        var out: [(Int, Int)] = []
        for m in regex.matches(in: joined, range: whole) where m.range.length > 0 {
            let lo = m.range.location, hi = lo + m.range.length
            guard let a = units.firstIndex(where: { $0.utf16End > lo }),
                  let b = units.lastIndex(where: { $0.utf16Start < hi }), a <= b else { continue }
            out.append((a, b))
        }
        return out
    }

    /// The per-line spans of units `a...b`, leaving out the joining spaces.
    private static func spans(from a: Int, to b: Int, units: [Unit]) -> [Span] {
        var out: [Span] = []
        var k = a
        while k <= b {
            let first = units[k]
            if first.line < 0 { k += 1; continue }
            var last = first
            var n = k + 1
            while n <= b, units[n].line == first.line { last = units[n]; n += 1 }
            out.append(Span(line: first.line, range: first.start..<last.end))
            k = n
        }
        return out
    }
}
