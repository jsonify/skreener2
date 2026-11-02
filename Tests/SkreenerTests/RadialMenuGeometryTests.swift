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
        XCTAssertNil(G.pickOnRelease(highlight: nil, pointerMoved: false))   // tap
        XCTAssertNil(G.pickOnRelease(highlight: nil, pointerMoved: true))    // let go in the hub
        XCTAssertNil(G.pickOnRelease(highlight: 2, pointerMoved: false))     // the ring was moved off the pointer
        XCTAssertEqual(G.pickOnRelease(highlight: 2, pointerMoved: true), 2)  // hold, move, let go
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
        XCTAssertEqual(G.hubText(for: nil, shortcut: nil, timerSeconds: 5), .init(title: "Skreener", detail: "Pick a mode"))
        XCTAssertEqual(G.hubText(for: G.slices[0], shortcut: "⌃⇧4", timerSeconds: 5), .init(title: "Area", detail: "⌃⇧4"))
        XCTAssertEqual(G.hubText(for: G.slices[1], shortcut: nil, timerSeconds: 5), .init(title: "Window", detail: ""))
        XCTAssertEqual(G.hubText(for: G.slices[2], shortcut: "⌃⇧T", timerSeconds: 10),
                       .init(title: "Self-Timer", detail: "Area · 10 s"))
    }
}
