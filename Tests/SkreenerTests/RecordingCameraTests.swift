import XCTest
@testable import Skreener

/// The webcam overlay drawn by the recording editor (#25).
final class RecordingCameraTests: XCTestCase {
    private let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                           screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())

    // MARK: Hiding for a while

    func testHiddenStretchesMergeAndSplit() {
        var c = CameraOverlay().hiding(from: 5, to: 2).hiding(from: 4, to: 8).hiding(from: 10, to: 12)
        XCTAssertEqual(c.hidden, [CameraHide(start: 2, end: 8), CameraHide(start: 10, end: 12)])
        c = c.showing(from: 3, to: 6)
        XCTAssertEqual(c.hidden, [CameraHide(start: 2, end: 3), CameraHide(start: 6, end: 8), CameraHide(start: 10, end: 12)])
        c = c.showing(from: 0, to: 20)
        XCTAssertEqual(c.hidden, [])
    }

    func testHidesTellsWhetherARangeTouchesAHiddenStretch() {
        let c = CameraOverlay().hiding(from: 2, to: 4)
        XCTAssertTrue(c.hides(from: 3, to: 10))
        XCTAssertFalse(c.hides(from: 4, to: 10))
        XCTAssertFalse(c.hides(from: 0, to: 2))
    }

    func testOpacityFadesAroundAHiddenStretch() {
        let c = CameraOverlay().hiding(from: 2, to: 4)
        XCTAssertEqual(c.opacity(at: 0), 1)
        XCTAssertEqual(c.opacity(at: 2 - CameraOverlay.fade / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.opacity(at: 3), 0)
        XCTAssertEqual(c.opacity(at: 4 + CameraOverlay.fade / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.opacity(at: 6), 1)
        var off = c
        off.shown = false
        XCTAssertEqual(off.opacity(at: 0), 0)
    }

    // MARK: Where it goes

    func testCircleIsSizedByTheShorterSideAndKeptOnTheCanvas() {
        var c = CameraOverlay()
        c.size = 0.25
        c.x = 1
        c.y = 0
        let r = c.rect(canvas: CGSize(width: 1600, height: 900), aspect: 16.0 / 9)
        XCTAssertEqual(r.size, CGSize(width: 225, height: 225))
        XCTAssertEqual(r.maxX, 1600)
        XCTAssertEqual(r.minY, 0)
    }

    func testRoundedRectangleHasTheCamerasShape() {
        var c = CameraOverlay()
        c.shape = .rounded
        c.size = 0.2
        c.x = 0.5
        c.y = 0.5
        let r = c.rect(canvas: CGSize(width: 1000, height: 1000), aspect: 16.0 / 9)
        XCTAssertEqual(r.height, 200, accuracy: 1e-9)
        XCTAssertEqual(r.width, 200 * 16 / 9, accuracy: 1e-9)
        XCTAssertEqual(r.midX, 500, accuracy: 1e-9)
    }

    func testMovedFollowsThePointerAndStaysInRange() {
        let canvas = CGSize(width: 800, height: 400)
        let c = CameraOverlay().moved(to: CGPoint(x: 200, y: 100), canvas: canvas)
        XCTAssertEqual(c.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(c.y, 0.25, accuracy: 1e-9)
        let off = CameraOverlay().moved(to: CGPoint(x: -500, y: 9000), canvas: canvas)
        XCTAssertEqual(off.x, 0)
        XCTAssertEqual(off.y, 1)
    }

    func testStartsWhereTheBubbleWas() {
        let c = CameraOverlay(placement: CameraPlacement(x: 0.1, y: 0.9, size: 0.3))
        XCTAssertEqual(c.x, 0.1)
        XCTAssertEqual(c.y, 0.9)
        XCTAssertEqual(c.size, 0.3)
        XCTAssertEqual(CameraOverlay(placement: CameraPlacement(x: 0.5, y: 0.5, size: 5)).size, CameraOverlay.maxSize)
        XCTAssertEqual(CameraOverlay(placement: nil), CameraOverlay())
    }

    // MARK: Saving

    func testStudioSettingsKeepTheCameraAndStartFromTheProject() throws {
        var p = project
        p.camera = CameraPlacement(x: 0.2, y: 0.3, size: 0.2)
        XCTAssertEqual(StudioSettings(project: p).camera.x, 0.2)
        var s = StudioSettings(project: p)
        s.camera.shape = .rounded
        s.camera.mirrored = false
        s.camera = s.camera.hiding(from: 1, to: 2)
        let read = try StudioSettings.decode(s.encoded(), project: p)
        XCTAssertEqual(read.camera, s.camera)
        XCTAssertEqual(s.withoutZoom, StudioSettings(project: p).withoutZoom, "moving the camera keeps the background")
        let readProject = try RecordingProject.decode(p.encoded())
        XCTAssertEqual(readProject.camera, p.camera)
    }

    func testOddSavedValuesAreTidied() throws {
        let json = #"{"shape":"hexagon","size":9,"x":-3,"hidden":[{"start":5,"end":1},{"start":1,"end":2}]}"#
        let c = try JSONDecoder().decode(CameraOverlay.self, from: Data(json.utf8))
        XCTAssertEqual(c.shape, .circle)
        XCTAssertEqual(c.size, CameraOverlay.maxSize)
        XCTAssertEqual(c.x, 0)
        XCTAssertEqual(c.hidden, [CameraHide(start: 1, end: 2)])
        XCTAssertTrue(c.shown)
        XCTAssertTrue(c.mirrored)
    }

    // MARK: Reading the recorded camera

    private func picture(red: Bool) -> CGImage {
        let ctx = CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red ? CGColor(red: 1, green: 0, blue: 0, alpha: 1) : CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
        return ctx.makeImage()!
    }

    func testFeedReadsForwardAndBackAndDrawsInTheFrame() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let none = await CameraFeed.open(folder: dir)
        XCTAssertNil(none, "no camera recorded")
        try await SequenceJoiner.writeStill(picture(red: true), seconds: 3, fps: 30,
                                            to: dir.appendingPathComponent(RecordingProject.cameraFile))
        let opened = await CameraFeed.open(folder: dir)
        let feed = try XCTUnwrap(opened)
        XCTAssertEqual(feed.aspect, 160.0 / 120, accuracy: 0.01)
        XCTAssertNotNil(feed.image(at: 0.5))
        XCTAssertNotNil(feed.image(at: 2.5))
        XCTAssertNotNil(feed.image(at: 0.1), "going back starts reading again")
        XCTAssertNotNil(feed.fresh().image(at: 1))

        // Drawn into a frame, the bubble's middle is the camera's red.
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var c = CameraOverlay()
        c.x = 0.5; c.y = 0.5; c.size = 0.5
        c.draw(try XCTUnwrap(feed.image(at: 1)), in: ctx, canvas: CGSize(width: 200, height: 100), opacity: 1)
        let image = try XCTUnwrap(ctx.makeImage())
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        let i = 50 * image.bytesPerRow + 100 * 4
        XCTAssertGreaterThan(data[i], 200, "red")
        XCTAssertLessThan(data[i + 2], 60, "not blue")
    }
}
