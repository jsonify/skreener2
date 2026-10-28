import AppKit
import XCTest
@testable import Skreener

final class AlignmentGuidesTests: XCTestCase {
    private let threshold: CGFloat = 8

    func testLeftEdgeWithinThresholdSnapsAndEmitsAVerticalGuide() {
        let moved = CGRect(x: 103, y: 50, width: 40, height: 40)
        // A wide, far-away neighbor so only its left edge is within reach (its center and right edge are not).
        let other = CGRect(x: 100, y: 200, width: 200, height: 30)
        let found = AlignmentGuides.align(moved, to: [other], threshold: threshold)
        XCTAssertEqual(found.dx, -3)                 // left edge pulled from 103 to 100
        XCTAssertEqual(found.dy, 0)                  // nothing lines up vertically
        XCTAssertEqual(found.guides.count, 1)
        let guide = found.guides[0]
        XCTAssertEqual(guide.from.x, 100)            // vertical: a constant X
        XCTAssertEqual(guide.to.x, 100)
        // Spans from the lowest to the highest edge of the moved and matched rects.
        XCTAssertEqual(min(guide.from.y, guide.to.y), 50)
        XCTAssertEqual(max(guide.from.y, guide.to.y), 230)
    }

    func testCenterXAlignmentSnapsToCenter() {
        let moved = CGRect(x: 50, y: 50, width: 40, height: 40)   // midX 70
        let other = CGRect(x: 40, y: 200, width: 64, height: 20)  // midX 72, edges out of reach
        let found = AlignmentGuides.align(moved, to: [other], threshold: threshold)
        XCTAssertEqual(found.dx, 2)                  // center pulled from 70 to 72
        XCTAssertEqual(found.dy, 0)
        XCTAssertEqual(found.guides.count, 1)
        XCTAssertEqual(found.guides[0].from.x, 72)   // guide on the shared center line
    }

    func testNothingWithinThresholdDoesNotSnap() {
        let moved = CGRect(x: 0, y: 0, width: 40, height: 40)
        let other = CGRect(x: 100, y: 100, width: 40, height: 40)
        let found = AlignmentGuides.align(moved, to: [other], threshold: threshold)
        XCTAssertEqual(found.dx, 0)
        XCTAssertEqual(found.dy, 0)
        XCTAssertTrue(found.guides.isEmpty)
        XCTAssertFalse(found.isActive)
    }

    func testXAndYSnapIndependently() {
        let other = CGRect(x: 100, y: 100, width: 40, height: 40)

        // Lines up in X only (far in Y): a vertical guide, no Y offset.
        let xOnly = AlignmentGuides.align(CGRect(x: 103, y: 500, width: 40, height: 40), to: [other], threshold: threshold)
        XCTAssertEqual(xOnly.dx, -3)
        XCTAssertEqual(xOnly.dy, 0)
        XCTAssertEqual(xOnly.guides.count, 1)
        XCTAssertEqual(xOnly.guides[0].from.x, xOnly.guides[0].to.x)   // vertical

        // Lines up in Y only (far in X): a horizontal guide, no X offset.
        let yOnly = AlignmentGuides.align(CGRect(x: 500, y: 102, width: 40, height: 40), to: [other], threshold: threshold)
        XCTAssertEqual(yOnly.dx, 0)
        XCTAssertEqual(yOnly.dy, -2)
        XCTAssertEqual(yOnly.guides.count, 1)
        XCTAssertEqual(yOnly.guides[0].from.y, yOnly.guides[0].to.y)   // horizontal

        // Lines up in both: one guide per axis.
        let both = AlignmentGuides.align(CGRect(x: 103, y: 102, width: 40, height: 40), to: [other], threshold: threshold)
        XCTAssertEqual(both.dx, -3)
        XCTAssertEqual(both.dy, -2)
        XCTAssertEqual(both.guides.count, 2)
    }

    func testNearestCandidateWinsOnEachAxis() {
        let moved = CGRect(x: 105, y: 50, width: 40, height: 40)   // minX 105
        let near = CGRect(x: 103, y: 200, width: 200, height: 20)  // left edge 103, 2 away
        let far = CGRect(x: 99, y: 300, width: 200, height: 20)    // left edge 99, 6 away
        let found = AlignmentGuides.align(moved, to: [far, near], threshold: threshold)
        XCTAssertEqual(found.dx, -2)                 // snaps to the closer neighbor, not the farther
        XCTAssertEqual(found.guides.first?.from.x, 103)
    }
}
