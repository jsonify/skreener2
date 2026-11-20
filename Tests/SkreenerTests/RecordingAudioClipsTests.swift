import AVFoundation
import XCTest
@testable import Skreener

/// Audio files added in the recording editor: a voiceover, music.
final class RecordingAudioClipsTests: XCTestCase {
    private func clip(start: Double = 2, length: Double = 4, offset: Double = 0, fileLength: Double? = nil) -> AudioClip {
        AudioClip(file: "a.m4a", name: "Voiceover.m4a", start: start, length: length, offset: offset, fileLength: fileLength)
    }

    func testSplitMakesTwoPiecesThatPlayOnFromEachOther() throws {
        let (a, b) = try XCTUnwrap(AudioClips.split(clip(), at: 3.5))
        XCTAssertEqual(a.start, 2)
        XCTAssertEqual(a.length, 1.5)
        XCTAssertEqual(a.offset, 0)
        XCTAssertEqual(b.start, 3.5)
        XCTAssertEqual(b.length, 2.5)
        XCTAssertEqual(b.offset, 1.5)
        XCTAssertEqual(b.fileLength, 4)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNil(AudioClips.split(clip(), at: 2.05), "too close to the start")
        XCTAssertNil(AudioClips.split(clip(), at: 7), "outside it")
    }

    func testTrimmingStaysInsideTheFile() {
        let piece = clip(start: 5, length: 2, offset: 1, fileLength: 4)
        // The start can go back as far as the file's beginning.
        let earlier = AudioClips.trimmed(piece, start: true, to: 0)
        XCTAssertEqual(earlier.start, 4)
        XCTAssertEqual(earlier.offset, 0)
        XCTAssertEqual(earlier.length, 3)
        // And the end as far as the file's end.
        let longer = AudioClips.trimmed(piece, start: false, to: 100)
        XCTAssertEqual(longer.length, 3)
        let shorter = AudioClips.trimmed(piece, start: false, to: 6)
        XCTAssertEqual(shorter.length, 1)
        let tiny = AudioClips.trimmed(piece, start: true, to: 100)
        XCTAssertEqual(tiny.length, AudioClips.minLength, accuracy: 1e-9)
        XCTAssertEqual(tiny.end, piece.end, accuracy: 1e-9, "the other end stays put")
    }

    func testMovedStaysInTheRecording() {
        XCTAssertEqual(AudioClips.moved(clip(), to: -3, duration: 10).start, 0)
        XCTAssertEqual(AudioClips.moved(clip(), to: 50, duration: 10).start, 9.9, accuracy: 1e-9)
        XCTAssertEqual(AudioClips.moved(clip(), to: 4, duration: 10).start, 4)
    }

    func testTidySortsAndDropsBrokenClips() {
        var loud = clip(start: 5)
        loud.volume = 9
        var nothing = clip(start: 1)
        nothing.length = 0
        var noFile = clip(start: 0)
        noFile.file = ""
        let tidy = AudioClips.tidy([loud, nothing, noFile, clip(start: 1)])
        XCTAssertEqual(tidy.map(\.start), [1, 5])
        XCTAssertEqual(tidy[1].volume, AudioSettings.maxVolume)
    }

    func testPlacedPutsTheSoundAtItsStartAndCutsItAtTheEnd() {
        let placed = AudioClips.placed([1, 1, 1, 1], at: 0.5, frames: 4, sampleRate: 4)
        XCTAssertEqual(placed, [0, 0, 1, 1])
        XCTAssertEqual(AudioClips.placed([1], at: 10, frames: 3, sampleRate: 4), [0, 0, 0])
    }

    func testTrackRowsKeepOverlappingClipsApart() {
        XCTAssertEqual(AudioClipTrackView.rows([clip(start: 0), clip(start: 1), clip(start: 10)]), [0, 1, 0])
    }

    func testClipsAreSavedAndMakeTheAudioNeedWork() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        XCTAssertTrue(s.audio.isNeutral)
        var c = clip(start: 1, length: 2, offset: 0.5, fileLength: 3)
        c.cleanup = false
        c.volume = 0.5
        s.audio.clips = [c]
        XCTAssertFalse(s.audio.isNeutral)
        let read = try StudioSettings.decode(s.encoded(), project: project)
        XCTAssertEqual(read.audio.clips, [c])
    }

    // MARK: Export

    /// A mono 440 Hz tone of `seconds` as a WAV file.
    private func tone(seconds: Double, to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let p = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<Int(frames) { p[i] = 0.3 * sin(2 * .pi * 440 * Float(i) / 48_000) }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        try file.write(from: buffer)
    }

    /// The loudest sample of `url`'s audio in each half second.
    private func loudness(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var peaks: [Float] = []
        var n = 0
        while let sb = output.copyNextSampleBuffer() {
            try sb.withAudioBufferList { list, _ in
                guard let b = list.first, let data = b.mData else { return }
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<(Int(b.mDataByteSize) / 4) {
                    let slot = n / 24_000
                    while peaks.count <= slot { peaks.append(0) }
                    peaks[slot] = max(peaks[slot], abs(p[i]))
                    n += 1
                }
            }
        }
        return peaks
    }

    func testExportMixesAPieceOfTheFileInWhereItIs() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A silent 3-second video, and a 2-second tone added from 1.5 s, trimmed to its first second.
        let video = dir.appendingPathComponent("video.mp4")
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        try await SequenceJoiner.writeStill(try XCTUnwrap(ctx.makeImage()), seconds: 3, fps: 30, to: video)
        let source = dir.appendingPathComponent("Tone.wav")
        try tone(seconds: 2, to: source)
        var clip = try await AudioClips.add(source, to: dir, at: 1.5)
        XCTAssertEqual(clip.length, 2, accuracy: 0.01)
        clip.length = 1
        clip.cleanup = false
        var settings = AudioSettings()
        settings.clips = [clip]
        try await AudioFinisher.finish(video, sources: [], settings: settings, folder: dir)

        let peaks = try await loudness(video)
        XCTAssertGreaterThanOrEqual(peaks.count, 5)
        XCTAssertLessThan(peaks[0], 0.01, "silent before the clip")
        XCTAssertLessThan(peaks[1], 0.01)
        XCTAssertGreaterThan(peaks[3], 0.1, "the tone from 1.5 s")
        XCTAssertGreaterThan(peaks[4], 0.1)
        if peaks.count > 5 { XCTAssertLessThan(peaks[5], 0.05, "trimmed to one second") }
    }
}
