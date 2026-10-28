import XCTest
@testable import Skreener

/// Capture Code's indentation and cleanup (#249), on made-up OCR lines: no screen or Vision needed.
final class CodeTextTests: XCTestCase {
    private let cw: CGFloat = 10   // character width of the made-up monospaced text
    private let pitch: CGFloat = 28
    private let height: CGFloat = 20

    /// A line `row` rows from the top (bottom-left origin), starting `indent` characters in, `x0` points from the edge.
    private func line(_ text: String, row: CGFloat, indent: Int = 0, x0: CGFloat = 100) -> CodeText.Line {
        CodeText.Line(text: text, rect: CGRect(x: x0 + CGFloat(indent) * cw, y: 800 - row * pitch,
                                               width: CGFloat(text.count) * cw, height: height))
    }

    // MARK: Layout

    func testEmptyAndBlankInput() {
        XCTAssertEqual(CodeText.layout([]), "")
        XCTAssertEqual(CodeText.format([line("   ", row: 0)]), "")
        XCTAssertEqual(CodeText.format([line("", row: 0)], fenced: true), "")
    }

    func testSingleLineHasNoIndent() {
        XCTAssertEqual(CodeText.layout([line("let x = 1", row: 0, x0: 240)]), "let x = 1")
    }

    func testOrdersTopToBottomWhateverTheInputOrder() {
        let lines = [line("c", row: 2), line("a", row: 0), line("b", row: 1)]
        XCTAssertEqual(CodeText.layout(lines), "a\nb\nc")
    }

    func testFourSpaceIndentation() {
        let lines = [
            line("func greet(name: String) {", row: 0),
            line("if name.isEmpty {", row: 1, indent: 4),
            line("return", row: 2, indent: 8),
            line("}", row: 3, indent: 4),
            line("}", row: 4),
        ]
        XCTAssertEqual(CodeText.layout(lines), """
        func greet(name: String) {
            if name.isEmpty {
                return
            }
        }
        """)
    }

    func testTwoSpaceIndentation() {
        let lines = [
            line("function f() {", row: 0),
            line("if (ok) {", row: 1, indent: 2),
            line("run();", row: 2, indent: 4),
            line("}", row: 3, indent: 2),
            line("}", row: 4),
        ]
        XCTAssertEqual(CodeText.layout(lines), "function f() {\n  if (ok) {\n    run();\n  }\n}")
    }

    func testIndentIsRelativeToTheLeftmostLine() {
        let lines = [line("if x {", row: 0, x0: 400), line("y()", row: 1, indent: 4, x0: 400)]
        XCTAssertEqual(CodeText.layout(lines), "if x {\n    y()")
    }

    func testCharacterWidthIsAMedianSoOneOddLineDoesNotSkewIt() {
        var lines = (0..<5).map { line("abcdefgh", row: CGFloat($0)) }
        lines.append(CodeText.Line(text: "abcd", rect: CGRect(x: 100, y: 0, width: 400, height: 20)))   // 100 per character
        XCTAssertEqual(CodeText.characterWidth(lines), 10, accuracy: 0.001)
    }

    func testCharacterWidthIgnoresShortLinesWhenLongerOnesExist() {
        let lines = [line("}", row: 0), line("let value = 3", row: 1), line("let other = 4", row: 2)]
        XCTAssertEqual(CodeText.characterWidth(lines), 10, accuracy: 0.001)
    }

    func testCharacterWidthFallsBackToLineHeight() {
        let empty = CodeText.Line(text: "x", rect: CGRect(x: 0, y: 0, width: 0, height: 20))
        XCTAssertEqual(CodeText.characterWidth([empty]), 12, accuracy: 0.001)
    }

    func testSmallMeasuringNoiseDoesNotChangeTheIndent() {
        // Boxes a few points off: still 0 / 4 / 8 characters.
        var lines = [line("if a {", row: 0), line("if b {", row: 1, indent: 4), line("go()", row: 2, indent: 8)]
        lines[1].rect.origin.x += 3
        lines[2].rect.origin.x -= 4
        XCTAssertEqual(CodeText.layout(lines), "if a {\n    if b {\n        go()")
    }

    func testBlankLineKeptWhereTheGapIsLarge() {
        let lines = [line("import Foundation", row: 0), line("let a = 1", row: 2), line("let b = 2", row: 3)]
        XCTAssertEqual(CodeText.layout(lines), "import Foundation\n\nlet a = 1\nlet b = 2")
    }

    func testNormalLineSpacingAddsNoBlankLines() {
        let lines = (0..<4).map { line("statement;", row: CGFloat($0)) }
        XCTAssertEqual(CodeText.layout(lines), "statement;\nstatement;\nstatement;\nstatement;")
    }

    func testSeveralMissingRowsCollapseToOneBlankLine() {
        let lines = [line("a = 1", row: 0), line("b = 2", row: 1), line("c = 3", row: 4)]
        XCTAssertEqual(CodeText.layout(lines), "a = 1\nb = 2\n\nc = 3")
    }

    func testTwoLinesOnlyUseTypicalPitch() {
        XCTAssertEqual(CodeText.layout([line("a = 1", row: 0), line("b = 2", row: 1)]), "a = 1\nb = 2")
        XCTAssertEqual(CodeText.layout([line("a = 1", row: 0), line("b = 2", row: 2)]), "a = 1\n\nb = 2")
    }

    func testPartsOfOneRowAreJoinedWithTheirGap() {
        let left = line("let x", row: 0)
        let right = CodeText.Line(text: "= 5", rect: CGRect(x: 100 + 7 * cw, y: left.rect.minY + 1, width: 30, height: height))
        let next = line("print(x)", row: 1)
        XCTAssertEqual(CodeText.layout([right, next, left]), "let x  = 5\nprint(x)")
    }

    // MARK: Snapping

    func testSnapToFour() {
        XCTAssertEqual(CodeText.snapIndents([0, 4, 8, 5, 3, 0]), [0, 4, 8, 4, 4, 0])
    }

    func testSnapToTwo() {
        XCTAssertEqual(CodeText.snapIndents([0, 2, 4, 6, 4, 2, 0, 2, 4, 6, 8]), [0, 2, 4, 6, 4, 2, 0, 2, 4, 6, 8])
        XCTAssertEqual(CodeText.snapIndents([0, 2, 4, 2, 4, 2, 4, 2, 4, 3]), [0, 2, 4, 2, 4, 2, 4, 2, 4, 2])
    }

    func testOddIndentsThatFitNoUnitStayAsMeasured() {
        XCTAssertEqual(CodeText.snapIndents([0, 3, 6, 3]), [0, 3, 6, 3])
    }

    func testOneCharacterIndentIsNotSnappedToFour() {
        XCTAssertEqual(CodeText.snapIndents([0, 1, 0]), [0, 1, 0])
    }

    func testNoIndentation() {
        XCTAssertEqual(CodeText.snapIndents([0, 0, 0]), [0, 0, 0])
        XCTAssertEqual(CodeText.snapIndents([]), [])
    }

    // MARK: Cleanup rules

    func testStraightensCurlyQuotes() {
        XCTAssertEqual(CodeText.straightenQuotes("print(\u{201C}hi\u{201D}) // it\u{2019}s"), "print(\"hi\") // it's")
        XCTAssertEqual(CodeText.straightenQuotes("\u{2018}a\u{2019}"), "'a'")
        XCTAssertEqual(CodeText.straightenQuotes("plain \"x\" 'y'"), "plain \"x\" 'y'")
    }

    func testNonBreakingSpaceAndEllipsis() {
        XCTAssertEqual(CodeText.plainSpacesAndDots("a\u{00A0}b"), "a b")
        XCTAssertEqual(CodeText.plainSpacesAndDots("[1, 2\u{2026}]"), "[1, 2...]")
    }

    func testLettersInsideNumbersBecomeDigits() {
        XCTAssertEqual(CodeText.fixDigits("let n = 1O0"), "let n = 100")
        XCTAssertEqual(CodeText.fixDigits("x = l00 + 2O0"), "x = 100 + 200")
        XCTAssertEqual(CodeText.fixDigits("port: 80O0,"), "port: 8000,")
        XCTAssertEqual(CodeText.fixDigits("rate = 1.5O"), "rate = 1.50")
        XCTAssertEqual(CodeText.fixDigits("[10l, 22I]"), "[101, 221]")
    }

    func testDigitFixLeavesWordsAndIdentifiersAlone() {
        for s in ["let l0 = 1", "Ol", "hello", "lol", "var x1O = 2", "a.l00", "foo_1O0", "I0", "color", "O0"] {
            XCTAssertEqual(CodeText.fixDigits(s), s, s)
        }
    }

    func testDigitFixNeedsMoreDigitsThanLetters() {
        XCTAssertEqual(CodeText.fixDigits("lO1"), "lO1")   // two letters, one digit
        XCTAssertEqual(CodeText.fixDigits("10"), "10")
    }

    func testDigitFixLeavesHexAndSuffixedNumbersAlone() {
        XCTAssertEqual(CodeText.fixDigits("0x1O"), "0x1O")
        XCTAssertEqual(CodeText.fixDigits("10px"), "10px")
    }

    func testCleanupKeepsIndentAndTrimsTrailingSpace() {
        XCTAssertEqual(CodeText.cleanup("    let s = \u{201C}a\u{201D}   "), "    let s = \"a\"")
        XCTAssertEqual(CodeText.cleanup(""), "")
    }

    // MARK: Format and Markdown

    func testFormatPlain() {
        let lines = [line("if x == \u{201C}1O0\u{201D} {", row: 0), line("run()", row: 1, indent: 4), line("}", row: 2)]
        XCTAssertEqual(CodeText.format(lines), "if x == \"100\" {\n    run()\n}")
    }

    func testFormatFenced() {
        let lines = [line("if x {", row: 0), line("run()", row: 1, indent: 4), line("}", row: 2)]
        XCTAssertEqual(CodeText.format(lines, fenced: true), "```\nif x {\n    run()\n}\n```")
    }

    func testFenceGrowsPastBackticksInTheCode() {
        XCTAssertEqual(CodeText.fence("a"), "```\na\n```")
        XCTAssertEqual(CodeText.fence("x ``` y"), "````\nx ``` y\n````")
        XCTAssertEqual(CodeText.fence("`one`"), "```\n`one`\n```")
    }

    func testBlankLinesSurviveFormatting() {
        let lines = [line("a = 1", row: 0), line("b = 2", row: 1), line("c = 3", row: 3)]
        XCTAssertEqual(CodeText.format(lines), "a = 1\nb = 2\n\nc = 3")
    }
}
