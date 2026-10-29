import AppKit
import XCTest
@testable import Skreener

/// The scratch pad's rich text (#326): blocks to an attributed string and back, italic in the Markdown, Join Lines.
final class RichPadTests: XCTestCase {
    private typealias F = FormattedText

    private func run(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, color: F.RGB? = nil) -> F.Run {
        F.Run(text: text, style: F.Style(bold: bold, italic: italic, code: code, color: color))
    }

    private let red = F.RGB(r: 0.8, g: 0.1, b: 0.1)
    private let blue = F.RGB(r: 0.1, g: 0.3, b: 0.9)

    private func roundTrip(_ blocks: [F.Block], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(F.blocks(from: F.attributed(blocks)), blocks, file: file, line: line)
    }

    func testHeadingsAndText() {
        roundTrip([
            .heading(level: 1, runs: [run("Release notes")]),
            .heading(level: 2, runs: [run("What's"), run("new", italic: true), run("today", code: true), run("now", color: red)]),
            .text([run("Plain words")]),
        ])
    }

    func testInlineStyles() {
        roundTrip([
            .text([run("Plain"), run("bold words", bold: true), run("and"), run("italic", italic: true),
                   run("both", bold: true, italic: true), run("code()", code: true), run("bold code", bold: true, code: true),
                   run("red", color: red), run("blue bold", bold: true, color: blue), run("end")]),
        ])
    }

    func testMixedListsThreeDeep() {
        roundTrip([
            .item(depth: 0, number: nil, runs: [run("one")]),
            .item(depth: 1, number: 3, runs: [run("three"), run("bold", bold: true)]),
            .item(depth: 1, number: 4, runs: [run("four")]),
            .item(depth: 2, number: nil, runs: [run("deep", color: blue)]),
            .item(depth: 2, number: nil, runs: [run("deeper", code: true)]),
            .item(depth: 1, number: 5, runs: [run("five")]),
            .item(depth: 0, number: nil, runs: [run("two")]),
            .gap,
            .item(depth: 0, number: 1, runs: [run("first")]),
            .item(depth: 0, number: 2, runs: [run("second")]),
            .text([run("After the list")]),
        ])
    }

    func testCodeBlocksAndGaps() {
        roundTrip([
            .text([run("Before")]),
            .code("let a = 1\n\n    return a"),
            .gap,
            .code("second()"),
            .text([run("After")]),
            .gap,
            .text([run("Last")]),
        ])
    }

    func testListMarkersFollowAppKit() {
        let text = F.attributed([.item(depth: 0, number: nil, runs: [run("a")]), .item(depth: 1, number: 3, runs: [run("b")])])
        XCTAssertEqual(text.string, "\t•\ta\n\t3.\tb")
        let style = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.textLists.count, 2)
        XCTAssertEqual(style?.textLists.last?.startingItemNumber, 3)
        XCTAssertEqual(F.plainText(text), "a\nb")
    }

    func testEmptyParagraphsAreOneGap() {
        let text = NSMutableAttributedString(attributedString: F.attributed([.text([run("a")]), .gap, .gap, .text([run("b")])]))
        text.append(NSAttributedString(string: "\n\n"))
        XCTAssertEqual(F.blocks(from: text), [.text([run("a")]), .gap, .text([run("b")])])
    }

    func testDefaultColorIsNone() {
        let text = NSAttributedString(string: "plain", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
        XCTAssertEqual(F.blocks(from: text), [.text([run("plain")])])
    }

    func testFormatKeepsBlocks() {
        XCTAssertEqual(F.format([]).blocks, [])
        XCTAssertEqual(F.markdown([.text([run("a", italic: true), run("b", bold: true, italic: true)])]), "*a* ***b***")
    }

    func testItalicMarkdown() {
        XCTAssertEqual(F.segments("*a* ***b*** 2 * 3"), [
            F.Segment(text: "a", italic: true), F.Segment(text: " "), F.Segment(text: "b", bold: true, italic: true),
            F.Segment(text: " 2 * 3"),
        ])
        XCTAssertEqual(F.segments("*open"), [F.Segment(text: "*"), F.Segment(text: "open")])
        XCTAssertEqual(F.html(markdown: "*a* ***b***", colors: []), "<p><i>a</i> <b><i>b</i></b></p>")
        XCTAssertEqual(F.plain(markdown: "- *a* **b**"), "• a b")
    }

    func testJoinedKeepsStylesAndFirstMarker() {
        let text = F.attributed([
            .item(depth: 0, number: nil, runs: [run("screen-", bold: true)]),
            .item(depth: 0, number: nil, runs: [run("shot", bold: true), run("tool")]),
        ])
        let joined = TextScratchPad.joined(text)
        XCTAssertEqual(joined.string, "\t•\tscreenshot tool")
        XCTAssertEqual(F.blocks(from: joined), [.item(depth: 0, number: nil, runs: [run("screenshot", bold: true), run("tool")])])
    }
}
