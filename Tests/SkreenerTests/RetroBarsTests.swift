import XCTest
@testable import Skreener

final class RetroBarsTests: XCTestCase {
    func testElapsedIsMinutesAndSeconds() {
        XCTAssertEqual(RetroBars.elapsed(0), "00:00")
        XCTAssertEqual(RetroBars.elapsed(42), "00:42")
        XCTAssertEqual(RetroBars.elapsed(83), "01:23")
    }

    /// Past 99 minutes the minutes get a third digit rather than wrapping.
    func testElapsedKeepsCountingPastAnHourAndAHalf() {
        XCTAssertEqual(RetroBars.elapsed(100 * 60 + 5), "100:05")
    }

    func testElapsedNeverGoesNegative() {
        XCTAssertEqual(RetroBars.elapsed(-3), "00:00")
    }

    /// Every character of the elapsed time is one the seven-segment display can draw.
    func testElapsedDrawsOnSevenSegments() {
        for s in [0, 59, 61, 3599, 6000] {
            for ch in RetroBars.elapsed(s) where ch != ":" {
                XCTAssertFalse(SevenSegment.lit(ch).isEmpty, "\(ch) lights nothing")
            }
        }
    }

    func testFormatLabel() {
        XCTAssertEqual(RetroBars.formatLabel(gif: false, fps: 60), "MP4 60")
        XCTAssertEqual(RetroBars.formatLabel(gif: false, fps: 30), "MP4 30")
        XCTAssertEqual(RetroBars.formatLabel(gif: true, fps: 60), "GIF")
    }
}
