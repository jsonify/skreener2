import XCTest
@testable import Skreener

/// Space in the capture overlay cycles through the modes that have a hint (#171).
final class SelectionModeTests: XCTestCase {
    private typealias Mode = SelectionOverlay.Mode

    func testCyclesAreaWindowScrollingAndWraps() {
        let all = Set(Mode.allCases)
        XCTAssertEqual(Mode.area.next(in: all), .window)
        XCTAssertEqual(Mode.window.next(in: all), .scrolling)
        XCTAssertEqual(Mode.scrolling.next(in: all), .area)
    }

    func testRecordScreenTogglesAreaAndWindowOnly() {
        let both: Set<Mode> = [.area, .window]
        XCTAssertEqual(Mode.area.next(in: both), .window)
        XCTAssertEqual(Mode.window.next(in: both), .area)
    }

    func testSkipsModesThatAreNotAvailable() {
        XCTAssertEqual(Mode.area.next(in: [.area, .scrolling]), .scrolling)
        XCTAssertEqual(Mode.scrolling.next(in: [.area, .scrolling]), .area)
        // A starting mode that isn't in the set still moves to the next one that is.
        XCTAssertEqual(Mode.window.next(in: [.area]), .area)
    }

    func testStaysPutWithNothingToSwitchTo() {
        XCTAssertEqual(Mode.area.next(in: []), .area)
        XCTAssertEqual(Mode.area.next(in: [.area]), .area)
    }
}
