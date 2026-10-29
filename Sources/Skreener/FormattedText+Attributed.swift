import AppKit

/// Capture Text's blocks as rich text for the scratch pad (#326), and back. Headings and code blocks carry their own
/// attribute, so reading back doesn't depend on font sizes. Lists are NSTextLists, and each item starts with its marker
/// between tabs ("\t•\t"), as TextEdit writes them. Colors are sRGB; text in the default `.textColor` has none.
extension FormattedText {
    /// What a paragraph is, which sets its font.
    enum Paragraph: Equatable {
        case body
        case heading(Int)
        case code
    }

    /// The heading level (an Int) of a heading's text.
    static let headingKey = NSAttributedString.Key("SkreenerHeading")
    /// Set on a code block's lines.
    static let codeBlockKey = NSAttributedString.Key("SkreenerCodeBlock")
    static let bodySize: CGFloat = 13
    /// How far each list level is indented.
    static let listIndent: CGFloat = 24

    /// The shade behind `code`, in light and dark mode.
    static var codeBackground: NSColor { .quaternaryLabelColor }

    // MARK: Attributes

    /// The paragraph that text with `attributes` sits in.
    static func paragraph(_ attributes: [NSAttributedString.Key: Any]) -> Paragraph {
        if let level = attributes[headingKey] as? Int { return .heading(level) }
        if attributes[codeBlockKey] != nil { return .code }
        return .body
    }

    /// The font of text in `style`: headings are bold at 20 or 16 points, `code` and code blocks monospaced.
    static func font(_ style: Style, in paragraph: Paragraph) -> NSFont {
        var size = bodySize, bold = style.bold
        switch paragraph {
        case .code: return .monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
        case .heading(let level): size = level <= 1 ? 20 : 16; bold = true
        case .body: break
        }
        let weight: NSFont.Weight = bold ? .bold : .regular
        let font = style.code ? NSFont.monospacedSystemFont(ofSize: size - 1, weight: weight) : .systemFont(ofSize: size, weight: weight)
        guard style.italic else { return font }
        let traits = font.fontDescriptor.symbolicTraits.union(.italic)
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    }

    /// The attributes of text in `style` in `paragraph`, with that paragraph's spacing.
    static func attributes(_ style: Style, in paragraph: Paragraph) -> [NSAttributedString.Key: Any] {
        var out: [NSAttributedString.Key: Any] = [.font: font(style, in: paragraph), .paragraphStyle: paragraphStyle(paragraph)]
        let color = paragraph == .code ? nil : style.color
        out[.foregroundColor] = color.map { NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) } ?? NSColor.textColor
        if style.code || paragraph == .code { out[.backgroundColor] = codeBackground }
        switch paragraph {
        case .heading(let level): out[headingKey] = level
        case .code: out[codeBlockKey] = true
        case .body: break
        }
        return out
    }

    /// The plain attributes of the paragraph `attributes` belong to (for markers, spaces and line breaks), keeping its
    /// paragraph style.
    static func baseAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var out = self.attributes(Style(), in: paragraph(attributes))
        if let style = attributes[.paragraphStyle] { out[.paragraphStyle] = style }
        return out
    }

    /// The style of text with `attributes`. Heading text is never bold (the heading is), code blocks have no styles,
    /// and only colors well away from grey count, so the default text color in either appearance reads as none.
    static func style(_ attributes: [NSAttributedString.Key: Any], in paragraph: Paragraph) -> Style {
        var s = Style()
        if paragraph == .code { return s }
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            s.bold = paragraph == .body && traits.contains(.bold)
            s.italic = traits.contains(.italic)
            s.code = font.isFixedPitch || traits.contains(.monoSpace)
        }
        if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
            let rgb = RGB(r: Double(color.redComponent), g: Double(color.greenComponent), b: Double(color.blueComponent))
            if rgb.chroma >= colorChroma { s.color = rgb }
        }
        return s
    }

    /// `text` with each piece's style kept, set in `paragraph` (a heading's text turned into body text, say).
    static func restyled(_ text: NSAttributedString, to paragraph: Paragraph) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var a = self.attributes(style(attributes, in: self.paragraph(attributes)), in: paragraph)
            if let p = attributes[.paragraphStyle] { a[.paragraphStyle] = p }
            out.setAttributes(a, range: range)
        }
        return out
    }

    static func paragraphStyle(_ paragraph: Paragraph) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        if case .heading(let level) = paragraph {
            p.paragraphSpacingBefore = level <= 1 ? 8 : 6
            p.paragraphSpacing = 4
        }
        return p
    }

    // MARK: Lists

    /// A list at `depth`: numbered, or with a •, ◦ or ▪ bullet by depth.
    static func list(depth: Int, ordered: Bool, start: Int = 1) -> NSTextList {
        let format: NSTextList.MarkerFormat = ordered ? .init(rawValue: "{decimal}.") : [.disc, .circle, .square][depth % 3]
        let list = NSTextList(markerFormat: format, options: .init())
        list.startingItemNumber = start
        return list
    }

    static func isOrdered(_ list: NSTextList) -> Bool { list.marker(forItemNumber: 1) != list.marker(forItemNumber: 2) }

    /// What item `number` of `list` starts with.
    static func marker(_ list: NSTextList, number: Int) -> String { "\t" + list.marker(forItemNumber: number) + "\t" }

    /// The length (UTF-16) of the "\t<marker>\t" that list item `paragraph` starts with, 0 when it has none.
    static func markerLength(_ paragraph: String) -> Int {
        let ns = paragraph as NSString
        let tab = UInt16(UInt8(ascii: "\t"))
        guard ns.length > 1, ns.character(at: 0) == tab else { return 0 }
        for i in 1..<min(ns.length, 16) where ns.character(at: i) == tab { return i + 1 }
        return 0
    }

    /// Items nested `lists` deep: the marker sits under the parent's text, the text one indent further in.
    static func listStyle(_ lists: [NSTextList]) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let depth = CGFloat(max(lists.count - 1, 0))
        let markerX = 6 + depth * listIndent, textX = markerX + listIndent
        p.tabStops = [NSTextTab(textAlignment: .natural, location: markerX, options: [:]),
                       NSTextTab(textAlignment: .natural, location: textX, options: [:])]
        p.defaultTabInterval = listIndent
        p.headIndent = textX
        p.paragraphSpacing = 2
        p.textLists = lists
        return p
    }

    // MARK: Blocks ⇄ rich text

    /// `blocks` as rich text, one paragraph each (a code block's lines one each); a gap is an empty paragraph.
    static func attributed(_ blocks: [Block]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var lineBreak: [NSAttributedString.Key: Any]?   // the attributes of the previous paragraph's line break
        func add(_ paragraph: NSAttributedString, _ base: [NSAttributedString.Key: Any]) {
            if let lineBreak { out.append(NSAttributedString(string: "\n", attributes: lineBreak)) }
            out.append(paragraph)
            lineBreak = base
        }
        func text(_ runs: [Run], _ paragraph: Paragraph, _ base: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
            let s = NSMutableAttributedString()
            for (i, run) in runs.enumerated() {
                if i > 0 { s.append(NSAttributedString(string: " ", attributes: base)) }
                var a = attributes(run.style, in: paragraph)
                a[.paragraphStyle] = base[.paragraphStyle]
                s.append(NSAttributedString(string: run.text, attributes: a))
            }
            return s
        }
        var lists: [NSTextList] = []   // the open lists, outermost first
        for block in blocks {
            switch block {
            case .item(let depth, let number, let runs):
                let d = min(depth, lists.count)   // a level can't be skipped
                lists = Array(lists.prefix(d + 1))
                if lists.count <= d || isOrdered(lists[d]) != (number != nil) {
                    lists = Array(lists.prefix(d)) + [list(depth: d, ordered: number != nil, start: number ?? 1)]
                }
                var base = attributes(Style(), in: .body)
                base[.paragraphStyle] = listStyle(lists)
                let p = NSMutableAttributedString(string: marker(lists[d], number: number ?? 1), attributes: base)
                p.append(text(runs, .body, base))
                add(p, base)
            case .heading(let level, let runs):
                lists = []
                let base = attributes(Style(), in: .heading(level))
                add(text(runs, .heading(level), base), base)
            case .text(let runs):
                lists = []
                let base = attributes(Style(), in: .body)
                add(text(runs, .body, base), base)
            case .code(let code):
                lists = []
                let base = attributes(Style(), in: .code)
                for line in code.components(separatedBy: "\n") { add(NSAttributedString(string: line, attributes: base), base) }
            case .gap:
                // Lists carry on past a gap, as in the Markdown.
                add(NSAttributedString(), attributes(Style(), in: .body))
            }
        }
        return out
    }

    /// The blocks of rich text written by `attributed(_:)` and edited in the scratch pad. Runs are split where the
    /// style changes, with the spaces between them dropped (the Markdown puts one back). Empty paragraphs and empty
    /// list items are gaps: several in a row make one, and there are none at the start or end. A paragraph without
    /// the heading attribute (pasted text, say) is still a heading when it is set bold at 15 points or more.
    static func blocks(from text: NSAttributedString) -> [Block] {
        var out: [Block] = []
        let ns = text.string as NSString
        func gap() { if let last = out.last, last != .gap { out.append(.gap) } }
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            let attributes = enclosing.length > 0 ? text.attributes(at: enclosing.location, effectiveRange: nil) : [:]
            let lists = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
            var kind = lists.isEmpty ? paragraph(attributes) : .body
            if kind == .code {
                let line = ns.substring(with: range)
                if case .code(let code)? = out.last {
                    out[out.count - 1] = .code(code + "\n" + line)
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    gap()
                } else {
                    out.append(.code(line))
                }
                return
            }
            let mark = lists.isEmpty ? 0 : markerLength(ns.substring(with: range))
            let content = NSRange(location: range.location + mark, length: range.length - mark)
            if kind == .body, lists.isEmpty, content.length > 0, let font = text.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont,
               font.fontDescriptor.symbolicTraits.contains(.bold), font.pointSize >= 15 {
                kind = .heading(font.pointSize >= 18 ? 1 : 2)
            }
            let pieces = self.runs(in: text, content, kind)
            if pieces.isEmpty { gap(); return }
            if let list = lists.last {
                var number: Int?
                if isOrdered(list) {
                    let shown = ns.substring(with: NSRange(location: range.location, length: mark)).trimmingCharacters(in: .whitespaces)
                    number = Int(shown.prefix(while: \.isNumber)) ?? text.itemNumber(in: list, at: range.location)
                }
                out.append(.item(depth: lists.count - 1, number: number, runs: pieces))
            } else if case .heading(let level) = kind {
                out.append(.heading(level: level, runs: pieces))
            } else {
                out.append(.text(pieces))
            }
        }
        if out.last == .gap { out.removeLast() }
        // An empty line at the end of a code block is a gap after it, which the Markdown adds anyway.
        return out.map { block in
            guard case .code(var code) = block else { return block }
            while code.hasSuffix("\n") { code.removeLast() }
            return .code(code)
        }
    }

    /// The runs of `range` of `text`, in `paragraph`: a new run where the style changes; spaces only inside a run.
    static func runs(in text: NSAttributedString, _ range: NSRange, _ paragraph: Paragraph) -> [Run] {
        var out: [Run] = []
        var space = ""   // the spaces since the last run's text
        let ns = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, piece, _ in
            let style = self.style(attributes, in: paragraph)
            for c in ns.substring(with: piece) {
                if c.isWhitespace {
                    if !out.isEmpty { space.append(c) }
                    continue
                }
                if let last = out.last, last.style == style {
                    out[out.count - 1].text += space + String(c)
                } else {
                    out.append(Run(text: String(c), style: style))
                }
                space = ""
            }
        }
        return out
    }

    /// `text` without its list markers, for speaking and counting.
    static func plainText(_ text: NSAttributedString) -> String {
        let ns = text.string as NSString
        var out = ""
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            var line = ns.substring(with: range)
            let style = enclosing.length > 0 ? text.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle : nil
            if style?.textLists.isEmpty == false { line = (line as NSString).substring(from: markerLength(line)) }
            out += line + ns.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(enclosing) - NSMaxRange(range)))
        }
        return out
    }
}
