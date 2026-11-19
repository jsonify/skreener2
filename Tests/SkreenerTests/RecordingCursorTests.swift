import XCTest
@testable import Skreener

/// The recording editor's cursor options (#382): smoothing that still lands on every click, size, and hiding the
/// cursor when idle.
final class RecordingCursorTests: XCTestCase {
    /// A jittery pointer moving right at 60 samples a second for `seconds`.
    private func jittery(seconds: Double = 2) -> [RecordingEvents.CursorSample] {
        (0..<Int(seconds * 60)).map { i in
            let t = Double(i) / 60
            let jitter = i % 2 == 0 ? 6.0 : -6.0
            return .init(t: t, x: 100 + t * 200, y: 300 + jitter, visible: true)
        }
    }

    private func click(_ t: Double, _ x: Double, _ y: Double, down: Bool = true) -> RecordingEvents.Click {
        .init(t: t, x: x, y: y, button: .left, down: down)
    }

    private func roughness(_ s: [RecordingEvents.CursorSample]) -> Double {
        s.indices.dropFirst().reduce(0) { $0 + abs(s[$1].y - s[$1 - 1].y) }
    }

    func testOffLeavesThePathAlone() {
        var e = RecordingEvents()
        e.cursor = jittery()
        XCTAssertEqual(CursorMotion.smoothed(e, .off), e)
    }

    func testSmoothingTakesOutJitter() {
        var e = RecordingEvents()
        e.cursor = jittery()
        let low = CursorMotion.smoothed(e, .low).cursor
        let high = CursorMotion.smoothed(e, .high).cursor
        XCTAssertEqual(low.count, e.cursor.count)
        XCTAssertLessThan(roughness(low), roughness(e.cursor) / 4)
        XCTAssertLessThan(roughness(high), roughness(e.cursor) / 4)
        // Still where it was going.
        XCTAssertEqual(low[60].x, e.cursor[60].x, accuracy: 2)
    }

    func testSmoothedPathLandsExactlyOnEveryClick() {
        var e = RecordingEvents()
        e.cursor = jittery()
        // Between samples, and off the line the samples are on.
        e.clicks = [click(0.505, 210, 320), click(0.6, 222, 290, down: false), click(1.5, 400, 300)]
        for smoothing in [CursorSmoothing.low, .high] {
            let smoothed = CursorMotion.smoothed(e, smoothing)
            for c in e.clicks {
                let state = smoothed.cursorState(at: c.t)
                XCTAssertEqual(Double(state?.point.x ?? 0), c.x, accuracy: 1e-9, "\(smoothing) at \(c.t)")
                XCTAssertEqual(Double(state?.point.y ?? 0), c.y, accuracy: 1e-9, "\(smoothing) at \(c.t)")
            }
        }
    }

    func testAClickReplacesASampleAtTheSameMoment() {
        var e = RecordingEvents()
        e.cursor = jittery()
        e.clicks = [click(e.cursor[30].t, 1, 2)]
        let (samples, anchors) = CursorMotion.anchored(e)
        XCTAssertEqual(samples.count, e.cursor.count)
        XCTAssertEqual(anchors.filter { $0 }.count, 1)
        XCTAssertEqual(samples[30].x, 1)
    }

    func testNotSmoothedAcrossLeavingTheArea() {
        var e = RecordingEvents()
        e.cursor = jittery()
        for i in 60..<e.cursor.count { e.cursor[i].visible = false; e.cursor[i].x += 1000 }
        let smoothed = CursorMotion.smoothed(e, .high).cursor
        // The last sample over the area and the first off it stay where they were.
        XCTAssertEqual(smoothed[59], e.cursor[59])
        XCTAssertEqual(smoothed[60], e.cursor[60])
        XCTAssertLessThan(smoothed[58].x, 500)
    }

    func testSegmentsSplitAtClicksGapsAndVisibility() {
        let s: [RecordingEvents.CursorSample] = [
            .init(t: 0, x: 0, y: 0, visible: true), .init(t: 0.1, x: 0, y: 0, visible: true),
            .init(t: 0.2, x: 0, y: 0, visible: true), .init(t: 1, x: 0, y: 0, visible: true),
            .init(t: 1.1, x: 0, y: 0, visible: false),
        ]
        let ranges = CursorMotion.segments(s, anchors: [false, true, false, false, false])
        XCTAssertEqual(ranges, [0...1, 1...2, 3...3, 4...4])
    }

    func testIdleCursorFadesOutAndBackIn() {
        var e = RecordingEvents()
        // Moves for a second, stops for 5, then moves again.
        e.cursor = (0...60).map { .init(t: Double($0) / 60, x: Double($0), y: 0, visible: true) }
            + (1...300).map { .init(t: 1 + Double($0) / 60, x: 60, y: 0, visible: true) }
            + (1...60).map { .init(t: 6 + Double($0) / 60, x: 60 + Double($0), y: 0, visible: true) }
        let v = CursorVisibility(events: e, delay: 2)
        XCTAssertEqual(v.opacity(at: 0.5), 1)
        XCTAssertEqual(v.opacity(at: 2.9), 1, "still there within the delay")
        XCTAssertEqual(v.opacity(at: 3 + CursorMotion.fadeOut / 2), 0.5, accuracy: 0.01)
        XCTAssertEqual(v.opacity(at: 4), 0, "hidden")
        XCTAssertEqual(v.opacity(at: 6 + 1.0 / 60 + CursorMotion.fadeIn / 2), 0.5, accuracy: 0.01, "fading back in")
        XCTAssertEqual(v.opacity(at: 6.5), 1)
    }

    func testAClickWakesTheCursor() {
        var e = RecordingEvents()
        e.cursor = (0...600).map { .init(t: Double($0) / 60, x: 10, y: 10, visible: true) }
        e.clicks = [click(5, 10, 10)]
        let v = CursorVisibility(events: e, delay: 1)
        XCTAssertEqual(v.opacity(at: 4), 0)
        XCTAssertEqual(v.opacity(at: 5.5), 1)
    }

    func testSettingsAreSavedAndClamped() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        s.cursor.smoothing = .high
        s.cursor.size = 2.5
        s.cursor.hideWhenIdle = true
        s.cursor.idleDelay = 3
        XCTAssertEqual(try StudioSettings.decode(s.encoded(), project: project).cursor, s.cursor)
        XCTAssertNotEqual(s.withoutZoom, StudioSettings(project: project).withoutZoom, "the cursor changes the picture")
        let odd = try JSONDecoder().decode(CursorSettings.self, from: Data(#"{"smoothing": "wobbly", "size": 9}"#.utf8))
        XCTAssertEqual(odd.smoothing, .off)
        XCTAssertEqual(odd.size, CursorSettings.maxSize)
        XCTAssertEqual(CursorSettings.sizeText(1), "1×")
        XCTAssertEqual(CursorSettings.sizeText(1.5), "1.5×")
    }
}
