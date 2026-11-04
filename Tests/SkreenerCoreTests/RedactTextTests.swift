import CoreGraphics
import XCTest
@testable import SkreenerCore

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

    func testCoverTitles() {
        XCTAssertEqual(RedactText.Cover.allCases.map(\.title), ["Solid", "Pixelate", "Blur", "Erase"])
    }
}
