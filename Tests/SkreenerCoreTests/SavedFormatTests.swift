import CoreGraphics
import XCTest
@testable import SkreenerCore

/// Backgrounds and frames saved before SkreenerCore (user defaults, editor documents) must read back the same, and be
/// written back in the same form.
final class SavedFormatTests: XCTestCase {
    func testABackgroundSavedInTodaysFormatRoundTrips() {
        let saved: [String: Any] = [
            "fill": 14, "direction": 3, "imageBlur": 15.0, "padding": 64.0, "inset": 8.0, "cornerRadius": 16.0,
            "outerRadius": 24.0, "shadow": 0.8, "aspect": [4, 3],
            "colors": [[1.0, 0.5, 0.0, 1.0], [0.2, 0.4, 0.6, 0.5]],
        ]
        let b = Background(plist: saved)
        XCTAssertEqual(b.fill, Background.customFill)
        XCTAssertEqual(b.direction, .radial)
        XCTAssertEqual(b.colors, [RGBColor(r: 1, g: 0.5, b: 0, a: 1), RGBColor(r: 0.2, g: 0.4, b: 0.6, a: 0.5)])
        XCTAssertEqual(b.aspect, Background.Aspect(width: 4, height: 3))
        XCTAssertEqual(b.imageBlur, 15); XCTAssertEqual(b.padding, 64); XCTAssertEqual(b.inset, 8)
        XCTAssertEqual(b.cornerRadius, 16); XCTAssertEqual(b.outerRadius, 24); XCTAssertEqual(b.shadow, 0.8)

        let written = b.plist
        XCTAssertEqual(Set(written.keys), Set(saved.keys))
        XCTAssertEqual(written["fill"] as? Int, 14)
        XCTAssertEqual(written["direction"] as? Int, 3)
        XCTAssertEqual(written["colors"] as? [[Double]], saved["colors"] as? [[Double]])
        XCTAssertEqual(written["aspect"] as? [Int], [4, 3])
        for key in ["imageBlur", "padding", "inset", "cornerRadius", "outerRadius", "shadow"] {
            XCTAssertEqual(written[key] as? Double, saved[key] as? Double, key)
        }
        XCTAssertEqual(Background(plist: written), b)
    }

    func testTheDefaultBackgroundWritesTheDefaultColors() {
        let colors = Background().plist["colors"] as? [[Double]]
        XCTAssertEqual(colors, [[0x4F / 255.0, 0xAC / 255.0, 0xFE / 255.0, 1], [0xF5 / 255.0, 0x57 / 255.0, 0x6C / 255.0, 1]])
    }

    func testAPictureBackgroundKeepsItsPath() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerCoreTests-\(UUID().uuidString).png")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let b = Background(plist: ["fill": Background.imageFill, "imagePath": file.path])
        XCTAssertEqual(b.fill, Background.imageFill)
        XCTAssertEqual(b.imageURL?.path, file.path)
        XCTAssertEqual(b.plist["imagePath"] as? String, file.path)
    }

    func testAFrameSavedInTodaysFormatRoundTrips() {
        let saved: [String: Any] = ["kind": 2, "dark": true, "url": "skreener.app/docs"]
        let f = DeviceFrame(plist: saved)
        XCTAssertEqual(f.kind, .browser)
        XCTAssertTrue(f.dark)
        XCTAssertEqual(f.url, "skreener.app/docs")
        let written = f.plist
        XCTAssertEqual(written["kind"] as? Int, 2)
        XCTAssertEqual(written["dark"] as? Bool, true)
        XCTAssertEqual(written["url"] as? String, "skreener.app/docs")
        XCTAssertEqual(Set(written.keys), Set(saved.keys))
    }
}
