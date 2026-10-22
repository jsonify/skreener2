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

    func testLineBoxesInAnArea() async {
        // Lines sit in 120 pt bands from the top of a 360 pt image: the lower two bands hold the second and third.
        let image = TestImages.text(["Top line here", "Middle words", "Bottom words"])
        let area = CGRect(x: 0, y: 0, width: 1000, height: 240)
        let boxes = await TextRecognizer.lineBoxes(in: image, area: area)
        XCTAssertEqual(boxes.count, 2, "\(boxes)")
        for box in boxes {
            XCTAssertTrue(area.insetBy(dx: -2, dy: -2).contains(box), "\(box)")
            XCTAssertGreaterThan(box.minX, 20, "\(box)")   // text starts at x = 40
            XCTAssertLessThan(box.height, 120, "\(box)")
        }
    }

    func testLineBoxesFindNothingInABlankArea() async {
        let image = TestImages.text(["Only one line"])
        let boxes = await TextRecognizer.lineBoxes(in: image, area: CGRect(x: 700, y: 0, width: 300, height: 120))
        XCTAssertTrue(boxes.isEmpty, "\(boxes)")
    }

    func testRedactFindsNothingWithoutMatches() async {
        let boxes = await TextRecognizer.boxes(in: TestImages.text(["Nothing private here"]), matching: .emails)
        XCTAssertTrue(boxes.isEmpty, "\(boxes)")
    }
}
