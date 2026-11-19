import XCTest
@testable import Skreener

/// The recording editor's export presets (#386): fitting the recording into each preset's frame, and where each
/// export is saved.
final class RecordingExportTests: XCTestCase {
    private let video = CGSize(width: 2880, height: 1800)

    func testAVerticalFrameFitsTheVideoCenteredWithoutABackground() {
        let l = StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: nil, frame: ExportPreset.vertical.frame)
        XCTAssertEqual(l.canvas, CGSize(width: 1080, height: 1920))
        // As wide as the frame, the video's own shape, in the middle.
        XCTAssertEqual(l.content.width, 1080, accuracy: 1e-6)
        XCTAssertEqual(l.content.height, 1080 * 1800 / 2880, accuracy: 1e-6)
        XCTAssertEqual(l.content.midY, 960, accuracy: 1e-6)
        XCTAssertEqual(l.content.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(l.pointScale, 2 * 1080 / 2880, accuracy: 1e-9)
    }

    func testAFrameKeepsTheBackgroundsPadding() {
        var bg = StudioBackground()
        bg.padding = 48
        let l = StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: bg, frame: ExportPreset.hd1080.frame)
        XCTAssertEqual(l.canvas, CGSize(width: 1920, height: 1080))
        let k = l.pointScale / 2
        // The padding, scaled with everything else, is still around the video.
        XCTAssertGreaterThanOrEqual(l.content.minX, 96 * k - 1e-6)
        XCTAssertGreaterThanOrEqual(l.content.minY, 96 * k - 1e-6)
        XCTAssertLessThanOrEqual(l.content.maxX, 1920 - 96 * k + 1e-6)
        XCTAssertLessThanOrEqual(l.content.maxY, 1080 - 96 * k + 1e-6)
        XCTAssertEqual(l.content.midX, 960, accuracy: 1e-6)
        XCTAssertEqual(l.content.midY, 540, accuracy: 1e-6)
        XCTAssertEqual(l.content.width / l.content.height, video.width / video.height, accuracy: 1e-6)
    }

    func testFourKStaysWithinWhatTheEncoderTakes() {
        let l = StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: nil, frame: ExportPreset.uhd4k.frame)
        XCTAssertEqual(l.canvas, CGSize(width: 3840, height: 2160))
        XCTAssertLessThanOrEqual(Int(l.canvas.width * l.canvas.height), ScreenRecorder.maxPixels)
    }

    func testNoFrameIsTheUsualLayout() {
        XCTAssertNil(ExportPreset.original.frame)
        XCTAssertNil(ExportPreset.gif.frame)
        XCTAssertEqual(StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: nil, frame: nil).canvas, video)
    }

    func testDestinations() {
        let rec = URL(fileURLWithPath: "/Movies/Demo.mp4")
        XCTAssertEqual(ExportPreset.original.destination(for: rec), rec)
        XCTAssertEqual(ExportPreset.gif.destination(for: rec).path, "/Movies/Demo.gif")
        XCTAssertEqual(ExportPreset.vertical.destination(for: rec).path, "/Movies/Demo (Vertical).mp4")
        XCTAssertEqual(ExportPreset.square.destination(for: rec).lastPathComponent, "Demo (Square).mp4")
        XCTAssertTrue(ExportPreset.original.replacesRecording)
        XCTAssertFalse(ExportPreset.hd1080.replacesRecording)
    }

    func testThePresetIsSavedAndChangesThePicture() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        s.exportPreset = .square
        XCTAssertEqual(try StudioSettings.decode(s.encoded(), project: project).exportPreset, .square)
        XCTAssertNotEqual(s.withoutZoom, StudioSettings(project: project).withoutZoom)
        let odd = try StudioSettings.decode(Data(#"{"version": 2, "exportPreset": "8k"}"#.utf8), project: project)
        XCTAssertEqual(odd.exportPreset, .original)
    }
}
