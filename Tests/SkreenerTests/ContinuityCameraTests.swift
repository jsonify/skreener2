import XCTest
@testable import Skreener

/// Reading a picture from an iPhone or iPad back off the pasteboard (#270).
final class ContinuityCameraTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("skreener.tests.continuity.\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() { pasteboard.releaseGlobally() }

    private let source = TestImages.image(width: 40, height: 30) { r in
        NSColor.red.setFill()
        r.fill()
    }

    private func rep() -> NSBitmapImageRep { NSBitmapImageRep(data: source.tiffRepresentation!)! }

    private func pdfData() -> Data {
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        view.image = source
        return view.dataWithPDF(inside: view.bounds)
    }

    private func assertRead(_ type: NSPasteboard.PasteboardType, _ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
        let image = ContinuityCamera.image(from: pasteboard)
        XCTAssertNotNil(image, "\(type.rawValue)", file: file, line: line)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0, file: file, line: line)
    }

    func testReadsPNG() { assertRead(.png, rep().representation(using: .png, properties: [:])!) }
    func testReadsTIFF() { assertRead(.tiff, source.tiffRepresentation!) }
    func testReadsJPEG() {
        assertRead(NSPasteboard.PasteboardType("public.jpeg"), rep().representation(using: .jpeg, properties: [:])!)
    }
    func testReadsPDFScan() { assertRead(.pdf, pdfData()) }

    func testPrefersPNGOverPDF() {
        pasteboard.setData(pdfData(), forType: .pdf)
        pasteboard.setData(rep().representation(using: .png, properties: [:])!, forType: .png)
        XCTAssertEqual(ContinuityCamera.image(from: pasteboard)?.representations.first is NSBitmapImageRep, true)
    }

    func testNoImageGivesNil() {
        XCTAssertNil(ContinuityCamera.image(from: pasteboard))
        pasteboard.setString("hello", forType: .string)
        XCTAssertNil(ContinuityCamera.image(from: pasteboard))
    }

    func testUndecodableDataGivesNil() {
        pasteboard.setData(Data([1, 2, 3]), forType: .png)
        XCTAssertNil(ContinuityCamera.image(from: pasteboard))
    }

    func testAcceptsOnlyImageReturnTypes() {
        XCTAssertTrue(ContinuityCamera.accepts(sendType: nil, returnType: .png))
        XCTAssertTrue(ContinuityCamera.accepts(sendType: nil, returnType: .pdf))
        XCTAssertFalse(ContinuityCamera.accepts(sendType: nil, returnType: .string))
        XCTAssertFalse(ContinuityCamera.accepts(sendType: nil, returnType: nil))
        XCTAssertFalse(ContinuityCamera.accepts(sendType: .string, returnType: .png))
    }
}
