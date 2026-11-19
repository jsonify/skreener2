import XCTest
@testable import Skreener

/// Cuts and speed changes in the recording editor (#381): the edited timeline's time mapping, tidying, the audio
/// laid out on it, and finding idle stretches.
final class RecordingEditsTests: XCTestCase {
    private func cut(_ a: Double, _ b: Double) -> TimelineEdit { TimelineEdit(start: a, end: b, speed: 0) }
    private func fast(_ a: Double, _ b: Double, _ speed: Double = 4) -> TimelineEdit { TimelineEdit(start: a, end: b, speed: speed) }

    func testNoEditsIsTheRecordingItself() {
        let t = EditTimeline(edits: [], duration: 10)
        XCTAssertTrue(t.isEmpty)
        XCTAssertEqual(t.outputDuration, 10)
        XCTAssertEqual(t.sourceTime(output: 3.5), 3.5)
        XCTAssertEqual(t.outputTime(source: 3.5), 3.5)
        XCTAssertEqual(t.sourceTime(output: 12), 10)
    }

    func testACutIsLeftOut() {
        let t = EditTimeline(edits: [cut(2, 5)], duration: 10)
        XCTAssertEqual(t.outputDuration, 7, accuracy: 1e-9)
        XCTAssertEqual(t.sourceTime(output: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(t.sourceTime(output: 2), 5, accuracy: 1e-9, "jumps over the cut")
        XCTAssertEqual(t.sourceTime(output: 4), 7, accuracy: 1e-9)
        XCTAssertEqual(t.outputTime(source: 3), 2, accuracy: 1e-9, "inside the cut: where it was")
        XCTAssertEqual(t.outputTime(source: 8), 5, accuracy: 1e-9)
    }

    func testASpeedUpPlaysFaster() {
        let t = EditTimeline(edits: [fast(2, 6, 4)], duration: 10)
        XCTAssertEqual(t.outputDuration, 7, accuracy: 1e-9)
        XCTAssertEqual(t.sourceTime(output: 2.5), 4, accuracy: 1e-9)
        XCTAssertEqual(t.sourceTime(output: 3), 6, accuracy: 1e-9)
        XCTAssertEqual(t.outputTime(source: 4), 2.5, accuracy: 1e-9)
        XCTAssertEqual(t.outputTime(source: 9), 6, accuracy: 1e-9)
    }

    func testMappingRoundTripsOutsideCuts() {
        let t = EditTimeline(edits: [cut(1, 2), fast(3, 5, 2), cut(7, 7.5), fast(8, 9.5, 8)], duration: 12)
        for s in stride(from: 0.0, to: 12, by: 0.25) where t.edit(at: s)?.isCut != true {
            XCTAssertEqual(t.sourceTime(output: t.outputTime(source: s)), s, accuracy: 1e-9, "at \(s)")
        }
        // Output time never goes backwards.
        var last = -1.0
        for s in stride(from: 0.0, through: 12, by: 0.1) {
            let o = t.outputTime(source: s)
            XCTAssertGreaterThanOrEqual(o, last)
            last = o
        }
    }

    func testTidyKeepsEditsInsideApartAndValid() {
        let tidy = EditTimeline.tidy([fast(-1, 2, 3), cut(9, 20), cut(4, 4.01), fast(5, 6, 4)], duration: 10)
        XCTAssertEqual(tidy, [fast(0, 2, 2), fast(5, 6, 4), cut(9, 10)], "clamped, too short dropped, speed snapped")
    }

    func testANewEditReplacesWhatItOverlaps() {
        let edits = [fast(0, 10, 4)]
        let split = EditTimeline.adding(cut(4, 6), to: edits)
        XCTAssertEqual(split, [fast(0, 4, 4), cut(4, 6), fast(6, 10, 4)])
        let trimmed = EditTimeline.adding(cut(8, 12), to: edits)
        XCTAssertEqual(trimmed, [fast(0, 8, 4), cut(8, 12)])
        let covered = EditTimeline.adding(fast(0, 10, 2), to: split)
        XCTAssertEqual(covered, [fast(0, 10, 2)])
    }

    func testLaterEditsWinWhenTidying() {
        XCTAssertEqual(EditTimeline.tidy([fast(0, 5), cut(2, 3)], duration: 10), [fast(0, 2), cut(2, 3), fast(3, 5)])
        XCTAssertEqual(EditTimeline.tidy([cut(2, 3), fast(0, 5)], duration: 10), [fast(0, 5)])
    }

    func testAudioIsLaidOutOnTheEditedTimeline() {
        let sr = 1000.0
        // Ten seconds; each second's samples hold its number.
        let source = (0..<10_000).map { Float($0 / 1000 + 1) }
        let t = EditTimeline(edits: [cut(2, 4), fast(6, 8, 2)], duration: 10)
        let out = t.remap(source, sampleRate: sr)
        XCTAssertEqual(out.count, 7000)
        XCTAssertEqual(out[1500], 2, "second 1")
        XCTAssertEqual(out[2500], 5, "second 4, after the cut")
        XCTAssertEqual(out[4500], 0, "sped up: silent")
        XCTAssertEqual(out[5500], 9, "second 8, after the speed-up")
        // Fades at the joins, none at the very start.
        XCTAssertEqual(out[0], 1)
        XCTAssertEqual(out[2000], 0, "fades in after the cut")
        XCTAssertEqual(out[1999], 0, "fades out before the cut")
        XCTAssertEqual(EditTimeline(edits: [], duration: 10).remap(source, sampleRate: sr), source)
    }

    func testIdleStretchesFromTheEventTrack() {
        var events = RecordingEvents()
        // The pointer moves until 2 s, rests until 9 s, moves again; a click at 12 s, then nothing until 20 s.
        for i in 0...200 {
            let t = Double(i) * 0.1
            let x = t < 2 ? t * 50 : (t < 9 ? 100 : 100 + (t - 9) * 50)
            events.cursor.append(.init(t: t, x: t < 10 ? x : 150, y: 0, visible: true))
        }
        events.clicks = [.init(t: 12, x: 150, y: 0, button: .left, down: true)]
        let idle = EditTimeline.idleRanges(events, duration: 20)
        XCTAssertEqual(idle.count, 2)
        XCTAssertEqual(idle[0].start, 2.5, accuracy: 0.11)
        XCTAssertEqual(idle[0].end, 8.6, accuracy: 0.11)
        XCTAssertEqual(idle[1].start, 12.5, accuracy: 1e-9)
        XCTAssertEqual(idle[1].end, 19.5, accuracy: 1e-9)
    }

    func testKeysKeepAStretchBusy() {
        var events = RecordingEvents()
        events.keys = (0..<10).map { .init(t: Double($0) * 2, text: "a", append: true) }
        XCTAssertTrue(EditTimeline.idleRanges(events, duration: 20).isEmpty)
    }

    func testStudioSettingsKeepTheEdits() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        s.edits = [cut(1, 2), fast(3, 4, 8)]
        XCTAssertEqual(try StudioSettings.decode(s.encoded(), project: project).edits, s.edits)
        XCTAssertEqual(s.withoutZoom, StudioSettings(project: project).withoutZoom, "edits don't change the picture")
    }
}
