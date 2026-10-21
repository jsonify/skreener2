import XCTest
@testable import Skreener

/// OCR (Capture Text, Copy Text) and Redact on text drawn in code.
final class TextRecognizerTests: XCTestCase {
    func testRecognizesText() async {
        let text = await TextRecognizer.recognize(TestImages.text(["Skreener reads this line"]))
        XCTAssertTrue(text.contains("Skreener reads this line"), "recognized: \(text)")
    }

    func testRegionLimitsRecognition() async {
        let image = TestImages.text(["Top line here", "Bottom words only"])
        // Normalized with a bottom-left origin, like Vision: the lower half holds the second line.
        let text = await TextRecognizer.recognize(image, region: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertTrue(text.contains("Bottom"), "recognized: \(text)")
        XCTAssertFalse(text.contains("Top"), "recognized: \(text)")
    }

    func testRedactAllText() async {
        let boxes = await TextRecognizer.boxes(in: TestImages.text(["First line", "Second line"]), matching: .allText)
        XCTAssertEqual(boxes.count, 2)
    }

    func testRedactEmailCoversJustTheAddress() async {
        let image = TestImages.text(["Mail jane@example.com today"])
        let boxes = await TextRecognizer.boxes(in: image, matching: .emails)
        XCTAssertEqual(boxes.count, 1)
        if let box = boxes.first {
            // "Mail " comes first, so the box starts well to the right of the line's start (x = 40).
            XCTAssertGreaterThan(box.minX, 100, "\(box)")
            XCTAssertLessThanOrEqual(box.maxX, image.size.width)
        }
    }

    func testRedactLinkAndPhoneNumber() async {
        let image = TestImages.text(["Visit https://example.com now", "Call 415-555-0132 soon"])
        let links = await TextRecognizer.boxes(in: image, matching: .links)
        let phones = await TextRecognizer.boxes(in: image, matching: .phoneNumbers)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(phones.count, 1)
    }

    func testRedactFindsNothingWithoutMatches() async {
        let boxes = await TextRecognizer.boxes(in: TestImages.text(["Nothing private here"]), matching: .emails)
        XCTAssertTrue(boxes.isEmpty, "\(boxes)")
    }
}
