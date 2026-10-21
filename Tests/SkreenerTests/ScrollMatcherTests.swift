import XCTest
@testable import Skreener

/// Scrolling-capture matching on made-up frames: every row of a "page" has its own pattern, like lines of text.
final class ScrollMatcherTests: XCTestCase {
    private let height = 200

    /// `rows` rows of `ScrollRows.bins` mid-range gray values (pseudo-random, the same for the same seed).
    private func page(rows: Int, seed: UInt32 = 1) -> [[UInt8]] {
        var state = seed
        return (0..<rows).map { _ in
            (0..<ScrollRows.bins).map { _ in
                state = state &* 1_664_525 &+ 1_013_904_223
                return UInt8(64 + (state >> 24) / 2)
            }
        }
    }

    private func frame(_ rows: ArraySlice<[UInt8]>) -> ScrollRows {
        ScrollRows(gray: rows.flatMap { $0 })
    }

    /// The frame showing `rows[top..<top + height]`.
    private func frame(_ rows: [[UInt8]], top: Int) -> ScrollRows {
        frame(rows[top..<(top + height)])
    }

    func testSameFrameIsUnchanged() {
        let f = frame(page(rows: height), top: 0)
        XCTAssertEqual(ScrollMatcher.match(f, f), .unchanged)
    }

    func testScrollDown() {
        let p = page(rows: 400)
        XCTAssertEqual(ScrollMatcher.match(frame(p, top: 0), frame(p, top: 37)), .moved(shift: 37, header: 0, footer: 0))
    }

    func testScrollBackUp() {
        let p = page(rows: 400)
        XCTAssertEqual(ScrollMatcher.match(frame(p, top: 30), frame(p, top: 0)), .moved(shift: -30, header: 0, footer: 0))
    }

    func testHintGivesTheSameAnswer() {
        let p = page(rows: 400)
        XCTAssertEqual(ScrollMatcher.match(frame(p, top: 0), frame(p, top: 50), hint: 50),
                       .moved(shift: 50, header: 0, footer: 0))
    }

    func testStickyHeaderStaysPut() {
        let header = page(rows: 20, seed: 7), content = page(rows: 400)
        let prev = frame(ArraySlice(header + content[20..<height]))
        let new = frame(ArraySlice(header + content[(20 + 40)..<(height + 40)]))
        guard case let .moved(shift, top, bottom) = ScrollMatcher.match(prev, new) else {
            return XCTFail("expected a move, got \(ScrollMatcher.match(prev, new))")
        }
        XCTAssertEqual(shift, 40)
        XCTAssertTrue((20...21).contains(top), "header \(top)")
        XCTAssertEqual(bottom, 0)
    }

    func testUnrelatedContentIsLost() {
        let a = frame(page(rows: height, seed: 1), top: 0), b = frame(page(rows: height, seed: 2), top: 0)
        XCTAssertEqual(ScrollMatcher.match(a, b), .lost)
    }
}
