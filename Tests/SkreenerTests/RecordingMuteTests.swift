import XCTest
@testable import Skreener

/// Muting a range of a recording and its waveform on the timeline (#385).
final class RecordingMuteTests: XCTestCase {
    private func mute(_ a: Double, _ b: Double) -> TimelineEdit { TimelineEdit(start: a, end: b, speed: TimelineEdit.mute) }
    private func cut(_ a: Double, _ b: Double) -> TimelineEdit { TimelineEdit(start: a, end: b, speed: 0) }

    func testAMuteKeepsTheTimeButNotTheSound() {
        let t = EditTimeline(edits: [mute(2, 4)], duration: 10)
        XCTAssertFalse(t.changesTime)
        XCTAssertEqual(t.outputDuration, 10, accuracy: 1e-9)
        XCTAssertEqual(t.sourceTime(output: 3), 3, accuracy: 1e-9)
        XCTAssertEqual(t.edits.first?.label, "Mute")
        XCTAssertEqual(t.edits.first?.kind, "Mute")
        XCTAssertTrue(EditTimeline(edits: [mute(2, 4), cut(6, 7)], duration: 10).changesTime)
    }

    func testTidyKeepsAMuteAMute() {
        XCTAssertEqual(EditTimeline.tidy([mute(1, 2)], duration: 10), [mute(1, 2)])
        // A later cut wins over the part of the mute it overlaps.
        XCTAssertEqual(EditTimeline.tidy([mute(1, 3), cut(2, 4)], duration: 10), [mute(1, 2), cut(2, 4)])
    }

    func testMutedRangeIsSilentWithFadesAcrossACut() {
        let rate = 1000.0
        let source = [Float](repeating: 1, count: 10_000)
        // Cut 2–3 s, mute 5–6 s (4–5 s in the output).
        let t = EditTimeline(edits: [cut(2, 3), mute(5, 6)], duration: 10)
        let out = t.remap(source, sampleRate: rate)
        XCTAssertEqual(out.count, 9000)
        let fade = Int(0.01 * rate)
        // Fully silent inside the muted range.
        XCTAssertTrue(out[4000..<5000].allSatisfy { $0 == 0 })
        // Fades down into it and back up out of it, no jumps.
        XCTAssertEqual(out[3000], 1)
        XCTAssertLessThan(out[3999], 0.2)
        XCTAssertLessThan(out[5000], 0.2)
        XCTAssertEqual(out[5000 + fade], 1)
        for i in 3990..<4000 { XCTAssertLessThanOrEqual(out[i], out[i - 1]) }
        for i in 5001..<(5000 + fade) { XCTAssertGreaterThanOrEqual(out[i], out[i - 1]) }
        // And around the cut too.
        XCTAssertLessThan(out[1999], 0.2)
        XCTAssertLessThan(out[2000], 0.2)
    }

    func testWaveformKeepsEachBucketsLoudestSample() {
        var w = WaveformPeaks(buckets: 4, frames: 8)
        let stereo: [Float] = [0.1, -0.2, 0.3, 0, 0, 0, -0.9, 0.1]
        stereo.withUnsafeBufferPointer { w.add($0, channels: 2, start: 0) }
        XCTAssertEqual(w.peaks, [0.3, 0.9, 0, 0])
        let late: [Float] = [0.5, 2, 0.4]
        late.withUnsafeBufferPointer { w.add($0, channels: 1, start: 6) }
        XCTAssertEqual(w.peaks, [0.3, 0.9, 0, 1], "frames past the end are left out, louder than full scale is full")
    }

    func testWaveformHeights() {
        XCTAssertEqual(WaveformPeaks.height(1), 1)
        XCTAssertEqual(WaveformPeaks.height(0), 0)
        XCTAssertEqual(WaveformPeaks.height(Float(pow(10, -24.0 / 20))), 0.5, accuracy: 1e-4)
    }
}
