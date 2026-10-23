import AppKit
import XCTest
@testable import Skreener

final class StrokeShapesTests: XCTestCase {
    /// `n` points around an ellipse centered at (100, 100), with a little noise.
    private func ellipse(rx: CGFloat, ry: CGFloat, n: Int = 60, noise: CGFloat = 1) -> [CGPoint] {
        var rng = SeededRandom(seed: 7)
        return (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n) * 2 * .pi
            return CGPoint(x: 100 + rx * cos(t) + rng.next(in: -noise...noise), y: 100 + ry * sin(t) + rng.next(in: -noise...noise))
        }
    }

    private func square(side: CGFloat) -> [CGPoint] {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: side), CGPoint(x: 0, y: side), CGPoint(x: 0, y: 0)]
        var out: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            for i in 0..<20 {
                let t = CGFloat(i) / 20
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out + [corners[0]]
    }

    func testShakyCircleBecomesAnEllipse() {
        guard case .ellipse(let r)? = StrokeShapes.fit(ellipse(rx: 50, ry: 50)) else { return XCTFail("not an ellipse") }
        XCTAssertEqual(r.midX, 100, accuracy: 2)
        XCTAssertEqual(r.width, 100, accuracy: 4)
    }

    func testBoxBecomesARectangle() {
        guard case .rect(let r)? = StrokeShapes.fit(square(side: 80)) else { return XCTFail("not a rectangle") }
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 80, height: 80))
    }

    func testNearlyStraightStrokeBecomesALine() {
        let pts = (0...30).map { CGPoint(x: CGFloat($0) * 5, y: CGFloat($0 % 2)) }
        XCTAssertEqual(StrokeShapes.fit(pts), .line(pts[0], pts[30]))
    }

    func testScribbleStaysAStroke() {
        let zigzag = (0...30).map { CGPoint(x: CGFloat($0) * 5, y: $0 % 2 == 0 ? 0 : 40) }
        XCTAssertNil(StrokeShapes.fit(zigzag))
    }

    func testSimplifyDropsPointsOnAStraightRun() {
        let pts = (0...10).map { CGPoint(x: CGFloat($0), y: 0) } + [CGPoint(x: 10, y: 10)]
        XCTAssertEqual(StrokeShapes.simplify(pts, epsilon: 0.5), [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    func testHandDrawnWobbleIsTheSameEachTime() {
        let rect = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 100))
        let a = StrokeShapes.handDrawn(rect, seed: 42, amplitude: 2)
        let b = StrokeShapes.handDrawn(rect, seed: 42, amplitude: 2)
        let c = StrokeShapes.handDrawn(rect, seed: 43, amplitude: 2)
        XCTAssertEqual(a.bounds, b.bounds)
        XCTAssertNotEqual(a.bounds, c.bounds)
        XCTAssertEqual(a.bounds.width, 200, accuracy: 8)
    }
}
