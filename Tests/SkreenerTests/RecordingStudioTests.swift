import AppKit
import AVFoundation
import XCTest
@testable import Skreener

final class RecordingStudioTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func project(width: Int = 1280, height: Int = 720, scale: Double = 2, exported: String? = nil,
                         created: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> RecordingProject {
        RecordingProject(created: created, area: CGRect(x: 0, y: 0, width: Double(width) / scale, height: Double(height) / scale),
                         screenScale: scale, videoWidth: width, videoHeight: height, fps: 10,
                         style: EffectsStyle(clicks: true, keystrokes: true), exported: exported)
    }

    // MARK: Layout

    func testWithoutABackgroundTheCanvasIsTheVideo() {
        let l = StudioLayout.make(videoSize: CGSize(width: 1280, height: 720), pixelsPerPoint: 2, background: nil)
        XCTAssertEqual(l.canvas, CGSize(width: 1280, height: 720))
        XCTAssertEqual(l.content, CGRect(x: 0, y: 0, width: 1280, height: 720))
        XCTAssertEqual(l.pointScale, 2)
    }

    func testPaddingIsInScreenPointsOnEverySide() {
        var bg = StudioBackground()
        bg.padding = 48
        let l = StudioLayout.make(videoSize: CGSize(width: 1280, height: 720), pixelsPerPoint: 2, background: bg)
        // 48 pt at 2 px per point is 96 px each side.
        XCTAssertEqual(l.canvas, CGSize(width: 1472, height: 912))
        XCTAssertEqual(l.content, CGRect(x: 96, y: 96, width: 1280, height: 720))
        XCTAssertEqual(l.pointScale, 2)
    }

    func testAnAspectRatioGrowsTheCanvasAroundTheCenteredVideo() {
        var bg = StudioBackground()
        bg.padding = 16
        bg.aspect = [1, 1]
        let l = StudioLayout.make(videoSize: CGSize(width: 1280, height: 720), pixelsPerPoint: 2, background: bg)
        XCTAssertEqual(l.canvas.width, l.canvas.height)
        XCTAssertEqual(Int(l.canvas.width) % 2, 0)
        XCTAssertTrue(CGRect(origin: .zero, size: l.canvas).contains(l.content.insetBy(dx: -32, dy: -32)))
        XCTAssertEqual(l.content.size, CGSize(width: 1280, height: 720))
        XCTAssertLessThanOrEqual(abs(l.content.minY - (l.canvas.height - l.content.maxY)), 1, "centered vertically")
    }

    func testABigCanvasIsScaledDownToWhatH264TakesWithEvenSides() {
        var bg = StudioBackground()
        bg.padding = 128
        let video = CGSize(width: 4096, height: 2304)
        let l = StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: bg)
        XCTAssertLessThanOrEqual(Int(l.canvas.width) * Int(l.canvas.height), ScreenRecorder.maxPixels)
        XCTAssertEqual(Int(l.canvas.width) % 2, 0)
        XCTAssertEqual(Int(l.canvas.height) % 2, 0)
        XCTAssertLessThan(l.pointScale, 2)
        // The video keeps its shape and fits with its padding.
        XCTAssertEqual(l.content.width / l.content.height, video.width / video.height, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(l.content.minX, 0)
        XCTAssertLessThanOrEqual(l.content.maxX, l.canvas.width + 1e-6)
        XCTAssertLessThanOrEqual(l.content.maxY, l.canvas.height + 1e-6)
        XCTAssertEqual(l.content.minX, 128 * l.pointScale, accuracy: 1)
    }

    func testOddSizesComeOutEven() {
        var bg = StudioBackground()
        bg.padding = 16
        bg.aspect = [1200, 627]
        let l = StudioLayout.make(videoSize: CGSize(width: 801, height: 517), pixelsPerPoint: 1, background: bg)
        XCTAssertEqual(Int(l.canvas.width) % 2, 0)
        XCTAssertEqual(Int(l.canvas.height) % 2, 0)
    }

    func testVideoPointsMapIntoTheContent() {
        var bg = StudioBackground()
        bg.padding = 50
        let l = StudioLayout.make(videoSize: CGSize(width: 200, height: 100), pixelsPerPoint: 1, background: bg)
        // Top-left of the video (event coordinates) is the content's top-left, in the canvas's bottom-left origin.
        XCTAssertEqual(l.canvasPoint(video: .zero), CGPoint(x: 50, y: 150))
        XCTAssertEqual(l.canvasPoint(video: CGPoint(x: 200, y: 100)), CGPoint(x: 250, y: 50))
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(l.transform()), CGPoint(x: 50, y: 50))
    }

    func testACropShowsThatPartOfTheVideoInTheContent() {
        let l = StudioLayout.make(videoSize: CGSize(width: 200, height: 100), pixelsPerPoint: 1, background: nil)
        // The top-left quarter, zoomed to fill the frame.
        let crop = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(l.canvasPoint(video: .zero, crop: crop), CGPoint(x: 0, y: 100))
        XCTAssertEqual(l.canvasPoint(video: CGPoint(x: 100, y: 50), crop: crop), CGPoint(x: 200, y: 0))
        XCTAssertEqual(l.canvasPoint(video: CGPoint(x: 50, y: 25), crop: crop), CGPoint(x: 100, y: 50))
    }

    func testPreviewScaleAndTimecode() {
        XCTAssertEqual(StudioLayout.previewScale(canvas: CGSize(width: 2560, height: 1440), fitting: CGSize(width: 1280, height: 800)), 0.5)
        XCTAssertEqual(StudioLayout.previewScale(canvas: CGSize(width: 640, height: 480), fitting: CGSize(width: 1280, height: 800)), 1)
        XCTAssertEqual(StudioLayout.timecode(0), "0:00.0")
        XCTAssertEqual(StudioLayout.timecode(65.37), "1:05.3")
        XCTAssertEqual(StudioLayout.timecode(3723.4), "1:02:03.4")
        XCTAssertEqual(StudioLayout.timecode(.nan), "0:00.0")
    }

    // MARK: Settings

    func testSettingsStartWithoutABackgroundAndTheRecordedEffects() {
        let p = project()
        let s = StudioSettings(project: p)
        XCTAssertFalse(s.backgroundOn)
        XCTAssertEqual(s.effects, p.style)
        XCTAssertTrue(s.spotlight)
    }

    func testSettingsRoundTrip() throws {
        let p = project()
        var s = StudioSettings(project: p)
        s.backgroundOn = true
        s.background.fill = Background.customFill
        s.background.padding = 64
        s.background.aspect = [16, 9]
        s.background.imagePath = "/tmp/x.png"
        s.effects.clicks = false
        s.effects.keystrokesAtTop = true
        s.spotlight = false
        XCTAssertEqual(try StudioSettings.decode(s.encoded(), project: p), s)
    }

    func testSettingsFromANewerSkreenerAreRefused() {
        let newer = Data(#"{"version": 99}"#.utf8)
        XCTAssertThrowsError(try StudioSettings.decode(newer, project: project())) {
            XCTAssertEqual($0 as? RecordingFileError, .newerVersion(99))
        }
        XCTAssertThrowsError(try StudioSettings.decode(Data("{}".utf8), project: project())) {
            XCTAssertEqual($0 as? RecordingFileError, .notARecordingFile)
        }
    }

    func testMissingSettingsKeepTheirDefaults() throws {
        let p = project()
        let s = try StudioSettings.decode(Data(#"{"version": 1, "backgroundOn": true, "background": {"padding": 16}}"#.utf8), project: p)
        XCTAssertTrue(s.backgroundOn)
        XCTAssertEqual(s.background.padding, 16)
        XCTAssertEqual(s.background.cornerRadius, StudioBackground().cornerRadius)
        XCTAssertEqual(s.effects, p.style)
    }

    func testSettingsAreSavedInTheProjectFolder() throws {
        let p = project()
        XCTAssertEqual(StudioSettings.load(folder: dir, project: p), StudioSettings(project: p), "defaults without a file")
        var s = StudioSettings(project: p)
        s.backgroundOn = true
        try s.save(folder: dir)
        XCTAssertEqual(StudioSettings.load(folder: dir, project: p), s)
    }

    func testTheBackgroundRoundTripsThroughTheEditorsBackground() {
        var b = Background()
        b.fill = Background.customFill
        b.colors = [NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)]
        b.direction = .radial
        b.aspect = Background.Aspect(width: 4, height: 3)
        b.padding = 64; b.cornerRadius = 16; b.shadow = 0.8; b.imageBlur = 15
        let back = StudioBackground(b).background
        XCTAssertEqual(back, b)
    }

    // MARK: Finding the project

    func testAProjectMadeTheFileAtItsExportedPathOrWhereItWasFiled() {
        let file = URL(fileURLWithPath: "/Users/me/Desktop/Rec.mp4")
        XCTAssertTrue(RecordingProject.made(file, exported: "/Users/me/Desktop/Rec.mp4"))
        XCTAssertTrue(RecordingProject.made(file, exported: "/Users/me/Desktop/./Rec.mp4"))
        XCTAssertFalse(RecordingProject.made(file, exported: "/Users/me/Desktop/Other.mp4"))
        XCTAssertFalse(RecordingProject.made(file, exported: nil))
        XCTAssertFalse(RecordingProject.made(file, exported: ""))
        let filed = URL(fileURLWithPath: "/Users/me/Videos/Rec.mp4")
        XCTAssertTrue(RecordingProject.made(filed, exported: file.path) { $0.path == file.path ? filed : $0 })
    }

    func testTheFirstMatchingProjectIsFound() {
        let file = URL(fileURLWithPath: "/tmp/Rec.mp4")
        let a = URL(fileURLWithPath: "/p/a.skreenerrec"), b = URL(fileURLWithPath: "/p/b.skreenerrec")
        XCTAssertEqual(RecordingProject.projectFolder(for: file, in: [(a, nil), (b, "/tmp/Rec.mp4")]), b)
        XCTAssertNil(RecordingProject.projectFolder(for: file, in: [(a, "/tmp/Other.mp4")]))
    }

    @MainActor func testLookupReadsTheProjectFolders() throws {
        func make(_ name: String, exported: String?, created: Double, video: Bool = true) throws -> URL {
            let folder = dir.appendingPathComponent("\(name).skreenerrec")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try project(exported: exported, created: Date(timeIntervalSince1970: created)).encoded()
                .write(to: folder.appendingPathComponent(RecordingProject.projectFile))
            if video { try Data().write(to: folder.appendingPathComponent(RecordingProject.videoFile)) }
            return folder
        }
        let file = dir.appendingPathComponent("Rec.mp4")
        _ = try make("old", exported: file.path, created: 1)
        let new = try make("new", exported: file.path, created: 2)
        _ = try make("other", exported: dir.appendingPathComponent("Other.mp4").path, created: 3)
        _ = try make("novideo", exported: dir.appendingPathComponent("Gone.mp4").path, created: 4, video: false)
        XCTAssertEqual(RecordingProjectLookup.folder(for: file, in: dir)?.resolvingSymlinksInPath().path,
                       new.resolvingSymlinksInPath().path, "the newest project that made it")
        XCTAssertNil(RecordingProjectLookup.folder(for: dir.appendingPathComponent("Nope.mp4"), in: dir))
        XCTAssertNil(RecordingProjectLookup.folder(for: dir.appendingPathComponent("Gone.mp4"), in: dir), "no clean video left")
    }

    // MARK: Drawing

    @MainActor func testTheCompositorDrawsTheBackgroundAroundTheRecording() throws {
        let p = project(width: 200, height: 100, scale: 1)
        var s = StudioSettings(project: p)
        s.effects.cursor = false
        s.backgroundOn = true
        s.background.fill = Background.presets.firstIndex { $0.name == "White" } ?? 0
        s.background.padding = 20
        s.background.cornerRadius = 10
        s.background.shadow = 0
        let c = StudioCompositor(project: p, events: RecordingEvents(), folder: nil, settings: s)
        XCTAssertEqual(c.size, CGSize(width: 240, height: 140))
        XCTAssertTrue(c.changesTheVideo)
        let pixel = try draw(c, source: solid(width: 200, height: 100, red: 1))
        XCTAssertEqual(pixel(5, 5), [255, 255, 255], "the background in the padding")
        XCTAssertEqual(pixel(120, 70), [255, 0, 0], "the recording in the middle")
        XCTAssertEqual(pixel(21, 21), [255, 255, 255], "the background past the rounded corner")
    }

    @MainActor func testWithoutABackgroundTheCompositorDrawsJustTheRecording() throws {
        let p = project(width: 200, height: 100, scale: 1)
        var s = StudioSettings(project: p)
        s.effects.cursor = false
        let c = StudioCompositor(project: p, events: RecordingEvents(), folder: nil, settings: s)
        XCTAssertEqual(c.size, CGSize(width: 200, height: 100))
        let pixel = try draw(c, source: solid(width: 200, height: 100, red: 1))
        XCTAssertEqual(pixel(0, 0), [255, 0, 0])
        XCTAssertEqual(pixel(199, 99), [255, 0, 0])
    }

    @MainActor func testThePreviewIsTheSameFrameSmaller() throws {
        let p = project(width: 200, height: 100, scale: 1)
        var s = StudioSettings(project: p)
        s.backgroundOn = true
        s.background.padding = 20
        let c = StudioCompositor(project: p, events: RecordingEvents(), folder: nil, settings: s, scale: 0.5)
        XCTAssertEqual(c.size, CGSize(width: 120, height: 70))
        XCTAssertEqual(c.layout.canvas, CGSize(width: 240, height: 140))
    }

    @MainActor func testExportComposesEveryFrameOnTheBiggerCanvasAndKeepsTheLength() async throws {
        let folder = dir.appendingPathComponent("p.skreenerrec")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await writeClip(to: folder.appendingPathComponent(RecordingProject.videoFile), frameTimes: [0, 0.3], duration: 1)
        let p = project(width: 160, height: 120, scale: 1)
        var s = StudioSettings(project: p)
        s.backgroundOn = true
        s.background.padding = 20
        let c = StudioCompositor(project: p, events: RecordingEvents(), folder: folder, settings: s)
        let out = dir.appendingPathComponent("out.mp4")
        let last = Last()
        try await RecordingRenderer.render(folder: folder, fps: 10, compositor: c, to: out) { last.set($0) }
        XCTAssertEqual(last.value, 1)
        let asset = AVURLAsset(url: out)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 200, height: 160))
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.15)
    }

    // MARK: Helpers

    private final class Last: @unchecked Sendable {
        private let lock = NSLock()
        private var v = 0.0
        func set(_ x: Double) { lock.lock(); v = x; lock.unlock() }
        var value: Double { lock.lock(); defer { lock.unlock() }; return v }
    }

    private func solid(width: Int, height: Int, red: CGFloat) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(CGColor(srgbRed: red, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// Draws `c` at 0; returns the RGB at a canvas point (bottom-left origin).
    @MainActor private func draw(_ c: StudioCompositor, source: CGImage) throws -> (Int, Int) -> [UInt8] {
        let w = Int(c.size.width), h = Int(c.size.height)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        c.draw(in: ctx, source: source, at: 0)
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: data, count: w * h * 4))
        // BGRA, first row at the top.
        return { x, y in
            let i = (h - 1 - y) * w * 4 + x * 4
            return [bytes[i + 2], bytes[i + 1], bytes[i]]
        }
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
