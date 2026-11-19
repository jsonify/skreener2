import XCTest
@testable import Skreener

/// Timed callouts over a recording (#383): when they show and how much, editing their times, where they are under a
/// zoom, saving them and drawing them.
final class RecordingCalloutsTests: XCTestCase {
    private let video = CGSize(width: 1000, height: 500)

    private func box(_ start: Double, _ end: Double, x: Double = 300, y: Double = 150, follows: Bool = true) -> Callout {
        var c = Callout(kind: .box, start: start, end: end, x: x, y: y, width: 100, height: 50)
        c.followsZoom = follows
        return c
    }

    func testOpacityFadesInAndOut() {
        let c = box(2, 5)
        XCTAssertEqual(Callouts.opacity(c, at: 1.9), 0)
        XCTAssertEqual(Callouts.opacity(c, at: 2), 0)
        XCTAssertEqual(Callouts.opacity(c, at: 2 + Callouts.fade / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Callouts.opacity(c, at: 3.5), 1)
        XCTAssertEqual(Callouts.opacity(c, at: 5 - Callouts.fade / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Callouts.opacity(c, at: 5), 0)
        // A short one fades over a third of its length each way, so it is fully shown in the middle.
        let short = box(0, 0.3)
        XCTAssertEqual(Callouts.opacity(short, at: 0.15), 1, accuracy: 1e-9)
    }

    func testShowingKeepsTheDrawingOrder() {
        let callouts = [box(0, 10), box(2, 4), box(5, 6)]
        XCTAssertEqual(Callouts.showing(callouts, at: 3), [0, 1])
        XCTAssertEqual(Callouts.showing(callouts, at: 4.5), [0])
        XCTAssertEqual(Callouts.showing(callouts, at: 11), [])
    }

    func testTidyMovingAndResizing() {
        let tidied = Callouts.tidy([box(-1, 0), box(9.9, 12), box(.nan, 2)], duration: 10)
        XCTAssertEqual(tidied.count, 2, "a callout with no time is left out")
        XCTAssertEqual(tidied[0].start, 0)
        XCTAssertEqual(tidied[0].end, Callouts.minLength, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(tidied[1].end, 10)
        XCTAssertGreaterThanOrEqual(tidied[1].duration, Callouts.minLength - 1e-9)

        let c = box(2, 5)
        XCTAssertEqual(Callouts.moved(c, to: 9, duration: 10).start, 7, "stays inside the recording, the same length")
        XCTAssertEqual(Callouts.moved(c, to: -3, duration: 10).end, 3)
        XCTAssertEqual(Callouts.resized(c, start: true, to: 4.9, duration: 10).start, 5 - Callouts.minLength, accuracy: 1e-9)
        XCTAssertEqual(Callouts.resized(c, start: false, to: 20, duration: 10).end, 10)
        XCTAssertEqual(Callouts.resized(c, start: true, to: 1, duration: 10).start, 1)
    }

    func testCountersAreNumberedByWhenTheyStart() {
        let counter = { (t: Double) in Callout(kind: .counter, start: t, end: t + 1, x: 0, y: 0, width: 0, height: 0) }
        let callouts = [counter(5), box(0, 1), counter(1), counter(5)]
        XCTAssertEqual(Callouts.number(of: 2, in: callouts), 1)
        XCTAssertEqual(Callouts.number(of: 0, in: callouts), 2)
        XCTAssertEqual(Callouts.number(of: 3, in: callouts), 3, "same start: the one added later comes after")
    }

    func testNewCalloutsAreAroundThePointAndInsideTheVideo() {
        let arrow = Callouts.make(.arrow, at: 1, duration: 10, videoSize: video, pixelsPerPoint: 2, around: CGPoint(x: 600, y: 200))
        XCTAssertEqual(arrow.to.x, 600, accuracy: 1e-9, "the tip is on the point")
        XCTAssertEqual(arrow.to.y, 200, accuracy: 1e-9)
        XCTAssertEqual(arrow.end, 1 + Callouts.defaultLength)
        let late = Callouts.make(.box, at: 9, duration: 10, videoSize: video, pixelsPerPoint: 2)
        XCTAssertEqual(late.end, 10, "ends with the recording")
        XCTAssertEqual(late.x + late.width / 2, 500, accuracy: 1e-9, "the middle of the video by default")
        let text = Callouts.make(.text, at: 0, duration: 10, videoSize: video, pixelsPerPoint: 2, around: CGPoint(x: 5000, y: -9))
        XCTAssertEqual(text.x, 1000)
        XCTAssertEqual(text.y, 0)
        XCTAssertEqual(text.text, "Text")
    }

    func testPositionsUnderAZoom() {
        let layout = StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: nil)
        let crop = CGRect(x: 250, y: 125, width: 500, height: 250)   // 2× on the middle
        let follows = box(0, 5), stays = box(0, 5, follows: false)
        let middle = CGPoint(x: 350, y: 175)
        // Following the zoom, the box is where its content is in the zoomed frame (twice as far from the middle).
        let zoomed = layout.canvasPoint(video: middle, crop: crop)
        XCTAssertEqual(zoomed.x, 200, accuracy: 1e-6)
        XCTAssertEqual(Callouts.hit([follows], at: zoomed, time: 1, layout: layout, crop: crop, pixelsPerPoint: 2, slop: 2)?.index, 0)
        XCTAssertNil(Callouts.hit([follows], at: layout.canvasPoint(video: middle), time: 1, layout: layout, crop: crop,
                                  pixelsPerPoint: 2, slop: 2))
        // Staying put, it is where it was in the frame.
        XCTAssertEqual(Callouts.hit([stays], at: layout.canvasPoint(video: middle), time: 1, layout: layout, crop: crop,
                                    pixelsPerPoint: 2, slop: 2)?.index, 0)
        XCTAssertEqual(Callouts.videoPoint(zoomed, for: follows, layout: layout, crop: crop).x, 350, accuracy: 1e-6)
        // Not at a time it isn't showing.
        XCTAssertNil(Callouts.hit([follows], at: zoomed, time: 6, layout: layout, crop: crop, pixelsPerPoint: 2, slop: 2))
        // A blur always follows, since it hides what is under it.
        var blur = stays
        blur.kind = .blur
        XCTAssertTrue(blur.follows)
    }

    func testHitFindsTheTopmostAndTheHandle() {
        let layout = StudioLayout.make(videoSize: video, pixelsPerPoint: 2, background: nil)
        let callouts = [box(0, 5), box(0, 5)]
        let inside = layout.canvasPoint(video: CGPoint(x: 320, y: 160))
        XCTAssertEqual(Callouts.hit(callouts, at: inside, time: 1, layout: layout, crop: nil, pixelsPerPoint: 2, slop: 2)?.index, 1)
        let corner = layout.canvasPoint(video: CGPoint(x: 400, y: 200))
        XCTAssertEqual(Callouts.hit(callouts, at: corner, time: 1, layout: layout, crop: nil, pixelsPerPoint: 2, slop: 4)?.handle, true)
        let arrow = Callout(kind: .arrow, start: 0, end: 5, x: 100, y: 100, width: 200, height: 0)
        let onShaft = layout.canvasPoint(video: CGPoint(x: 200, y: 103))
        XCTAssertEqual(Callouts.hit([arrow], at: onShaft, time: 1, layout: layout, crop: nil, pixelsPerPoint: 2, slop: 2)?.handle, false)
        let resized = Callouts.resizing(box(0, 5), handleTo: CGPoint(x: 290, y: 140), minSize: 8)
        XCTAssertEqual(resized.width, 8, "never smaller than the minimum")
        XCTAssertEqual(Callouts.resizing(arrow, handleTo: CGPoint(x: 50, y: 60), minSize: 8).to, CGPoint(x: 50, y: 60))
    }

    func testSavedWithTheSettings() throws {
        let project = RecordingProject(created: Date(timeIntervalSince1970: 0), area: CGRect(x: 0, y: 0, width: 100, height: 100),
                                       screenScale: 2, videoWidth: 200, videoHeight: 200, fps: 30, style: EffectsStyle())
        var s = StudioSettings(project: project)
        var text = Callouts.make(.text, at: 1, duration: 10, videoSize: video, pixelsPerPoint: 2)
        text.text = "Click here"
        text.color = [0, 0.5, 1, 1]
        text.followsZoom = false
        s.callouts = [text, box(2, 4)]
        let read = try StudioSettings.decode(s.encoded(), project: project)
        XCTAssertEqual(read.callouts, s.callouts)
        XCTAssertEqual(s.withoutZoom, StudioSettings(project: project).withoutZoom, "moving a callout keeps the background")
        let odd = try JSONDecoder().decode(Callout.self, from: Data(#"{"kind": "sparkles", "start": 1, "color": [2, 0]}"#.utf8))
        XCTAssertEqual(odd.kind, .box)
        XCTAssertEqual(odd.end, 1 + Callouts.defaultLength)
        XCTAssertEqual(odd.color, Callout.red)
    }

    // MARK: Drawing

    private func canvas(_ size: CGSize, fill: CGColor? = nil) -> CGContext {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let fill {
            ctx.setFillColor(fill)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return ctx
    }

    /// Red, green, blue, alpha at a top-left-origin pixel.
    private func pixel(_ ctx: CGContext, _ x: Int, _ y: Int) -> [UInt8] {
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = y * ctx.bytesPerRow + x * 4
        return [data[i], data[i + 1], data[i + 2], data[i + 3]]
    }

    func testDrawsEachKindAtItsOpacity() {
        let size = CGSize(width: 400, height: 200)
        for kind in Callout.Kind.allCases where kind != .blur {
            var c = Callouts.make(kind, at: 0, duration: 10, videoSize: size, pixelsPerPoint: 1)
            c.color = [0, 0, 1, 1]
            let ctx = canvas(size)
            Callouts.draw([c], index: 0, opacity: 1, in: ctx, videoSize: size, pixelsPerPoint: 1, source: nil)
            let image = ctx.makeImage()!
            let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
            let painted = (0..<(image.height * ctx.bytesPerRow)).contains { $0 % 4 == 3 && data[$0] > 0 }
            XCTAssertTrue(painted, "\(kind) draws something")
        }
        // Half faded: half as opaque.
        let ctx = canvas(size)
        var c = Callout(kind: .highlight, start: 0, end: 1, x: 100, y: 50, width: 100, height: 50)
        c.color = [0, 0, 1, 1]
        Callouts.draw([c], index: 0, opacity: 0.5, in: ctx, videoSize: size, pixelsPerPoint: 1, source: nil)
        let alpha = pixel(ctx, 150, 75)[3]
        XCTAssertGreaterThan(alpha, 0)
        XCTAssertLessThan(alpha, 200)
    }

    func testBlurHidesWhatIsUnderIt() {
        let size = CGSize(width: 200, height: 100)
        // Stripes one pixel wide.
        let source = canvas(size, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        source.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: 200, by: 2) { source.fill(CGRect(x: x, y: 0, width: 1, height: 100)) }
        let frame = source.makeImage()!
        let ctx = canvas(size)
        ctx.draw(frame, in: CGRect(origin: .zero, size: size))
        let c = Callout(kind: .blur, start: 0, end: 1, x: 50, y: 25, width: 100, height: 50)
        Callouts.draw([c], index: 0, opacity: 1, in: ctx, videoSize: size, pixelsPerPoint: 1, source: frame)
        // Inside, neighbouring pixels are nearly the same grey; outside, still black and white.
        let a = Int(pixel(ctx, 100, 50)[0]), b = Int(pixel(ctx, 101, 50)[0])
        XCTAssertLessThan(abs(a - b), 40)
        let c0 = Int(pixel(ctx, 10, 50)[0]), c1 = Int(pixel(ctx, 11, 50)[0])
        XCTAssertGreaterThan(abs(c0 - c1), 200)
    }
}

/// The callout track's rows: overlapping callouts stack.
final class CalloutTrackRowsTests: XCTestCase {
    func testOverlappingCalloutsGetTheirOwnRows() {
        let c = { (a: Double, b: Double) in Callout(kind: .box, start: a, end: b, x: 0, y: 0, width: 1, height: 1) }
        XCTAssertEqual(CalloutTrackView.rows([c(0, 2), c(1, 3), c(2, 4), c(1.5, 5), c(1.6, 2)], maxRows: 3), [0, 1, 0, 2, 2])
    }
}
