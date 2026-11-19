import AVFoundation
import XCTest
@testable import Skreener

/// Joining the recording with title cards, pictures and other videos (#384).
final class RecordingSequenceTests: XCTestCase {
    // MARK: Timing

    func testCutsPlaceClipsEndToEnd() {
        let p = ClipSequence.layout(durations: [3, 10, 2], crossfades: [false, false, false])
        XCTAssertEqual(p.map(\.start), [0, 3, 13])
        XCTAssertEqual(p.map(\.fadeIn), [0, 0, 0])
        XCTAssertEqual(ClipSequence.total(p), 15)
    }

    func testCrossfadesOverlapTheClipBefore() {
        let p = ClipSequence.layout(durations: [3, 10, 2], crossfades: [true, true, true], fade: 0.6)
        XCTAssertEqual(p[0], .init(start: 0, duration: 3, fadeIn: 0), "nothing to fade in from")
        XCTAssertEqual(p[1].start, 2.4, accuracy: 1e-9)
        XCTAssertEqual(p[1].fadeIn, 0.6, accuracy: 1e-9)
        XCTAssertEqual(p[2].start, 11.8, accuracy: 1e-9)
        XCTAssertEqual(ClipSequence.total(p), 13.8, accuracy: 1e-9)
    }

    func testCrossfadeNeverTakesMoreThanHalfAShortClip() {
        let p = ClipSequence.layout(durations: [0.5, 4, 0.8], crossfades: [false, true, true], fade: 0.6)
        XCTAssertEqual(p[1].fadeIn, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p[2].fadeIn, 0.4, accuracy: 1e-9)
        // At most two clips at once: each starts after the one two before ends.
        XCTAssertGreaterThanOrEqual(p[2].start, p[0].end)
    }

    func testBadLengthsCountAsNothing() {
        let p = ClipSequence.layout(durations: [.nan, -2, 3], crossfades: [false, true, true])
        XCTAssertEqual(p.map(\.duration), [0, 0, 3])
        XCTAssertEqual(ClipSequence.total(p), 3)
        XCTAssertEqual(ClipSequence.total([]), 0)
    }

    // MARK: Tidying

    func testEmptyStaysEmpty() {
        XCTAssertEqual(ClipSequence.tidy([]), [])
        XCTAssertFalse(ClipSequence.joins([]))
    }

    func testTidyKeepsExactlyOneRecording() {
        let title = SequenceClip(kind: .title, title: "Intro")
        let tidy = ClipSequence.tidy([title, SequenceClip(kind: .recording), SequenceClip(kind: .recording)])
        XCTAssertEqual(tidy.map(\.kind), [.title, .recording])
        let added = ClipSequence.tidy([title])
        XCTAssertEqual(added.map(\.kind), [.recording, .title], "the recording goes first when it's missing")
    }

    func testTidyDropsFilesWithoutAPathAndClampsLengths() {
        let tidy = ClipSequence.tidy([
            SequenceClip(kind: .recording),
            SequenceClip(kind: .video),
            SequenceClip(kind: .still, path: ""),
            SequenceClip(kind: .still, path: "/tmp/a.png", duration: 0.1),
            SequenceClip(kind: .title, duration: 500),
            SequenceClip(kind: .title, duration: .infinity),
        ])
        XCTAssertEqual(tidy.map(\.kind), [.recording, .still, .title, .title])
        XCTAssertEqual(tidy.map(\.duration), [ClipSequence.defaultStill, ClipSequence.minStill, ClipSequence.maxStill,
                                              ClipSequence.defaultStill])
    }

    func testTidyNeverFadesIntoTheFirstClip() {
        let tidy = ClipSequence.tidy([SequenceClip(kind: .title, crossfade: true), SequenceClip(kind: .recording)])
        XCTAssertFalse(tidy[0].crossfade)
        XCTAssertTrue(tidy[1].crossfade)
    }

    func testJoinsOnlyWithMoreThanTheRecording() {
        XCTAssertFalse(ClipSequence.joins([SequenceClip(kind: .recording)]))
        XCTAssertTrue(ClipSequence.joins([SequenceClip(kind: .recording), SequenceClip(kind: .title)]))
    }

    func testNamesAndLengths() {
        XCTAssertEqual(SequenceClip(kind: .recording).name, "This recording")
        XCTAssertEqual(SequenceClip(kind: .title).name, "Title card")
        XCTAssertEqual(SequenceClip(kind: .title, title: "Setup").name, "Title: Setup")
        XCTAssertEqual(SequenceClip(kind: .still, path: "/tmp/Shot.png").name, "Shot.png")
        XCTAssertTrue(SequenceClip(kind: .still, path: "/x.png").hasDuration)
        XCTAssertFalse(SequenceClip(kind: .video, path: "/x.mp4").hasDuration)
        XCTAssertEqual(ClipSequence.lengthText(3), "3 s")
        XCTAssertEqual(ClipSequence.lengthText(1.5), "1.5 s")
    }

    // MARK: Saving

    func testUnknownKindReadsAsATitleAndMissingValuesKeepDefaults() throws {
        let clip = try JSONDecoder().decode(SequenceClip.self, from: Data(#"{"kind":"hologram","title":"Hi"}"#.utf8))
        XCTAssertEqual(clip.kind, .title)
        XCTAssertEqual(clip.title, "Hi")
        XCTAssertEqual(clip.duration, ClipSequence.defaultStill)
        XCTAssertTrue(clip.crossfade)
    }

    func testStudioSettingsKeepTheSequence() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        s.sequence = [SequenceClip(kind: .title, title: "Intro", subtitle: "Part 1", duration: 4),
                      SequenceClip(kind: .recording),
                      SequenceClip(kind: .still, path: "/tmp/Shot.png", crossfade: false)]
        let read = try StudioSettings.decode(s.encoded(), project: project)
        XCTAssertEqual(read.sequence, ClipSequence.tidy(s.sequence))
        XCTAssertEqual(read.sequence[0].subtitle, "Part 1")
        XCTAssertEqual(s.withoutZoom, StudioSettings(project: project).withoutZoom, "the sequence keeps the background")
    }

    // MARK: Making the video

    private func image(width: Int, height: Int, red: Bool) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red ? CGColor(red: 1, green: 0, blue: 0, alpha: 1) : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testStillsAreJoinedWithACrossfade() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.mp4"), b = dir.appendingPathComponent("b.mp4")
        try await SequenceJoiner.writeStill(image(width: 320, height: 240, red: true), seconds: 2, fps: 30, to: a)
        try await SequenceJoiner.writeStill(image(width: 160, height: 160, red: false), seconds: 2, fps: 30, to: b)
        let still = try await AVURLAsset(url: a).load(.duration).seconds
        XCTAssertEqual(still, 2, accuracy: 0.1)

        let out = dir.appendingPathComponent("joined.mp4")
        try await SequenceJoiner.join([a, b], crossfades: [false, true], canvas: CGSize(width: 320, height: 240), fps: 30, to: out)
        let joined = AVURLAsset(url: out)
        let duration = try await joined.load(.duration).seconds
        XCTAssertEqual(duration, 2 + 2 - ClipSequence.crossfade, accuracy: 0.15)
        let track = try await joined.loadTracks(withMediaType: .video).first
        let size = try await track?.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 240))
    }
}
