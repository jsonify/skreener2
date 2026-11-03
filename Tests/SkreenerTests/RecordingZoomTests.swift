import AppKit
import XCTest
@testable import Skreener

final class RecordingZoomTests: XCTestCase {
    private let video = CGSize(width: 1000, height: 500)

    private func click(_ t: Double, _ x: Double, _ y: Double, button: RecordingEvents.Click.Button = .left,
                       down: Bool = true) -> RecordingEvents.Click {
        RecordingEvents.Click(t: t, x: x, y: y, button: button, down: down)
    }

    private func events(_ clicks: [RecordingEvents.Click]) -> RecordingEvents {
        var e = RecordingEvents()
        e.clicks = clicks
        return e
    }

    private func sections(_ clicks: [RecordingEvents.Click], duration: Double = 30) -> [ZoomSection] {
        AutoZoom.sections(from: events(clicks), videoSize: video, duration: duration)
    }

    private func assertSpans(_ s: [ZoomSection], _ spans: [(Double, Double)], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.count, spans.count, "\(s)", file: file, line: line)
        for (a, b) in zip(s, spans) {
            XCTAssertEqual(a.start, b.0, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(a.end, b.1, accuracy: 1e-9, file: file, line: line)
        }
    }

    // MARK: Sections from clicks

    func testClicksCloseInTimeAndPlaceMakeOneSectionWithPadding() {
        let s = sections([click(2, 100, 100), click(3.5, 120, 110), click(5, 130, 100)])
        assertSpans(s, [(1.6, 6.5)])
        XCTAssertEqual(s[0].level, AutoZoom.defaultLevel)
        XCTAssertEqual(s[0].mode, .follow)
        XCTAssertEqual(s[0].center, CGPoint(x: 100, y: 100), "aimed at the first click")
    }

    func testClicksFarApartInTimeMakeTwoSections() {
        assertSpans(sections([click(2, 100, 100), click(6, 100, 100)]), [(1.6, 3.5), (5.6, 7.5)])
    }

    func testClicksOutsideTheZoomedViewMakeTheirOwnSection() {
        // 2.9 s apart: close enough in time, but the second is outside the 2× view around the first.
        assertSpans(sections([click(2, 100, 100), click(4.9, 900, 400)]), [(1.6, 3.5), (4.5, 6.4)])
        // The same clicks in the same view make one.
        assertSpans(sections([click(2, 100, 100), click(4.9, 300, 200)]), [(1.6, 6.4)])
    }

    func testSectionsWithAShortGapMerge() {
        // Apart by place, but only 0.1 s between the sections.
        assertSpans(sections([click(2, 100, 100), click(4, 900, 400)]), [(1.6, 5.5)])
    }

    func testSectionsStayInsideTheVideo() {
        assertSpans(sections([click(0.1, 100, 100), click(29, 100, 100)], duration: 30), [(0, 1.6), (28.6, 30)])
    }

    func testOnlyLeftClicksDownInsideTheVideoCount() {
        let s = sections([click(2, 100, 100, button: .right), click(4, 100, 100, down: false), click(6, -5, 100),
                          click(8, 100, 600), click(10, 100, 100)])
        assertSpans(s, [(9.6, 11.5)])
        XCTAssertTrue(sections([]).isEmpty)
    }

    func testSectionsNeverOverlapAndKeepTheirGap() {
        var generator = SystemRandomNumberGenerator()
        var clicks: [RecordingEvents.Click] = []
        for _ in 0..<200 {
            clicks.append(click(Double.random(in: 0..<60, using: &generator), Double.random(in: 0..<1000, using: &generator),
                                Double.random(in: 0..<500, using: &generator)))
        }
        let s = sections(clicks, duration: 60)
        XCTAssertFalse(s.isEmpty)
        for (a, b) in zip(s, s.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.start - a.end, AutoZoom.minGap)
        }
        for x in s {
            XCTAssertLessThan(x.start, x.end)
            XCTAssertGreaterThanOrEqual(x.start, 0)
            XCTAssertLessThanOrEqual(x.end, 60)
        }
    }

    // MARK: Camera

    private func fixed(_ start: Double, _ end: Double, at x: Double, _ y: Double, level: Double = 2) -> ZoomSection {
        ZoomSection(start: start, end: end, level: level, mode: .fixed, x: x, y: y)
    }

    private func assertRect(_ a: CGRect, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-6, file: file, line: line)
    }

    func testTheCropZoomsInAndOutEased() {
        let cam = ZoomCamera(sections: [fixed(2, 6, at: 500, 250)], events: RecordingEvents(), videoSize: video)
        let full = CGRect(origin: .zero, size: video)
        assertRect(cam.crop(at: 1), full)
        assertRect(cam.crop(at: 2), full)
        assertRect(cam.crop(at: 7), full)
        assertRect(cam.crop(at: 4), CGRect(x: 250, y: 125, width: 500, height: 250))
        // Halfway through easing in (and out) the zoom is halfway.
        XCTAssertEqual(cam.level(at: 2 + AutoZoom.ease / 2), 1.5, accuracy: 1e-9)
        XCTAssertEqual(cam.level(at: 6 - AutoZoom.ease / 2), 1.5, accuracy: 1e-9)
        assertRect(cam.crop(at: 2.3), CGRect(x: 500 - 1000 / 3, y: 250 - 500 / 3, width: 2000 / 3, height: 1000 / 3))
        // Eased: slow at the ends, never past the level.
        XCTAssertLessThan(cam.level(at: 2.1) - 1, (cam.level(at: 2.3) - 1) / 3)
        var last = 1.0
        for i in 0...60 {
            let l = cam.level(at: 2 + Double(i) * 0.01)
            XCTAssertGreaterThanOrEqual(l, last)
            XCTAssertLessThanOrEqual(l, 2)
            last = l
        }
        XCTAssertEqual(cam.level(at: 2 + AutoZoom.ease), 2, accuracy: 1e-9)
    }

    func testTheCropStaysInsideTheVideo() {
        let cam = ZoomCamera(sections: [fixed(0, 4, at: 10, 10), fixed(10, 14, at: 990, 490)], events: RecordingEvents(),
                             videoSize: video)
        assertRect(cam.crop(at: 2), CGRect(x: 0, y: 0, width: 500, height: 250))
        assertRect(cam.crop(at: 12), CGRect(x: 500, y: 250, width: 500, height: 250))
        for t in stride(from: 0.0, through: 14, by: 0.05) {
            let c = cam.crop(at: t)
            XCTAssertGreaterThanOrEqual(c.minX, -1e-9)
            XCTAssertGreaterThanOrEqual(c.minY, -1e-9)
            XCTAssertLessThanOrEqual(c.maxX, 1000 + 1e-9)
            XCTAssertLessThanOrEqual(c.maxY, 500 + 1e-9)
            XCTAssertEqual(c.width / c.height, 2, accuracy: 1e-9, "the video's shape, never stretched")
        }
    }

    private func pointer(_ samples: [(Double, Double, Double)]) -> RecordingEvents {
        var e = RecordingEvents()
        e.cursor = samples.map { RecordingEvents.CursorSample(t: $0.0, x: $0.1, y: $0.2, visible: true) }
        return e
    }

    func testFollowIgnoresSmallMovesInTheDeadZone() {
        let e = pointer([(0, 500, 250), (2, 530, 260), (4, 470, 240), (6, 500, 250), (10, 500, 250)])
        let cam = ZoomCamera(sections: [ZoomSection(start: 0, end: 10, x: 0, y: 0)], events: e, videoSize: video)
        for t in [1.0, 3, 5, 8] {
            let c = cam.crop(at: t)
            XCTAssertEqual(c.midX, 500, accuracy: 1e-9)
            XCTAssertEqual(c.midY, 250, accuracy: 1e-9)
        }
    }

    func testFollowCatchesUpWithTheMovedPointerSmoothly() {
        let e = pointer([(0, 500, 250), (5, 500, 250), (5.01, 800, 250), (10, 800, 250)])
        let cam = ZoomCamera(sections: [ZoomSection(start: 0, end: 10, x: 0, y: 0)], events: e, videoSize: video)
        // The view stops when the pointer is at the dead zone's edge: 800 − 20 % of the 500 px view.
        XCTAssertEqual(cam.crop(at: 8).midX, 700, accuracy: 1)
        // On the way there it moves a bit each frame, without jumping.
        var last = cam.crop(at: 5).midX
        XCTAssertEqual(last, 500, accuracy: 1e-6)
        for i in 1...60 {
            let x = cam.crop(at: 5 + Double(i) / 30).midX
            XCTAssertGreaterThanOrEqual(x, last - 1e-9)
            XCTAssertLessThan(x - last, 40)
            last = x
        }
    }

    func testTheCameraIsTheSameForAnyOrderOfTimes() {
        var samples: [(Double, Double, Double)] = []
        for i in 0..<300 {
            let k = Double(i)
            let x: Double = 300 + 200 * sin(k / 20)
            let y: Double = 250 + 150 * cos(k / 15)
            samples.append((k / 30, x, y))
        }
        let e = pointer(samples)
        let s = [ZoomSection(start: 1, end: 5, x: 0, y: 0), fixed(6, 9, at: 200, 100, level: 3)]
        let times: [Double] = Array(stride(from: 0.0, through: 10, by: 0.07))
        let cam = ZoomCamera(sections: s, events: e, videoSize: video)
        let forward = times.map { cam.crop(at: $0) }
        let shuffled = times.shuffled()
        let again = ZoomCamera(sections: s, events: e, videoSize: video)
        var fromShuffled: [Double: CGRect] = [:]
        for t in shuffled { fromShuffled[t] = again.crop(at: t) }
        for (t, c) in zip(times, forward) {
            XCTAssertEqual(fromShuffled[t], c)
            XCTAssertEqual(cam.crop(at: t), c)
        }
    }

    // MARK: Editing sections

    private let ab = [ZoomSection(start: 1, end: 3, x: 0, y: 0), ZoomSection(start: 5, end: 7, x: 0, y: 0)]

    func testMovingStopsAtTheNeighboursAndTheEnds() {
        assertSpans(AutoZoom.move(ab, index: 1, to: 2, duration: 10), [(1, 3), (3, 5)])
        assertSpans(AutoZoom.move(ab, index: 1, to: 9, duration: 10), [(1, 3), (8, 10)])
        assertSpans(AutoZoom.move(ab, index: 0, to: -1, duration: 10), [(0, 2), (5, 7)])
        assertSpans(AutoZoom.move(ab, index: 0, to: 4, duration: 10), [(3, 5), (5, 7)])
        assertSpans(AutoZoom.move(ab, index: 0, to: 1.5, duration: 10), [(1.5, 3.5), (5, 7)])
    }

    func testResizingStopsAtTheNeighboursAndKeepsAMinimumLength() {
        assertSpans(AutoZoom.resize(ab, index: 1, edge: .start, to: 2, duration: 10), [(1, 3), (3, 7)])
        assertSpans(AutoZoom.resize(ab, index: 1, edge: .start, to: 6.9, duration: 10), [(1, 3), (7 - AutoZoom.minLength, 7)])
        assertSpans(AutoZoom.resize(ab, index: 0, edge: .end, to: 6, duration: 10), [(1, 5), (5, 7)])
        assertSpans(AutoZoom.resize(ab, index: 0, edge: .end, to: 0, duration: 10), [(1, 1 + AutoZoom.minLength), (5, 7)])
        assertSpans(AutoZoom.resize(ab, index: 1, edge: .end, to: 12, duration: 10), [(1, 3), (5, 10)])
        assertSpans(AutoZoom.resize(ab, index: 0, edge: .start, to: -3, duration: 10), [(0, 3), (5, 7)])
    }

    func testAddingFitsInTheFreeTime() throws {
        let between = try XCTUnwrap(AutoZoom.add(to: ab, at: 4, duration: 10, center: CGPoint(x: 10, y: 20)))
        assertSpans(between.sections, [(1, 3), (3, 5), (5, 7)])
        XCTAssertEqual(between.index, 1)
        XCTAssertEqual(between.sections[1].center, CGPoint(x: 10, y: 20))
        let after = try XCTUnwrap(AutoZoom.add(to: ab, at: 7.5, duration: 10, center: .zero))
        assertSpans(after.sections, [(1, 3), (5, 7), (7.5, 9.5)])
        XCTAssertEqual(after.index, 2)
        let atEnd = try XCTUnwrap(AutoZoom.add(to: ab, at: 9.5, duration: 10, center: .zero))
        assertSpans(atEnd.sections, [(1, 3), (5, 7), (8, 10)])
        XCTAssertNil(AutoZoom.add(to: ab, at: 2, duration: 10, center: .zero), "inside a section")
        let tight = [ZoomSection(start: 1, end: 3, x: 0, y: 0), ZoomSection(start: 3.3, end: 5, x: 0, y: 0)]
        XCTAssertNil(AutoZoom.add(to: tight, at: 3.1, duration: 10, center: .zero), "no room")
        let first = try XCTUnwrap(AutoZoom.add(to: [], at: 0, duration: 10, center: .zero))
        assertSpans(first.sections, [(0, AutoZoom.addedLength)])
    }

    func testSectionsReadFromAFileAreTidied() {
        let messy = [ZoomSection(start: 5, end: 8, x: 0, y: 0), ZoomSection(start: 1, end: 6, x: 0, y: 0),
                     ZoomSection(start: 9, end: 9, x: 0, y: 0)]
        assertSpans(AutoZoom.tidy(messy), [(1, 6), (6, 8)])
    }

    // MARK: Settings

    private func project() -> RecordingProject {
        RecordingProject(created: Date(timeIntervalSince1970: 1_700_000_000), area: CGRect(x: 0, y: 0, width: 200, height: 100),
                         screenScale: 1, videoWidth: 200, videoHeight: 100, fps: 10, style: EffectsStyle(), exported: nil)
    }

    func testZoomSettingsRoundTripAtTheNewVersion() throws {
        let p = project()
        var s = StudioSettings(project: p)
        XCTAssertTrue(s.autoZoom)
        XCTAssertFalse(s.zoomGenerated)
        XCTAssertTrue(s.zoomSections.isEmpty)
        s.autoZoom = false
        s.zoomGenerated = true
        s.zoomSections = [fixed(1, 3, at: 40, 50, level: 3), ZoomSection(start: 4, end: 6, level: 1.25, x: 1, y: 2)]
        let data = try s.encoded()
        XCTAssertEqual(StudioSettings.currentVersion, 2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        XCTAssertEqual(try StudioSettings.decode(data, project: p), s)
    }

    func testAnOlderSettingsFileHasNoZoomYet() throws {
        let p = project()
        let s = try StudioSettings.decode(Data(#"{"version": 1, "backgroundOn": true, "spotlight": false}"#.utf8), project: p)
        XCTAssertTrue(s.backgroundOn)
        XCTAssertFalse(s.spotlight)
        XCTAssertTrue(s.autoZoom)
        XCTAssertTrue(s.zoomSections.isEmpty)
        XCTAssertFalse(s.zoomGenerated, "made from the clicks when the editor first opens it")
        XCTAssertThrowsError(try StudioSettings.decode(Data(#"{"version": 3}"#.utf8), project: p))
    }

    func testZoomLevelsAreKeptInRange() throws {
        let p = project()
        let json = #"{"version": 2, "zoomSections": [{"start": 1, "end": 2, "level": 9, "x": 1, "y": 1}, {"start": 3, "end": 4}]}"#
        let s = try StudioSettings.decode(Data(json.utf8), project: p)
        XCTAssertEqual(s.zoomSections.map(\.level), [AutoZoom.maxLevel, AutoZoom.defaultLevel])
        XCTAssertEqual(s.zoomSections[1].mode, .follow)
    }

    // MARK: Drawing through the crop

    func testEffectsMapThroughTheCropOntoTheContent() {
        let layout = StudioLayout.make(videoSize: video, pixelsPerPoint: 1, background: nil)
        let cam = ZoomCamera(sections: [fixed(0, 4, at: 300, 200)], events: RecordingEvents(), videoSize: video)
        let crop = cam.crop(at: 2)
        assertRect(crop, CGRect(x: 50, y: 75, width: 500, height: 250))
        // A click at the zoom's point lands in the middle of the frame, at twice the distance from it as unzoomed.
        let p = layout.canvasPoint(video: CGPoint(x: 300, y: 200), crop: crop)
        XCTAssertEqual(p.x, 500, accuracy: 1e-9)
        XCTAssertEqual(p.y, 250, accuracy: 1e-9)
        let q = layout.canvasPoint(video: CGPoint(x: 350, y: 200), crop: crop)
        XCTAssertEqual(q.x - p.x, 100, accuracy: 1e-9)
        // And back.
        let v = layout.videoPoint(canvas: q, crop: crop)
        XCTAssertEqual(v.x, 350, accuracy: 1e-9)
        XCTAssertEqual(v.y, 200, accuracy: 1e-9)
    }

    @MainActor func testTheCompositorDrawsTheZoomedFrameOnlyWhenAutoZoomIsOn() throws {
        let p = project()
        var s = StudioSettings(project: p)
        s.effects.cursor = false
        s.zoomSections = [fixed(0, 4, at: 50, 50)]
        let on = StudioCompositor(project: p, events: RecordingEvents(), folder: nil, settings: s)
        XCTAssertTrue(on.composes)
        XCTAssertTrue(on.changesTheVideo)
        let source = try halves()
        // Zoomed on the red left half: red reaches the right edge.
        XCTAssertEqual(try pixel(on, source, at: 2)(190, 50), [255, 0, 0])
        XCTAssertEqual(try pixel(on, source, at: 6)(190, 50), [0, 0, 255], "after the section, the whole video")
        s.autoZoom = false
        let off = on.zoomed(s)
        XCTAssertFalse(off.composes)
        XCTAssertNil(off.crop(at: 2))
        XCTAssertEqual(try pixel(off, source, at: 2)(190, 50), [0, 0, 255])
    }

    func testZoomTrackLevelText() {
        XCTAssertEqual(ZoomTrackView.levelText(2), "2×")
        XCTAssertEqual(ZoomTrackView.levelText(1.25), "1.25×")
        XCTAssertEqual(ZoomTrackView.levelText(1.5), "1.5×")
    }

    // MARK: Helpers

    /// 200 × 100: red on the left half, blue on the right.
    private func halves() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// Draws `c` at `t`; returns the RGB at a canvas point (bottom-left origin).
    private func pixel(_ c: StudioCompositor, _ source: CGImage, at t: Double) throws -> (Int, Int) -> [UInt8] {
        let w = Int(c.size.width), h = Int(c.size.height)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        c.draw(in: ctx, source: source, at: t)
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: data, count: w * h * 4))
        return { x, y in
            let i = (h - 1 - y) * w * 4 + x * 4
            return [bytes[i + 2], bytes[i + 1], bytes[i]]
        }
    }
}
