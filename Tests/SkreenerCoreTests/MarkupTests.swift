import CoreGraphics
import XCTest
@testable import SkreenerCore

/// Markup's drawing: each kind paints where it should and nowhere it shouldn't.
final class MarkupTests: XCTestCase {
    private let w = 400, h = 300

    /// A white image with `markups` drawn over it, as pixels (top-left origin).
    private func drawn(_ markups: [Markup]) -> PixelBuffer {
        let out = TestImages.image(width: w, height: h) { ctx, r in
            ctx.setFillColor(TestImages.white)
            ctx.fill(r)
            Markup.draw(markups, imageWidth: w, in: ctx)
        }
        return PixelBuffer(out)!
    }

    /// The pixel at a y-up image point.
    private func pixel(_ out: PixelBuffer, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        out.rgba(x: x, y: h - 1 - y)
    }

    private func isWhite(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r == 255 && p.g == 255 && p.b == 255 }

    /// About the default red (255, 59, 48).
    private func isRed(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r > 200 && p.g < 110 && p.b < 110 }

    func testRectangleStrokesItsEdgeNotItsCentre() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let out = drawn([Markup(.rectangle(rect))])
        XCTAssertTrue(isRed(pixel(out, 100, 150)), "left edge is \(pixel(out, 100, 150))")
        XCTAssertTrue(isRed(pixel(out, 200, 200)), "top edge is \(pixel(out, 200, 200))")
        XCTAssertTrue(isWhite(pixel(out, 200, 150)), "centre is \(pixel(out, 200, 150))")
        XCTAssertTrue(isWhite(pixel(out, 20, 20)), "far corner is \(pixel(out, 20, 20))")
    }

    func testHighlightTintsInsideOnly() {
        let rect = CGRect(x: 120, y: 80, width: 160, height: 60)
        let out = drawn([Markup(.highlight(rect), color: RGBColor.hex(0xFFCC00))])
        let inside = pixel(out, 200, 110)
        XCTAssertFalse(isWhite(inside), "highlight left the inside white")
        XCTAssertGreaterThanOrEqual(inside.r, 254)
        XCTAssertLessThan(inside.b, 200)
        // No shadow and no stroke: everything outside stays white.
        var changed = 0
        for y in 0..<h {
            for x in 0..<w where !rect.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                if !isWhite(pixel(out, x, y)) { changed += 1 }
            }
        }
        XCTAssertEqual(changed, 0, "pixels changed outside the highlight")
    }

    func testHighlightMultipliesSoDarkStaysDark() {
        let out = TestImages.image(width: w, height: h) { ctx, r in
            ctx.setFillColor(TestImages.black)
            ctx.fill(r)
            Markup.draw([Markup(.highlight(r))], imageWidth: w, in: ctx)
        }
        let p = PixelBuffer(out)!.rgba(x: 200, y: 150)
        XCTAssertTrue(p.r == 0 && p.g == 0 && p.b == 0, "black under a highlight is \(p)")
    }

    func testArrowPaintsItsShaftAndTip() {
        let out = drawn([Markup(.arrow(from: CGPoint(x: 50, y: 150), to: CGPoint(x: 350, y: 150)))])
        XCTAssertTrue(isRed(pixel(out, 200, 150)), "shaft is \(pixel(out, 200, 150))")
        XCTAssertTrue(isRed(pixel(out, 345, 150)), "near the tip is \(pixel(out, 345, 150))")
        // The head is wider than the shaft.
        let head = Markup.headLength(imageWidth: w)
        XCTAssertTrue(isRed(pixel(out, 350 - Int(head * 0.8), 150 + Int(head * 0.2))), "head is too narrow")
        XCTAssertTrue(isWhite(pixel(out, 200, 150 + Int(head * 2))), "shaft is too wide")
        XCTAssertTrue(isWhite(pixel(out, 380, 150)), "past the tip is \(pixel(out, 380, 150))")
    }

    func testTextPaintsInsideItsBounds() {
        let at = CGPoint(x: 60, y: 150)
        let bounds = Markup.textBounds("Hello", at: at, imageWidth: w)
        XCTAssertGreaterThan(bounds.width, 20)
        XCTAssertEqual(bounds.midY, at.y, accuracy: bounds.height / 4)
        let out = drawn([Markup(.text("Hello", at: at))])
        var red = 0
        for y in Int(bounds.minY)..<Int(bounds.maxY) {
            for x in Int(bounds.minX)..<Int(bounds.maxX) where isRed(pixel(out, x, y)) { red += 1 }
        }
        XCTAssertGreaterThan(red, 20, "text drew almost nothing in its bounds")
        XCTAssertTrue(isWhite(pixel(out, 300, 40)), "text drew far away")
    }

    func testTextIsUprightNotMirrored() {
        // "L" has its foot at the bottom right of its stem: more ink in the lower half than the upper, and on the left.
        let at = CGPoint(x: 100, y: 150)
        let bounds = Markup.textBounds("L", at: at, imageWidth: w)
        let out = drawn([Markup(.text("L", at: at), color: RGBColor.hex(0x000000))])
        var top = 0, bottom = 0, left = 0, right = 0
        for y in Int(bounds.minY)..<Int(bounds.maxY) {
            for x in Int(bounds.minX)..<Int(bounds.maxX) where pixel(out, x, y).r < 100 {
                if CGFloat(y) < bounds.midY { bottom += 1 } else { top += 1 }
                if CGFloat(x) < bounds.midX { left += 1 } else { right += 1 }
            }
        }
        XCTAssertGreaterThan(left, right, "L is mirrored left to right")
        XCTAssertGreaterThan(bottom, top / 2, "L has no foot at the bottom")
    }

    func testEmptyTextDrawsNothing() {
        let out = drawn([Markup(.text("", at: CGPoint(x: 100, y: 100)))])
        XCTAssertTrue(isWhite(pixel(out, 100, 100)))
    }

    func testSizesScaleWithTheImage() {
        XCTAssertEqual(Markup.lineWidth(imageWidth: 1179), 9, accuracy: 0.01)
        XCTAssertEqual(Markup.fontSize(imageWidth: 1179), 66, accuracy: 0.01)
        XCTAssertEqual(Markup.headLength(imageWidth: 1179), 45, accuracy: 0.01)
        XCTAssertEqual(Markup.lineWidth(imageWidth: 100), 3)
        XCTAssertEqual(Markup.lineWidth(imageWidth: 2358) / Markup.lineWidth(imageWidth: 1179), 2, accuracy: 0.001)
    }

    func testScaledScalesTheGeometryAndKeepsTheColor() {
        let blue = RGBColor.hex(0x007AFF)
        let arrow = Markup(.arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 30, y: 40)), color: blue)
        XCTAssertEqual(arrow.scaled(by: 0.5),
                       Markup(.arrow(from: CGPoint(x: 5, y: 10), to: CGPoint(x: 15, y: 20)), color: blue))
        XCTAssertEqual(Markup(.rectangle(CGRect(x: 10, y: 20, width: 30, height: 40))).scaled(by: 2),
                       Markup(.rectangle(CGRect(x: 20, y: 40, width: 60, height: 80))))
        XCTAssertEqual(Markup(.highlight(CGRect(x: 10, y: 20, width: 30, height: 40))).scaled(by: 0.5),
                       Markup(.highlight(CGRect(x: 5, y: 10, width: 15, height: 20))))
        XCTAssertEqual(Markup(.text("Hi", at: CGPoint(x: 10, y: 20))).scaled(by: 0.5),
                       Markup(.text("Hi", at: CGPoint(x: 5, y: 10))))
    }

    func testScaledLooksTheSameAtHalfSize() {
        // The preview (half size) draws the same picture as the export, only smaller.
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let small = TestImages.image(width: w / 2, height: h / 2) { ctx, r in
            ctx.setFillColor(TestImages.white)
            ctx.fill(r)
            Markup.draw([Markup(.rectangle(rect)).scaled(by: 0.5)], imageWidth: w / 2, in: ctx)
        }
        let out = PixelBuffer(small)!
        XCTAssertTrue(isRed(out.rgba(x: 50, y: h / 2 - 1 - 75)), "scaled edge is \(out.rgba(x: 50, y: h / 2 - 1 - 75))")
        XCTAssertTrue(isWhite(out.rgba(x: 100, y: h / 2 - 1 - 75)))
    }
}
