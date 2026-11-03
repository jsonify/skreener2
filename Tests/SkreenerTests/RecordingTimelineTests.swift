import XCTest
@testable import Skreener

final class RecordingTimelineTests: XCTestCase {
    // MARK: Host time → video time

    func testClockMapsHostTimeFromTheFirstFrame() throws {
        var c = RecordingClock()
        XCTAssertNil(c.videoTime(host: 100), "no video before the first frame")
        c.firstFrame(at: 100)
        XCTAssertEqual(try XCTUnwrap(c.videoTime(host: 102.5)), 2.5, accuracy: 1e-9)
        XCTAssertNil(c.videoTime(host: 99), "before the video starts")
        c.firstFrame(at: 200)
        XCTAssertEqual(try XCTUnwrap(c.videoTime(host: 101)), 1, accuracy: 1e-9, "only the first frame counts")
    }

    func testClockLeavesOutTimePausedAndDropsEventsWhilePaused() throws {
        var c = RecordingClock()
        c.firstFrame(at: 100)
        c.pause(at: 105)
        XCTAssertTrue(c.isPaused)
        XCTAssertNil(c.videoTime(host: 107))
        XCTAssertEqual(try XCTUnwrap(c.videoTime(host: 107, holdWhilePaused: true)), 5, accuracy: 1e-9)
        c.resume(at: 110)
        XCTAssertEqual(try XCTUnwrap(c.videoTime(host: 111)), 6, accuracy: 1e-9)
        // A second pause adds up.
        c.pause(at: 112)
        c.pause(at: 113)   // ignored: already paused
        c.resume(at: 114)
        XCTAssertEqual(c.pausedTotal, 7, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(c.videoTime(host: 115)), 8, accuracy: 1e-9)
        c.resume(at: 120)   // ignored: not paused
        XCTAssertEqual(c.pausedTotal, 7, accuracy: 1e-9)
    }

    func testClockMatchesTheRecorderWhenPausedBeforeTheFirstFrame() throws {
        // The recorder shifts the first frame (host 20) back by the 3 s paused before it and starts the video there.
        var c = RecordingClock()
        c.pause(at: 10)
        c.resume(at: 13)
        c.firstFrame(at: 20)
        XCTAssertEqual(c.start, 17)
        XCTAssertEqual(try XCTUnwrap(c.videoTime(host: 21)), 1, accuracy: 1e-9)
    }

    // MARK: Geometry

    func testVideoSizeIsEvenAndScaledDownWhenTooBig() {
        XCTAssertEqual(RecordingGeometry.videoSize(area: CGSize(width: 1000, height: 500), backingScale: 2, maxPixels: .max),
                       CGSize(width: 2000, height: 1000))
        XCTAssertEqual(RecordingGeometry.videoSize(area: CGSize(width: 101, height: 51), backingScale: 1, maxPixels: .max),
                       CGSize(width: 100, height: 50))
        let big = RecordingGeometry.videoSize(area: CGSize(width: 5120, height: 2880), backingScale: 2, maxPixels: 4096 * 2304)
        XCTAssertLessThanOrEqual(big.width * big.height, 4096 * 2304)
        XCTAssertEqual(big.width, 4096, accuracy: 2)
        XCTAssertEqual(big.height, 2304, accuracy: 2)
        XCTAssertEqual(Int(big.width) % 2, 0)
        XCTAssertEqual(RecordingGeometry.videoSize(area: CGSize(width: 0.5, height: 0.5), backingScale: 1, maxPixels: .max),
                       CGSize(width: 2, height: 2))
    }

    func testVideoPointHasATopLeftOriginInPixels() {
        let area = CGRect(x: 100, y: 200, width: 400, height: 300)
        let size = CGSize(width: 800, height: 600)
        XCTAssertEqual(RecordingGeometry.videoPoint(global: CGPoint(x: 100, y: 500), area: area, videoSize: size), .zero)
        XCTAssertEqual(RecordingGeometry.videoPoint(global: CGPoint(x: 300, y: 350), area: area, videoSize: size),
                       CGPoint(x: 400, y: 300))
        XCTAssertEqual(RecordingGeometry.videoPoint(global: CGPoint(x: 50, y: 600), area: area, videoSize: size),
                       CGPoint(x: -100, y: -200), "outside the area stays outside")
        XCTAssertEqual(RecordingGeometry.pixelsPerPoint(area: area.size, videoSize: size), 2)
    }

    func testVideoPointFollowsAScaledDownVideo() {
        let area = CGRect(x: 0, y: 0, width: 5120, height: 2880)
        let size = CGSize(width: 4096, height: 2304)
        let top = RecordingGeometry.videoPoint(global: CGPoint(x: 2560, y: 2880), area: area, videoSize: size)
        XCTAssertEqual(top.x, 2048, accuracy: 1e-6)
        XCTAssertEqual(top.y, 0, accuracy: 1e-6)
        let corner = RecordingGeometry.videoPoint(global: CGPoint(x: 5120, y: 0), area: area, videoSize: size)
        XCTAssertEqual(corner.x, 4096, accuracy: 1e-6)
        XCTAssertEqual(corner.y, 2304, accuracy: 1e-6)
        XCTAssertEqual(RecordingGeometry.pixelsPerPoint(area: area.size, videoSize: size), 0.8, accuracy: 1e-9)
    }

    func testQuartzPointsFlipToAppKit() {
        XCTAssertEqual(RecordingGeometry.appKitPoint(quartz: CGPoint(x: 10, y: 20), mainHeight: 1000), CGPoint(x: 10, y: 980))
    }

    func testContainsIsHalfOpen() {
        let size = CGSize(width: 100, height: 50)
        XCTAssertTrue(RecordingGeometry.contains(.zero, videoSize: size))
        XCTAssertTrue(RecordingGeometry.contains(CGPoint(x: 99.5, y: 49.5), videoSize: size))
        XCTAssertFalse(RecordingGeometry.contains(CGPoint(x: 100, y: 10), videoSize: size))
        XCTAssertFalse(RecordingGeometry.contains(CGPoint(x: -1, y: 10), videoSize: size))
    }

    // MARK: Cursor

    private func cursorEvents() -> RecordingEvents {
        var e = RecordingEvents()
        e.cursor = [.init(t: 0, x: 0, y: 0, visible: true), .init(t: 1, x: 100, y: 50, visible: true),
                    .init(t: 2, x: 200, y: 200, visible: false), .init(t: 3, x: 300, y: 300, visible: true)]
        e.cursorImages = [.init(file: "0.png", width: 16, height: 16, hotspotX: 0, hotspotY: 0),
                          .init(file: "1.png", width: 16, height: 16, hotspotX: 8, hotspotY: 8)]
        e.cursorChanges = [.init(t: 0.2, image: 0), .init(t: 1, image: 1)]
        return e
    }

    func testCursorInterpolatesBetweenVisibleSamples() throws {
        let e = cursorEvents()
        let mid = try XCTUnwrap(e.cursorState(at: 0.5))
        XCTAssertEqual(mid.point, CGPoint(x: 50, y: 25))
        XCTAssertTrue(mid.visible)
        XCTAssertEqual(try XCTUnwrap(e.cursorState(at: 1)).point, CGPoint(x: 100, y: 50))
    }

    func testCursorJumpsAcrossInvisibleSamples() throws {
        let e = cursorEvents()
        let leaving = try XCTUnwrap(e.cursorState(at: 1.5))
        XCTAssertEqual(leaving.point, CGPoint(x: 100, y: 50), "no sliding toward a point off the area")
        XCTAssertTrue(leaving.visible)
        let away = try XCTUnwrap(e.cursorState(at: 2.5))
        XCTAssertEqual(away.point, CGPoint(x: 200, y: 200))
        XCTAssertFalse(away.visible)
    }

    func testCursorHoldsBeforeTheFirstAndAfterTheLastSample() throws {
        let e = cursorEvents()
        XCTAssertEqual(try XCTUnwrap(e.cursorState(at: -1)).point, .zero)
        let end = try XCTUnwrap(e.cursorState(at: 10))
        XCTAssertEqual(end.point, CGPoint(x: 300, y: 300))
        XCTAssertTrue(end.visible)
        XCTAssertNil(RecordingEvents().cursorState(at: 1))
    }

    func testCursorImageFollowsChanges() {
        let e = cursorEvents()
        XCTAssertEqual(e.cursorImage(at: 0), 0, "before the first change: the first image seen")
        XCTAssertEqual(e.cursorImage(at: 0.5), 0)
        XCTAssertEqual(e.cursorImage(at: 1), 1)
        XCTAssertEqual(e.cursorState(at: 2.5)?.image, 1)
        var none = RecordingEvents()
        XCTAssertNil(none.cursorImage(at: 1))
        none.cursorChanges = [.init(t: 0, image: 5)]
        XCTAssertNil(none.cursorImage(at: 1), "an index without an image")
    }

    // MARK: Clicks, keys, spotlight

    func testClickRingsAnimateForHalfASecond() throws {
        var e = RecordingEvents()
        e.clicks = [.init(t: 1, x: 50, y: 50, button: .left, down: true),
                    .init(t: 1.1, x: 50, y: 50, button: .left, down: false),
                    .init(t: 1, x: -5, y: 10, button: .right, down: true)]
        let size = CGSize(width: 100, height: 100)
        XCTAssertTrue(e.rings(at: 0.9, videoSize: size).isEmpty)
        let start = try XCTUnwrap(e.rings(at: 1, videoSize: size).first)
        XCTAssertEqual(e.rings(at: 1, videoSize: size).count, 1, "releases and clicks off the video have no ring")
        XCTAssertEqual(start.center, CGPoint(x: 50, y: 50))
        XCTAssertEqual(start.progress, 0, accuracy: 1e-9)
        XCTAssertEqual(start.scale, EffectsLook.ringStartScale, accuracy: 1e-6)
        XCTAssertEqual(start.opacity, 1, accuracy: 1e-6)
        let half = try XCTUnwrap(e.rings(at: 1.25, videoSize: size).first)
        XCTAssertEqual(half.progress, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(half.scale, 0.7, "ease-out: past the linear midpoint")
        XCTAssertLessThan(half.scale, 1)
        XCTAssertEqual(half.opacity, 1 - (half.scale - 0.4) / 0.6, accuracy: 1e-6)
        XCTAssertTrue(e.rings(at: 1.5, videoSize: size).isEmpty)
    }

    func testEaseOutMatchesCoreAnimationsCurve() {
        XCTAssertEqual(EffectsLook.easeOut(0), 0, accuracy: 1e-6)
        XCTAssertEqual(EffectsLook.easeOut(1), 1, accuracy: 1e-6)
        XCTAssertEqual(EffectsLook.easeOut(-1), 0, accuracy: 1e-6)
        XCTAssertEqual(EffectsLook.easeOut(2), 1, accuracy: 1e-6)
        var last = 0.0
        for i in 1...20 {
            let v = EffectsLook.easeOut(Double(i) / 20)
            XCTAssertGreaterThanOrEqual(v, last)
            last = v
        }
        // cubic-bezier(0, 0, 0.58, 1) at x = 0.5 is about 0.69.
        XCTAssertEqual(EffectsLook.easeOut(0.5), 0.69, accuracy: 0.02)
    }

    func testKeystrokePillsRunTogetherUntilAPause() {
        var e = RecordingEvents()
        e.keys = [.init(t: 0, text: "a", append: true), .init(t: 0.5, text: "b", append: true),
                  .init(t: 3, text: "c", append: true), .init(t: 3.2, text: "⌘S", append: false),
                  .init(t: 3.4, text: "x", append: true)]
        XCTAssertEqual(e.keystrokePills(), [
            KeystrokePill(start: 0, end: 0.5, text: "a"),
            KeystrokePill(start: 0.5, end: 0.5 + EffectsLook.pillHold, text: "ab"),
            KeystrokePill(start: 3, end: 3.2, text: "c"),
            KeystrokePill(start: 3.2, end: 3.4, text: "⌘S"),
            KeystrokePill(start: 3.4, end: 3.4 + EffectsLook.pillHold, text: "⌘Sx"),
        ])
        XCTAssertNil(e.keystroke(at: -0.1))
        XCTAssertEqual(e.keystroke(at: 0.2), "a")
        XCTAssertEqual(e.keystroke(at: 1), "ab")
        XCTAssertNil(e.keystroke(at: 2), "hidden after the pause")
        XCTAssertEqual(e.keystroke(at: 3.1), "c", "after the pause, typing starts over")
        XCTAssertEqual(e.keystroke(at: 3.3), "⌘S")
        XCTAssertEqual(e.keystroke(at: 4), "⌘Sx")
        XCTAssertNil(e.keystroke(at: 5))
    }

    func testKeystrokePillKeepsTheLastCharacters() {
        var e = RecordingEvents()
        e.keys = (0..<50).map { RecordingEvents.Keystroke(t: Double($0) * 0.1, text: String($0 % 10), append: true) }
        let text = e.keystroke(at: 5)
        XCTAssertEqual(text?.count, EffectsLook.pillMaxCharacters)
        XCTAssertEqual(text?.last, "9")
    }

    func testSpotlightFollowsToggles() {
        var e = RecordingEvents()
        e.spotlight = [.init(t: 1, on: true), .init(t: 2, on: false)]
        XCTAssertFalse(e.isSpotlightOn(at: 0.5))
        XCTAssertTrue(e.isSpotlightOn(at: 1))
        XCTAssertTrue(e.isSpotlightOn(at: 1.5))
        XCTAssertFalse(e.isSpotlightOn(at: 2.5))
        e.spotlightAtStart = true
        e.spotlight = []
        XCTAssertTrue(e.isSpotlightOn(at: 100))
    }

    func testPillFrameIsCenteredNearTheEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let size = CGSize(width: 100, height: 30)
        XCTAssertEqual(EffectsLook.pillFrame(textSize: size, padding: 10, edgeInset: 24, in: bounds, atTop: false),
                       CGRect(x: 140, y: 24, width: 120, height: 40))
        XCTAssertEqual(EffectsLook.pillFrame(textSize: size, padding: 10, edgeInset: 24, in: bounds, atTop: true),
                       CGRect(x: 140, y: 236, width: 120, height: 40))
        XCTAssertEqual(EffectsLook.pillPadding(fontSize: 24), 14.4, accuracy: 1e-9)
    }
}
