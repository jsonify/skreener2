import XCTest
@testable import Skreener

/// Geometry for the pen's polygonal mode: point-in-polygon and the decision to close.
final class PolygonToolTests: XCTestCase {
    /// A 100×100 square with its bottom-left corner at the origin.
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    func testPointInsidePolygon() {
        XCTAssertTrue(PolygonTool.contains(square, point: CGPoint(x: 50, y: 50)))
        XCTAssertTrue(PolygonTool.contains(square, point: CGPoint(x: 1, y: 1)))
    }

    func testPointOutsidePolygon() {
        XCTAssertFalse(PolygonTool.contains(square, point: CGPoint(x: 150, y: 50)))
        XCTAssertFalse(PolygonTool.contains(square, point: CGPoint(x: -1, y: 50)))
        XCTAssertFalse(PolygonTool.contains(square, point: CGPoint(x: 50, y: 200)))
    }

    func testConcavePolygonInsideAndOutside() {
        // An arrow-like notch cut into the right edge: the notch is outside the shape.
        let notched = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100),
                       CGPoint(x: 50, y: 50), CGPoint(x: 0, y: 100)]
        XCTAssertTrue(PolygonTool.contains(notched, point: CGPoint(x: 20, y: 50)))
        XCTAssertFalse(PolygonTool.contains(notched, point: CGPoint(x: 70, y: 80)))
    }

    func testFewerThanThreeVerticesEncloseNothing() {
        XCTAssertFalse(PolygonTool.contains([], point: .zero))
        XCTAssertFalse(PolygonTool.contains([CGPoint(x: 0, y: 0)], point: .zero))
        XCTAssertFalse(PolygonTool.contains([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)], point: CGPoint(x: 5, y: 5)))
    }

    func testClosesOnlyNearTheFirstVertexWithEnoughVertices() {
        let triangle = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        // Three vertices and the point lands within the threshold of the first: close.
        XCTAssertTrue(PolygonTool.shouldClose(triangle, at: CGPoint(x: 4, y: 3), within: 12))
        // Near the first vertex but too far away: do not close.
        XCTAssertFalse(PolygonTool.shouldClose(triangle, at: CGPoint(x: 20, y: 20), within: 12))
    }

    func testDoesNotCloseWithTooFewVertices() {
        let twoNearStart = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        XCTAssertFalse(PolygonTool.shouldClose(twoNearStart, at: CGPoint(x: 1, y: 1), within: 12))
        XCTAssertFalse(PolygonTool.shouldClose([], at: .zero, within: 12))
    }

    func testPathClosesOnlyWhenAsked() {
        let triangle = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        // Closed (the default): move, two lines, then the closing edge back to the first vertex and
        // the close marker that NSBezierPath.close() appends.
        XCTAssertEqual(PolygonTool.path(triangle).elementCount, 5)
        // Open: move and two lines, with no closing edge.
        XCTAssertEqual(PolygonTool.path(triangle, closed: false).elementCount, 3)
    }
}
