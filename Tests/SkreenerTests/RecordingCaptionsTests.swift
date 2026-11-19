import XCTest
@testable import Skreener

/// Captions in the recording editor (#386): grouping words into lines, timing across cuts, and the .srt file.
final class RecordingCaptionsTests: XCTestCase {
    private func w(_ start: Double, _ text: String, _ duration: Double = 0.3) -> Captions.Word {
        Captions.Word(start: start, duration: duration, text: text)
    }

    func testWordsBecomeLinesAtPausesAndSentenceEnds() {
        let words = [w(0, "Hello"), w(0.4, "there."), w(1, "This"), w(1.4, "is"), w(1.8, "Skreener"), w(4, "Next")]
        let lines = Captions.lines(words)
        XCTAssertEqual(lines.map(\.text), ["Hello there.", "This is Skreener", "Next"])
        XCTAssertEqual(lines[0].start, 0)
        XCTAssertEqual(lines[1].start, 1)
        // Shown at least a second, but never into the next line.
        XCTAssertEqual(lines[0].end, 1, accuracy: 1e-9)
        XCTAssertEqual(lines[1].end, 2.1, accuracy: 1e-9)
    }

    func testLongLinesAreSplit() {
        let words = (0..<20).map { w(Double($0) * 0.2, "word") }
        let lines = Captions.lines(words)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { $0.text.count <= Captions.maxCharacters })
        XCTAssertTrue(lines.allSatisfy { $0.end - $0.start <= Captions.maxDuration + Captions.minDuration })
    }

    func testIndexAtTime() {
        let c = [Caption(start: 1, end: 2, text: "a"), Caption(start: 3, end: 4, text: "b")]
        XCTAssertEqual(Captions.index(at: 1.5, in: c), 0)
        XCTAssertNil(Captions.index(at: 2.5, in: c))
        XCTAssertEqual(Captions.index(at: 3, in: c), 1)
    }

    func testTimingFollowsCutsAndLeavesOutSpedUpAndMutedRanges() {
        let captions = [Caption(start: 1, end: 2, text: "before"), Caption(start: 3, end: 4, text: "cut out"),
                        Caption(start: 5, end: 7, text: "split"), Caption(start: 9, end: 10, text: "fast"),
                        Caption(start: 11, end: 12, text: "muted")]
        let timeline = EditTimeline(edits: [TimelineEdit(start: 2.5, end: 4.5, speed: 0),
                                            TimelineEdit(start: 5.5, end: 6.5, speed: 0),
                                            TimelineEdit(start: 8.5, end: 10.5, speed: 4),
                                            TimelineEdit(start: 11, end: 12, speed: TimelineEdit.mute)],
                                    duration: 20)
        let out = Captions.laidOut(captions, on: timeline)
        XCTAssertEqual(out.map(\.text), ["before", "split"])
        XCTAssertEqual(out[0].start, 1, accuracy: 1e-9)
        XCTAssertEqual(out[0].end, 2, accuracy: 1e-9)
        // 5–7 with 2.5–4.5 cut before it and 5.5–6.5 cut from its middle: 3–4 in the output, in one piece.
        XCTAssertEqual(out[1].start, 3, accuracy: 1e-9)
        XCTAssertEqual(out[1].end, 4, accuracy: 1e-9)
    }

    func testWithoutEditsTheCaptionsStay() {
        let c = [Caption(start: 1, end: 2, text: "a")]
        XCTAssertEqual(Captions.laidOut(c, on: EditTimeline(edits: [], duration: 10)), c)
    }

    func testSRT() {
        let srt = Captions.srt([Caption(start: 1.5, end: 3, text: "Hello"), Caption(start: 3661.25, end: 3662, text: "Later")])
        XCTAssertEqual(srt, "1\n00:00:01,500 --> 00:00:03,000\nHello\n\n2\n01:01:01,250 --> 01:01:02,000\nLater\n")
        XCTAssertEqual(Captions.srtURL(for: URL(fileURLWithPath: "/a/Demo (Vertical).mp4")).path, "/a/Demo (Vertical).srt")
    }

    func testCaptionsAreSavedWithTheSettings() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        s.captions = [Caption(start: 1, end: 2, text: "Hi")]
        s.captionsFile = false
        let read = try StudioSettings.decode(s.encoded(), project: project)
        XCTAssertEqual(read.captions, s.captions)
        XCTAssertFalse(read.captionsFile)
        XCTAssertTrue(read.captionsShown)
    }
}
