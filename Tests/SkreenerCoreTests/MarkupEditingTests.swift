import CoreGraphics
import XCTest
@testable import SkreenerCore

/// Editing drawn markups and redactions (#440): picking one under a finger, moving it and dragging its handles.
final class MarkupEditingTests: XCTestCase {
    private let width = 400

    func testArrowIsHitNearItsShaftOnly() {
        let arrow = Markup(.arrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100)))
        XCTAssertTrue(arrow.hits(CGPoint(x: 200, y: 108), tolerance: 10, imageWidth: width))
        XCTAssertFalse(arrow.hits(CGPoint(x: 200, y: 140), tolerance: 10, imageWidth: width))
        XCTAssertFalse(arrow.hits(CGPoint(x: 340, y: 100), tolerance: 10, imageWidth: width), "past the head")
    }

    func testRectangleIsHitOnItsOutlineNotItsMiddle() {
        let rect = Markup(.rectangle(CGRect(x: 100, y: 100, width: 200, height: 100)))
        XCTAssertTrue(rect.hits(CGPoint(x: 104, y: 150), tolerance: 10, imageWidth: width))
        XCTAssertTrue(rect.hits(CGPoint(x: 200, y: 92), tolerance: 10, imageWidth: width))
        XCTAssertFalse(rect.hits(CGPoint(x: 200, y: 150), tolerance: 10, imageWidth: width))
    }

    func testTinyRectangleIsHitAnywhereInside() {
        let rect = Markup(.rectangle(CGRect(x: 100, y: 100, width: 12, height: 12)))
        XCTAssertTrue(rect.hits(CGPoint(x: 106, y: 106), tolerance: 10, imageWidth: width))
    }

    func testEllipseIsHitOnItsCurve() {
        let ellipse = Markup(.ellipse(CGRect(x: 100, y: 100, width: 200, height: 100)))
        XCTAssertTrue(ellipse.hits(CGPoint(x: 200, y: 198), tolerance: 10, imageWidth: width), "top of the curve")
        XCTAssertTrue(ellipse.hits(CGPoint(x: 103, y: 150), tolerance: 10, imageWidth: width), "left of the curve")
        XCTAssertFalse(ellipse.hits(CGPoint(x: 200, y: 150), tolerance: 10, imageWidth: width), "centre")
        XCTAssertFalse(ellipse.hits(CGPoint(x: 104, y: 104), tolerance: 10, imageWidth: width), "box corner")
    }

    func testHighlightAndTextAreHitInside() {
        let highlight = Markup(.highlight(CGRect(x: 100, y: 100, width: 200, height: 40)))
        XCTAssertTrue(highlight.hits(CGPoint(x: 200, y: 120), tolerance: 0, imageWidth: width))
        let text = Markup(.text("Hello", at: CGPoint(x: 100, y: 200)))
        XCTAssertTrue(text.hits(CGPoint(x: 110, y: 200), tolerance: 0, imageWidth: width))
        XCTAssertFalse(text.hits(CGPoint(x: 90, y: 260), tolerance: 0, imageWidth: width))
    }

    func testPenIsHitAlongItsPath() {
        let pen = Markup(.pen([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]))
        XCTAssertTrue(pen.hits(CGPoint(x: 104, y: 50), tolerance: 6, imageWidth: width))
        XCTAssertFalse(pen.hits(CGPoint(x: 50, y: 50), tolerance: 6, imageWidth: width))
    }

    func testIndexPicksTheNewestUnderThePoint() {
        let a = Markup(.highlight(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let b = Markup(.highlight(CGRect(x: 50, y: 50, width: 100, height: 100)))
        XCTAssertEqual(Markup.index(at: CGPoint(x: 75, y: 75), in: [a, b], tolerance: 0, imageWidth: width), 1)
        XCTAssertEqual(Markup.index(at: CGPoint(x: 25, y: 25), in: [a, b], tolerance: 0, imageWidth: width), 0)
        XCTAssertNil(Markup.index(at: CGPoint(x: 300, y: 300), in: [a, b], tolerance: 0, imageWidth: width))
    }

    func testMovingKeepsColourWidthAndShape() {
        let m = Markup(.line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 20)), color: .hex(0x007AFF), width: 2)
        let moved = m.offsetBy(dx: 5, dy: -3)
        XCTAssertEqual(moved.kind, .line(from: CGPoint(x: 15, y: 7), to: CGPoint(x: 55, y: 17)))
        XCTAssertEqual(moved.color, m.color)
        XCTAssertEqual(moved.width, 2)
    }

    func testDraggingAnArrowsHeadKeepsItsTail() {
        let m = Markup(.arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(m.moving(.end, to: CGPoint(x: 80, y: 20)).kind,
                       .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 20)))
        XCTAssertEqual(m.moving(.start, to: CGPoint(x: 0, y: 0)).kind,
                       .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50)))
    }

    func testDraggingACornerKeepsTheOppositeOne() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 50)
        // Corner 2 is the top right (y-up); the bottom left stays.
        XCTAssertEqual(BoxHandles.rect(r, movingCorner: 2, to: CGPoint(x: 250, y: 300)),
                       CGRect(x: 100, y: 100, width: 150, height: 200))
        // Dragged past the opposite corner, the box flips.
        XCTAssertEqual(BoxHandles.rect(r, movingCorner: 2, to: CGPoint(x: 50, y: 60)),
                       CGRect(x: 50, y: 60, width: 50, height: 40))
        let m = Markup(.rectangle(r)).moving(.corner(0), to: CGPoint(x: 90, y: 80))
        XCTAssertEqual(m.kind, .rectangle(CGRect(x: 90, y: 80, width: 110, height: 70)))
    }

    func testHandles() {
        XCTAssertEqual(Markup(.arrow(from: .zero, to: CGPoint(x: 1, y: 1))).handles.map { $0.handle }, [.start, .end])
        XCTAssertEqual(Markup(.ellipse(CGRect(x: 0, y: 0, width: 10, height: 10))).handles.count, 4)
        XCTAssertTrue(Markup(.text("Hi", at: .zero)).handles.isEmpty)
        XCTAssertTrue(Markup(.pen([.zero, CGPoint(x: 5, y: 5)])).handles.isEmpty)
    }

    func testRedactionEditing() {
        let r = Redaction(rect: CGRect(x: 10, y: 10, width: 40, height: 20), style: .blur)
        XCTAssertEqual(r.offsetBy(dx: 5, dy: 5).rect, CGRect(x: 15, y: 15, width: 40, height: 20))
        XCTAssertEqual(r.moving(corner: 1, to: CGPoint(x: 70, y: 0)).rect, CGRect(x: 10, y: 0, width: 60, height: 30))
        XCTAssertEqual(r.moving(corner: 1, to: CGPoint(x: 70, y: 0)).style, .blur)
        let other = Redaction(rect: CGRect(x: 30, y: 10, width: 40, height: 20), style: .solid)
        XCTAssertEqual(Redaction.index(at: CGPoint(x: 40, y: 20), in: [r, other], tolerance: 0), 1)
        XCTAssertEqual(Redaction.index(at: CGPoint(x: 5, y: 20), in: [r, other], tolerance: 6), 0)
        XCTAssertNil(Redaction.index(at: CGPoint(x: 200, y: 200), in: [r, other], tolerance: 6))
    }

    func testNudgeDistanceIsTwoPercentOfShorterSide() {
        XCTAssertEqual(Nudge.distance(imageSize: CGSize(width: 1000, height: 2000)), 20, accuracy: 0.001)
        XCTAssertEqual(Nudge.distance(imageSize: CGSize(width: 3000, height: 500)), 10, accuracy: 0.001)
        XCTAssertEqual(Nudge.distance(imageSize: CGSize(width: 10, height: 10)), 1, "never less than a pixel")
    }

    func testNudgeDirectionsAreAsTheyLookOnScreen() {
        let size = CGSize(width: 1000, height: 1000)
        let box = CGRect(x: 400, y: 400, width: 100, height: 100)
        XCTAssertEqual(Nudge.up.offset(for: box, imageSize: size), CGVector(dx: 0, dy: 20), "up is +y")
        XCTAssertEqual(Nudge.down.offset(for: box, imageSize: size), CGVector(dx: 0, dy: -20))
        XCTAssertEqual(Nudge.left.offset(for: box, imageSize: size), CGVector(dx: -20, dy: 0))
        XCTAssertEqual(Nudge.right.offset(for: box, imageSize: size), CGVector(dx: 20, dy: 0))
    }

    func testNudgeStopsAtTheImageEdge() {
        let size = CGSize(width: 1000, height: 1000)
        XCTAssertEqual(Nudge.right.offset(for: CGRect(x: 890, y: 0, width: 100, height: 50), imageSize: size).dx, 10,
                       "only the 10 px left to the edge")
        XCTAssertEqual(Nudge.right.offset(for: CGRect(x: 900, y: 0, width: 100, height: 50), imageSize: size), .zero)
        XCTAssertEqual(Nudge.left.offset(for: CGRect(x: 0, y: 10, width: 100, height: 50), imageSize: size), .zero)
        XCTAssertEqual(Nudge.up.offset(for: CGRect(x: 0, y: 950, width: 10, height: 50), imageSize: size), .zero)
        XCTAssertEqual(Nudge.down.offset(for: CGRect(x: 0, y: 5, width: 10, height: 50), imageSize: size).dy, -5)
    }

    func testNudgeOfAFlatOrEmptyBoundsAndOversizedBounds() {
        let size = CGSize(width: 1000, height: 1000)
        let flat = CGRect(x: 100, y: 100, width: 200, height: 0)
        XCTAssertEqual(Nudge.up.offset(for: flat, imageSize: size).dy, 20, "an arrow's bounds can be flat")
        XCTAssertEqual(Nudge.up.offset(for: .null, imageSize: size), .zero)
        let wide = CGRect(x: -50, y: 0, width: 1200, height: 10)
        XCTAssertEqual(Nudge.right.offset(for: wide, imageSize: size).dx, 20, "wider than the image: not held back")
    }

    func testNudgedMarkupAndRedactionMoveByTheOffset() {
        let size = CGSize(width: 500, height: 800)
        let m = Markup(.rectangle(CGRect(x: 100, y: 100, width: 50, height: 50)))
        let v = Nudge.right.offset(for: m.selectionBounds(imageWidth: 500), imageSize: size)
        XCTAssertEqual(m.offsetBy(dx: v.dx, dy: v.dy).kind, .rectangle(CGRect(x: 110, y: 100, width: 50, height: 50)))
        let r = Redaction(rect: CGRect(x: 0, y: 0, width: 40, height: 40), style: .solid)
        XCTAssertEqual(Nudge.left.offset(for: r.rect, imageSize: size), .zero)
        let w = Nudge.up.offset(for: r.rect, imageSize: size)
        XCTAssertEqual(r.offsetBy(dx: w.dx, dy: w.dy).rect, CGRect(x: 0, y: 10, width: 40, height: 40))
    }
}
