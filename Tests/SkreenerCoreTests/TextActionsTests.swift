import XCTest
@testable import SkreenerCore

/// What the editor's Text sheet offers from the text in a screenshot (#441).
final class TextActionsTests: XCTestCase {
    func testLinksKeepHttpOnlyAndAreDeduplicated() {
        let found = TextActions.find(in: [
            "Read https://example.com/a today",
            "or visit example.com/b.",
            "again HTTPS://EXAMPLE.COM/a",
            "mail jane@example.com",
        ])
        XCTAssertEqual(found.links.map(\.url.absoluteString), ["https://example.com/a", "http://example.com/b"])
        XCTAssertEqual(found.links.map(\.text), ["https://example.com/a", "example.com/b"])
    }

    func testEmailsAreDeduplicatedIgnoringCase() {
        let found = TextActions.find(in: ["Jane@Example.com", "write to jane@example.com or bob@example.org."])
        XCTAssertEqual(found.emails, ["Jane@Example.com", "bob@example.org"])
    }

    func testPhoneNumbersAreDeduplicatedByDigits() {
        let found = TextActions.find(in: ["Call (415) 555-0132 now", "or 415-555-0132", "or 415 555 0199"])
        XCTAssertEqual(found.phones.count, 2)
        XCTAssertEqual(found.phones.map { $0.filter(\.isNumber) }, ["4155550132", "4155550199"])
    }

    func testDateWithTimeHasAnHourByDefault() throws {
        let found = TextActions.find(in: ["Dinner with Sam, March 5, 2031 at 3:30 PM"])
        let event = try XCTUnwrap(found.dates.first)
        XCTAssertFalse(event.allDay)
        XCTAssertEqual(event.duration, 3600)
        XCTAssertEqual(event.end.timeIntervalSince(event.start), 3600)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.start)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2031, 3, 5, 15, 30])
        XCTAssertEqual(event.title, "Dinner with Sam")
    }

    func testDateWithoutTimeIsAllDay() throws {
        let found = TextActions.find(in: ["March 5, 2031"])
        let event = try XCTUnwrap(found.dates.first)
        XCTAssertTrue(event.allDay)
        XCTAssertEqual(event.end, event.start)
        XCTAssertEqual(event.title, "Event")
    }

    func testTitleDropsTheDateAndDanglingWords() {
        let line = "Team lunch on March 5, 2031"
        let range = line.range(of: "March 5, 2031")!
        XCTAssertEqual(TextActions.title(line: line, removing: range), "Team lunch")
        let alone = "at 7 pm"
        XCTAssertEqual(TextActions.title(line: alone, removing: alone.range(of: "7 pm")!), "Event")
    }

    func testTimeOfDayDetection() {
        XCTAssertTrue(TextActions.hasTimeOfDay("March 5 at 7:30"))
        XCTAssertTrue(TextActions.hasTimeOfDay("Friday 7 pm"))
        XCTAssertTrue(TextActions.hasTimeOfDay("tomorrow at noon"))
        XCTAssertFalse(TextActions.hasTimeOfDay("March 5, 2031"))
    }

    func testNothingFoundInPlainText() {
        XCTAssertTrue(TextActions.find(in: ["Hello there", "General Kenobi"]).isEmpty)
        XCTAssertTrue(TextActions.find(in: []).isEmpty)
    }

    // MARK: Lines

    private func box(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 100, h: CGFloat = 20) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    func testReadingOrderIsTopToBottomThenLeftToRight() {
        // Bottom-left origin: the larger y is higher. Indexes 1 and 2 share a row (2 is a little lower, still the
        // same row) and 2 is left of 1.
        let boxes = [box(0, 10), box(200, 300), box(10, 296), box(0, 150)]
        XCTAssertEqual(TextActions.readingOrder(boxes), [2, 1, 3, 0])
    }

    func testVisibleLinesAreOrderedAndLeaveOutCoveredOnes() {
        let lines = ["last", "secret", "first", "middle"]
        let boxes = [box(0, 10), box(0, 200), box(0, 300), box(0, 100)]
        let covered = [CGRect(x: 0, y: 195, width: 120, height: 30)]
        XCTAssertEqual(TextActions.visibleLines(lines, boxes: boxes, covered: []), ["first", "secret", "middle", "last"])
        XCTAssertEqual(TextActions.visibleLines(lines, boxes: boxes, covered: covered), ["first", "middle", "last"])
    }

    func testARedactionBesideALineOnlyTouchingItsEdgeDoesNotHideIt() {
        let lines = ["a"]
        let boxes = [box(0, 100)]
        // Overlaps the line by 2 of its 20 points of height.
        XCTAssertEqual(TextActions.visibleLines(lines, boxes: boxes, covered: [box(0, 118, h: 30)]), ["a"])
        // Overlaps half of it.
        XCTAssertEqual(TextActions.visibleLines(lines, boxes: boxes, covered: [box(50, 110, h: 30)]), [])
    }

    func testVisibleLinesWithoutBoxesComeBackAsTheyAre() {
        XCTAssertEqual(TextActions.visibleLines(["a", "b"], boxes: [], covered: [box(0, 0)]), ["a", "b"])
    }
}
