import XCTest
@testable import Skreener

/// The radial menu's picking, placement and hub text (#359). Points are from the ring's centre, y up.
final class RadialMenuGeometryTests: XCTestCase {
    private typealias G = RadialMenuGeometry

    func testDefaultSlices() {
        XCTAssertEqual(G.slices.map(\.action), [.captureArea, .captureWindow, .timedArea, .captureScrolling, .captureText,
                                               .recordScreen])
    }

    func testAnglesRunClockwiseFromTheTop() {
        XCTAssertEqual(G.angle(of: CGPoint(x: 0, y: 10)), 0, accuracy: 1e-9)
        XCTAssertEqual(G.angle(of: CGPoint(x: 10, y: 0)), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(G.angle(of: CGPoint(x: 0, y: -10)), .pi, accuracy: 1e-9)
        XCTAssertEqual(G.angle(of: CGPoint(x: -10, y: 0)), 3 * .pi / 2, accuracy: 1e-9)
        let p = G.point(angle: .pi / 2, radius: 5)
        XCTAssertEqual(p.x, 5, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0, accuracy: 1e-9)
    }

    func testSliceByDirection() {
        // Six slices of 60°: 0 is centred on the top, 1 on the upper right, 3 on the bottom.
        XCTAssertEqual(G.slice(at: CGPoint(x: 0, y: 80), count: 6), 0)
        XCTAssertEqual(G.slice(at: G.point(angle: .pi / 3, radius: 80), count: 6), 1)
        XCTAssertEqual(G.slice(at: CGPoint(x: 0, y: -80), count: 6), 3)
        XCTAssertEqual(G.slice(at: G.point(angle: 5 * .pi / 3, radius: 80), count: 6), 5)
        // Either side of the top slice's left edge (at -30°).
        XCTAssertEqual(G.slice(at: G.point(angle: -29 * .pi / 180, radius: 80), count: 6), 0)
        XCTAssertEqual(G.slice(at: G.point(angle: -31 * .pi / 180, radius: 80), count: 6), 5)
    }

    func testHubIsADeadZone() {
        XCTAssertNil(G.slice(at: .zero, count: 6))
        XCTAssertNil(G.slice(at: CGPoint(x: 0, y: G.hubRadius - 1), count: 6))
        XCTAssertEqual(G.slice(at: CGPoint(x: 0, y: G.hubRadius), count: 6), 0)
    }

    func testAFlickPastTheRingStillPicks() {
        XCTAssertEqual(G.slice(at: CGPoint(x: 0, y: -900), count: 6), 3)
        // With a reach (the ring open for clicks), beyond it picks nothing.
        XCTAssertNil(G.slice(at: CGPoint(x: 0, y: -900), count: 6, reach: G.outerRadius))
        XCTAssertEqual(G.slice(at: CGPoint(x: 0, y: -100), count: 6, reach: G.outerRadius), 3)
    }

    func testTapLeavesTheRingOpenAndHoldPicks() {
        XCTAssertNil(G.pickOnRelease(nil, pointerMoved: false))                  // tap
        XCTAssertNil(G.pickOnRelease(nil, pointerMoved: true))                   // let go in the hub
        XCTAssertNil(G.pickOnRelease(.slice(2), pointerMoved: false))            // the ring was moved off the pointer
        XCTAssertEqual(G.pickOnRelease(.slice(2), pointerMoved: true), .slice(2)) // hold, move, let go
        XCTAssertEqual(G.pickOnRelease(.option(slice: 2, option: 1), pointerMoved: true), .option(slice: 2, option: 1))
    }

    func testOptions() {
        XCTAssertEqual(G.slices[0].options.map(\.action), [.capturePreviousArea, .captureAreaAndPin, .captureAreaAndLivePin])
        XCTAssertEqual(G.slices[1].options.map(\.action), [.captureActiveWindow, .livePinWindow])
        XCTAssertEqual(G.slices[2].options.map(\.action), [.timedArea, .timedWindow, .timedFullscreen])
        XCTAssertTrue(G.slices[3].options.isEmpty)
        XCTAssertEqual(G.slices[4].options.map(\.action), [.captureCode, .scanQRCode])
        XCTAssertEqual(G.slices[5].options.map(\.action), [.stepRecorder, .presenter])
        XCTAssertEqual(G.slices.filter(\.hasDelay).map(\.title), ["Self-Timer"])
        XCTAssertEqual(G.action(for: .slice(2)), .timedArea)
        XCTAssertEqual(G.action(for: .option(slice: 2, option: 2)), .timedFullscreen)
        XCTAssertNil(G.action(for: .option(slice: 3, option: 0)))
    }

    func testTheBandFansOutPastItsSlice() {
        // Self-Timer (slice 2, centred at 120°) has three options, the middle one straight out from it.
        let mid = G.centerAngle(of: 2, count: 6)
        let bandMiddle = (G.bandInner + G.bandOuter) / 2
        XCTAssertEqual(G.optionAngle(slice: 2, count: 6, option: 1, options: 3), mid, accuracy: 1e-9)
        XCTAssertEqual(G.target(at: G.point(angle: mid, radius: bandMiddle), active: 2, held: false),
                       .option(slice: 2, option: 1))
        XCTAssertEqual(G.target(at: G.point(angle: mid - G.optionWidth, radius: bandMiddle), active: 2, held: false),
                       .option(slice: 2, option: 0))
        XCTAssertEqual(G.target(at: G.point(angle: mid + G.optionWidth, radius: bandMiddle), active: 2, held: false),
                       .option(slice: 2, option: 2))
        // On the ring itself, and in the gap between the ring and the band, it is still the slice.
        XCTAssertEqual(G.target(at: G.point(angle: mid, radius: 90), active: 2, held: false), .slice(2))
        XCTAssertEqual(G.target(at: G.point(angle: mid, radius: G.outerRadius + 6), active: 2, held: false), .slice(2))
        // The band only shows (and picks) for the slice pointed at.
        XCTAssertNil(G.target(at: G.point(angle: mid, radius: bandMiddle), active: nil, held: false))
        XCTAssertNil(G.target(at: G.point(angle: mid, radius: bandMiddle), active: 0, held: false))
        // Beyond the band, a click picks nothing; while held, the direction still picks the option.
        XCTAssertNil(G.target(at: G.point(angle: mid, radius: 400), active: 2, held: false))
        XCTAssertEqual(G.target(at: G.point(angle: mid, radius: 400), active: 2, held: true), .option(slice: 2, option: 1))
    }

    func testASliceWithoutOptionsStillPicksPastTheRing() {
        let scrolling = G.centerAngle(of: 3, count: 6)
        XCTAssertEqual(G.target(at: G.point(angle: scrolling, radius: 400), active: 3, held: true), .slice(3))
        XCTAssertNil(G.target(at: G.point(angle: scrolling, radius: 400), active: 3, held: false))
        XCTAssertNil(G.target(at: .zero, active: 3, held: true))
    }

    func testAnglesWrapForTheTopSlicesBand() {
        // Area (slice 0) is centred on 0°: its first option is just left of the top.
        XCTAssertEqual(G.delta(.pi * 1.9, from: 0), -.pi * 0.1, accuracy: 1e-9)
        let left = G.optionAngle(slice: 0, count: 6, option: 0, options: 3)
        let bandMiddle = (G.bandInner + G.bandOuter) / 2
        XCTAssertEqual(G.target(at: G.point(angle: left, radius: bandMiddle), active: 0, held: false),
                       .option(slice: 0, option: 0))
    }

    func testTabStepsThroughOptions() {
        XCTAssertEqual(G.stepOption(nil, forward: true, count: 3), 0)
        XCTAssertEqual(G.stepOption(2, forward: true, count: 3), nil)   // back to the slice
        XCTAssertEqual(G.stepOption(nil, forward: false, count: 3), 2)
        XCTAssertEqual(G.stepOption(0, forward: false, count: 3), nil)
        XCTAssertNil(G.stepOption(nil, forward: true, count: 0))
    }

    func testDelayKeysOnTheHub() {
        let rects = G.delayRects()
        XCTAssertEqual(rects.count, 3)
        for r in rects { XCTAssertLessThan(hypot(max(abs(r.minX), abs(r.maxX)), max(abs(r.minY), abs(r.maxY))), G.hubRadius - 4) }
        XCTAssertEqual(G.delay(at: CGPoint(x: rects[0].midX, y: rects[0].midY)), 3)
        XCTAssertEqual(G.delay(at: CGPoint(x: rects[2].midX, y: rects[2].midY)), 10)
        XCTAssertNil(G.delay(at: CGPoint(x: 0, y: 20)))
    }

    func testFrameIsCentredOnThePointer() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 280, height: 280)
        XCTAssertEqual(G.frame(size: size, centeredAt: CGPoint(x: 700, y: 400), in: visible),
                       CGRect(x: 560, y: 260, width: 280, height: 280))
    }

    func testFrameMovesInsideTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 280, height: 280)
        XCTAssertEqual(G.frame(size: size, centeredAt: CGPoint(x: 10, y: 10), in: visible),
                       CGRect(x: 0, y: 0, width: 280, height: 280))
        XCTAssertEqual(G.frame(size: size, centeredAt: CGPoint(x: 1435, y: 870), in: visible),
                       CGRect(x: 1160, y: 595, width: 280, height: 280))
        // A second display left of and below the main one.
        let other = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(G.frame(size: size, centeredAt: CGPoint(x: -1915, y: -195), in: other),
                       CGRect(x: -1920, y: -200, width: 280, height: 280))
    }

    func testNumberKeys() {
        XCTAssertEqual(G.slice(forKey: "1", count: 6), 0)
        XCTAssertEqual(G.slice(forKey: "6", count: 6), 5)
        XCTAssertNil(G.slice(forKey: "7", count: 6))
        XCTAssertNil(G.slice(forKey: "0", count: 6))
        XCTAssertNil(G.slice(forKey: "a", count: 6))
        XCTAssertNil(G.slice(forKey: "", count: 6))
    }

    func testArrowsStepAroundTheRing() {
        XCTAssertEqual(G.step(nil, clockwise: true, count: 6), 0)
        XCTAssertEqual(G.step(nil, clockwise: false, count: 6), 5)
        XCTAssertEqual(G.step(5, clockwise: true, count: 6), 0)
        XCTAssertEqual(G.step(0, clockwise: false, count: 6), 5)
        XCTAssertEqual(G.step(2, clockwise: true, count: 6), 3)
    }

    func testHubText() {
        XCTAssertEqual(G.hubText(for: nil, shortcut: nil), .init(title: "Skreener", detail: "Pick a mode"))
        XCTAssertEqual(G.hubText(for: .slice(0), shortcut: "⌃⇧4"), .init(title: "Area", detail: "⌃⇧4"))
        XCTAssertEqual(G.hubText(for: .slice(1), shortcut: nil), .init(title: "Window", detail: ""))
        XCTAssertEqual(G.hubText(for: .option(slice: 0, option: 2), shortcut: nil), .init(title: "Live Pin", detail: ""))
        XCTAssertEqual(G.hubText(for: .slice(2), shortcut: "⌃⇧T"), .init(title: "Self-Timer", detail: "", showsDelays: true))
        XCTAssertEqual(G.hubText(for: .option(slice: 2, option: 1), shortcut: nil),
                       .init(title: "Window", detail: "", showsDelays: true))
    }

    func testHubLineWidthIsTheChordAtTheLinesFarEdge() {
        XCTAssertEqual(G.hubLineWidth(radius: 10, top: 5, bottom: -5), 2 * (75 as CGFloat).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(G.hubLineWidth(radius: 10, top: 8, bottom: 2), 12, accuracy: 1e-9)   // 2·√(100 − 64)
        XCTAssertEqual(G.hubLineWidth(radius: 10, top: -2, bottom: -8), 12, accuracy: 1e-9)
        XCTAssertEqual(G.hubLineWidth(radius: 10, top: 11, bottom: 1), 0)
    }

    func testHubTitleBreaksAtTheMostEvenSpace() {
        XCTAssertEqual(G.hubTitleLayouts("Self-Timer"), [["Self-Timer"]])
        XCTAssertEqual(G.hubTitleLayouts("Step Recorder"), [["Step Recorder"], ["Step", "Recorder"]])
        XCTAssertEqual(G.hubTitleLayouts("Live Pin Window"), [["Live Pin Window"], ["Live Pin", "Window"]])
    }
}
