import AppKit
import XCTest
@testable import Skreener

/// The editor document capture history keeps beside each capture (#30).
final class EditorDocumentTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkreenerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Skreener test.skreener", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        super.tearDown()
    }

    private func base() -> NSImage {
        TestImages.image(width: 40, height: 30) { r in NSColor.white.setFill(); r.fill() }
    }

    private func sample() -> [Annotation] {
        var arrowStyle = Style()
        arrowStyle.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        arrowStyle.lineWidth = 5
        arrowStyle.arrowStyle = .tapered
        arrowStyle.handDrawn = true
        var arrow = Annotation(tool: .arrow, start: NSPoint(x: 1, y: 2), end: NSPoint(x: 30, y: 20), style: arrowStyle)
        arrow.bend = 7

        var textStyle = Style()
        textStyle.fontName = "Helvetica"
        textStyle.textBox = .solid
        var text = Annotation(tool: .text, start: NSPoint(x: 5, y: 25), end: NSPoint(x: 5, y: 25), style: textStyle)
        text.text = "Hello\nthere"
        text.wrapWidth = 120
        text.tail = NSPoint(x: 9, y: 3)

        var pen = Annotation(tool: .pen, start: .zero, end: NSPoint(x: 3, y: 3), style: Style())
        pen.points = [.zero, NSPoint(x: 1, y: 2), NSPoint(x: 3, y: 3)]

        var lens = Annotation(tool: .magnifier, start: .zero, end: NSPoint(x: 10, y: 10), style: Style())
        lens.lens = NSPoint(x: 20, y: 20)
        return [arrow, text, pen, lens]
    }

    func testAnnotationsRoundTrip() throws {
        let items = sample()
        try EditorDocument(items: items).write(to: folder, base: base())
        let read = try XCTUnwrap(EditorDocument.read(from: folder))
        XCTAssertEqual(read.document.items.count, items.count)
        for (a, b) in zip(items, read.document.items) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.seq, b.seq)
            XCTAssertEqual(a.tool, b.tool)
            XCTAssertEqual(a.start, b.start)
            XCTAssertEqual(a.end, b.end)
            XCTAssertEqual(a.points, b.points)
            XCTAssertEqual(a.text, b.text)
            XCTAssertEqual(a.lens, b.lens)
            XCTAssertEqual(a.tail, b.tail)
            XCTAssertEqual(a.wrapWidth, b.wrapWidth)
            XCTAssertEqual(a.bend, b.bend)
            XCTAssertEqual(a.seed, b.seed)
            XCTAssertEqual(a.style.plist as NSDictionary, b.style.plist as NSDictionary)
        }
    }

    func testCropAndBackgroundRoundTrip() throws {
        var background = Background()
        background.fill = 2
        background.padding = 20
        background.aspect = Background.Aspect(width: 16, height: 9)
        let crop = NSRect(x: 4, y: 5, width: 20, height: 15)
        try EditorDocument(items: [], crop: crop, background: background).write(to: folder, base: base())
        let read = try XCTUnwrap(EditorDocument.read(from: folder)).document
        XCTAssertEqual(read.crop, crop)
        XCTAssertEqual(read.background?.plist as NSDictionary?, background.plist as NSDictionary)
    }

    func testPictureAnnotationsKeepTheirImage() throws {
        var picture = Annotation(tool: .image, start: .zero, end: NSPoint(x: 10, y: 8), style: Style())
        picture.image = TestImages.image(width: 10, height: 8) { r in NSColor.red.setFill(); r.fill() }
        try EditorDocument(items: [picture]).write(to: folder, base: base())
        let read = try XCTUnwrap(EditorDocument.read(from: folder)).document
        XCTAssertEqual(read.items.first?.image?.size, NSSize(width: 10, height: 8))
        // Removing it from the capture removes its file the next time the document is written.
        try EditorDocument(items: []).write(to: folder, base: nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("img-") })
    }

    func testLoadingKeepsNewAnnotationsAfterTheLoadedOnes() throws {
        var a = Annotation(tool: .counter, start: .zero, end: .zero, style: Style())
        a.seq = 5_000
        try EditorDocument(items: [a]).write(to: folder, base: base())
        _ = EditorDocument.read(from: folder)
        let next = Annotation(tool: .counter, start: .zero, end: .zero, style: Style())
        XCTAssertGreaterThan(next.seq, 5_000)
    }

    func testMissingOrNewerDocumentsReadAsNil() throws {
        XCTAssertNil(EditorDocument.read(from: folder))
        try EditorDocument().write(to: folder, base: base())
        let file = folder.appendingPathComponent("document.json")
        let newer = try JSONSerialization.data(withJSONObject: ["version": EditorDocument.version + 1, "items": []])
        try newer.write(to: file)
        XCTAssertNil(EditorDocument.read(from: folder))
    }

    func testDocumentFolderSitsBesideTheCapture() {
        let png = URL(fileURLWithPath: "/tmp/History/Skreener 2026-10-24 at 10.00.00.123.png")
        XCTAssertEqual(CaptureHistory.documentFolder(for: png).lastPathComponent, "Skreener 2026-10-24 at 10.00.00.123.skreener")
    }

    func testRemovingACaptureRemovesItsDocument() throws {
        let png = folder.deletingLastPathComponent().appendingPathComponent("Skreener test.png")
        try FileManager.default.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: png)
        try EditorDocument().write(to: CaptureHistory.documentFolder(for: png), base: base())
        CaptureHistory.remove(png)
        XCTAssertFalse(FileManager.default.fileExists(atPath: png.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CaptureHistory.documentFolder(for: png).path))
    }
}
