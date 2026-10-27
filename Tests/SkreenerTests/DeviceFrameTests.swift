import AppKit
import XCTest
@testable import Skreener

/// Geometry and saving of the device and browser frames (#271).
final class DeviceFrameTests: XCTestCase {
    private let shot = CGRect(x: 10, y: 20, width: 800, height: 500)

    private func frame(_ kind: DeviceFrame.Kind) -> DeviceFrame {
        var f = DeviceFrame()
        f.kind = kind
        return f
    }

    func testNoFrameLeavesTheScreenshotAlone() {
        let l = frame(.none).layout(around: shot)
        XCTAssertEqual(l.outer, shot)
        XCTAssertEqual(l.screen, shot)
        XCTAssertEqual(l.bar.height, 0)
    }

    func testWindowAddsATitleBarOnTopAndKeepsTheScreenshotExact() {
        let l = frame(.macWindow).layout(around: shot)
        XCTAssertEqual(l.screen, shot)
        XCTAssertEqual(l.bar.height, 28)
        XCTAssertEqual(l.outer, CGRect(x: 10, y: 20, width: 800, height: 528))
        XCTAssertEqual(l.bar.minY, shot.maxY)
        XCTAssertEqual(l.outerRadius, 10)
        XCTAssertNil(l.urlField)
    }

    func testBrowserHasATallerBarWithACenteredAddressField() throws {
        let l = frame(.browser).layout(around: shot)
        XCTAssertEqual(l.screen, shot)
        XCTAssertEqual(l.bar.height, 44)
        let field = try XCTUnwrap(l.urlField)
        XCTAssertTrue(l.bar.contains(field))
        XCTAssertEqual(field.midX, l.bar.midX, accuracy: 0.001)
        XCTAssertEqual(field.midY, l.bar.midY, accuracy: 0.001)
    }

    func testNarrowScreenshotsGetNoAddressField() {
        let l = frame(.browser).layout(around: CGRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertNil(l.urlField)
    }

    func testVeryWideScreenshotsGetBiggerChrome() {
        XCTAssertEqual(DeviceFrame.unit(forWidth: 600), 1)
        XCTAssertEqual(DeviceFrame.unit(forWidth: 2400), 2)
        XCTAssertEqual(DeviceFrame.unit(forWidth: 100_000), 3)
        let l = frame(.macWindow).layout(around: CGRect(x: 0, y: 0, width: 2400, height: 1000))
        XCTAssertEqual(l.bar.height, 56)
    }

    func testDeviceScreensHoldTheScreenshotAtTheirOwnShape() {
        for (kind, landscape) in [(DeviceFrame.Kind.iPhone, 19.5 / 9), (.iPad, 4.0 / 3), (.macBook, 1.6)] {
            let l = frame(kind).layout(around: shot)
            XCTAssertTrue(l.screen.contains(shot), "\(kind)")
            XCTAssertTrue(l.outer.contains(l.screen), "\(kind)")
            XCTAssertEqual(l.screen.midX, shot.midX, accuracy: 2)
            XCTAssertEqual(l.screen.midY, shot.midY, accuracy: 2)
            // A wide screenshot gets the landscape screen (a MacBook's always is).
            XCTAssertEqual(l.screen.width / l.screen.height, landscape, accuracy: 0.01, "\(kind)")
        }
    }

    func testTallScreenshotsGetAPortraitPhone() {
        let tall = CGRect(x: 0, y: 0, width: 390, height: 844)
        let l = frame(.iPhone).layout(around: tall)
        XCTAssertTrue(l.screen.contains(tall))
        XCTAssertEqual(l.screen.width / l.screen.height, 9 / 19.5, accuracy: 0.01)
        XCTAssertGreaterThan(l.bezel, 0)
        XCTAssertEqual(l.outer, l.screen.insetBy(dx: -l.bezel, dy: -l.bezel))
        XCTAssertEqual(l.outerRadius, l.screenRadius + l.bezel, accuracy: 0.001)
    }

    func testScreenNeverLeavesTheScreenshotStickingOutWhateverTheOrigin() {
        for content in [CGRect(x: 0.4, y: -3.7, width: 333.3, height: 777.1), CGRect(x: -50, y: -50, width: 641, height: 359)] {
            let screen = DeviceFrame.screen(holding: content, ratio: 9 / 19.5)
            XCTAssertTrue(screen.contains(content))
        }
    }

    func testMacBookHasABaseBelowAndWiderThanTheLid() throws {
        let l = frame(.macBook).layout(around: shot)
        let base = try XCTUnwrap(l.base)
        XCTAssertLessThan(base.maxY, l.body.minY + 0.001)
        XCTAssertGreaterThan(base.width, l.body.width)
        XCTAssertEqual(l.outer, l.body.union(base))
        XCTAssertTrue(l.body.contains(l.screen))
    }

    func testPlistRoundTrips() {
        var f = frame(.browser)
        f.dark = true
        f.url = "skreener.app/docs"
        XCTAssertEqual(DeviceFrame(plist: f.plist), f)
        // Unknown kinds fall back to no frame.
        XCTAssertEqual(DeviceFrame(plist: ["kind": 99]).kind, .none)
        XCTAssertEqual(DeviceFrame(plist: [:]), DeviceFrame())
    }

    func testEditorDocumentSavesAndRestoresTheFrame() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkreenerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Frame test.skreener", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let base = TestImages.image(width: 40, height: 30) { r in NSColor.white.setFill(); r.fill() }
        var f = frame(.iPad)
        f.dark = true
        try EditorDocument(deviceFrame: f).write(to: folder, base: base)
        XCTAssertEqual(try XCTUnwrap(EditorDocument.read(from: folder)).document.deviceFrame, f)

        // Documents saved without a frame (older ones, or None) read back as None.
        try EditorDocument().write(to: folder, base: nil)
        XCTAssertTrue(try XCTUnwrap(EditorDocument.read(from: folder)).document.deviceFrame.isNone)
    }
}
