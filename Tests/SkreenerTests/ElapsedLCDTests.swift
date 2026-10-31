import XCTest
@testable import Skreener

final class ElapsedLCDTests: XCTestCase {
    func testElapsedIsMinutesAndSeconds() {
        XCTAssertEqual(ElapsedLCD.elapsed(0), "00:00")
        XCTAssertEqual(ElapsedLCD.elapsed(42), "00:42")
        XCTAssertEqual(ElapsedLCD.elapsed(83), "01:23")
    }

    /// Past 99 minutes the minutes get a third digit rather than wrapping.
    func testElapsedKeepsCountingPastAnHourAndAHalf() {
        XCTAssertEqual(ElapsedLCD.elapsed(100 * 60 + 5), "100:05")
    }

    func testElapsedNeverGoesNegative() {
        XCTAssertEqual(ElapsedLCD.elapsed(-3), "00:00")
    }

    /// Every character of the elapsed time is one the seven-segment display can draw.
    func testElapsedDrawsOnSevenSegments() {
        for s in [0, 59, 61, 3599, 6000] {
            for ch in ElapsedLCD.elapsed(s) where ch != ":" {
                XCTAssertFalse(SevenSegment.lit(ch).isEmpty, "\(ch) lights nothing")
            }
        }
    }

    func testFormatLabel() {
        XCTAssertEqual(ElapsedLCD.formatLabel(gif: false, fps: 60), "MP4 60")
        XCTAssertEqual(ElapsedLCD.formatLabel(gif: false, fps: 30), "MP4 30")
        XCTAssertEqual(ElapsedLCD.formatLabel(gif: true, fps: 60), "GIF")
    }
}
