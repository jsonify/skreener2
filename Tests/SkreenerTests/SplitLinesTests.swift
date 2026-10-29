import XCTest
@testable import Skreener

/// The scratch pad's Split into Lines (#334): which parts of the text become a selection each.
final class SplitLinesTests: XCTestCase {
    private func lines(_ text: String, _ selection: NSRange = NSRange(location: 0, length: 0), markers: Bool = true) -> [String] {
        let ns = text as NSString
        return TextScratchPad.lineRanges(in: text, selection: selection, listMarkers: markers).map { ns.substring(with: $0) }
    }

    func testPlainLines() {
        XCTAssertEqual(lines("one\ntwo\nthree"), ["one", "two", "three"])
        XCTAssertEqual(lines("one\ntwo\n"), ["one", "two"])
    }

    func testListMarkersAreLeftOut() {
        XCTAssertEqual(lines("\t•\tapple\n\t•\tpear\n\t10.\tplum"), ["apple", "pear", "plum"])
        XCTAssertEqual(lines("Fruit\n\t1.\tapple"), ["Fruit", "apple"])
        // The plain pad has no markers: a tab in the text stays.
        XCTAssertEqual(lines("a\tb\tc", markers: false), ["a\tb\tc"])
    }

    func testEmptyAndBlankLinesAreSkipped() {
        XCTAssertEqual(lines("one\n\n   \n\ttwo  \n\n"), ["one", "two"])
        XCTAssertEqual(lines("\t•\t\n\t•\tfull"), ["full"])
        XCTAssertEqual(lines(""), [])
    }

    func testSelectionStartingAndEndingMidLine() {
        let text = "alpha beta\ngamma delta\nepsilon zeta"
        // From "beta" to "delta".
        XCTAssertEqual(lines(text, NSRange(location: 6, length: 4 + 1 + 11)), ["beta", "gamma delta"])
        // From "gamma" to "eps".
        XCTAssertEqual(lines(text, NSRange(location: 11, length: 11 + 1 + 3)), ["gamma delta", "eps"])
        // Inside one line.
        XCTAssertEqual(lines(text, NSRange(location: 1, length: 3)), ["lph"])
    }

    func testSelectionInsideAMarkerStartsAfterIt() {
        XCTAssertEqual(lines("\t•\tapple\n\t•\tpear", NSRange(location: 1, length: 15)), ["apple", "pear"])
    }

    func testCRLFAndOtherLineBreaks() {
        XCTAssertEqual(lines("one\r\ntwo\r\nthree"), ["one", "two", "three"])
        XCTAssertEqual(lines("one\rtwo"), ["one", "two"])
        XCTAssertEqual(lines("one\u{2028}two\u{2029}three"), ["one", "two", "three"])
    }

    func testEmptySelectionMeansAllText() {
        XCTAssertEqual(lines("a\nb\nc", NSRange(location: 2, length: 0)), ["a", "b", "c"])
    }

    func testSingleLine() {
        XCTAssertEqual(lines("  just one line  "), ["just one line"])
        let ranges = TextScratchPad.lineRanges(in: "  just one line  ", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(ranges, [NSRange(location: 2, length: 13)])
    }

    func testSelectionPastTheEndIsClipped() {
        XCTAssertEqual(lines("a\nb", NSRange(location: 2, length: 50)), ["b"])
    }
}
