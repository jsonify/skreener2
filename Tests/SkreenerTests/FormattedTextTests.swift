import XCTest
@testable import Skreener

/// Capture Text with formatting: lists, headings, styles, Markdown and HTML on made-up OCR lines and bitmaps.
final class FormattedTextTests: XCTestCase {
    private typealias F = FormattedText
    private let cw: CGFloat = 10      // character width of the made-up text
    private let pitch: CGFloat = 28
    private let height: CGFloat = 20

    /// A line `row` rows from the top (bottom-left origin) starting at `x`, its words laid out 10 points a character.
    private func line(_ text: String, row: CGFloat, x: CGFloat = 100, height: CGFloat? = nil,
                      looks: [Int: F.Look] = [:], bullet: Bool = false) -> F.Line {
        let h = height ?? self.height
        var words: [F.Word] = []
        var cursor = x
        for (i, word) in text.split(separator: " ").enumerated() {
            let w = CGFloat(word.count) * cw
            words.append(F.Word(text: String(word), rect: CGRect(x: cursor, y: 800 - row * pitch, width: w, height: h),
                                look: looks[i] ?? F.Look()))
            cursor += w + cw
        }
        return F.Line(rect: CGRect(x: x, y: 800 - row * pitch, width: cursor - cw - x, height: h), words: words, bullet: bullet)
    }

    private func markdown(_ lines: [F.Line]) -> String { F.format(lines).text }

    // MARK: Lists

    func testEmptyInput() {
        XCTAssertEqual(F.format([]), F.Result())
    }

    func testPlainLinesStayAsTheyAre() {
        XCTAssertEqual(markdown([line("Hello there", row: 0), line("second line", row: 1)]), "Hello there\nsecond line")
    }

    func testBulletsBecomeDashes() {
        let lines = [line("• Apples", row: 0), line("•Bread", row: 1), line("- Milk", row: 2), line("* Eggs", row: 3)]
        XCTAssertEqual(markdown(lines), "- Apples\n- Bread\n- Milk\n- Eggs")
    }

    func testNumberedItemsKeepTheirNumbers() {
        XCTAssertEqual(markdown([line("1. Mix", row: 0), line("2) Bake", row: 1)]), "1. Mix\n2. Bake")
        XCTAssertEqual(markdown([line("3. Rest", row: 0)]), "3. Rest")
    }

    func testIndentedItemsNest() {
        let lines = [
            line("• Fruit", row: 0),
            line("◦ Apples", row: 1, x: 130),
            line("◦ Pears", row: 2, x: 131),
            line("• Bread", row: 3),
        ]
        XCTAssertEqual(markdown(lines), "- Fruit\n  - Apples\n  - Pears\n- Bread")
    }

    func testNestedUnderANumberLinesUpWithItsText() {
        let lines = [line("1. Mix", row: 0), line("- flour", row: 1, x: 130), line("2. Bake", row: 2)]
        XCTAssertEqual(markdown(lines), "1. Mix\n   - flour\n2. Bake")
    }

    func testHollowBulletReadAsOCountsOnlyWhenNested() {
        XCTAssertEqual(markdown([line("• Fruit", row: 0), line("o Apples", row: 1, x: 130)]), "- Fruit\n  - Apples")
        XCTAssertEqual(markdown([line("o Apples", row: 0)]), "o Apples")
    }

    func testWrappedItemLineJoinsItsItem() {
        let lines = [line("• A long item that", row: 0), line("wraps here", row: 1, x: 120), line("• Next", row: 2)]
        XCTAssertEqual(markdown(lines), "- A long item that wraps here\n- Next")
    }

    func testTextAfterAListStandsApart() {
        XCTAssertEqual(markdown([line("• one", row: 0), line("Plain after", row: 1)]), "- one\n\nPlain after")
        XCTAssertEqual(markdown([line("Before", row: 0), line("• one", row: 1)]), "Before\n\n- one")
    }

    func testDashesAndAsterisksTouchingAWordAreText() {
        XCTAssertEqual(markdown([line("-5 degrees", row: 0), line("*args too", row: 1)]), "-5 degrees\n\\*args too")
        XCTAssertEqual(markdown([line("1.5 million", row: 0)]), "1.5 million")
    }

    func testStrayBulletJoinsTheLineBesideIt() {
        let bullet = F.Line(rect: CGRect(x: 100, y: 805, width: 8, height: 8),
                            words: [F.Word(text: "•", rect: CGRect(x: 100, y: 805, width: 8, height: 8))])
        XCTAssertEqual(markdown([line("Item", row: 0, x: 130), bullet]), "- Item")
    }

    func testBulletSeenInThePixelsMakesAnItem() {
        XCTAssertEqual(markdown([line("Item", row: 0, bullet: true), line("Other", row: 1, bullet: true)]), "- Item\n- Other")
    }

    // MARK: Headings and paragraphs

    func testTallLinesAreHeadings() {
        let lines = [
            line("Title", row: 0, height: 40),
            line("Body one", row: 2),
            line("Section", row: 3, height: 28),
            line("Body two", row: 4),
            line("Body three", row: 5),
        ]
        XCTAssertEqual(markdown(lines), "# Title\n\nBody one\n\n## Section\n\nBody two\nBody three")
    }

    func testAWideGapStartsAParagraph() {
        let lines = [line("one", row: 0), line("two", row: 1), line("three", row: 2), line("four", row: 4)]
        XCTAssertEqual(markdown(lines), "one\ntwo\nthree\n\nfour")
    }

    func testLeadingHashIsEscaped() {
        XCTAssertEqual(markdown([line("#hashtag here", row: 0)]), "\\#hashtag here")
    }

    // MARK: Styles

    private let white = F.RGB(r: 1, g: 1, b: 1)
    private let black = F.RGB(r: 0, g: 0, b: 0)
    private func plain(_ stroke: Double = 0.1) -> F.Look { F.Look(stroke: stroke, ink: black, background: white) }

    func testThickStrokesAreBold() {
        let looks = [0: plain(), 1: plain(), 2: plain(0.16), 3: plain(0.15), 4: plain(), 5: plain(), 6: plain()]
        let text = markdown([line("Make it really very clear for everyone", row: 0, looks: looks)])
        XCTAssertEqual(text, "Make it **really very** clear for everyone")
    }

    func testShortWordBetweenBoldWordsStaysInTheRun() {
        let looks = [0: plain(), 1: plain(), 2: plain(0.16), 3: plain(0.3), 4: plain(0.16), 5: plain(), 6: plain()]
        XCTAssertEqual(markdown([line("Keep this salt & pepper in mind", row: 0, looks: looks)]),
                       "Keep this **salt & pepper** in mind")
    }

    func testTooFewWordsToJudgeBold() {
        XCTAssertEqual(markdown([line("Bold maybe", row: 0, looks: [0: plain(0.3), 1: plain()])]), "Bold maybe")
    }

    func testWordsOnAShadedChipAreCode() {
        let chip = F.Look(stroke: 0.1, ink: black, background: F.RGB(r: 0.92, g: 0.92, b: 0.93))
        let looks = [0: plain(), 1: chip, 2: chip, 3: plain(), 4: plain()]
        XCTAssertEqual(markdown([line("Run npm test before pushing", row: 0, looks: looks)]), "Run `npm test` before pushing")
    }

    func testCodeLinesInARowAreACodeBlock() {
        let chip = F.Look(stroke: 0.1, ink: black, background: F.RGB(r: 0.9, g: 0.9, b: 0.9))
        let lines = [
            line("Install it:", row: 0, looks: [0: plain(), 1: plain()]),
            line("brew install x", row: 1, looks: [0: chip, 1: chip, 2: chip]),
            line("x --help", row: 2, looks: [0: chip, 1: chip]),
            line("Then run it right away.", row: 3, looks: [0: plain(), 1: plain(), 2: plain(), 3: plain(), 4: plain()]),
        ]
        XCTAssertEqual(markdown(lines), "Install it:\n\n```\nbrew install x\nx --help\n```\n\nThen run it right away.")
    }

    func testColoredWordsTravelBesideTheMarkdown() {
        let red = F.Look(stroke: 0.1, ink: F.RGB(r: 0.86, g: 0.12, b: 0.12), background: white)
        let red2 = F.Look(stroke: 0.1, ink: F.RGB(r: 0.9, g: 0.15, b: 0.1), background: white)
        let grey = F.Look(stroke: 0.1, ink: F.RGB(r: 0.5, g: 0.5, b: 0.5), background: white)
        let result = F.format([line("This is very urgent for today", row: 0,
                                    looks: [0: plain(), 1: grey, 2: red, 3: red2, 4: plain(), 5: plain()])])
        XCTAssertEqual(result.text, "This is very urgent for today")
        XCTAssertEqual(result.colors, [F.Painted(text: "very urgent", hex: "#db1f1f")])
    }

    // MARK: Markdown pieces

    func testCodeSpanFencesBackticks() {
        XCTAssertEqual(F.codeSpan("a`b"), "``a`b``")
        XCTAssertEqual(F.codeSpan("`x"), "`` `x ``")
        XCTAssertEqual(F.inline([F.Run(text: "go", style: F.Style(bold: true, code: true))]), "**`go`**")
    }

    func testMarkers() {
        XCTAssertEqual(F.marker("12. Twelve"), F.Marker(number: 12, length: 4))
        XCTAssertEqual(F.marker("•x"), F.Marker(number: nil, length: 1))
        XCTAssertNil(F.marker("2024. A year"))
        XCTAssertNil(F.marker("—"))
    }

    // MARK: HTML

    func testHTMLForListsHeadingsAndParagraphs() {
        let md = "# Title\n\n- one\n  - inner\n- two\n\n3. three\n4. four\n\nPlain **bold** and `code`\nnext line"
        XCTAssertEqual(F.html(markdown: md, colors: []),
                       "<h1>Title</h1><ul><li>one<ul><li>inner</li></ul></li><li>two</li></ul>"
                       + "<ol start=\"3\"><li>three</li><li>four</li></ol>"
                       + "<p>Plain <b>bold</b> and <code>code</code><br>next line</p>")
    }

    func testHTMLSwitchesListKindAtTheSameDepth() {
        XCTAssertEqual(F.html(markdown: "- a\n1. b", colors: []), "<ul><li>a</li></ul><ol><li>b</li></ol>")
    }

    func testHTMLCodeBlockAndEscapes() {
        XCTAssertEqual(F.html(markdown: "```\nif a < b {\n```\n\\*not bold\\* & <tag>", colors: []),
                       "<pre><code>if a &lt; b {</code></pre><p>*not bold* &amp; &lt;tag&gt;</p>")
    }

    func testHTMLPaintsEachColoredPhraseOnceAsWholeWords() {
        let colors = [F.Painted(text: "red", hex: "#ff0000")]
        XCTAssertEqual(F.html(markdown: "bored red red", colors: colors),
                       "<p>bored <span style=\"color:#ff0000\">red</span> red</p>")
        XCTAssertEqual(F.html(markdown: "**red**", colors: colors), "<p><b><span style=\"color:#ff0000\">red</span></b></p>")
    }

    func testSegments() {
        XCTAssertEqual(F.segments("a **b** ``c`d`` \\*e"), [
            F.Segment(text: "a "), F.Segment(text: "b", bold: true), F.Segment(text: " "),
            F.Segment(text: "c`d", code: true), F.Segment(text: " *e"),
        ])
        XCTAssertEqual(F.segments("2 ** 3"), [F.Segment(text: "2 "), F.Segment(text: "**"), F.Segment(text: " 3")])
        XCTAssertEqual(F.segments("a ` b"), [F.Segment(text: "a ` b")])
    }

    // MARK: Pixels

    private typealias Paint = (rect: CGRect, color: (UInt8, UInt8, UInt8))

    /// A white `width` × `height` bitmap with `fills` painted in order (rects in pixels, bottom-left origin).
    private func bitmap(_ width: Int, _ height: Int, _ fills: [Paint]) -> F.Bitmap {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for fill in fills {
            for y in Int(fill.rect.minY)..<Int(fill.rect.maxY) {
                for x in Int(fill.rect.minX)..<Int(fill.rect.maxX) {
                    let i = ((height - 1 - y) * width + x) * 4
                    (bytes[i], bytes[i + 1], bytes[i + 2]) = fill.color
                }
            }
        }
        return F.Bitmap(width: width, height: height, bytes: bytes)
    }

    /// Vertical bars `barWidth` wide, every 10 pixels across the word box x 20–120, y 20–40.
    private func bars(_ barWidth: Int, _ color: (UInt8, UInt8, UInt8) = (0, 0, 0)) -> [Paint] {
        stride(from: 22, to: 118, by: 10).map { (CGRect(x: $0, y: 20, width: barWidth, height: 20), color) }
    }

    private let word = CGRect(x: 20, y: 20, width: 100, height: 20)

    func testStrokeWidthOverLineHeight() throws {
        let thin = bitmap(200, 60, bars(2)).look(word, lineHeight: 20)
        let thick = bitmap(200, 60, bars(4)).look(word, lineHeight: 20)
        XCTAssertEqual(try XCTUnwrap(thin.stroke), 0.1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(thick.stroke), 0.2, accuracy: 0.01)
        XCTAssertEqual(thin.background, white)
        XCTAssertEqual(thin.ink, black)
    }

    func testChipBackgroundAndInkColor() throws {
        let chip: Paint = (CGRect(x: 14, y: 14, width: 112, height: 32), (230, 230, 230))
        let look = bitmap(200, 60, [chip] + bars(3, (220, 30, 30))).look(word, lineHeight: 20)
        let bg = try XCTUnwrap(look.background)
        XCTAssertEqual(bg.r, 230.0 / 255, accuracy: 0.001)
        let ink = try XCTUnwrap(look.ink)
        XCTAssertEqual(ink.r, 220.0 / 255, accuracy: 0.001)
        XCTAssertEqual(ink.g, 30.0 / 255, accuracy: 0.001)
    }

    func testUnevenSurroundingsHaveNoBackground() {
        // Half the ring runs through a dark block.
        let block: Paint = (CGRect(x: 0, y: 0, width: 70, height: 60), (40, 40, 40))
        XCTAssertNil(bitmap(200, 60, [block] + bars(2, (255, 0, 0))).look(word, lineHeight: 20).background)
    }

    func testBlankWordHasNoInk() {
        let look = bitmap(200, 60, []).look(word, lineHeight: 20)
        XCTAssertNil(look.stroke)
        XCTAssertNil(look.ink)
        XCTAssertEqual(look.background, white)
    }

    func testBulletLeftOfALine() {
        let line = CGRect(x: 100, y: 20, width: 200, height: 20)
        let dot: Paint = (CGRect(x: 80, y: 27, width: 6, height: 6), (0, 0, 0))
        let dash: Paint = (CGRect(x: 76, y: 29, width: 12, height: 2), (0, 0, 0))
        let touching: Paint = (CGRect(x: 96, y: 27, width: 6, height: 6), (0, 0, 0))
        XCTAssertTrue(bitmap(320, 60, [dot]).hasBullet(leftOf: line))
        XCTAssertFalse(bitmap(320, 60, []).hasBullet(leftOf: line))
        XCTAssertFalse(bitmap(320, 60, [dash]).hasBullet(leftOf: line))
        XCTAssertFalse(bitmap(320, 60, [touching]).hasBullet(leftOf: line))
    }

    // MARK: Vision

    /// Drawn text with a heading, lists, a bold word, a code chip and a red word, read back as Markdown.
    func testReadsFormattingFromAnImage() async {
        let body = NSFont.systemFont(ofSize: 40)
        func plain(_ s: String) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: body, .foregroundColor: NSColor.black])
        }
        func styled(_ s: String, _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: body, .foregroundColor: NSColor.black].merging(attrs) { $1 })
        }
        func join(_ parts: NSAttributedString...) -> NSAttributedString {
            let s = NSMutableAttributedString()
            parts.forEach(s.append)
            return s
        }
        let lines: [NSAttributedString] = [
            NSAttributedString(string: "Shopping list", attributes: [.font: NSFont.boldSystemFont(ofSize: 72)]),
            plain("• Fresh apples"),
            plain("• Brown bread"),
            plain("1. First step"),
            plain("2. Second step"),
            join(plain("Make it "), styled("really", [.font: NSFont.boldSystemFont(ofSize: 40)]), plain(" clear for everyone")),
            join(plain("Run "), styled(" npm test ", [.font: NSFont.monospacedSystemFont(ofSize: 40, weight: .regular),
                                                      .backgroundColor: NSColor(white: 0.88, alpha: 1)]),
                 plain(" before you push")),
            join(plain("This is "), styled("urgent", [.foregroundColor: NSColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1)]),
                 plain(" for today")),
        ]
        let image = TestImages.image(width: 1400, height: 160 + 80 * (lines.count - 1)) { r in
            NSColor.white.setFill()
            r.fill()
            lines[0].draw(at: NSPoint(x: 40, y: r.height - 120))
            for (i, line) in lines.enumerated().dropFirst() {
                line.draw(at: NSPoint(x: 40, y: r.height - 140 - CGFloat(i) * 80))
            }
        }
        let read = await TextRecognizer.formattedLines(image)
        let result = F.format(read)
        // What was measured, for when an assertion fails.
        let md = result.text + "\n---\n" + read.map { line in
            "\(line.rect.integral) " + line.words.map { w in
                "\(w.text)[\(w.rect.integral.minY),\(w.rect.integral.height) s=\(w.look.stroke.map { String(format: "%.3f", $0) } ?? "-")"
                    + " bg=\(w.look.background?.hex ?? "-") ink=\(w.look.ink?.hex ?? "-")]"
            }.joined(separator: " ")
        }.joined(separator: "\n")
        XCTAssertTrue(md.split(separator: "\n").contains { $0.hasPrefix("#") && $0.contains("Shopping list") }, md)
        XCTAssertTrue(md.contains("- Fresh apples\n- Brown bread"), md)
        XCTAssertTrue(md.contains("1. First step\n2. Second step"), md)
        XCTAssertTrue(md.contains("Make it **really** clear for everyone"), md)
        XCTAssertTrue(md.contains("Run `npm test` before you push"), md)
        XCTAssertTrue(md.contains("This is urgent for today"), md)
        XCTAssertEqual(result.colors.map(\.text), ["urgent"], md)
    }
}
