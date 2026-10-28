import CoreGraphics
import Foundation

/// Capture Text with formatting: rebuilds headings, bullet and numbered lists, bold, `code` and colored words from OCR
/// lines as Markdown, and renders that Markdown as HTML for rich-text paste. Vision reports no fonts or colors, so the
/// styles come from the pixels around each word (`Bitmap.look`). All of it is pure, so it runs without a screen.
enum FormattedText {
    // MARK: Model

    /// One recognized word: its text, box (pixels, bottom-left origin) and what the pixels say about it.
    struct Word: Equatable, Sendable {
        var text: String
        var rect: CGRect
        var look = Look()
    }

    /// How a word is drawn; nil where the pixels can't tell.
    struct Look: Equatable, Sendable {
        /// Average stroke width in pixels: bold strokes are thicker.
        var stroke: Double?
        /// The color of the letters.
        var ink: RGB?
        /// The background behind the word, when it is even.
        var background: RGB?
    }

    /// One recognized line: its box and words, left to right.
    struct Line: Equatable, Sendable {
        var rect: CGRect
        var words: [Word]
        /// A bullet is drawn just left of the box that Vision didn't read as text.
        var bullet = false
        var text: String { words.map(\.text).joined(separator: " ") }
        /// How tall the text is: the median height of its words. Vision sometimes reads a line as slanted, which makes
        /// the line's box much taller than its words.
        var size: CGFloat { FormattedText.median(words.map(\.rect.height)) }
    }

    struct RGB: Equatable, Hashable, Sendable {
        var r, g, b: Double
        /// The largest difference in any channel, 0...1.
        func distance(to o: RGB) -> Double { max(abs(r - o.r), abs(g - o.g), abs(b - o.b)) }
        /// How far from grey.
        var chroma: Double { max(r, g, b) - min(r, g, b) }
        var hex: String { String(format: "#%02lx%02lx%02lx", byte(r), byte(g), byte(b)) }
        private func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    }

    struct Style: Equatable, Sendable {
        var bold = false
        var code = false
        var color: RGB?
    }

    /// Words of one line in one style.
    struct Run: Equatable, Sendable {
        var text: String
        var style = Style()
    }

    enum Block: Equatable, Sendable {
        case heading(level: Int, runs: [Run])
        /// A list item; `number` is nil for a bullet.
        case item(depth: Int, number: Int?, runs: [Run])
        case text([Run])
        /// Lines on a shaded background, laid out like Capture Code.
        case code(String)
        /// A blank line between paragraphs.
        case gap
    }

    /// Words drawn in color: Markdown has no color, so they travel beside it to the rich-text copy.
    struct Painted: Equatable, Sendable {
        var text: String
        var hex: String
    }

    struct Result: Equatable, Sendable {
        var text = ""
        var colors: [Painted] = []
    }

    /// The Markdown of `lines`, with its colored words.
    static func format(_ lines: [Line]) -> Result {
        let parsed = blocks(lines)
        return Result(text: markdown(parsed), colors: colors(parsed))
    }

    /// The ranges of the words (runs of non-whitespace) in `text`.
    static func wordRanges(_ text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isWhitespace {
                if let s = start { out.append(s..<i); start = nil }
            } else if start == nil {
                start = i
            }
            i = text.index(after: i)
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    // MARK: Thresholds

    /// A line this many times the usual height is a heading: level 1, then level 2.
    static let headingRatios: (CGFloat, CGFloat) = (1.75, 1.3)
    /// A word whose strokes are this many times the usual width is bold.
    static let boldRatio = 1.3
    /// A word whose background differs this much from the page's sits on a code chip.
    static let chipContrast = 0.035
    /// Ink this far from grey, and from the usual ink, is colored.
    static let colorChroma = 0.2

    // MARK: Layout

    /// The blocks of `lines` (in Vision's reading order): headings by height, list items by their markers and
    /// indentation, wrapped list lines joined to their item, runs of all-code lines as code blocks.
    static func blocks(_ input: [Line]) -> [Block] {
        let lines = joinStrayBullets(input.filter { !$0.words.isEmpty && $0.rect.height > 0 })
        guard !lines.isEmpty else { return [] }
        let body = median(lines.map(\.size))
        let levels = lines.map { headingLevel($0, body: body, count: lines.count) }
        let styles = self.styles(lines, headings: levels.map { $0 != nil })
        let isCode = lines.indices.map { levels[$0] == nil && styles[$0].allSatisfy(\.code) }
        let pitch = self.pitch(lines, body: body)
        let tolerance = body * 0.5

        var out: [Block] = []
        var listX: [CGFloat] = []   // where the open list's markers start, one per depth
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let breaks = i > 0 && isBreak(from: lines[i - 1], to: line, pitch: pitch, body: body)
            if breaks, !out.isEmpty, out.last != .gap { out.append(.gap) }

            // Two or more code lines in a row are a code block.
            var end = i
            while isCode[i], end + 1 < lines.count, isCode[end + 1] { end += 1 }
            if end > i {
                out.append(.code(CodeText.format(lines[i...end].map { CodeText.Line(text: $0.text, rect: $0.rect) })))
                listX = []
                i = end + 1
                continue
            }

            var runs = self.runs(line.words, styles[i])
            if let level = levels[i] {
                out.append(.heading(level: level, runs: runs))
                listX = []
            } else if let mark = marker(line.text, nested: listX.first.map { line.rect.minX > $0 + tolerance } ?? false)
                        ?? (line.bullet ? Marker(number: nil, length: 0) : nil) {
                runs = dropPrefix(runs, mark.length)
                // A bullet left of the box sits about a line height before the text.
                let x = line.rect.minX - (mark.length == 0 ? line.rect.height : 0)
                out.append(.item(depth: depth(x, &listX, tolerance: tolerance), number: mark.number, runs: runs))
            } else if case .item(let depth, let number, let previous)? = out.last, !breaks,
                      listX.indices.contains(depth), line.rect.minX > listX[depth] + tolerance {
                // A wrapped line of the item: indented past its marker.
                out[out.count - 1] = .item(depth: depth, number: number, runs: joined(previous, runs))
            } else {
                out.append(.text(runs))
                listX = []
            }
            i += 1
        }
        return out
    }

    /// Level 1 or 2 for a short line well taller than the usual one; nil for body text.
    static func headingLevel(_ line: Line, body: CGFloat, count: Int) -> Int? {
        guard count >= 3, body > 0, line.words.count <= 12 else { return nil }
        let ratio = line.size / body
        return ratio >= headingRatios.0 ? 1 : ratio >= headingRatios.1 ? 2 : nil
    }

    /// The typical (lower median) step between rows; a typical one when there are too few to tell.
    private static func pitch(_ lines: [Line], body: CGFloat) -> CGFloat {
        let steps = zip(lines, lines.dropFirst()).map { $0.rect.midY - $1.rect.midY }.filter { $0 > body * 0.5 }.sorted()
        return steps.count >= 2 ? steps[(steps.count - 1) / 2] : body * 1.4
    }

    /// A new paragraph: more than 1.5 rows down, or back up (the next column).
    private static func isBreak(from previous: Line, to line: Line, pitch: CGFloat, body: CGFloat) -> Bool {
        let step = previous.rect.midY - line.rect.midY
        return step < -body * 0.5 || step > pitch * 1.5
    }

    /// The depth of a list item whose marker starts at `x`: the same as an earlier item within `tolerance`, deeper
    /// when further right.
    private static func depth(_ x: CGFloat, _ listX: inout [CGFloat], tolerance: CGFloat) -> Int {
        while let last = listX.last, x < last - tolerance { listX.removeLast() }
        if let last = listX.last, abs(x - last) <= tolerance { return listX.count - 1 }
        listX.append(x)
        return listX.count - 1
    }

    /// The bullets Vision reads as a line of their own, joined to the line just right of them on the same row.
    static func joinStrayBullets(_ input: [Line]) -> [Line] {
        var lines = input
        var i = 0
        while i < lines.count {
            let b = lines[i]
            guard b.words.count == 1, b.text.count == 1, bulletGlyphs.contains(b.text) || "-*+".contains(b.text) else {
                i += 1
                continue
            }
            let target = lines.indices.filter { j in
                j != i && lines[j].rect.minX >= b.rect.midX
                    && abs(lines[j].rect.midY - b.rect.midY) < max(lines[j].rect.height, b.rect.height) * 0.5
            }.min { lines[$0].rect.minX < lines[$1].rect.minX }
            guard let j = target else { i += 1; continue }
            lines[j].words.insert(b.words[0], at: 0)
            lines[j].rect = lines[j].rect.union(b.rect)
            lines.remove(at: i)
        }
        return lines
    }

    // MARK: Markers

    static let bulletGlyphs = "•◦▪▫‣⁃●○■□·∙►▸➢✓✔"

    /// A list marker at the start of a line: `number` for `1.` or `1)`, nil for a bullet; `length` is the characters
    /// it takes, with the spaces after it.
    struct Marker: Equatable {
        var number: Int?
        var length: Int
    }

    /// The list marker `text` starts with. Bullet glyphs may touch the word; dashes and asterisks need a space, so
    /// `-5` and `*args` stay text. A hollow bullet read as `o` counts only on a `nested` line (indented past the list).
    static func marker(_ text: String, nested: Bool = false) -> Marker? {
        let patterns = ["^(\\d{1,3})[.)]\\s+(?=\\S)", "^[\(bulletGlyphs)]\\s*(?=\\S)", "^[-*+–—]\\s+(?=\\S)"]
            + (nested ? ["^o\\s+(?=\\S)"] : [])
        let ns = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: ns), let range = Range(m.range, in: text) else { continue }
            let number = m.numberOfRanges > 1 ? Range(m.range(at: 1), in: text).flatMap { Int(text[$0]) } : nil
            return Marker(number: number, length: text.distance(from: text.startIndex, to: range.upperBound))
        }
        return nil
    }

    /// `runs` without their first `count` characters (runs are joined by single spaces).
    private static func dropPrefix(_ runs: [Run], _ count: Int) -> [Run] {
        var left = count
        var out: [Run] = []
        for run in runs {
            if left <= 0 { out.append(run); continue }
            if left >= run.text.count { left -= run.text.count + 1; continue }   // and the space after it
            out.append(Run(text: String(run.text.dropFirst(left)), style: run.style))
            left = 0
        }
        return out
    }

    // MARK: Styles

    /// Each word's style, from how it is drawn compared to the rest: a background unlike the page's is a code chip,
    /// strokes well thicker than the usual are bold (never in headings), ink unlike the usual and not grey is colored.
    /// Strokes are measured against the text size; the usual stroke is the line's own when it has enough words (the
    /// measurements vary from line to line), or the page's when that is thinner (a line that is all bold).
    static func styles(_ lines: [Line], headings: [Bool]) -> [[Style]] {
        let page = mostCommon(lines.flatMap(\.words).compactMap(\.look.background))
        func onChip(_ w: Word) -> Bool {
            guard let page, let bg = w.look.background else { return false }
            return bg.distance(to: page) > chipContrast
        }
        /// Plain-text strokes over the text size, by word (nil where not measured or not counted).
        func strokes(_ line: Line, heading: Bool) -> [Double?] {
            line.words.map { w in
                guard !heading, !onChip(w), letters(w.text) >= 2, let s = w.look.stroke, line.size > 0 else { return nil }
                return s / Double(line.size)
            }
        }
        let byLine = zip(lines, headings).map { strokes($0, heading: $1) }
        let all = byLine.flatMap { $0.compactMap { $0 } }
        let pageStroke = all.count >= 5 ? median(all) : nil
        let inks = zip(lines, headings).filter { !$0.1 }.flatMap { $0.0.words.filter { !onChip($0) }.compactMap(\.look.ink) }
        let usualInk = inks.isEmpty ? nil : median(inks)
        // Colors close to one already seen take its value, so a colored phrase stays one run.
        var palette: [RGB] = []
        func colored(_ ink: RGB?) -> RGB? {
            guard let ink, ink.chroma >= colorChroma, usualInk.map({ ink.distance(to: $0) >= colorChroma }) ?? true else { return nil }
            if let near = palette.first(where: { $0.distance(to: ink) < 0.15 }) { return near }
            palette.append(ink)
            return ink
        }
        return lines.indices.map { i in
            let line = lines[i]
            let own = byLine[i].compactMap { $0 }
            let usual = own.count >= 4 ? min(median(own), pageStroke ?? .infinity) : pageStroke
            var out = line.words.indices.map { k -> Style in
                let w = line.words[k]
                var s = Style(code: onChip(w), color: colored(w.look.ink))
                if let usual, let stroke = byLine[i][k] { s.bold = stroke >= usual * boldRatio }
                return s
            }
            // A short word between two bold ones ("a", "&") is bold too, so the bold run isn't broken.
            for k in out.indices.dropFirst().dropLast() where letters(line.words[k].text) < 2 && out[k - 1].bold && out[k + 1].bold {
                out[k].bold = true
            }
            return out
        }
    }

    /// Adjacent words in the same style, as runs.
    static func runs(_ words: [Word], _ styles: [Style]) -> [Run] {
        var out: [Run] = []
        for (w, s) in zip(words, styles) {
            if let last = out.last, last.style == s {
                out[out.count - 1].text += " " + w.text
            } else {
                out.append(Run(text: w.text, style: s))
            }
        }
        return out
    }

    private static func joined(_ a: [Run], _ b: [Run]) -> [Run] {
        guard let last = a.last, let first = b.first else { return a + b }
        if last.style == first.style {
            return a.dropLast() + [Run(text: last.text + " " + first.text, style: last.style)] + b.dropFirst()
        }
        return a + b
    }

    private static func letters(_ text: String) -> Int { text.filter(\.isLetter).count }

    /// The most common color (to within 1/32 in each channel), averaged over its bucket.
    static func mostCommon(_ colors: [RGB]) -> RGB? {
        var buckets: [[Int]: [RGB]] = [:]
        for c in colors { buckets[[c.r, c.g, c.b].map { Int(($0 * 31.99).rounded(.down)) }, default: []].append(c) }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let n = Double(best.count)
        return RGB(r: best.map(\.r).reduce(0, +) / n, g: best.map(\.g).reduce(0, +) / n, b: best.map(\.b).reduce(0, +) / n)
    }

    /// The median of each channel.
    static func median(_ colors: [RGB]) -> RGB {
        RGB(r: median(colors.map(\.r)), g: median(colors.map(\.g)), b: median(colors.map(\.b)))
    }

    static func median<T: BinaryFloatingPoint>(_ values: [T]) -> T {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    // MARK: Markdown

    /// `blocks` as Markdown: `#` headings, `-` and `1.` items indented under their parent's text, `**bold**`,
    /// `` `code` ``, fenced code blocks; blank lines between paragraphs and around headings, lists and code.
    static func markdown(_ blocks: [Block]) -> String {
        var out: [String] = []
        var widths: [Int] = []   // the marker width of the open item at each depth
        var previous: Block?
        func blank() { if let last = out.last, !last.isEmpty { out.append("") } }
        for block in blocks {
            if needsBlank(after: previous, before: block) { blank() }
            switch block {
            case .gap:
                blank()
            case .heading(let level, let runs):
                out.append(String(repeating: "#", count: level) + " " + inline(runs))
                widths = []
            case .code(let code):
                out.append(CodeText.fence(code))
                widths = []
            case .item(let depth, let number, let runs):
                widths = Array(widths.prefix(min(depth, widths.count)))   // a level can't be skipped
                let mark = number.map { "\($0). " } ?? "- "
                out.append(String(repeating: " ", count: widths.reduce(0, +)) + mark + inline(runs))
                widths.append(mark.count)
            case .text(let runs):
                var line = inline(runs)
                if line.hasPrefix("#") || line.hasPrefix(">") { line = "\\" + line }
                out.append(line)
                widths = []
            }
            previous = block
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// Headings and code blocks stand apart, and so do lists from paragraphs (text right after an item would join it).
    private static func needsBlank(after previous: Block?, before block: Block) -> Bool {
        guard let previous, block != .gap else { return false }
        switch (previous, block) {
        case (.heading, _), (.code, _), (_, .heading), (_, .code), (.text, .item), (.item, .text): return true
        default: return false
        }
    }

    static func inline(_ runs: [Run]) -> String {
        runs.map { run in
            let text = run.style.code ? codeSpan(run.text) : escape(run.text)
            return run.style.bold ? "**\(text)**" : text
        }.joined(separator: " ")
    }

    /// Backslashes, asterisks and backticks escaped, so they show as typed.
    static func escape(_ text: String) -> String {
        var out = ""
        for c in text {
            if "\\*`".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// `text` as inline code, fenced by more backticks than any run inside it.
    static func codeSpan(_ text: String) -> String {
        var longest = 0, run = 0
        for c in text { run = c == "`" ? run + 1 : 0; longest = max(longest, run) }
        let mark = String(repeating: "`", count: longest + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        return mark + pad + text + pad + mark
    }

    /// The colored runs, in order.
    static func colors(_ blocks: [Block]) -> [Painted] {
        blocks.flatMap { block -> [Run] in
            switch block {
            case .heading(_, let runs), .item(_, _, let runs), .text(let runs): return runs
            case .code, .gap: return []
            }
        }.compactMap { run in run.style.color.map { Painted(text: run.text, hex: $0.hex) } }
    }

    // MARK: Plain text

    private static let headingPattern = "^(#{1,6})\\s+(.*)$"
    private static let itemPattern = "^( *)([-*+]|(\\d{1,9})[.)])\\s+(.*)$"

    /// The capture groups of `pattern` matched against all of `line`, nil when it doesn't match.
    private static func groups(_ pattern: String, in line: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: line).map { String(line[$0]) } }
    }

    /// `markdown` as clean plain text for fields that don't read Markdown: headings as their text, lists with `•` `◦` `▪`
    /// bullets (3 spaces per level) or their numbers, code indented 4 spaces, and no `**`, backticks or escapes.
    static func plain(markdown: String) -> String {
        var out: [String] = []
        var indents: [Int] = []   // the open lists' indents, outermost first
        var textIndent = 0        // where the current item's text starts, for its wrapped lines
        var fence: String?
        let bullets = ["•", "◦", "▪"]

        func text(_ markdown: String) -> String { segments(markdown).map(\.text).joined() }
        func blank() { if let last = out.last, !last.isEmpty { out.append("") } }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open), trimmed.allSatisfy({ $0 == "`" }) {
                    fence = nil
                } else {
                    out.append(line.isEmpty ? "" : "    " + line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                indents = []
                fence = String(trimmed.prefix { $0 == "`" })
                continue
            }
            if trimmed.isEmpty { blank(); continue }
            if let g = groups(headingPattern, in: line), let content = g[2] {
                indents = []
                out.append(text(content))
                continue
            }
            if let g = groups(itemPattern, in: line), let spaces = g[1], let content = g[4] {
                let indent = spaces.count
                while let last = indents.last, last > indent { indents.removeLast() }
                if indents.last.map({ $0 < indent }) ?? true { indents.append(indent) }
                let depth = indents.count - 1
                let marker = g[3].map { "\($0)." } ?? bullets[depth % bullets.count]
                let pad = String(repeating: "   ", count: depth)
                out.append(pad + marker + " " + text(content))
                textIndent = pad.count + marker.count + 1
                continue
            }
            if !indents.isEmpty, line.hasPrefix("  ") {
                out.append(String(repeating: " ", count: textIndent) + text(trimmed))
                continue
            }
            indents = []
            out.append(text(trimmed))
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    // MARK: HTML

    /// `markdown` (as written by `markdown(_:)`, or edited in the scratch pad) as HTML for rich-text paste: headings,
    /// nested lists, paragraphs (line breaks kept), code blocks, bold and `code`, with `colors` on their words.
    static func html(markdown: String, colors: [Painted]) -> String {
        var html = ""
        var paint = Paint(left: colors)
        var paragraph: [String] = []
        var lists: [(indent: Int, tag: String)] = []
        var fence: String?   // the open code block's fence
        var code: [String] = []

        func closeParagraph() {
            if !paragraph.isEmpty { html += "<p>" + paragraph.joined(separator: "<br>") + "</p>" }
            paragraph = []
        }
        func closeLists(deeperThan indent: Int = -1) {
            while let last = lists.last, last.indent > indent {
                html += "</li></\(last.tag)>"
                lists.removeLast()
            }
        }
        let heading = headingPattern, item = itemPattern

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open), trimmed.allSatisfy({ $0 == "`" }) {
                    html += "<pre><code>" + escapeHTML(code.joined(separator: "\n")) + "</code></pre>"
                    fence = nil
                    code = []
                } else {
                    code.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                closeParagraph()
                closeLists()
                fence = String(trimmed.prefix { $0 == "`" })
                continue
            }
            if trimmed.isEmpty { closeParagraph(); continue }
            if let g = groups(heading, in: line), let marks = g[1], let text = g[2] {
                closeParagraph()
                closeLists()
                html += "<h\(marks.count)>" + paint.inline(text) + "</h\(marks.count)>"
                continue
            }
            if let g = groups(item, in: line), let spaces = g[1], let text = g[4] {
                closeParagraph()
                let indent = spaces.count
                let tag = g[3] == nil ? "ul" : "ol"
                closeLists(deeperThan: indent)
                if let last = lists.last, last.indent == indent {
                    if last.tag == tag {
                        html += "</li>"
                    } else {
                        html += "</li></\(last.tag)>"
                        lists.removeLast()
                    }
                }
                if lists.last.map({ $0.indent < indent }) ?? true {
                    let start = g[3].flatMap { Int($0) } ?? 1
                    html += start == 1 ? "<\(tag)>" : "<ol start=\"\(start)\">"
                    lists.append((indent, tag))
                }
                html += "<li>" + paint.inline(text)
                continue
            }
            if !lists.isEmpty, paragraph.isEmpty, line.hasPrefix("  ") {
                html += "<br>" + paint.inline(trimmed)   // a wrapped line of the item
                continue
            }
            closeLists()
            paragraph.append(paint.inline(trimmed))
        }
        if fence != nil { html += "<pre><code>" + escapeHTML(code.joined(separator: "\n")) + "</code></pre>" }
        closeParagraph()
        closeLists()
        return html
    }

    /// A piece of inline Markdown.
    struct Segment: Equatable {
        var text: String
        var bold = false
        var code = false
    }

    /// Inline Markdown as segments: backslash escapes, `` `code` `` spans (any number of backticks) and `**bold**`.
    /// An unclosed `**` stays as text.
    static func segments(_ markdown: String) -> [Segment] {
        let chars = Array(markdown)
        var out: [Segment] = []
        var text = ""
        var bold = false
        var boldStart = 0
        func flush() {
            if !text.isEmpty { out.append(Segment(text: text, bold: bold)) }
            text = ""
        }
        func ticks(at i: Int) -> Int {
            var n = 0
            while i + n < chars.count, chars[i + n] == "`" { n += 1 }
            return n
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1].isPunctuation || chars[i + 1].isSymbol {
                text.append(chars[i + 1])
                i += 2
            } else if c == "`" {
                let n = ticks(at: i)
                var j = i + n, close: Int?
                while j < chars.count {
                    let m = ticks(at: j)
                    if m == n { close = j; break }
                    j += max(m, 1)
                }
                guard let close else { text += String(repeating: "`", count: n); i += n; continue }
                flush()
                var code = String(chars[(i + n)..<close])
                if code.count >= 2, code.hasPrefix(" "), code.hasSuffix(" "), code.contains(where: { $0 != " " }) {
                    code = String(code.dropFirst().dropLast())
                }
                out.append(Segment(text: code, bold: bold, code: true))
                i = close + n
            } else if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                flush()
                if !bold { boldStart = out.count }
                bold.toggle()
                i += 2
            } else {
                text.append(c)
                i += 1
            }
        }
        flush()
        if bold {
            for k in boldStart..<out.count { out[k].bold = false }
            out.insert(Segment(text: "**"), at: boldStart)
        }
        return out
    }

    /// Inline Markdown to HTML, coloring the painted words: each one once, in order of appearance, as whole words.
    private struct Paint {
        var left: [Painted]

        mutating func inline(_ markdown: String) -> String {
            FormattedText.segments(markdown).map { segment in
                var s = color(segment.text)
                if segment.code { s = "<code>\(s)</code>" }
                if segment.bold { s = "<b>\(s)</b>" }
                return s
            }.joined()
        }

        private mutating func color(_ text: String) -> String {
            var out = ""
            var rest = Substring(text)
            while true {
                var best: (range: Range<Substring.Index>, index: Int)?
                for (k, p) in left.enumerated() where !p.text.isEmpty {
                    guard let r = Self.wholeWords(p.text, in: rest) else { continue }
                    if let b = best, r.lowerBound > b.range.lowerBound
                        || (r.lowerBound == b.range.lowerBound && r.upperBound <= b.range.upperBound) { continue }
                    best = (r, k)
                }
                guard let best else { break }
                out += FormattedText.escapeHTML(String(rest[..<best.range.lowerBound]))
                out += "<span style=\"color:\(left[best.index].hex)\">" + FormattedText.escapeHTML(String(rest[best.range])) + "</span>"
                rest = rest[best.range.upperBound...]
                left.remove(at: best.index)
            }
            return out + FormattedText.escapeHTML(String(rest))
        }

        /// The first place `phrase` stands in `text` without a letter or digit touching it.
        private static func wholeWords(_ phrase: String, in text: Substring) -> Range<Substring.Index>? {
            func wordy(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: phrase, range: from..<text.endIndex) {
                let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
                let after = r.upperBound < text.endIndex ? text[r.upperBound] : nil
                if !(wordy(phrase.first) && wordy(before)) && !(wordy(phrase.last) && wordy(after)) { return r }
                from = text.index(after: r.lowerBound)
            }
            return nil
        }
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
