import CoreMedia
import XCTest
@testable import Skreener

/// Where a recording's video ends when it stops (#380): ScreenCaptureKit only sends frames when the screen changes,
/// so the session is ended at the moment Stop was pressed, not at the last frame.
final class RecordingEndTests: XCTestCase {
    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) }
    private let frame = CMTime(value: 1, timescale: 30)

    func testEndsWhenStopWasPressedNotAtTheLastChange() {
        // Host clock: last frame at 103 s, Stop at 110 s, never paused.
        let end = ScreenRecorder.sessionEnd(stop: t(110), pauseStart: .invalid, pausedTotal: .zero, lastFrame: t(103),
                                            frameDuration: frame)
        XCTAssertEqual(end.seconds, 110, accuracy: 1e-6)
    }

    func testTimePausedIsLeftOut() {
        // Paused for 4 s earlier: samples were shifted back by 4 s, so the end is too.
        let end = ScreenRecorder.sessionEnd(stop: t(110), pauseStart: .invalid, pausedTotal: t(4), lastFrame: t(100),
                                            frameDuration: frame)
        XCTAssertEqual(end.seconds, 106, accuracy: 1e-6)
    }

    func testStoppedWhilePausedEndsWhereThePauseBegan() {
        // Paused at 107 s (after 2 s of earlier pauses), stopped at 115 s.
        let end = ScreenRecorder.sessionEnd(stop: t(115), pauseStart: t(107), pausedTotal: t(2), lastFrame: t(104),
                                            frameDuration: frame)
        XCTAssertEqual(end.seconds, 105, accuracy: 1e-6)
    }

    func testNeverCutsTheLastFrame() {
        // A frame stamped just after Stop (it was on its way) still gets its full length.
        let end = ScreenRecorder.sessionEnd(stop: t(110), pauseStart: .invalid, pausedTotal: .zero, lastFrame: t(110.01),
                                            frameDuration: frame)
        XCTAssertEqual(end.seconds, 110.01 + 1.0 / 30, accuracy: 1e-6)
    }

    func testWithoutAFrameItIsTheStopMoment() {
        let end = ScreenRecorder.sessionEnd(stop: t(50), pauseStart: .invalid, pausedTotal: t(1), lastFrame: .invalid,
                                            frameDuration: frame)
        XCTAssertEqual(end.seconds, 49, accuracy: 1e-6)
    }
}
