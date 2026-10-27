import AppKit
import XCTest
@testable import Skreener

final class PaddingBalancerTests: XCTestCase {
    /// A white canvas of `w` × `h` pixels with `fill` blocks given as top-left pixel rects.
    private func buffer(_ w: Int, _ h: Int, blocks: [(CGRect, NSColor)] = [], noise: Int = 0) throws -> PixelBuffer {
        let img = TestImages.image(width: w, height: h) { r in
            NSColor.white.setFill()
            r.fill()
            for (rect, color) in blocks {
                color.setFill()
                // Drawing is bottom-left origin.
                NSRect(x: rect.minX, y: CGFloat(h) - rect.maxY, width: rect.width, height: rect.height).fill()
            }
            if noise > 0 {
                // A faint speckle in the margins, within the tolerance.
                NSColor(white: 1 - CGFloat(noise) / 255, alpha: 1).setFill()
                for i in stride(from: 0, to: w, by: 3) { NSRect(x: i, y: 0, width: 1, height: 1).fill() }
            }
        }
        var r = CGRect(x: 0, y: 0, width: w, height: h)
        let cg = try XCTUnwrap(img.cgImage(forProposedRect: &r, context: nil, hints: nil))
        return try XCTUnwrap(PixelBuffer(cg))
    }

    func testFindsOffCentreBlock() throws {
        let buf = try buffer(100, 80, blocks: [(CGRect(x: 10, y: 5, width: 30, height: 20), .red)])
        XCTAssertEqual(PaddingBalancer.contentBox(in: buf), CGRect(x: 10, y: 5, width: 30, height: 20))
    }

    func testBalancedUsesSmallestMargin() throws {
        // Margins: left 10, right 60, top 5, bottom 55 -> 5 each way.
        let buf = try buffer(100, 80, blocks: [(CGRect(x: 10, y: 5, width: 30, height: 20), .red)])
        XCTAssertEqual(PaddingBalancer.balance(in: buf), CGRect(x: 5, y: 0, width: 40, height: 30))
    }

    func testNoiseWithinToleranceIsMargin() throws {
        let buf = try buffer(99, 60, blocks: [(CGRect(x: 20, y: 10, width: 20, height: 20), .blue)], noise: 6)
        XCTAssertEqual(PaddingBalancer.contentBox(in: buf), CGRect(x: 20, y: 10, width: 20, height: 20))
    }

    func testAlreadyBalancedIsNoOp() throws {
        let buf = try buffer(100, 100, blocks: [(CGRect(x: 30, y: 30, width: 40, height: 40), .black)])
        XCTAssertNil(PaddingBalancer.balance(in: buf))
    }

    func testContentFillingImageIsNoOp() throws {
        let buf = try buffer(50, 50, blocks: [(CGRect(x: 0, y: 0, width: 50, height: 50), .black)])
        XCTAssertNil(PaddingBalancer.balance(in: buf))
    }

    func testFlatImageIsNoOp() throws {
        let buf = try buffer(40, 40)
        XCTAssertNil(PaddingBalancer.contentBox(in: buf))
        XCTAssertNil(PaddingBalancer.balance(in: buf))
    }

    func testContentTouchingOneEdgeTrimsToTheBox() throws {
        let buf = try buffer(100, 100, blocks: [(CGRect(x: 0, y: 40, width: 30, height: 20), .red)])
        XCTAssertEqual(PaddingBalancer.balance(in: buf), CGRect(x: 0, y: 40, width: 30, height: 20))
    }

    func testBalancesWithinARegion() throws {
        let buf = try buffer(100, 100, blocks: [(CGRect(x: 40, y: 40, width: 10, height: 10), .red)])
        let region = CGRect(x: 30, y: 20, width: 40, height: 60)
        XCTAssertEqual(PaddingBalancer.balance(in: buf, region: region), CGRect(x: 30, y: 30, width: 30, height: 30))
    }

    func testAnnotationsStayInside() throws {
        let buf = try buffer(100, 80, blocks: [(CGRect(x: 40, y: 30, width: 20, height: 20), .red)])
        let result = PaddingBalancer.balance(in: buf, keeping: [CGRect(x: 5, y: 35, width: 10, height: 10)])
        // Content now spans x 5...60, y 30...50: margins left 5, right 40, top 30, bottom 30.
        XCTAssertEqual(result, CGRect(x: 0, y: 25, width: 65, height: 30))
    }

    func testEdgeColorIsTheOneMostCornersShare() throws {
        let buf = try buffer(60, 60, blocks: [(CGRect(x: 0, y: 0, width: 5, height: 5), .black),
                                              (CGRect(x: 20, y: 20, width: 10, height: 10), .red)])
        XCTAssertEqual(PaddingBalancer.contentBox(in: buf)?.size, CGSize(width: 30, height: 30))
    }
}
