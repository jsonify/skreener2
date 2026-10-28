import CoreMedia
import XCTest
@testable import Skreener

/// Live Pin's stream numbers (#241) that run without a screen.
final class LivePinTests: XCTestCase {
    func testFrameRatesAndDefault() {
        XCTAssertEqual(LivePinGeometry.frameRates, [5, 10, 15])
        XCTAssertEqual(LivePinGeometry.frameRate(10), 10)
        XCTAssertEqual(LivePinGeometry.frameRate(15), 15)
        XCTAssertEqual(LivePinGeometry.frameRate(0), 5)    // nothing stored yet
        XCTAssertEqual(LivePinGeometry.frameRate(60), 5)
    }

    func testFrameInterval() {
        XCTAssertEqual(LivePinGeometry.frameInterval(fps: 5), CMTime(value: 1, timescale: 5))
        XCTAssertEqual(LivePinGeometry.frameInterval(fps: 15).seconds, 1.0 / 15, accuracy: 1e-9)
        XCTAssertEqual(LivePinGeometry.frameInterval(fps: 7), CMTime(value: 1, timescale: 5))
    }

    func testPixelSizeIsFullResolution() {
        let px = LivePinGeometry.pixelSize(points: CGSize(width: 400, height: 300), scale: 2)
        XCTAssertEqual(px.width, 800)
        XCTAssertEqual(px.height, 600)
        let one = LivePinGeometry.pixelSize(points: CGSize(width: 401, height: 33), scale: 1)
        XCTAssertEqual(one.width, 401)
        XCTAssertEqual(one.height, 33)
    }

    func testBigAreasAreScaledDownKeepingTheShape() {
        let px = LivePinGeometry.pixelSize(points: CGSize(width: 3000, height: 2000), scale: 2)
        XCTAssertLessThanOrEqual(px.width * px.height, LivePinGeometry.maxPixels + px.width + px.height)
        XCTAssertEqual(Double(px.width) / Double(px.height), 1.5, accuracy: 0.01)
    }

    func testTinyAreasGetAtLeastOnePixel() {
        let px = LivePinGeometry.pixelSize(points: CGSize(width: 0.2, height: 0), scale: 2)
        XCTAssertEqual(px.width, 1)
        XCTAssertEqual(px.height, 1)
    }

    func testSourceRectIsDisplayLocalTopLeft() {
        // A 1440 × 900 screen to the right of the main one; the area is 100 pt from its top and left.
        let screen = CGRect(x: 1512, y: 0, width: 1440, height: 900)
        let area = CGRect(x: 1612, y: 600, width: 200, height: 200)
        XCTAssertEqual(LivePinGeometry.sourceRect(area, in: screen), CGRect(x: 100, y: 100, width: 200, height: 200))
    }
}
