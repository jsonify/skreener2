import XCTest
@testable import Skreener

/// The recording HUD's mic meter (#469): levels in dBFS, the bar's fall, the peak marker, the clip light and the
/// advice in its tooltip.
final class MicMeterTests: XCTestCase {
    /// The amplitude of a level in dBFS.
    private func amp(_ db: Double) -> Float { Float(pow(10, db / 20)) }

    func testDecibels() {
        XCTAssertEqual(MicLevel.decibels(1), 0, accuracy: 1e-9)
        XCTAssertEqual(MicLevel.decibels(0.5), -6.02, accuracy: 0.01)
        XCTAssertEqual(MicLevel.decibels(0), MicMeter.floor)
        XCTAssertEqual(MicLevel.decibels(1e-9), MicMeter.floor)
        XCTAssertEqual(MicLevel.decibels(2), 0, "louder than full scale is shown as full scale")
    }

    func testPeakOfFloatAndInt16Samples() {
        let floats: [Float] = [0.1, -0.7, 0.3]
        floats.withUnsafeBufferPointer { XCTAssertEqual(MicLevel.peak($0), 0.7, accuracy: 1e-6) }
        let ints: [Int16] = [100, Int16.min, 2000]
        ints.withUnsafeBufferPointer { XCTAssertEqual(MicLevel.peak($0), 1, accuracy: 1e-6) }
        let half: [Int16] = [0, 16384]
        half.withUnsafeBufferPointer { XCTAssertEqual(MicLevel.peak($0), 0.5, accuracy: 1e-4) }
    }

    func testTapKeepsTheLoudestUntilRead() {
        let tap = MicLevelTap()
        XCTAssertNil(tap.take())
        tap.record(0.2); tap.record(0.6); tap.record(0.4)
        XCTAssertEqual(tap.take(), 0.6)
        XCTAssertNil(tap.take(), "reading empties it")
    }

    func testSegmentsLightUpToTheLevel() {
        XCTAssertEqual(MicMeter.lit(MicMeter.floor), 0)
        XCTAssertEqual(MicMeter.lit(-12), 8)
        XCTAssertEqual(MicMeter.lit(-10), 8)
        XCTAssertEqual(MicMeter.lit(0), MicMeter.segments.count)
        XCTAssertEqual(MicMeter.zone(ofSegment: 0), .good)
        XCTAssertEqual(MicMeter.zone(ofSegment: 8), .good, "-9 dBFS is still a good speaking level")
        XCTAssertEqual(MicMeter.zone(ofSegment: 9), .hot)
        XCTAssertEqual(MicMeter.zone(ofSegment: MicMeter.segments.count - 1), .clipping)
    }

    func testBarJumpsUpAndFallsBackSlowly() {
        var m = MicMeter()
        m.update(peak: amp(-12), at: 0)
        XCTAssertEqual(m.level, -12, accuracy: 1e-6)
        m.update(peak: nil, at: 0.5)
        XCTAssertEqual(m.level, -12 - MicMeter.fallRate * 0.5, accuracy: 1e-6)
        m.update(peak: nil, at: 10)
        XCTAssertEqual(m.level, MicMeter.floor)
    }

    func testPeakMarkerHoldsThenFalls() {
        var m = MicMeter()
        m.update(peak: amp(-6), at: 0)
        m.update(peak: amp(-30), at: 1)
        XCTAssertEqual(m.held, -6, accuracy: 1e-6, "held during the hold time")
        XCTAssertEqual(m.heldSegment, MicMeter.lit(-6) - 1)
        m.update(peak: nil, at: 2)
        XCTAssertLessThan(m.held, -6, "falls after the hold time")
    }

    func testClipLightStaysOnForTwoSeconds() {
        var m = MicMeter()
        m.update(peak: 1, at: 0)
        XCTAssertTrue(m.isClipping)
        XCTAssertEqual(m.advice, .tooLoud)
        m.update(peak: amp(-20), at: 1.9)
        XCTAssertTrue(m.isClipping)
        m.update(peak: amp(-20), at: 2.1)
        XCTAssertFalse(m.isClipping)
        XCTAssertEqual(m.advice, .good)
    }

    func testDigitalSilenceMeansNoSound() {
        var m = MicMeter()
        m.update(peak: 0, at: 0)
        m.update(peak: 0, at: 2)
        XCTAssertEqual(m.advice, .good, "not yet")
        m.update(peak: 0, at: 3.1)
        XCTAssertEqual(m.advice, .noSound)
        m.update(peak: amp(-20), at: 3.2)
        XCTAssertEqual(m.advice, .good)
    }

    func testNoAudioAtAllMeansNoSound() {
        var m = MicMeter()
        m.update(peak: nil, at: 0)
        m.update(peak: nil, at: 3.5)
        XCTAssertEqual(m.advice, .noSound)
    }

    func testAQuietRoomIsQuietButNotSilent() {
        var m = MicMeter()
        for i in 0...40 { m.update(peak: amp(-55), at: Double(i) * 0.1) }
        XCTAssertEqual(m.advice, .quiet)
    }

    func testAPauseBetweenSentencesIsNotQuiet() {
        var m = MicMeter()
        m.update(peak: amp(-12), at: 0)
        for i in 1...40 { m.update(peak: amp(-55), at: Double(i) * 0.1) }
        XCTAssertEqual(m.advice, .good, "4 s after speaking at -12 dBFS")
    }
}
