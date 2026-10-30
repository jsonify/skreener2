import AppKit
import XCTest
@testable import Skreener

final class CaptureTextTests: XCTestCase {
    func testPixelRectFlipsToTopLeftOrigin() {
        // The bottom-left quarter of a 200 × 100 image is the lower half in pixel rows.
        XCTAssertEqual(CaptureText.pixelRect(of: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), width: 200, height: 100),
                       CGRect(x: 0, y: 50, width: 100, height: 50))
        XCTAssertEqual(CaptureText.pixelRect(of: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), width: 200, height: 100),
                       CGRect(x: 100, y: 0, width: 100, height: 50))
    }

    func testPixelRectWidensToWholePixelsInsideTheImage() {
        let r = CaptureText.pixelRect(of: CGRect(x: 0.101, y: -0.2, width: 0.3, height: 1.5), width: 100, height: 10)
        XCTAssertEqual(r, CGRect(x: 10, y: 0, width: 31, height: 10))
    }

    func testCroppedKeepsFullResolution() throws {
        // A 2× image: 100 × 50 points, 200 × 100 pixels.
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 100, height: 50)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        let part = try XCTUnwrap(CaptureText.cropped(image, to: CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5)))
        XCTAssertEqual(part.size, NSSize(width: 50, height: 25))
        var rect = CGRect(origin: .zero, size: part.size)
        let cg = try XCTUnwrap(part.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 100)
        XCTAssertEqual(cg.height, 50)
    }

    func testCroppedIsNilOutsideTheImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        XCTAssertNil(CaptureText.cropped(image, to: CGRect(x: 2, y: 2, width: 1, height: 1)))
    }
}
