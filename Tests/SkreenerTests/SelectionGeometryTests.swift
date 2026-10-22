import XCTest
@testable import Skreener

/// Keyboard and drag math for the area selection (#102, #103). Bottom-left origin, like the overlay's views.
final class SelectionGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 150)

    private func apply(_ key: SelectionGeometry.Key, command: Bool = false, shift: Bool = false,
                       to r: CGRect? = nil) -> CGRect {
        SelectionGeometry.apply(key, command: command, shift: shift, to: r ?? rect, in: bounds)
    }

    func testKeyMapping() {
        XCTAssertEqual(SelectionGeometry.key(keyCode: 123), .left)
        XCTAssertEqual(SelectionGeometry.key(keyCode: 124), .right)
        XCTAssertEqual(SelectionGeometry.key(keyCode: 125), .down)
        XCTAssertEqual(SelectionGeometry.key(keyCode: 126), .up)
        XCTAssertNil(SelectionGeometry.key(keyCode: 30))   // ] no longer resizes: the scroll wheel does
        XCTAssertNil(SelectionGeometry.key(keyCode: 0))
    }

    func testArrowsMoveOneOrTenPoints() {
        XCTAssertEqual(apply(.right), rect.offsetBy(dx: 1, dy: 0))
        XCTAssertEqual(apply(.left, shift: true), rect.offsetBy(dx: -10, dy: 0))
        XCTAssertEqual(apply(.up), rect.offsetBy(dx: 0, dy: 1))
        XCTAssertEqual(apply(.down, shift: true), rect.offsetBy(dx: 0, dy: -10))
    }

    func testMovesStopAtTheScreenEdge() {
        let corner = CGRect(x: 0, y: 0, width: 50, height: 50)
        XCTAssertEqual(apply(.left, to: corner), corner)
        XCTAssertEqual(apply(.down, shift: true, to: corner), corner)
        let topRight = CGRect(x: 945, y: 745, width: 50, height: 50)
        XCTAssertEqual(apply(.right, shift: true, to: topRight), CGRect(x: 950, y: 745, width: 50, height: 50))
        XCTAssertEqual(apply(.up, shift: true, to: topRight), CGRect(x: 945, y: 750, width: 50, height: 50))
    }

    func testCommandArrowsResizeTheRightAndBottomEdges() {
        XCTAssertEqual(apply(.right, command: true), CGRect(x: 100, y: 100, width: 201, height: 150))
        XCTAssertEqual(apply(.left, command: true, shift: true), CGRect(x: 100, y: 100, width: 190, height: 150))
        // ↓ moves the bottom edge down: the top (maxY = 250) stays.
        XCTAssertEqual(apply(.down, command: true), CGRect(x: 100, y: 99, width: 200, height: 151))
        XCTAssertEqual(apply(.up, command: true, shift: true), CGRect(x: 100, y: 110, width: 200, height: 140))
    }

    func testCommandArrowsStayOnScreenAndKeepAPoint() {
        let edge = CGRect(x: 900, y: 5, width: 95, height: 20)
        XCTAssertEqual(apply(.right, command: true, shift: true, to: edge).maxX, 1000)
        XCTAssertEqual(apply(.down, command: true, shift: true, to: edge), CGRect(x: 900, y: 0, width: 95, height: 25))
        let tiny = CGRect(x: 10, y: 10, width: 3, height: 3)
        XCTAssertEqual(apply(.left, command: true, shift: true, to: tiny).width, SelectionGeometry.minSide)
        XCTAssertEqual(apply(.up, command: true, shift: true, to: tiny), CGRect(x: 10, y: 12, width: 3, height: 1))
    }

    func testScrollGrowsAndShrinksEverySide() {
        XCTAssertEqual(SelectionGeometry.resizeAllSides(rect, by: 1, in: bounds), CGRect(x: 99, y: 99, width: 202, height: 152))
        XCTAssertEqual(SelectionGeometry.resizeAllSides(rect, by: 10, in: bounds), CGRect(x: 90, y: 90, width: 220, height: 170))
        XCTAssertEqual(SelectionGeometry.resizeAllSides(rect, by: -1, in: bounds), CGRect(x: 101, y: 101, width: 198, height: 148))
        XCTAssertEqual(SelectionGeometry.resizeAllSides(rect, by: -10, in: bounds), CGRect(x: 110, y: 110, width: 180, height: 130))
    }

    func testGrowStopsAtTheScreenAndShrinkKeepsAPoint() {
        XCTAssertEqual(SelectionGeometry.resizeAllSides(CGRect(x: 2, y: 0, width: 50, height: 40), by: 10, in: bounds),
                       CGRect(x: 0, y: 0, width: 62, height: 50))
        XCTAssertEqual(SelectionGeometry.resizeAllSides(bounds, by: 1, in: bounds), bounds)
        let small = CGRect(x: 10, y: 10, width: 5, height: 1)
        XCTAssertEqual(SelectionGeometry.resizeAllSides(small, by: -10, in: bounds), CGRect(x: 12, y: 10, width: 1, height: 1))
    }

    func testRoundingKeepsTheSizeOfAFractionalPosition() {
        // `integral` would make this 201 × 151; dragging repeated that on every move and grew the selection.
        let r = CGRect(x: 100.5, y: 99.5, width: 200, height: 150)
        XCTAssertEqual(SelectionGeometry.rounded(r).size, r.size)
        XCTAssertEqual(SelectionGeometry.rounded(CGRect(x: 10.2, y: 20.7, width: 30.6, height: 40.1)),
                       CGRect(x: 10, y: 21, width: 31, height: 40))
    }

    func testPlainDragSpansStartAndCurrent() {
        let r = SelectionGeometry.dragRect(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 200, y: 450),
                                           square: false, fromCenter: false, in: bounds)
        XCTAssertEqual(r, CGRect(x: 200, y: 300, width: 100, height: 150))
    }

    func testShiftDragMakesASquareOnTheLongerSide() {
        let r = SelectionGeometry.dragRect(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 200, y: 450),
                                           square: true, fromCenter: false, in: bounds)
        XCTAssertEqual(r, CGRect(x: 150, y: 300, width: 150, height: 150))
    }

    func testShiftDragStaysSquareAtTheScreenEdge() {
        // 200 points to the right, but only 50 down to the bottom edge.
        let r = SelectionGeometry.dragRect(from: CGPoint(x: 500, y: 50), to: CGPoint(x: 700, y: 0),
                                           square: true, fromCenter: false, in: bounds)
        XCTAssertEqual(r, CGRect(x: 500, y: 0, width: 50, height: 50))
    }

    func testOptionDragGrowsAroundTheStart() {
        let r = SelectionGeometry.dragRect(from: CGPoint(x: 500, y: 400), to: CGPoint(x: 560, y: 380),
                                           square: false, fromCenter: true, in: bounds)
        XCTAssertEqual(r, CGRect(x: 440, y: 380, width: 120, height: 40))
        let sq = SelectionGeometry.dragRect(from: CGPoint(x: 500, y: 400), to: CGPoint(x: 560, y: 380),
                                            square: true, fromCenter: true, in: bounds)
        XCTAssertEqual(sq, CGRect(x: 440, y: 340, width: 120, height: 120))
    }

    func testResizeByHandles() {
        // Top-right corner (index 4) to (350, 300).
        XCTAssertEqual(SelectionGeometry.resize(rect, handle: 4, to: CGPoint(x: 350, y: 300), in: bounds),
                       CGRect(x: 100, y: 100, width: 250, height: 200))
        // Left edge (index 7) only moves x, and stops at the screen edge.
        XCTAssertEqual(SelectionGeometry.resize(rect, handle: 7, to: CGPoint(x: -40, y: 700), in: bounds),
                       CGRect(x: 0, y: 100, width: 300, height: 150))
        // Bottom edge (index 1) dragged above the top flips the rect.
        XCTAssertEqual(SelectionGeometry.resize(rect, handle: 1, to: CGPoint(x: 0, y: 300), in: bounds),
                       CGRect(x: 100, y: 250, width: 200, height: 50))
    }

    func testMoveStaysOnScreen() {
        XCTAssertEqual(SelectionGeometry.move(rect, to: CGPoint(x: 900, y: -20), in: bounds),
                       CGRect(x: 800, y: 0, width: 200, height: 150))
    }
}
