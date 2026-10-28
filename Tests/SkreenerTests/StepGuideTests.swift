import XCTest
@testable import Skreener

/// Step Recorder (#242): step names, click handling, the Markdown and HTML guides, and the steps on disk.
final class StepGuideTests: XCTestCase {
    // MARK: Step text

    func testAccessibilityNameComesFirst() {
        XCTAssertEqual(StepText.make(axName: "Save", axRole: "AXButton", ocrLine: "Cancel", app: "Notes"), "Click **Save**")
    }

    func testRolesChooseTheVerb() {
        XCTAssertEqual(StepText.make(axName: "Name", axRole: "AXTextField", ocrLine: nil, app: nil), "Click the **Name** field")
        XCTAssertEqual(StepText.make(axName: "Export…", axRole: "AXMenuItem", ocrLine: nil, app: nil), "Choose **Export…**")
        // The role belongs to the accessibility name: an OCR line is just clicked.
        XCTAssertEqual(StepText.make(axName: nil, axRole: "AXTextField", ocrLine: "Search", app: nil), "Click **Search**")
    }

    func testOCRLineWhenThereIsNoName() {
        XCTAssertEqual(StepText.make(axName: "  ", axRole: "AXButton", ocrLine: " Add  to\nCart ", app: "Safari"),
                       "Click **Add to Cart**")
    }

    func testFallbackNamesTheApp() {
        XCTAssertEqual(StepText.make(axName: nil, axRole: nil, ocrLine: "…", app: "Finder"), "Click in Finder")
        XCTAssertEqual(StepText.make(axName: nil, axRole: nil, ocrLine: nil, app: nil), "Click here")
    }

    func testNamesAreEscaped() {
        XCTAssertEqual(StepText.make(axName: "*New* file_1", axRole: nil, ocrLine: nil, app: nil), "Click **\\*New\\* file\\_1**")
    }

    func testCleanShortensAtAWord() {
        let long = String(repeating: "word ", count: 20)
        let cleaned = StepText.clean(long, limit: 22)
        XCTAssertEqual(cleaned, "word word word word…")
        XCTAssertNil(StepText.clean(" - • "))
    }

    func testBestLineIsTheOneUnderTheClick() {
        let lines: [(text: String, box: CGRect)] = [
            ("Cancel", CGRect(x: 0, y: 0, width: 50, height: 20)),
            ("OK", CGRect(x: 100, y: 0, width: 30, height: 20)),
            ("  ", CGRect(x: 60, y: 0, width: 30, height: 20)),
        ]
        XCTAssertEqual(StepText.bestLine(lines, near: CGPoint(x: 110, y: 10)), "OK")
        XCTAssertEqual(StepText.bestLine(lines, near: CGPoint(x: 70, y: 10)), "Cancel")   // nearest readable line
        XCTAssertNil(StepText.bestLine([], near: .zero))
    }

    func testSegments() {
        XCTAssertEqual(StepText.segments("Click **Save** now"), [
            .init(text: "Click ", bold: false), .init(text: "Save", bold: true), .init(text: " now", bold: false),
        ])
        XCTAssertEqual(StepText.segments("2 \\* 3 **x"), [.init(text: "2 * 3 **x", bold: false)])
        XCTAssertEqual(StepText.plain("Click **\\*New\\***"), "Click *New*")
    }

    // MARK: Clicks

    func testDebounce() {
        XCTAssertTrue(StepClicks.accepts(10, after: nil))
        XCTAssertFalse(StepClicks.accepts(10.2, after: 10))
        XCTAssertTrue(StepClicks.accepts(10.5, after: 10))
    }

    func testClickInImageCoordinates() {
        let rect = CGRect(x: 100, y: 200, width: 400, height: 300)
        XCTAssertEqual(StepClicks.imagePoint(CGPoint(x: 150, y: 450), in: rect), CGPoint(x: 50, y: 250))
        XCTAssertEqual(StepClicks.imagePoint(CGPoint(x: 50, y: 900), in: rect), CGPoint(x: 0, y: 300))
    }

    func testOCRAreaStaysInTheImage() {
        let area = StepClicks.ocrArea(around: CGPoint(x: 10, y: 10), imageSize: CGSize(width: 500, height: 400),
                                      size: CGSize(width: 100, height: 40))
        XCTAssertEqual(area, CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    func testMoved() {
        XCTAssertEqual(StepClicks.moved([1, 2, 3], from: 0, by: 1), [2, 1, 3])
        XCTAssertEqual(StepClicks.moved([1, 2, 3], from: 2, by: -1), [1, 3, 2])
        XCTAssertEqual(StepClicks.moved([1, 2, 3], from: 0, by: -1), [1, 2, 3])
        XCTAssertEqual(StepClicks.moved([1, 2, 3], from: 2, by: 5), [1, 2, 3])
        XCTAssertEqual(StepClicks.moved([1, 2, 3], from: 7, by: 1), [1, 2, 3])
    }

    // MARK: Export

    func testImageNames() {
        XCTAssertEqual(StepGuideExport.imageName(3, of: 9), "step-03.png")
        XCTAssertEqual(StepGuideExport.imageName(7, of: 120), "step-007.png")
    }

    func testMarkdown() {
        let md = StepGuideExport.markdown(title: "My Guide", steps: [
            .init(text: "Click **Save**", image: "My Guide images/step-01.png"),
            .init(text: "Click in Finder\n", image: "My Guide images/step-02.png"),
        ])
        XCTAssertEqual(md, """
        # My Guide

        ## Step 1

        Click **Save**

        ![Step 1](My%20Guide%20images/step-01.png)

        ## Step 2

        Click in Finder

        ![Step 2](My%20Guide%20images/step-02.png)

        """)
    }

    func testLinkPathEncodesParentheses() {
        XCTAssertEqual(StepGuideExport.linkPath("a (1)/b.png"), "a%20%281%29/b.png")
    }

    func testHTML() {
        let html = StepGuideExport.html(title: "Fish & <Chips>", steps: [
            .init(text: "Click **Save <now>**\nthen wait", image: "data:image/png;base64,AAAA"),
        ])
        XCTAssertTrue(html.contains("<title>Fish &amp; &lt;Chips&gt;</title>"))
        XCTAssertTrue(html.contains("<li><p>Click <strong>Save &lt;now&gt;</strong><br>then wait</p>"
                                    + "<img src=\"data:image/png;base64,AAAA\" alt=\"Step 1\"></li>"))
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
    }

    func testPDFImageFit() {
        let box = CGRect(x: 48, y: 48, width: 516, height: 600)
        // Too wide: scaled down to the width, at the top.
        XCTAssertEqual(StepGuideExport.fit(CGSize(width: 1032, height: 400), in: box), CGRect(x: 48, y: 448, width: 516, height: 200))
        // Small: kept at its size, centered across.
        XCTAssertEqual(StepGuideExport.fit(CGSize(width: 116, height: 100), in: box), CGRect(x: 248, y: 548, width: 116, height: 100))
        XCTAssertEqual(StepGuideExport.fit(.zero, in: box), .zero)
    }

    // MARK: Steps on disk

    @MainActor func testStoreKeepsStepsInOrderOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StepStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StepStore(directory: dir)
        let image = TestImages.text(["Save"])
        store.add(image, click: CGPoint(x: 100, y: 60), text: "Click **Save**")
        store.add(image, click: CGPoint(x: 200, y: 60), text: "Click in Notes")
        XCTAssertEqual(store.steps.map(\.text), ["Click **Save**", "Click in Notes"])
        let first = try XCTUnwrap(store.steps.first)
        XCTAssertNotNil(NSImage(contentsOf: store.png(for: first)))
        // The editor document holds the screenshot and the step's marker, numbered by its place.
        let saved = try XCTUnwrap(CaptureHistory.document(for: store.png(for: first)))
        let marker = try XCTUnwrap(saved.document.items.first)
        XCTAssertEqual(marker.tool, .counter)
        XCTAssertEqual(marker.id, first.marker)
        XCTAssertEqual(marker.text, "1")

        store.setText("Click **Save** in the toolbar", for: first.id)
        store.move(first.id, by: 1)
        XCTAssertEqual(store.steps.map(\.text), ["Click in Notes", "Click **Save** in the toolbar"])
        XCTAssertEqual(StepStore(directory: dir).steps, store.steps)

        store.delete(store.steps[0].id)
        XCTAssertEqual(StepStore(directory: dir).steps.map(\.text), ["Click **Save** in the toolbar"])
        store.clear()
        XCTAssertTrue(StepStore(directory: dir).steps.isEmpty)
    }
}
