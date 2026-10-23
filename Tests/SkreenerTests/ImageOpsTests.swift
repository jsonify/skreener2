import AppKit
import XCTest
@testable import Skreener

final class ImageOpsTests: XCTestCase {
    private func pixels(_ img: NSImage) throws -> (width: Int, height: Int) {
        var r = CGRect(origin: .zero, size: img.size)
        let cg = try XCTUnwrap(img.cgImage(forProposedRect: &r, context: nil, hints: nil))
        return (cg.width, cg.height)
    }

    private func color(_ img: NSImage, x: Int, y: Int) throws -> NSColor {
        let rep = try XCTUnwrap(img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    // MARK: Resize (#122)

    func testSizeLimits() {
        XCTAssertNil(ImageOps.resizeProblem(width: 8, height: 16_384))
        XCTAssertNotNil(ImageOps.resizeProblem(width: 7, height: 100))
        XCTAssertNotNil(ImageOps.resizeProblem(width: 100, height: 16_385))
    }

    func testProportionalSide() {
        XCTAssertEqual(ImageOps.proportional(800, isWidth: true, original: (1600, 1000)), 500)
        XCTAssertEqual(ImageOps.proportional(250, isWidth: false, original: (1600, 1000)), 400)
    }

    func testResizeHalvesPixelsAndKeepsDensity() throws {
        // A Retina image: 40 × 20 px shown at 20 × 10 pt.
        let img = TestImages.image(width: 40, height: 20, points: NSSize(width: 20, height: 10)) { r in
            NSColor.red.setFill(); r.fill()
        }
        let out = try XCTUnwrap(ImageOps.resized(img, width: 20, height: 10))
        let px = try pixels(out)
        XCTAssertEqual(px.width, 20)
        XCTAssertEqual(px.height, 10)
        XCTAssertEqual(out.size, NSSize(width: 10, height: 5))
    }

    // MARK: Cut Out (#121)

    /// 10 px wide, 30 px tall: red, green and blue bands of 10 rows, red at the top.
    private func bands() -> NSImage {
        TestImages.image(width: 10, height: 30) { r in
            NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 10, height: 10).fill()
            NSColor.green.setFill(); NSRect(x: 0, y: 10, width: 10, height: 10).fill()
            NSColor.red.setFill(); NSRect(x: 0, y: 20, width: 10, height: 10).fill()
        }
    }

    func testRemovingRowsJoinsTheRest() throws {
        let out = try XCTUnwrap(ImageOps.removing(10..<20, axis: .horizontal, from: bands()))
        let px = try pixels(out)
        XCTAssertEqual(px.width, 10)
        XCTAssertEqual(px.height, 20)
        // Red stays on top, blue now right under it (bitmap rows count from the top).
        XCTAssertGreaterThan(try color(out, x: 5, y: 5).redComponent, 0.9)
        XCTAssertGreaterThan(try color(out, x: 5, y: 15).blueComponent, 0.9)
        XCTAssertLessThan(try color(out, x: 5, y: 15).greenComponent, 0.1)
    }

    func testRemovingColumns() throws {
        let img = TestImages.image(width: 30, height: 4) { r in
            NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 10, height: 4).fill()
            NSColor.green.setFill(); NSRect(x: 10, y: 0, width: 10, height: 4).fill()
            NSColor.blue.setFill(); NSRect(x: 20, y: 0, width: 10, height: 4).fill()
        }
        let out = try XCTUnwrap(ImageOps.removing(0..<10, axis: .vertical, from: img))
        XCTAssertEqual(try pixels(out).width, 20)
        XCTAssertGreaterThan(try color(out, x: 2, y: 2).greenComponent, 0.9)
        XCTAssertGreaterThan(try color(out, x: 15, y: 2).blueComponent, 0.9)
    }

    func testCannotRemoveEverything() {
        XCTAssertNil(ImageOps.removing(0..<30, axis: .horizontal, from: bands()))
        XCTAssertNil(ImageOps.removing(5..<5, axis: .horizontal, from: bands()))
    }

    func testCoordinatesAfterACut() {
        XCTAssertEqual(ImageOps.afterCut(5, lo: 10, hi: 20), 5)     // before the strip: stays
        XCTAssertEqual(ImageOps.afterCut(15, lo: 10, hi: 20), 10)   // inside: on the join
        XCTAssertEqual(ImageOps.afterCut(25, lo: 10, hi: 20), 15)   // past it: moves back by its length
    }
}
