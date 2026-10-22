import CoreMedia
import XCTest
@testable import Skreener

final class RecordingTrimTests: XCTestCase {
    private let duration = CMTime(value: 10, timescale: 1)
    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    func testUntouchedHandlesTrimNothing() {
        XCTAssertNil(RecordingTrim.keptRange(start: .invalid, end: .invalid, duration: duration))
        XCTAssertNil(RecordingTrim.keptRange(start: .zero, end: duration, duration: duration))
        XCTAssertNil(RecordingTrim.keptRange(start: t(0.001), end: t(9.999), duration: duration), "within the slack")
    }

    func testStartOnly() throws {
        let range = try XCTUnwrap(RecordingTrim.keptRange(start: t(2), end: .invalid, duration: duration))
        XCTAssertEqual(range.start.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(range.end.seconds, 10, accuracy: 0.001)
    }

    func testEndOnly() throws {
        let range = try XCTUnwrap(RecordingTrim.keptRange(start: .invalid, end: t(7.5), duration: duration))
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(range.duration.seconds, 7.5, accuracy: 0.001)
    }

    func testClampsToTheVideo() throws {
        let before = try XCTUnwrap(RecordingTrim.keptRange(start: t(-1), end: t(4), duration: duration))
        XCTAssertEqual(before.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(before.end.seconds, 4, accuracy: 0.001)
        let past = try XCTUnwrap(RecordingTrim.keptRange(start: t(3), end: t(12), duration: duration))
        XCTAssertEqual(past.start.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(past.end.seconds, 10, accuracy: 0.001)
    }

    func testEmptyOrUnknown() {
        XCTAssertNil(RecordingTrim.keptRange(start: t(5), end: t(5), duration: duration))
        XCTAssertNil(RecordingTrim.keptRange(start: t(6), end: t(4), duration: duration))
        XCTAssertNil(RecordingTrim.keptRange(start: t(1), end: t(2), duration: .indefinite))
    }
}
