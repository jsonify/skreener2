import XCTest
@testable import Skreener

/// The recording editor's audio cleanup (#385): filters, noise gate, compressor, levelling, mixing and settings.
final class AudioCleanupTests: XCTestCase {
    private let sr = 48_000.0

    private func sine(_ frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        (0..<Int(seconds * sr)).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sr)) }
    }

    private func rmsDB(_ x: ArraySlice<Float>) -> Double {
        10 * log10(x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count))
    }

    /// Deterministic white noise.
    private func noise(amplitude: Float, seconds: Double) -> [Float] {
        var state: UInt32 = 12345
        return (0..<Int(seconds * sr)).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return amplitude * (Float(state >> 8) / Float(1 << 24) * 2 - 1)
        }
    }

    // MARK: Filters

    func testHighPassCutsRumbleAndKeepsTheVoice() {
        let f = Biquad.highPass(80, sampleRate: sr)
        XCTAssertLessThan(f.response(at: 20, sampleRate: sr), -20)
        XCTAssertEqual(f.response(at: 80, sampleRate: sr), -3, accuracy: 0.2)
        XCTAssertEqual(f.response(at: 1000, sampleRate: sr), 0, accuracy: 0.1)
    }

    func testPeakingAndShelvesHitTheirGain() {
        XCTAssertEqual(Biquad.peaking(3500, gain: 3, q: 1, sampleRate: sr).response(at: 3500, sampleRate: sr), 3, accuracy: 0.05)
        XCTAssertEqual(Biquad.peaking(250, gain: -2, q: 1, sampleRate: sr).response(at: 250, sampleRate: sr), -2, accuracy: 0.05)
        XCTAssertEqual(Biquad.lowShelf(150, gain: 2.5, sampleRate: sr).response(at: 20, sampleRate: sr), 2.5, accuracy: 0.1)
        XCTAssertEqual(Biquad.lowShelf(150, gain: 2.5, sampleRate: sr).response(at: 5000, sampleRate: sr), 0, accuracy: 0.1)
        XCTAssertEqual(Biquad.highShelf(10000, gain: 2, sampleRate: sr).response(at: 20000, sampleRate: sr), 2, accuracy: 0.2)
        XCTAssertEqual(Biquad.highShelf(10000, gain: 2, sampleRate: sr).response(at: 200, sampleRate: sr), 0, accuracy: 0.05)
    }

    func testFilteringASignalMatchesTheResponse() {
        var low = sine(30, amplitude: 0.5, seconds: 1)
        Biquad.highPass(80, sampleRate: sr).process(&low)
        var mid = sine(1000, amplitude: 0.5, seconds: 1)
        Biquad.highPass(80, sampleRate: sr).process(&mid)
        // Skip the filter's start-up.
        XCTAssertLessThan(rmsDB(low[24000...]), rmsDB(mid[24000...]) - 12)
        XCTAssertEqual(rmsDB(mid[24000...]), 20 * log10(0.5 / sqrt(2)), accuracy: 0.1)
    }

    // MARK: Dynamics

    func testCompressorCurve() {
        XCTAssertEqual(Compressor.gainChange(level: -40, threshold: -20, ratio: 3, knee: 6), 0)
        // 12 dB over at 3:1 comes out 4 dB over: 8 dB down.
        XCTAssertEqual(Compressor.gainChange(level: -8, threshold: -20, ratio: 3, knee: 6), -8, accuracy: 1e-9)
        // In the knee, a little.
        let knee = Compressor.gainChange(level: -20, threshold: -20, ratio: 3, knee: 6)
        XCTAssertLessThan(knee, 0)
        XCTAssertGreaterThan(knee, -1)
    }

    func testCompressorTurnsDownLoudPassagesOnly() {
        var quiet = sine(440, amplitude: 0.02, seconds: 0.5)
        var loud = sine(440, amplitude: 0.9, seconds: 0.5)
        let c = Compressor(threshold: -22, ratio: 3)
        let quietBefore = rmsDB(quiet[12000...]), loudBefore = rmsDB(loud[12000...])
        c.process(&quiet, sampleRate: sr)
        c.process(&loud, sampleRate: sr)
        XCTAssertEqual(rmsDB(quiet[12000...]), quietBefore, accuracy: 0.1)
        XCTAssertLessThan(rmsDB(loud[12000...]), loudBefore - 6)
    }

    func testNoiseFloorIsTheQuietPart() {
        let x = noise(amplitude: 0.01, seconds: 1) + sine(300, amplitude: 0.5, seconds: 1)
        let floor = NoiseGate.noiseFloor(x, sampleRate: sr)!
        XCTAssertEqual(floor, 20 * log10(0.01 / sqrt(3)), accuracy: 1.5)
        XCTAssertNil(NoiseGate.noiseFloor([Float](repeating: 0, count: 48000), sampleRate: sr))
        XCTAssertEqual(NoiseGate.threshold(noiseFloor: -60), -50)
        XCTAssertEqual(NoiseGate.threshold(noiseFloor: -20), -25, "speech always opens the gate")
    }

    func testGateTurnsDownNoiseBetweenWordsAndKeepsTheVoice() {
        let gap = noise(amplitude: 0.01, seconds: 1)
        let word = zip(sine(300, amplitude: 0.4, seconds: 1), noise(amplitude: 0.01, seconds: 1)).map { $0 + $1 }
        var x = gap + word + gap
        // From half a second in: the gate has had time to close.
        let before = (gap: rmsDB(x[24000..<46000]), word: rmsDB(x[60000..<84000]))
        NoiseGate(reduction: 18).process(&x, sampleRate: sr)
        XCTAssertLessThan(rmsDB(x[24000..<46000]), before.gap - 15, "noise between words")
        XCTAssertEqual(rmsDB(x[60000..<84000]), before.word, accuracy: 0.5, "the word")
    }

    func testLimiterKeepsPeaksUnderTheCeiling() {
        var channels = [sine(200, amplitude: 1.5, seconds: 0.2), sine(200, amplitude: 0.2, seconds: 0.2)]
        Limiter.process(&channels, sampleRate: sr)
        XCTAssertLessThanOrEqual(Loudness.peak(channels[0]), Limiter.ceiling + 1e-6)
        XCTAssertLessThanOrEqual(Loudness.peak(channels[1]), Limiter.ceiling + 1e-6)
        var quiet = [sine(200, amplitude: 0.3, seconds: 0.2)]
        let copy = quiet
        Limiter.process(&quiet, sampleRate: sr)
        XCTAssertEqual(quiet, copy, "nothing to limit")
    }

    // MARK: Loudness

    func testLoudnessOfASine() {
        // A sine's mean square is half its amplitude squared.
        let l = Loudness.integrated(sine(1000, amplitude: 0.5, seconds: 2), sampleRate: sr)!
        XCTAssertEqual(l, 10 * log10(0.125), accuracy: 0.05)
        XCTAssertNil(Loudness.integrated([Float](repeating: 0, count: 96000), sampleRate: sr))
        XCTAssertNil(Loudness.integrated([0.1, 0.2], sampleRate: sr), "shorter than a block")
    }

    func testSilenceBetweenSentencesDoesNotCount() {
        let speech = sine(300, amplitude: 0.1, seconds: 2)
        let x = speech + [Float](repeating: 0, count: Int(4 * sr)) + speech
        XCTAssertEqual(Loudness.integrated(x, sampleRate: sr)!, Loudness.integrated(speech, sampleRate: sr)!, accuracy: 0.5)
    }

    func testNormalizingBringsAQuietVoiceToTheTarget() {
        var x = sine(300, amplitude: 0.02, seconds: 2)
        Loudness.normalize(&x, sampleRate: sr)
        XCTAssertEqual(Loudness.integrated(x, sampleRate: sr)!, Loudness.target, accuracy: 0.1)
    }

    func testNormalizingGainIsCapped() {
        XCTAssertEqual(Loudness.normalizingGain(loudness: -60, peak: 0.001), Loudness.maxGain)
        // Peaks at 0 dBFS: at most 5 dB over the -1 dBFS ceiling, whatever the loudness.
        XCTAssertEqual(Loudness.normalizingGain(loudness: -30, peak: 1), 20 * log10(Double(Limiter.ceiling)) + 6, accuracy: 1e-6)
        XCTAssertEqual(Loudness.normalizingGain(loudness: -10, peak: 0.5), -6, accuracy: 1e-9, "turns a loud voice down")
    }

    // MARK: Chain and mix

    func testPresetsBuildTheirChains() {
        XCTAssertFalse(VoiceChain(preset: .off, noiseRemoval: .off, sampleRate: sr).doesAnything)
        let gateOnly = VoiceChain(preset: .off, noiseRemoval: .low, sampleRate: sr)
        XCTAssertEqual(gateOnly.gate?.reduction, 10)
        XCTAssertFalse(gateOnly.normalizes)
        let voice = VoiceChain(preset: .voice, noiseRemoval: .high, sampleRate: sr)
        XCTAssertEqual(voice.highPass, 80)
        XCTAssertEqual(voice.gate?.reduction, 18)
        XCTAssertEqual(voice.eq.count, 3)
        XCTAssertTrue(voice.normalizes)
        XCTAssertEqual(VoiceChain(preset: .podcast, noiseRemoval: .off, sampleRate: sr).compressor?.ratio, 4)
    }

    func testOffLeavesTheVoiceAlone() {
        var x = sine(300, amplitude: 0.3, seconds: 0.5)
        let copy = x
        VoiceChain(preset: .off, noiseRemoval: .off, sampleRate: sr).process(&x, sampleRate: sr)
        XCTAssertEqual(x, copy)
    }

    func testVoicePresetLevelsAQuietVoice() {
        var x = sine(300, amplitude: 0.01, seconds: 3)
        VoiceChain(preset: .voice, noiseRemoval: .off, sampleRate: sr).process(&x, sampleRate: sr)
        XCTAssertEqual(Loudness.integrated(x, sampleRate: sr)!, Loudness.target, accuracy: 0.5)
    }

    func testMixPutsTheVoiceOnBothSidesWithGains() {
        let voice: [Float] = [0.1, 0.2, 0.3]
        let system: [[Float]] = [[0.1, 0, 0], [0, 0.1, 0]]
        let out = AudioMix.stereo(mono: [(voice, 2)], stereo: [(system, 0.5)], frames: 4, sampleRate: sr)
        assertClose(out[0], [0.25, 0.4, 0.6, 0].map { Float($0) }, accuracy: 1e-6)
        assertClose(out[1], [0.2, 0.45, 0.6, 0].map { Float($0) }, accuracy: 1e-6)
        let muted = AudioMix.stereo(mono: [(voice, 0)], stereo: [], frames: 3, sampleRate: sr)
        XCTAssertEqual(muted, [[0, 0, 0], [0, 0, 0]])
    }

    // MARK: Settings

    func testSourcesForOldAndNewRecordings() {
        XCTAssertEqual(AudioFinisher.sources([.microphone], trackCount: 1), [.microphone])
        XCTAssertEqual(AudioFinisher.sources([.system, .microphone], trackCount: 2), [.system, .microphone])
        XCTAssertEqual(AudioFinisher.sources(nil, trackCount: 1), [.mixed], "before #385: one mixed track")
        XCTAssertEqual(AudioFinisher.sources(nil, trackCount: 2), [.system, .microphone])
        XCTAssertEqual(AudioFinisher.sources([.microphone], trackCount: 2), [.system, .microphone], "doesn't match the file")
        XCTAssertEqual(AudioFinisher.sources(nil, trackCount: 0), [])
    }

    func testSettingsRoundTripAndDefaults() throws {
        var a = AudioSettings()
        XCTAssertTrue(a.isNeutral)
        a.preset = .podcast
        a.noiseRemoval = .high
        a.micVolume = 1.5
        XCTAssertFalse(a.isNeutral)
        let data = try JSONEncoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(AudioSettings.self, from: data), a)

        let partial = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"preset":"voice","micVolume":9}"#.utf8))
        XCTAssertEqual(partial.preset, .voice)
        XCTAssertEqual(partial.noiseRemoval, .off)
        XCTAssertEqual(partial.micVolume, AudioSettings.maxVolume, "clamped")
        let future = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"preset":"radio"}"#.utf8))
        XCTAssertEqual(future.preset, .off, "a preset from a newer Skreener")
        XCTAssertEqual(AudioSettings.percent(1.5), "150%")
    }

    func testStudioSettingsKeepTheAudio() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        s.audio.preset = .voice
        let read = try StudioSettings.decode(s.encoded(), project: project)
        XCTAssertEqual(read.audio.preset, .voice)
        XCTAssertEqual(s.withoutZoom, StudioSettings(project: project).withoutZoom, "audio doesn't change the picture")
    }

    func testProjectKeepsItsAudioTracks() throws {
        var project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        XCTAssertNil(try RecordingProject.decode(project.encoded()).audioTracks)
        project.audioTracks = [.system, .microphone]
        XCTAssertEqual(try RecordingProject.decode(project.encoded()).audioTracks, [.system, .microphone])
    }
}

private func assertClose(_ a: [Float], _ b: [Float], accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
