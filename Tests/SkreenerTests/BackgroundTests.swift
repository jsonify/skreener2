import AppKit
import XCTest
@testable import Skreener

final class BackgroundTests: XCTestCase {
    private let shot = NSRect(x: 0, y: 0, width: 801, height: 517)

    func testNoAspectKeepsThePaddingOnEverySide() {
        XCTAssertEqual(Background.canvas(around: shot, margin: 48, aspect: nil), shot.insetBy(dx: -48, dy: -48))
    }

    func testSixteenByNineIsExactAndHoldsTheScreenshotWithItsPadding() {
        for aspect in [Background.Aspect(width: 16, height: 9), Background.Aspect(width: 1600, height: 900)] {
            let r = Background.canvas(around: shot, margin: 48, aspect: aspect)
            XCTAssertEqual(r.width * 9, r.height * 16)
            XCTAssertEqual(r.width, r.width.rounded())
            XCTAssertTrue(r.contains(shot.insetBy(dx: -48, dy: -48)))
        }
    }

    func testTallRatiosGrowTheHeight() {
        let r = Background.canvas(around: shot, margin: 16, aspect: Background.Aspect(width: 2, height: 3))
        XCTAssertEqual(r.width * 3, r.height * 2)
        XCTAssertTrue(r.contains(shot.insetBy(dx: -16, dy: -16)))
        // Centered: the screenshot is as far from the top as from the bottom, give or take a point.
        XCTAssertLessThanOrEqual(abs((shot.minY - r.minY) - (r.maxY - shot.maxY)), 1)
    }

    func testOddRatiosComeWithinAPoint() {
        let r = Background.canvas(around: shot, margin: 32, aspect: Background.Aspect(width: 1200, height: 627))
        XCTAssertEqual(r.width / r.height, 1200 / 627, accuracy: 0.01)
        XCTAssertTrue(r.contains(shot.insetBy(dx: -32, dy: -32)))
    }

    func testTheLastBackgroundIsSavedAndReadBack() {
        var b = Background()
        b.fill = Background.customFill
        b.colors = [NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)]
        b.direction = .radial
        b.aspect = Background.Aspect(width: 4, height: 3)
        b.padding = 64; b.inset = 8; b.cornerRadius = 16; b.outerRadius = 24; b.shadow = 0.8; b.imageBlur = 15
        let back = Background(plist: b.plist)
        XCTAssertEqual(back, b)
    }

    func testAPictureThatIsGoneFallsBackToAPreset() {
        var b = Background()
        b.fill = Background.imageFill
        b.imageURL = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")
        XCTAssertEqual(Background(plist: b.plist).fill, 0)
    }
}
