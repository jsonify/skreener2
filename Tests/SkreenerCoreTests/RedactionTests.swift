import CoreGraphics
import XCTest
@testable import SkreenerCore

/// Redaction's drawing: each style changes only its rect.
final class RedactionTests: XCTestCase {
    private let w = 400, h = 300

    /// A color ramp, so every pixel differs from its neighbours and a cover is easy to see.
    private func image() -> CGImage {
        TestImages.image(width: w, height: h) { ctx, _ in
            for y in 0..<h {
                for x in 0..<w {
                    ctx.setFillColor(TestImages.srgb(CGFloat(x) / CGFloat(w), CGFloat(y) / CGFloat(h),
                                                     CGFloat((x * 7 + y * 13) % 256) / 255))
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    /// The image with `redactions` drawn over it, as pixels (top-left origin).
    private func redacted(_ source: CGImage, _ redactions: [Redaction]) -> PixelBuffer {
        let out = TestImages.image(width: w, height: h) { ctx, r in
            ctx.draw(source, in: r)
            Redaction.draw(redactions, over: source, in: ctx)
        }
        return PixelBuffer(out)!
    }

    /// The pixel rows (top-left origin) of a y-up rect.
    private func rows(_ r: CGRect) -> Range<Int> { (h - Int(r.maxY))..<(h - Int(r.minY)) }

    private func same(_ a: PixelBuffer, _ b: PixelBuffer, x: Int, y: Int) -> Bool {
        a.rgba(x: x, y: y) == b.rgba(x: x, y: y)
    }

    private func assertOutsideUntouched(_ out: PixelBuffer, _ original: PixelBuffer, rect: CGRect,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let inside = CGRect(x: rect.minX, y: CGFloat(h) - rect.maxY, width: rect.width, height: rect.height)
        var changed = 0
        for y in 0..<h {
            for x in 0..<w where !inside.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                if !same(out, original, x: x, y: y) { changed += 1 }
            }
        }
        XCTAssertEqual(changed, 0, "pixels changed outside the rect", file: file, line: line)
    }

    func testSolidMakesTheRectBlack() {
        let source = image(), original = PixelBuffer(source)!
        let rect = CGRect(x: 50, y: 60, width: 120, height: 40)
        let out = redacted(source, [Redaction(rect: rect, style: .solid)])
        for y in rows(rect) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let p = out.rgba(x: x, y: y)
                XCTAssertTrue(p.r == 0 && p.g == 0 && p.b == 0 && p.a == 255, "(\(x), \(y)) is \(p)")
            }
        }
        assertOutsideUntouched(out, original, rect: rect)
    }

    func testPixelateMakesEachBlockUniform() {
        let source = image(), original = PixelBuffer(source)!
        let block = Int(Redaction.blockSize(imageWidth: w))
        XCTAssertEqual(block, 10)
        let rect = CGRect(x: 40, y: 40, width: 100, height: 60)
        let out = redacted(source, [Redaction(rect: rect, style: .pixelate)])
        var differs = false
        for by in stride(from: Int(rect.minY), to: Int(rect.maxY), by: block) {
            for bx in stride(from: Int(rect.minX), to: Int(rect.maxX), by: block) {
                let cell = CGRect(x: bx, y: by, width: block, height: block)
                let first = out.rgba(x: bx, y: rows(cell).lowerBound)
                for y in rows(cell) {
                    for x in bx..<(bx + block) {
                        XCTAssertTrue(out.rgba(x: x, y: y) == first, "block at (\(bx), \(by)) is not uniform")
                        if !same(out, original, x: x, y: y) { differs = true }
                    }
                }
            }
        }
        XCTAssertTrue(differs, "pixelate left the image as it was")
        assertOutsideUntouched(out, original, rect: rect)
    }

    func testPixelateTakesEachBlocksCenterColor() {
        let source = image(), original = PixelBuffer(source)!
        let rect = CGRect(x: 40, y: 40, width: 10, height: 10)
        let out = redacted(source, [Redaction(rect: rect, style: .pixelate)])
        // The cell's center is (45, 45) y-up: the pixel in column 45, row h - 45 from the top.
        let p = out.rgba(x: 42, y: h - 42), q = original.rgba(x: 45, y: h - 45)
        XCTAssertEqual(Double(p.r), Double(q.r), accuracy: 1)
        XCTAssertEqual(Double(p.g), Double(q.g), accuracy: 1)
        XCTAssertEqual(Double(p.b), Double(q.b), accuracy: 1)
    }

    func testBlurChangesOnlyTheRect() {
        let source = image(), original = PixelBuffer(source)!
        let rect = CGRect(x: 100, y: 100, width: 80, height: 50)
        let out = redacted(source, [Redaction(rect: rect, style: .blur)])
        var changed = 0
        for y in rows(rect) {
            for x in Int(rect.minX)..<Int(rect.maxX) where !same(out, original, x: x, y: y) { changed += 1 }
        }
        XCTAssertGreaterThan(changed, Int(rect.width * rect.height) / 2, "blur barely changed the rect")
        assertOutsideUntouched(out, original, rect: rect)
    }

    func testRectsOutsideTheImageAreClipped() {
        let source = image(), original = PixelBuffer(source)!
        let rect = CGRect(x: w - 20, y: -30, width: 60, height: 60)
        let out = redacted(source, [Redaction(rect: rect, style: .solid)])
        XCTAssertEqual(out.rgba(x: w - 1, y: h - 1).r, 0)
        assertOutsideUntouched(out, original, rect: rect.intersection(CGRect(x: 0, y: 0, width: w, height: h)))
    }

    func testScaledKeepsTheStyle() {
        let r = Redaction(rect: CGRect(x: 10, y: 20, width: 30, height: 40), style: .blur).scaled(by: 0.5)
        XCTAssertEqual(r, Redaction(rect: CGRect(x: 5, y: 10, width: 15, height: 20), style: .blur))
    }
}
