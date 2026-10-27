import AppIntents
import AppKit
import XCTest
@testable import Skreener

final class AppIntentsTests: XCTestCase {
    private let keys = ["imageFormat", "downscaleRetina"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private let red = TestImages.image(width: 20, height: 10) { r in
        NSColor.red.setFill()
        r.fill()
    }

    func testCaptureGoesOutAsAPNGFile() throws {
        let file = try ShortcutImages.file(red, format: .png)
        XCTAssertEqual(file.type, .png)
        XCTAssertTrue(file.filename.hasSuffix(".png"))
        XCTAssertTrue(file.filename.hasPrefix("Skreener "))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: file.data))
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 10)
    }

    func testCaptureGoesOutAsAJPEGFile() throws {
        let file = try ShortcutImages.file(red, format: .jpeg)
        XCTAssertEqual(file.type, .jpeg)
        XCTAssertTrue(file.filename.hasSuffix(".jpg"))
        XCTAssertNotNil(NSBitmapImageRep(data: file.data))
    }

    func testImageInputComesBackAsTheImage() throws {
        let image = try ShortcutImages.image(ShortcutImages.file(red, format: .png))
        let rep = try XCTUnwrap(image.representations.first)
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 10)
    }

    func testInputThatIsNotAnImageIsRejected() {
        let text = IntentFile(data: Data("not an image".utf8), filename: "note.txt", type: .plainText)
        XCTAssertThrowsError(try ShortcutImages.image(text)) { XCTAssertEqual($0 as? ShortcutError, .notAnImage) }
    }
}
