import AppKit
import XCTest
@testable import Skreener

final class ObjectSnapTests: XCTestCase {
    /// A white 400 × 300 px image with a blue "button" from (100, 80) to (220, 120), top-left origin, and some darker
    /// "text" inside it.
    private func button() -> PixelBuffer {
        let img = TestImages.image(width: 400, height: 300) { r in
            NSColor.white.setFill(); r.fill()
            NSColor.systemBlue.setFill()
            // Bottom-left origin: top 80 → y = 300 - 120.
            NSRect(x: 100, y: 180, width: 120, height: 40).fill()
            NSColor.black.setFill()
            NSRect(x: 130, y: 195, width: 60, height: 10).fill()
        }
        var r = CGRect(origin: .zero, size: img.size)
        return PixelBuffer(img.cgImage(forProposedRect: &r, context: nil, hints: nil)!)!
    }

    func testABoxDrawnRoughlyAroundAButtonGetsItsExactBounds() {
        let found = ObjectSnap.snap(CGRect(x: 94, y: 75, width: 132, height: 52), in: button(), reach: 8)
        XCTAssertEqual(found.rect, CGRect(x: 100, y: 80, width: 120, height: 40))
        XCTAssertEqual(found.sides, ObjectSnap.Sides(left: true, right: true, top: true, bottom: true))
    }

    func testABoxDrawnJustInsideSnapsOutToTheEdges() {
        let found = ObjectSnap.snap(CGRect(x: 104, y: 84, width: 112, height: 33), in: button(), reach: 8)
        XCTAssertEqual(found.rect, CGRect(x: 100, y: 80, width: 120, height: 40))
    }

    func testNothingNearbyLeavesTheBoxAlone() {
        let box = CGRect(x: 250, y: 150, width: 100, height: 100)
        let found = ObjectSnap.snap(box, in: button(), reach: 8)
        XCTAssertEqual(found.rect, box)
        XCTAssertFalse(found.sides.any)
    }

    func testSimilarObjectsAreFound() {
        // Four identical badges in a row, each 40 × 40 px with a mark inside.
        let img = TestImages.image(width: 400, height: 100) { r in
            NSColor.white.setFill(); r.fill()
            for i in 0..<4 {
                let x = CGFloat(20 + i * 90)
                NSColor.systemOrange.setFill(); NSRect(x: x, y: 30, width: 40, height: 40).fill()
                NSColor.black.setFill(); NSRect(x: x + 10, y: 40, width: 12, height: 20).fill()
            }
        }
        var r = CGRect(origin: .zero, size: img.size)
        let buf = PixelBuffer(img.cgImage(forProposedRect: &r, context: nil, hints: nil)!)!
        // The first badge, top-left origin: y = 100 - 70.
        let found = ObjectSnap.similarNow(to: CGRect(x: 20, y: 30, width: 40, height: 40), in: buf)
        XCTAssertEqual(Set(found.map { Int($0.minX) }), [110, 200, 290])
        XCTAssertTrue(found.allSatisfy { $0.minY == 30 && $0.width == 40 && $0.height == 40 })
    }

    func testAFlatBoxMatchesNothing() {
        let found = ObjectSnap.similarNow(to: CGRect(x: 300, y: 200, width: 40, height: 40), in: button())
        XCTAssertTrue(found.isEmpty)
    }
}
