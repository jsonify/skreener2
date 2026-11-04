import CoreGraphics
import XCTest
@testable import SkreenerCore

/// OCR (Capture Text, Copy Text) and Redact on text drawn in code, with CoreText.
final class TextRecognizerTests: XCTestCase {
    private func size(_ image: CGImage) -> CGSize { TestImages.size(of: image) }

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
        let image = TestImages.text(["First line", "Second line"])
        let boxes = await TextRecognizer.boxes(in: image, size: size(image), matching: .allText)
        XCTAssertEqual(boxes.count, 2)
    }

    func testRedactEmailCoversJustTheAddress() async {
        let image = TestImages.text(["Mail jane@example.com today"])
        let boxes = await TextRecognizer.boxes(in: image, size: size(image), matching: .emails)
        XCTAssertEqual(boxes.count, 1)
        if let box = boxes.first {
            // "Mail " comes first, so the box starts well to the right of the line's start (x = 40).
            XCTAssertGreaterThan(box.minX, 100, "\(box)")
            XCTAssertLessThanOrEqual(box.maxX, size(image).width)
        }
    }

    func testRedactLinkAndPhoneNumber() async {
        let image = TestImages.text(["Visit https://example.com now", "Call 415-555-0132 soon"])
        let links = await TextRecognizer.boxes(in: image, size: size(image), matching: .links)
        let phones = await TextRecognizer.boxes(in: image, size: size(image), matching: .phoneNumbers)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(phones.count, 1)
    }

    func testLineBoxesInAnArea() async {
        // Lines sit in 120 pt bands from the top of a 360 pt image: the lower two bands hold the second and third.
        let image = TestImages.text(["Top line here", "Middle words", "Bottom words"])
        let area = CGRect(x: 0, y: 0, width: 1000, height: 240)
        let boxes = await TextRecognizer.lineBoxes(in: image, size: size(image), area: area)
        XCTAssertEqual(boxes.count, 2, "\(boxes)")
        for box in boxes {
            XCTAssertTrue(area.insetBy(dx: -2, dy: -2).contains(box), "\(box)")
            XCTAssertGreaterThan(box.minX, 20, "\(box)")   // text starts at x = 40
            XCTAssertLessThan(box.height, 120, "\(box)")
        }
    }

    func testLineBoxesFindNothingInABlankArea() async {
        let image = TestImages.text(["Only one line"])
        let boxes = await TextRecognizer.lineBoxes(in: image, size: size(image), area: CGRect(x: 700, y: 0, width: 300, height: 120))
        XCTAssertTrue(boxes.isEmpty, "\(boxes)")
    }

    func testIndexBoxesAPhraseWithinItsLine() async {
        let image = TestImages.text(["Pay Jane Smith today", "Nothing else here"])
        let index = await TextRecognizer.index(of: image, size: size(image))
        let matches = TextMatcher.matches(of: ["Jane Smith"], in: index.lines, options: .init())
        XCTAssertEqual(matches.count, 1, "\(index.lines)")
        guard let span = matches.first?.spans.first else { return }
        XCTAssertEqual(matches.first?.spans.count, 1)
        guard let box = index.box(line: span.line, range: span.range) else { return XCTFail("no box for the phrase") }
        // One box for both words, inside the first line's (the top 120 pt band of a 240 pt image) and narrower.
        let line = index.lineBoxes[span.line]
        XCTAssertTrue(line.insetBy(dx: -2, dy: -2).contains(box), "\(box) in \(line)")
        XCTAssertLessThan(box.width, line.width * 0.8, "\(box) in \(line)")
        XCTAssertGreaterThan(box.minY, 110, "\(box)")
    }

    func testIndexBoxSitsOnTheMatch() async {
        let image = TestImages.text(["Mail jane@example.com today"])
        let index = await TextRecognizer.index(of: image, size: size(image))
        let matches = TextMatcher.matches(of: ["jane@example.com"], in: index.lines, options: .init())
        XCTAssertEqual(matches.count, 1, "\(index.lines)")
        guard let span = matches.first?.spans.first else { return }
        guard let box = index.box(line: span.line, range: span.range) else { return XCTFail("no box for the address") }
        // "Mail " comes first, so the box starts well to the right of the line's start (x = 40).
        XCTAssertGreaterThan(box.minX, 100, "\(box)")
        XCTAssertLessThanOrEqual(box.maxX, size(image).width)
    }

    func testIndexOfABlankImageIsEmpty() async {
        let blank = TestImages.image(width: 300, height: 120) { ctx, r in ctx.setFillColor(TestImages.white); ctx.fill(r) }
        let index = await TextRecognizer.index(of: blank, size: size(blank))
        XCTAssertTrue(index.lines.isEmpty, "\(index.lines)")
        XCTAssertNil(index.box(line: 0, range: "".startIndex..<"".endIndex))
    }

    func testRedactFindsNothingWithoutMatches() async {
        let image = TestImages.text(["Nothing private here"])
        let boxes = await TextRecognizer.boxes(in: image, size: size(image), matching: .emails)
        XCTAssertTrue(boxes.isEmpty, "\(boxes)")
    }
}

