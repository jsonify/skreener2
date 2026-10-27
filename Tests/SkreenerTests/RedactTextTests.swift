import XCTest
@testable import Skreener

/// The Redact Text tool's matches, highlights, count and redaction (#295); OCR itself is in TextRecognizerTests.
final class RedactTextTests: XCTestCase {
    private let a = CGRect(x: 10, y: 10, width: 50, height: 20)
    private let b = CGRect(x: 10, y: 40, width: 30, height: 20)
    private let c = CGRect(x: 80, y: 40, width: 30, height: 20)

    func testMatchBoxesArePaddedAndSkipSpansWithoutABox() {
        let first = "Jane Smith", second = "lives here"
        let match = TextMatcher.Match(term: 0, spans: [
            .init(line: 0, range: first.startIndex..<first.endIndex), .init(line: 1, range: second.startIndex..<second.endIndex),
        ])
        let boxes = RedactText.boxes(for: match) { span in span.line == 0 ? self.a : nil }
        XCTAssertEqual(boxes, [a.insetBy(dx: -3, dy: -2)])
    }

    func testNewMatchesStartSelected() {
        let hits = RedactText.hits([[a], [b, c]], keeping: [])
        XCTAssertEqual(hits, [.init(boxes: [a]), .init(boxes: [b, c])])
        XCTAssertTrue(hits.allSatisfy(\.selected))
    }

    func testRecomputingKeepsDeselectionsOfUnchangedMatches() {
        let old = [RedactText.Hit(boxes: [a], selected: false), RedactText.Hit(boxes: [b])]
        let hits = RedactText.hits([[a], [b], [c]], keeping: old)
        XCTAssertEqual(hits.map(\.selected), [false, true, true])
        // A match that moved is new, so it is selected.
        let moved = RedactText.hits([[a.offsetBy(dx: 5, dy: 0)]], keeping: old)
        XCTAssertEqual(moved.map(\.selected), [true])
        // Matches with no box at all are dropped.
        XCTAssertEqual(RedactText.hits([[], [b]], keeping: []).count, 1)
    }

    func testClickTogglesAllBoxesOfOneMatch() {
        let hits = [RedactText.Hit(boxes: [a]), RedactText.Hit(boxes: [b, c])]
        let toggled = RedactText.toggling(hits, at: CGPoint(x: 90, y: 50))
        XCTAssertEqual(toggled?.map(\.selected), [true, false])
        XCTAssertEqual(RedactText.toggling(toggled ?? [], at: CGPoint(x: 20, y: 50))?.map(\.selected), [true, true])
        XCTAssertNil(RedactText.toggling(hits, at: CGPoint(x: 300, y: 300)))
    }

    func testCountText() {
        let hit = RedactText.Hit(boxes: [a]), off = RedactText.Hit(boxes: [b], selected: false)
        XCTAssertEqual(RedactText.status([], reading: true, invalidPattern: false, searching: true), "Reading text…")
        XCTAssertEqual(RedactText.status([], reading: false, invalidPattern: true, searching: true), "Invalid pattern")
        XCTAssertEqual(RedactText.status([], reading: false, invalidPattern: false, searching: false), "")
        XCTAssertEqual(RedactText.status([], reading: false, invalidPattern: false, searching: true), "No matches")
        XCTAssertEqual(RedactText.status([hit], reading: false, invalidPattern: false, searching: true), "1 match · 1 selected")
        let twelve = Array(repeating: hit, count: 10) + [off, off]
        XCTAssertEqual(RedactText.status(twelve, reading: false, invalidPattern: false, searching: true),
                       "12 matches · 10 selected")
    }

    func testInvalidPatternOnlyCountsInRegexMode() {
        var o = TextMatcher.Options()
        XCTAssertFalse(RedactText.hasInvalidPattern(["("], options: o))
        o.regex = true
        XCTAssertTrue(RedactText.hasInvalidPattern(["ok", "("], options: o))
        XCTAssertFalse(RedactText.hasInvalidPattern(["\\d+", "  "], options: o))
    }

    func testSolidIsAnOpaqueBlackSquareBox() {
        var style = Style()
        style.color = .systemRed
        style.cornerRadius = 8
        style.textOnly = true
        let added = RedactText.annotations([a, b], cover: .solid, style: style)
        XCTAssertEqual(added.count, 2)
        for x in added {
            XCTAssertEqual(x.tool, .filledRect)
            XCTAssertEqual(x.style.color, .black)
            XCTAssertEqual(x.style.cornerRadius, 0)
            XCTAssertFalse(x.style.textOnly)
        }
        XCTAssertEqual(added[0].start, a.origin)
        XCTAssertEqual(added[0].end, NSPoint(x: a.maxX, y: a.maxY))
        XCTAssertNotEqual(added[0].id, added[1].id)
    }

    func testOtherCovers() {
        var style = Style()
        style.pixelSize = 4
        XCTAssertEqual(RedactText.annotations([a], cover: .pixelate, style: style).first?.style.pixelSize, 8)
        XCTAssertEqual(RedactText.annotations([a], cover: .pixelate, style: style).first?.tool, .pixelate)
        XCTAssertEqual(RedactText.annotations([a], cover: .blur, style: style).first?.tool, .blur)
        XCTAssertEqual(RedactText.annotations([a], cover: .erase, style: style).first?.tool, .erase)
        XCTAssertEqual(RedactText.Cover.allCases.map(\.title), ["Solid", "Pixelate", "Blur", "Erase"])
    }

    /// Added last, so stored tool numbers keep their meaning; no single-key shortcut.
    func testRedactTextIsLastAndHasNoShortcut() {
        XCTAssertEqual(Tool.allCases.last, .redactText)
        XCTAssertEqual(Tool.redactText.rawValue, Tool.ruler.rawValue + 1)
        XCTAssertFalse(Tool.shortcuts.values.contains(.redactText))
        XCTAssertEqual(Tool.redactText.name, "Redact Text")
    }
}
