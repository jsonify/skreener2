import AppKit
import XCTest
@testable import Skreener

final class OutputTests: XCTestCase {
    private let keys = ["imageFormat", "downscaleRetina"]
    /// 7 March 2026, 09:05:02 local time.
    private let date: Date = {
        let c = DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5, second: 2)
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: File names

    func testDefaultTemplate() {
        XCTAssertEqual(Output.filename(for: date, template: Preferences.defaultFilenameTemplate),
                       "Skreener 2026-03-07 at 09.05.02")
    }

    func testEveryToken() {
        XCTAssertEqual(Output.filename(for: date, template: "%Y %y %m %d %H %M %S"), "2026 26 03 07 09 05 02")
    }

    func testPercentSigns() {
        XCTAssertEqual(Output.filename(for: date, template: "100%% %q 50%"), "100% %q 50%")
    }

    func testFolderAndColonCharactersAreReplaced() {
        XCTAssertEqual(Output.filename(for: date, template: "a/b:c"), "a-b.c")
    }

    func testEmptyNameFallsBack() {
        XCTAssertEqual(Output.filename(for: date, template: "   "), "Skreener")
    }

    func testLeadingDotIsNotHidden() {
        XCTAssertEqual(Output.filename(for: date, template: ".shot %Y"), "Skreener .shot 2026")
    }

    func testTakenNamesGetANumber() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for expected in ["Shot.png", "Shot 2.png", "Shot 3.png"] {
            let url = Output.uniqueURL(in: dir, name: "Shot", ext: "png")
            XCTAssertEqual(url.lastPathComponent, expected)
            try Data().write(to: url)
        }
    }

    // MARK: Saved file data

    func testPNGKeepsTransparency() throws {
        let data = try XCTUnwrap(Output.fileData(TestImages.clear(width: 4, height: 4)))
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "not a PNG")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.colorAt(x: 1, y: 1)?.alphaComponent, 0)
    }

    func testJPEGFlattensOntoWhite() throws {
        Preferences.imageFormat = .jpeg
        let data = try XCTUnwrap(Output.fileData(TestImages.clear(width: 4, height: 4)))
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8]), "not a JPEG")
        let color = try XCTUnwrap(NSBitmapImageRep(data: data)?.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.95)
        XCTAssertGreaterThan(color.greenComponent, 0.95)
        XCTAssertGreaterThan(color.blueComponent, 0.95)
    }

    func testRetinaKeepsFullResolutionByDefault() throws {
        let image = TestImages.clear(width: 8, height: 8, points: NSSize(width: 4, height: 4))
        let rep = try XCTUnwrap(Output.fileData(image).flatMap { NSBitmapImageRep(data: $0) })
        XCTAssertEqual(rep.pixelsWide, 8)
        XCTAssertEqual(rep.pixelsHigh, 8)
    }

    func testRetinaSavedAt1x() throws {
        Preferences.downscaleRetina = true
        let image = TestImages.clear(width: 8, height: 8, points: NSSize(width: 4, height: 4))
        let rep = try XCTUnwrap(Output.fileData(image).flatMap { NSBitmapImageRep(data: $0) })
        XCTAssertEqual(rep.pixelsWide, 4)
        XCTAssertEqual(rep.pixelsHigh, 4)
    }

    // MARK: Saving over a file (#118)

    func testFormatFromExtension() {
        XCTAssertEqual(ImageFormat(fileExtension: "PNG"), .png)
        XCTAssertEqual(ImageFormat(fileExtension: "jpg"), .jpeg)
        XCTAssertEqual(ImageFormat(fileExtension: "jpeg"), .jpeg)
        XCTAssertNil(ImageFormat(fileExtension: "heic"))
    }

    func testOverwriteKeepsTheFilesFormat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Shot.jpg")
        try Data([1, 2, 3]).write(to: url)
        // Settings say PNG, but the file is a JPEG: it stays one, with the same name and no copy beside it.
        XCTAssertTrue(Output.overwrite(TestImages.clear(width: 4, height: 4), at: url))
        XCTAssertTrue(try Data(contentsOf: url).starts(with: [0xFF, 0xD8]), "not a JPEG")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["Shot.jpg"])
        XCTAssertFalse(Output.overwrite(TestImages.clear(width: 4, height: 4), at: dir.appendingPathComponent("Shot.heic")))
    }
}
