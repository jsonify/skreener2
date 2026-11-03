import AVFoundation
import XCTest
@testable import Skreener

final class RecordingRendererTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    /// The times the renderer asked to draw, from its own queue.
    private final class Times: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func add(_ t: Double) { lock.lock(); values.append(t); lock.unlock() }
        var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
    }

    func testRendersAConstantFrameRateAndDrawsOnEveryFrame() async throws {
        let clean = dir.appendingPathComponent("clean.mp4")
        // Like a screen recording of a still screen: only two frames in one second.
        try await writeClip(to: clean, frameTimes: [0, 0.5], duration: 1)
        let out = dir.appendingPathComponent("out.mp4")
        let times = Times()
        try await RecordingRenderer.render(video: clean, fps: 10, to: out) { ctx, t in
            times.add(t)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
        let drawn = times.all
        XCTAssertEqual(drawn.count, 10)
        for (i, t) in drawn.enumerated() { XCTAssertEqual(t, Double(i) / 10, accuracy: 1e-6) }

        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.15)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames = 0
        var firstPixels: (left: [UInt8], right: [UInt8])?
        while let sb = output.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(sb) else { continue }
            if firstPixels == nil {
                CVPixelBufferLockBaseAddress(image, .readOnly)
                let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to: UInt8.self)
                let row = CVPixelBufferGetBytesPerRow(image)
                let pixel = { (x: Int, y: Int) in (0..<4).map { base[y * row + x * 4 + $0] } }
                firstPixels = (pixel(20, 60), pixel(140, 60))
                CVPixelBufferUnlockBaseAddress(image, .readOnly)
            }
            frames += 1
        }
        XCTAssertEqual(frames, 10)
        let pixels = try XCTUnwrap(firstPixels)
        // BGRA: drawn red on the left, the clip's gray on the right.
        XCTAssertGreaterThan(pixels.left[2], 180)
        XCTAssertLessThan(pixels.left[1], 90)
        XCTAssertEqual(Int(pixels.right[1]), 128, accuracy: 20)
        XCTAssertEqual(Int(pixels.right[2]), 128, accuracy: 20)
    }

    func testOverlayDrawsTheEffectsWhereTheyBelong() throws {
        // A 400 × 300 pt area recorded at 2×.
        var style = EffectsStyle(clicks: true, keystrokes: true)
        style.cursor = false
        let project = RecordingProject(created: Date(), area: CGRect(x: 0, y: 0, width: 400, height: 300), screenScale: 2,
                                       videoWidth: 800, videoHeight: 600, fps: 30, style: style)
        var events = RecordingEvents()
        events.clicks = [.init(t: 0, x: 100, y: 100, button: .left, down: true)]
        events.keys = [.init(t: 0, text: "⌘S", append: false)]
        let overlay = EffectsOverlay(project: project, events: events, folder: nil)
        XCTAssertTrue(overlay.drawsAnything)

        let alpha = try render(overlay, at: 0.1)
        XCTAssertGreaterThan(alpha(100, 100), 0, "the ring around the click")
        XCTAssertGreaterThan(alpha(400, 600 - 60), 150, "the keystroke pill near the bottom")
        XCTAssertEqual(alpha(790, 10), 0, "nothing in the corner")
        let later = try render(overlay, at: 3)
        XCTAssertEqual(later(100, 100), 0, "the ring is gone")
        XCTAssertEqual(later(400, 600 - 60), 0, "the pill is hidden")
    }

    func testOverlayDimsAroundThePointerWithTheSpotlight() throws {
        var style = EffectsStyle()
        style.cursor = false
        style.spotlightDim = 0.5
        let project = RecordingProject(created: Date(), area: CGRect(x: 0, y: 0, width: 400, height: 300), screenScale: 2,
                                       videoWidth: 800, videoHeight: 600, fps: 30, style: style)
        var events = RecordingEvents()
        events.cursor = [.init(t: 0, x: 400, y: 300, visible: true)]
        events.spotlightAtStart = true
        let overlay = EffectsOverlay(project: project, events: events, folder: nil)
        XCTAssertTrue(overlay.drawsAnything)
        let alpha = try render(overlay, at: 0)
        XCTAssertEqual(alpha(400, 300), 0, "clear around the pointer")
        XCTAssertEqual(Int(alpha(5, 5)), 128, accuracy: 3, "dimmed elsewhere")
    }

    func testOverlayWithNothingToDrawSaysSo() {
        var style = EffectsStyle()
        style.cursor = false
        let project = RecordingProject(created: Date(), area: CGRect(x: 0, y: 0, width: 100, height: 100), screenScale: 1,
                                       videoWidth: 100, videoHeight: 100, fps: 30, style: style)
        var events = RecordingEvents()
        events.cursor = [.init(t: 0, x: 1, y: 1, visible: true)]
        events.clicks = [.init(t: 0, x: 1, y: 1, button: .left, down: true)]
        XCTAssertFalse(EffectsOverlay(project: project, events: events, folder: nil).drawsAnything)
    }

    /// Draws `overlay` at `t` on a clear 800 × 600 canvas; returns the alpha at a video point (top-left origin).
    private func render(_ overlay: EffectsOverlay, at t: Double) throws -> (Int, Int) -> UInt8 {
        let w = Int(overlay.videoSize.width), h = Int(overlay.videoSize.height)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        overlay.draw(in: ctx, at: t)
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: data, count: w * h * 4))
        // The bitmap's first row is the top of the picture.
        return { x, y in bytes[y * w * 4 + x * 4 + 3] }
    }

    /// A 160 × 120 gray H.264 clip with frames only at `frameTimes`, `duration` seconds long.
    private func writeClip(to url: URL, frameTimes: [Double], duration: Double) async throws {
        let width = 160, height = 120
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        writer.add(video)
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        for t in frameTimes {
            while !video.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, 128, CVPixelBufferGetDataSize(pixels)) }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)))
        }
        video.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }
}
