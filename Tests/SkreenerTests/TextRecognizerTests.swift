import XCTest
@testable import Skreener

/// Join Lines in Capture Text's scratch pad (#134).
final class ScratchPadJoinTests: XCTestCase {
    func testJoinsLinesWithSingleSpaces() {
        XCTAssertEqual(TextScratchPad.joined("one  \n  two\n\nthree"), "one two three")
    }

    func testMendsWordsHyphenatedAcrossLines() {
        XCTAssertEqual(TextScratchPad.joined("screen-\nshot tool"), "screenshot tool")
        // Not a broken word: a capital after the hyphen, or a dash on its own.
        XCTAssertEqual(TextScratchPad.joined("Jean-\nPaul"), "Jean- Paul")
        XCTAssertEqual(TextScratchPad.joined("wait -\nthen"), "wait - then")
    }

    func testLaterCaptureAtTheEndGoesOnANewLine() {
        XCTAssertEqual(TextScratchPad.lineInsertion("two", into: "one", replacing: NSRange(location: 3, length: 0)), "\ntwo")
        XCTAssertEqual(TextScratchPad.lineInsertion("two", into: "one\n", replacing: NSRange(location: 4, length: 0)), "two")
    }

    func testLaterCaptureMidLineGetsItsOwnLine() {
        XCTAssertEqual(TextScratchPad.lineInsertion("new", into: "ab", replacing: NSRange(location: 1, length: 0)), "\nnew\n")
    }

    func testLaterCaptureAtALineStartPushesTheLineDown() {
        XCTAssertEqual(TextScratchPad.lineInsertion("new", into: "one\ntwo", replacing: NSRange(location: 4, length: 0)), "new\n")
        XCTAssertEqual(TextScratchPad.lineInsertion("new", into: "one", replacing: NSRange(location: 0, length: 0)), "new\n")
    }

    func testLaterCaptureReplacesTheSelectedLine() {
        XCTAssertEqual(TextScratchPad.lineInsertion("new", into: "one\ntwo\nthree", replacing: NSRange(location: 4, length: 3)), "new")
    }
}
