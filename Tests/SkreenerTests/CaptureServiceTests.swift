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
