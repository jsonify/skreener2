import XCTest
@testable import Skreener

/// Global screen rects (points, bottom-left origin) to pixel rects in a captured frame (top-left origin).
final class CaptureServiceTests: XCTestCase {
    func testRetinaMainScreen() {
        let r = CaptureService.pixelRect(CGRect(x: 100, y: 700, width: 200, height: 100),
                                         in: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                         pixelSize: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(r, CGRect(x: 200, y: 200, width: 400, height: 200))
    }

    func testSecondScreenToTheRightAndLower() {
        // A 1× screen right of the main one, with its top 200 pt lower: its frame starts at y = -200.
        let r = CaptureService.pixelRect(CGRect(x: 1540, y: 780, width: 300, height: 100),
                                         in: CGRect(x: 1440, y: -200, width: 1920, height: 1080),
                                         pixelSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(r, CGRect(x: 100, y: 0, width: 300, height: 100))
    }

    func testScreenAboveTheMainOne() {
        let r = CaptureService.pixelRect(CGRect(x: -500, y: 900, width: 100, height: 50),
                                         in: CGRect(x: -600, y: 900, width: 1600, height: 1000),
                                         pixelSize: CGSize(width: 3200, height: 2000))
        XCTAssertEqual(r, CGRect(x: 200, y: 1900, width: 200, height: 100))
    }

    func testFractionalPointsCoverWholePixels() {
        let r = CaptureService.pixelRect(CGRect(x: 10.3, y: 0, width: 20.2, height: 10),
                                         in: CGRect(x: 0, y: 0, width: 100, height: 100),
                                         pixelSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(r, CGRect(x: 10, y: 90, width: 21, height: 10))
    }
}

/// The space around a captured window (its rounded corners, padding, shadow): transparent or white (#138).
final class WindowDecorationTests: XCTestCase {
    /// A 20 × 20 px red "window" with its top-left pixel left clear, like a rounded corner.
    private func window() -> CGImage {
        TestImages.image(width: 20, height: 20) { r in
            NSColor.red.setFill()
            r.fill()
            NSColor.clear.setFill()
            NSRect(x: 0, y: r.height - 1, width: 1, height: 1).fill(using: .copy)
        }.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    private func alpha(_ cg: CGImage, x: Int, y: Int) -> CGFloat? {
        NSBitmapImageRep(cgImage: cg).colorAt(x: x, y: y)?.alphaComponent
    }

    func testTransparentPaddingStaysClear() {
        let out = CaptureService.decorateWindow(window(), scale: 1, shadow: false, transparent: true, padding: 16)
        XCTAssertEqual(out.width, 52)
        XCTAssertEqual(alpha(out, x: 0, y: 0), 0)
        XCTAssertEqual(alpha(out, x: 16, y: 16), 0)   // the window's own clear corner
        XCTAssertEqual(alpha(out, x: 26, y: 26), 1)
    }

    func testTransparentWithoutPaddingKeepsTheCorner() {
        let out = CaptureService.decorateWindow(window(), scale: 1, shadow: false, transparent: true, padding: 0)
        XCTAssertEqual(out.width, 20)
        XCTAssertEqual(alpha(out, x: 0, y: 0), 0)
    }

    func testShadowAreaIsTransparentPastTheShadow() throws {
        let out = CaptureService.decorateWindow(window(), scale: 1, shadow: true, transparent: true, padding: 0)
        XCTAssertEqual(out.width, 100)
        XCTAssertLessThan(try XCTUnwrap(alpha(out, x: 0, y: 0)), 0.02)
    }

    func testOpaqueFillsWithWhite() throws {
        let out = CaptureService.decorateWindow(window(), scale: 1, shadow: false, transparent: false, padding: 16)
        let rep = NSBitmapImageRep(cgImage: out)
        let corner = try XCTUnwrap(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        XCTAssertEqual(corner.alphaComponent, 1)
        XCTAssertEqual(corner.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(corner.greenComponent, 1, accuracy: 0.01)
        XCTAssertEqual(rep.colorAt(x: 16, y: 16)?.alphaComponent, 1)   // the window's corner is white too
    }
}
