import CoreGraphics
import Foundation

/// Capture Code (#249): rebuilds code from OCR lines. Indentation comes from where each line's box starts, measured in
/// character widths; a few safe fixes undo common OCR mistakes. All of it is pure, so it runs without a screen.
enum CodeText {
    /// One recognized line: its text and box (any consistent units, bottom-left origin so higher y is higher up).
    struct Line: Equatable, Sendable {
        var text: String
        var rect: CGRect
    }

    /// The code in `lines`: ordered top to bottom, indented, blank lines kept, mistakes fixed. `fenced` wraps it in a
    /// Markdown code block.
    static func format(_ lines: [Line], fenced: Bool = false) -> String {
        let code = layout(lines).split(separator: "\n", omittingEmptySubsequences: false)
            .map { cleanup(String($0)) }.joined(separator: "\n")
        return fenced && !code.isEmpty ? fence(code) : code
    }

    // MARK: Layout

    /// The lines as text: top to bottom, parts of one row joined, indentation rebuilt, one blank line where the rows
    /// are more than 1.5 line pitches apart.
    static func layout(_ lines: [Line]) -> String {
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.rect.height > 0 }
        guard !lines.isEmpty else { return "" }
        let width = characterWidth(lines)
        let rows = groupRows(lines, characterWidth: width)
        let left = rows.map(\.minX).min() ?? 0
        let indents = snapIndents(rows.map { max(0, Int(((($0.minX - left) / width)).rounded())) })

        var distances: [CGFloat] = []
        for i in rows.indices.dropFirst() { distances.append(rows[i - 1].midY - rows[i].midY) }
        // The pitch is the typical (lower median) distance between rows; with a single gap a typical one stands in.
        let height = median(rows.map(\.height).sorted())
        let pitch = distances.count >= 2 ? distances.sorted()[(distances.count - 1) / 2] : height * 1.4

        var out: [String] = []
        for (i, row) in rows.enumerated() {
            if i > 0, pitch > 0, distances[i - 1] > pitch * 1.5 { out.append("") }
            out.append(String(repeating: " ", count: indents[i]) + row.text)
        }
        return out.joined(separator: "\n")
    }

    /// Width of one character: the median of each line's width over its character count (code is monospaced).
    /// Short lines are skipped as too coarse unless nothing else is left.
    static func characterWidth(_ lines: [Line]) -> CGFloat {
        func widths(_ minCount: Int) -> [CGFloat] {
            lines.compactMap { line in
                let n = line.text.trimmingCharacters(in: .whitespaces).count
                return n >= minCount && line.rect.width > 0 ? line.rect.width / CGFloat(n) : nil
            }.sorted()
        }
        let long = widths(4)
        let w = long.isEmpty ? widths(1) : long
        if !w.isEmpty { return median(w) }
        return max(1, median(lines.map(\.rect.height).sorted()) * 0.6)
    }

    private struct Row { var text: String; var minX: CGFloat; var midY: CGFloat; var height: CGFloat }

    /// Top-to-bottom rows; boxes that sit on the same row (Vision sometimes splits one) are joined left to right,
    /// with spaces for the gap between them.
    private static func groupRows(_ lines: [Line], characterWidth: CGFloat) -> [Row] {
        var groups: [[Line]] = []
        for line in lines.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let first = groups.last?.first,
               abs(first.rect.midY - line.rect.midY) < 0.5 * min(first.rect.height, line.rect.height) {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let parts = group.sorted { $0.rect.minX < $1.rect.minX }
            var text = parts[0].text.trimmingCharacters(in: .whitespaces)
            for (prev, next) in zip(parts, parts.dropFirst()) {
                let gap = max(1, Int(((next.rect.minX - prev.rect.maxX) / characterWidth).rounded()))
                text += String(repeating: " ", count: gap) + next.text.trimmingCharacters(in: .whitespaces)
            }
            let mid = parts.map(\.rect.midY).reduce(0, +) / CGFloat(parts.count)
            return Row(text: text, minX: parts[0].rect.minX, midY: mid, height: parts.map(\.rect.height).max() ?? 0)
        }
    }

    /// Snaps measured indents (in characters) to a 4- or 2-space unit when they fit one, to absorb a character of
    /// measuring noise. Indents that fit neither stay as measured.
    static func snapIndents(_ indents: [Int]) -> [Int] {
        let nonzero = indents.filter { $0 > 0 }
        guard !nonzero.isEmpty else { return indents }
        func nearest4(_ n: Int) -> Int { 4 * Int((Double(n) / 4).rounded()) }
        // 4: every indent is within one of a multiple of 4 (and an indent of 1 or 2 is real, not noise).
        if nonzero.allSatisfy({ $0 >= 3 && abs($0 - nearest4($0)) <= 1 }) {
            return indents.map(nearest4)
        }
        // 2: at most a quarter of the indents are odd; those round down to the unit.
        if nonzero.filter({ $0 % 2 == 1 }).count * 4 <= nonzero.count {
            return indents.map { $0 - $0 % 2 }
        }
        return indents
    }

    private static func median(_ sorted: [CGFloat]) -> CGFloat {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    // MARK: Cleanup

    /// Every rule, on one line of code. Leading indentation is kept; trailing spaces go.
    static func cleanup(_ line: String) -> String {
        let indent = line.prefix { $0 == " " }
        var body = String(line.dropFirst(indent.count))
        body = straightenQuotes(body)
        body = plainSpacesAndDots(body)
        body = fixDigits(body)
        return indent + body.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    /// Curly quotes and primes become straight ones: code never uses the curly kind.
    static func straightenQuotes(_ text: String) -> String {
        var out = text
        for (from, to) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201A}", "'"), ("\u{201B}", "'"),
                           ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""), ("\u{2032}", "'"), ("\u{2033}", "\"")] {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }

    /// Non-breaking spaces become spaces and the ellipsis character becomes three dots.
    static func plainSpacesAndDots(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{2026}", with: "...")
    }

    /// In a number made of digits and look-alike letters (l, I, O, o), the letters become 1 and 0, only when the
    /// number has at least two digits and no more letters than digits: `1O0` is 100, but `l0`, `lo` and `Il` are
    /// left alone, as are words and identifiers (`x1O`, `a.l00`).
    static func fixDigits(_ text: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_$.])[0-9lIOo]+(?:\\.[0-9lIOo]+)?(?![A-Za-z0-9_$])") else { return text }
        var out = text
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let token = ns.substring(with: m.range)
            let digits = token.filter { $0.isASCII && $0.isNumber }.count
            let letters = token.filter { "lIOo".contains($0) }.count
            guard letters > 0, digits >= 2, letters <= digits else { continue }
            let fixed = String(token.map { "lI".contains($0) ? "1" : "Oo".contains($0) ? "0" : $0 })
            out = (out as NSString).replacingCharacters(in: m.range, with: fixed)
        }
        return out
    }

    // MARK: Markdown

    /// `code` in a fenced block, with a fence longer than any run of backticks inside it.
    static func fence(_ code: String) -> String {
        var longest = 0, run = 0
        for c in code { run = c == "`" ? run + 1 : 0; longest = max(longest, run) }
        let mark = String(repeating: "`", count: max(3, longest + 1))
        return "\(mark)\n\(code)\n\(mark)"
    }
}
