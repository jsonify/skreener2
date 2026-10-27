import Carbon.HIToolbox
import XCTest
@testable import Skreener

/// Presenter mode's zoom math, arrowheads and keys (#266). Bottom-left origin, like the overlay's views.
final class PresenterTests: XCTestCase {
    private let size = CGSize(width: 1000, height: 800)

    private func assertEqual(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.0001, file: file, line: line)
    }

    func testStartsUnzoomedShowingTheWholeScreen() {
        let z = PresenterZoom(size: size)
        XCTAssertFalse(z.isZoomed)
        XCTAssertEqual(z.visibleRect, CGRect(origin: .zero, size: size))
        XCTAssertEqual(z.transform, .identity)
    }

    func testZoomKeepsThePointUnderThePointer() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 2, anchor: CGPoint(x: 100, y: 100))
        XCTAssertEqual(z.scale, 2)
        XCTAssertEqual(z.visibleRect, CGRect(x: 50, y: 50, width: 500, height: 400))
        assertEqual(z.screenPoint(at: CGPoint(x: 100, y: 100)), CGPoint(x: 100, y: 100))

        // Zooming further around another point keeps that one in place too.
        let anchor = CGPoint(x: 600, y: 300), under = z.screenPoint(at: anchor)
        z.zoom(to: 3, anchor: anchor)
        assertEqual(z.screenPoint(at: anchor), under)
    }

    func testZoomAroundTheCenter() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 2, anchor: CGPoint(x: 500, y: 400))
        XCTAssertEqual(z.visibleRect, CGRect(x: 250, y: 200, width: 500, height: 400))
    }

    func testVisiblePartStaysOnTheScreen() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 4, anchor: CGPoint(x: 1000, y: 800))
        XCTAssertEqual(z.visibleRect, CGRect(x: 750, y: 600, width: 250, height: 200))
        z.zoom(to: 4, anchor: CGPoint(x: -50, y: -50))
        XCTAssertGreaterThanOrEqual(z.visibleRect.minX, 0)
        XCTAssertGreaterThanOrEqual(z.visibleRect.minY, 0)
        XCTAssertLessThanOrEqual(z.visibleRect.maxX, size.width)
        XCTAssertLessThanOrEqual(z.visibleRect.maxY, size.height)
    }

    func testZoomIsLimitedAndSnapsBackToOne() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 20, anchor: .zero)
        XCTAssertEqual(z.scale, PresenterZoom.range.upperBound)
        z.zoom(to: 1.01, anchor: CGPoint(x: 300, y: 300))
        XCTAssertEqual(z.scale, 1)
        XCTAssertFalse(z.isZoomed)
        XCTAssertEqual(z.visibleRect, CGRect(origin: .zero, size: size))
        z.zoom(to: 0.25, anchor: .zero)
        XCTAssertEqual(z.scale, 1)
    }

    func testFollowShowsWhatIsReallyUnderThePointer() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 2, anchor: CGPoint(x: 500, y: 400))
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 1000, y: 800), CGPoint(x: 120, y: 700), CGPoint(x: 500, y: 400)] {
            z.follow(p)
            assertEqual(z.screenPoint(at: p), p)
        }
        z.follow(CGPoint(x: 1000, y: 800))
        XCTAssertEqual(z.visibleRect, CGRect(x: 500, y: 400, width: 500, height: 400))
        // A pointer beyond the screen (another display's overlay) still leaves the view inside the screen.
        z.follow(CGPoint(x: 5000, y: -300))
        XCTAssertEqual(z.visibleRect, CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    func testTransformMapsScreenPointsToTheView() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 3, anchor: CGPoint(x: 700, y: 250))
        for p in [CGPoint(x: 10, y: 20), CGPoint(x: 700, y: 250), CGPoint(x: 999, y: 799)] {
            assertEqual(z.screenPoint(at: p).applying(z.transform), p)
        }
    }

    func testResetGoesBackToTheWholeScreen() {
        var z = PresenterZoom(size: size)
        z.zoom(to: 3, anchor: CGPoint(x: 700, y: 250))
        z.reset()
        XCTAssertEqual(z, PresenterZoom(size: size))
    }

    func testScrollFactor() {
        XCTAssertGreaterThan(PresenterZoom.factor(scrollDelta: 1, inverted: false, precise: false), 1)
        XCTAssertLessThan(PresenterZoom.factor(scrollDelta: 1, inverted: true, precise: false), 1)
        XCTAssertLessThan(PresenterZoom.factor(scrollDelta: -1, inverted: false, precise: true), 1)
        // A wheel notch zooms more than a point of trackpad scrolling.
        XCTAssertGreaterThan(PresenterZoom.factor(scrollDelta: 1, inverted: false, precise: false),
                             PresenterZoom.factor(scrollDelta: 1, inverted: false, precise: true))
        XCTAssertEqual(PresenterZoom.factor(scrollDelta: 0, inverted: false, precise: true), 1)
    }

    func testArrowHead() {
        let head = PresenterMark.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), length: 20)
        assertEqual(head.base, CGPoint(x: 80, y: 0))
        assertEqual(head.left, CGPoint(x: 80, y: 11))
        assertEqual(head.right, CGPoint(x: 80, y: -11))
        // A short arrow gets a head of at most half its length.
        let short = PresenterMark.arrowHead(from: .zero, to: CGPoint(x: 0, y: 10), length: 20)
        assertEqual(short.base, CGPoint(x: 0, y: 5))
        let none = PresenterMark.arrowHead(from: CGPoint(x: 3, y: 3), to: CGPoint(x: 3, y: 3), length: 20)
        assertEqual(none.base, CGPoint(x: 3, y: 3))
    }

    func testTinyArrowsAndBoxesAreDropped() {
        let click = PresenterMark(tool: .arrow, points: [.zero, CGPoint(x: 2, y: 2)], color: .red, width: 4)
        XCTAssertFalse(click.isVisible)
        let drag = PresenterMark(tool: .rect, points: [.zero, CGPoint(x: 40, y: 2)], color: .red, width: 4)
        XCTAssertTrue(drag.isVisible)
        let dot = PresenterMark(tool: .pen, points: [CGPoint(x: 5, y: 5)], color: .red, width: 4)
        XCTAssertTrue(dot.isVisible)
    }

    func testKeys() {
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_Escape, command: false), .escape)
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_Equal, command: true), .zoomIn)
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_Equal, command: false), .zoomIn)
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_Minus, command: true), .zoomOut)
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_0, command: true), .resetZoom)
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_Z, command: true), .undo)
        XCTAssertNil(PresenterCommand.from(keyCode: kVK_ANSI_Z, command: false))
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_P, command: false), .tool(.pen))
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_A, command: false), .tool(.arrow))
        XCTAssertEqual(PresenterCommand.from(keyCode: kVK_ANSI_R, command: false), .tool(.rect))
        XCTAssertNil(PresenterCommand.from(keyCode: kVK_ANSI_A, command: true))
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        for (i, key) in digits.enumerated() {
            XCTAssertEqual(PresenterCommand.from(keyCode: key, command: false), .color(i))
            XCTAssertLessThan(i, PresenterMark.colors.count)
        }
        XCTAssertNil(PresenterCommand.from(keyCode: kVK_ANSI_6, command: false))
    }
}
