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
}
