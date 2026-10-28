import XCTest
@testable import Skreener

final class SelfTimerTests: XCTestCase {
    private let deadline = Date(timeIntervalSinceReferenceDate: 1000)

    func testShowsWholeSecondsRoundedUp() {
        XCTAssertEqual(SelfTimer.secondsLeft(until: deadline, now: deadline.addingTimeInterval(-3)), 3)
        XCTAssertEqual(SelfTimer.secondsLeft(until: deadline, now: deadline.addingTimeInterval(-2.5)), 3)
        XCTAssertEqual(SelfTimer.secondsLeft(until: deadline, now: deadline.addingTimeInterval(-0.2)), 1)
    }

    func testReachesZeroAtTheDeadline() {
        XCTAssertEqual(SelfTimer.secondsLeft(until: deadline, now: deadline), 0)
    }

    /// A stall (menu open, App Nap) must not stretch the countdown: past the deadline it is simply due.
    func testIsDueAfterAStall() {
        XCTAssertEqual(SelfTimer.secondsLeft(until: deadline, now: deadline.addingTimeInterval(5)), 0)
    }
}
