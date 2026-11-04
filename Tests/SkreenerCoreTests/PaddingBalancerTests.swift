import CoreGraphics
import XCTest
@testable import SkreenerCore

final class PaddingBalancerTests: XCTestCase {
    /// A white canvas of `w` × `h` pixels with `fill` blocks given as top-left pixel rects.
    private func buffer(_ w: Int, _ h: Int, blocks: [(CGRect, CGColor)] = [], noise: Int = 0) throws -> PixelBuffer {
        let img = TestImages.image(width: w, height: h) { ctx, r in
            ctx.setFillColor(TestImages.white)
            ctx.fill(r)
            for (rect, color) in blocks {
                ctx.setFillColor(color)
                // Drawing is bottom-left origin.
                ctx.fill(CGRect(x: rect.minX, y: CGFloat(h) - rect.maxY, width: rect.width, height: rect.height))
            }
            if noise > 0 {
                // A faint speckle in the margins, within the tolerance.
                let v = 1 - CGFloat(noise) / 255
                ctx.setFillColor(TestImages.srgb(v, v, v))
                for i in stride(from: 0, to: w, by: 3) { ctx.fill(CGRect(x: i, y: 0, width: 1, height: 1)) }
            }
        }
        return try XCTUnwrap(PixelBuffer(img))
    }

    func testFindsOffCentreBlock() throws {
        let buf = try buffer(100, 80, blocks: [(CGRect(x: 10, y: 5, width: 30, height: 20), TestImages.red)])
        XCTAssertEqual(PaddingBalancer.contentBox(in: buf), CGRect(x: 10, y: 5, width: 30, height: 20))
    }

    func testBalancedUsesSmallestMargin() throws {
        // Margins: left 10, right 60, top 5, bottom 55 -> 5 each way.
        let buf = try buffer(100, 80, blocks: [(CGRect(x: 10, y: 5, width: 30, height: 20), TestImages.red)])
        XCTAssertEqual(PaddingBalancer.balance(in: buf), CGRect(x: 5, y: 0, width: 40, height: 30))
    }

    func testNoiseWithinToleranceIsMargin() throws {
        let buf = try buffer(99, 60, blocks: [(CGRect(x: 20, y: 10, width: 20, height: 20), TestImages.blue)], noise: 6)
        XCTAssertEqual(PaddingBalancer.contentBox(in: buf), CGRect(x: 20, y: 10, width: 20, height: 20))
    }

    func testAlreadyBalancedIsNoOp() throws {
        let buf = try buffer(100, 100, blocks: [(CGRect(x: 30, y: 30, width: 40, height: 40), TestImages.black)])
        XCTAssertNil(PaddingBalancer.balance(in: buf))
    }

    func testContentFillingImageIsNoOp() throws {
        let buf = try buffer(50, 50, blocks: [(CGRect(x: 0, y: 0, width: 50, height: 50), TestImages.black)])
        XCTAssertNil(PaddingBalancer.balance(in: buf))
    }

    func testFlatImageIsNoOp() throws {
        let buf = try buffer(40, 40)
        XCTAssertNil(PaddingBalancer.contentBox(in: buf))
        XCTAssertNil(PaddingBalancer.balance(in: buf))
    }

    func testContentTouchingOneEdgeTrimsToTheBox() throws {
        let buf = try buffer(100, 100, blocks: [(CGRect(x: 0, y: 40, width: 30, height: 20), TestImages.red)])
        XCTAssertEqual(PaddingBalancer.balance(in: buf), CGRect(x: 0, y: 40, width: 30, height: 20))
    }

    func testBalancesWithinARegion() throws {
        let buf = try buffer(100, 100, blocks: [(CGRect(x: 40, y: 40, width: 10, height: 10), TestImages.red)])
        let region = CGRect(x: 30, y: 20, width: 40, height: 60)
        XCTAssertEqual(PaddingBalancer.balance(in: buf, region: region), CGRect(x: 30, y: 30, width: 30, height: 30))
    }

    func testAnnotationsStayInside() throws {
        let buf = try buffer(100, 80, blocks: [(CGRect(x: 40, y: 30, width: 20, height: 20), TestImages.red)])
        let result = PaddingBalancer.balance(in: buf, keeping: [CGRect(x: 5, y: 35, width: 10, height: 10)])
        // Content now spans x 5...60, y 30...50: margins left 5, right 40, top 30, bottom 30.
        XCTAssertEqual(result, CGRect(x: 0, y: 25, width: 65, height: 30))
    }

    func testEdgeColorIsTheOneMostCornersShare() throws {
        let buf = try buffer(60, 60, blocks: [(CGRect(x: 0, y: 0, width: 5, height: 5), TestImages.black),
                                              (CGRect(x: 20, y: 20, width: 10, height: 10), TestImages.red)])
        XCTAssertEqual(PaddingBalancer.contentBox(in: buf)?.size, CGSize(width: 30, height: 30))
    }
}
