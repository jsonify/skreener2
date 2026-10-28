import XCTest
import CoreImage
@testable import Skreener

/// Smart actions (#243): the mapping, URLs, calendar file and detection, none of which need a screen.
final class SmartActionsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26T07:33:20Z

    // MARK: Calendar file

    func testUTCStamp() {
        XCTAssertEqual(ICalendar.utc(Date(timeIntervalSince1970: 0)), "19700101T000000Z")
        XCTAssertEqual(ICalendar.utc(start), "20261026T073320Z")
    }

    func testEscaping() {
        XCTAssertEqual(ICalendar.escape("a;b,c\\d"), "a\\;b\\,c\\\\d")
        XCTAssertEqual(ICalendar.escape("one\ntwo\r\nthree"), "one\\ntwo\\nthree")
    }

    func testEventFile() {
        let event = CalendarEvent(title: "Lunch; with Sam, 1st", start: start, end: start.addingTimeInterval(3600),
                                  location: "1 Main St, Town")
        let file = ICalendar.file(for: event, uid: "abc", stamp: start)
        XCTAssertTrue(file.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(file.hasSuffix("END:VEVENT\r\nEND:VCALENDAR\r\n"))
        XCTAssertTrue(file.contains("\r\nUID:abc\r\n"))
        XCTAssertTrue(file.contains("\r\nDTSTART:20261026T073320Z\r\n"))
        XCTAssertTrue(file.contains("\r\nDTEND:20261026T083320Z\r\n"))
        XCTAssertTrue(file.contains("\r\nSUMMARY:Lunch\\; with Sam\\, 1st\r\n"))
        XCTAssertTrue(file.contains("\r\nLOCATION:1 Main St\\, Town\r\n"))
        XCTAssertFalse(file.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    func testNoLocationLine() {
        let file = ICalendar.file(for: CalendarEvent(title: "x", start: start, end: start, location: nil))
        XCTAssertFalse(file.contains("LOCATION"))
    }

    func testLongLinesFoldWithinSeventyFiveBytes() {
        let folded = ICalendar.fold("SUMMARY:" + String(repeating: "é", count: 100))
        for line in folded.components(separatedBy: "\r\n") { XCTAssertLessThanOrEqual(line.utf8.count, 75) }
        let unfolded = folded.replacingOccurrences(of: "\r\n ", with: "")
        XCTAssertEqual(unfolded, "SUMMARY:" + String(repeating: "é", count: 100))
    }

    // MARK: URLs

    func testMapsURL() {
        XCTAssertEqual(SmartActions.mapsURL(for: "1 Infinite Loop\nCupertino, CA 95014")?.absoluteString,
                       "https://maps.apple.com/?q=1%20Infinite%20Loop%2C%20Cupertino%2C%20CA%2095014")
        XCTAssertEqual(SmartActions.mapsURL(for: "A&B + C")?.absoluteString, "https://maps.apple.com/?q=A%26B%20%2B%20C")
        XCTAssertNil(SmartActions.mapsURL(for: "  \n "))
    }

    func testTelURL() {
        XCTAssertEqual(SmartActions.telURL(for: "(415) 555-0132")?.absoluteString, "tel:4155550132")
        XCTAssertEqual(SmartActions.telURL(for: "+44 20 7946 0958")?.absoluteString, "tel:+442079460958")
        XCTAssertNil(SmartActions.telURL(for: "12"))
    }

    func testOpenableURL() {
        XCTAssertEqual(SmartActions.openableURL(" https://example.com/a?b=1 ")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertNotNil(SmartActions.openableURL("mailto:a@example.com"))
        XCTAssertNil(SmartActions.openableURL("WIFI:S:home;T:WPA;P:secret;;"))
        XCTAssertNil(SmartActions.openableURL("javascript:alert(1)"))
        XCTAssertNil(SmartActions.openableURL("just some text"))
        XCTAssertNil(SmartActions.openableURL("https://"))
    }

    // MARK: Mapping, ordering and de-duplication

    func testMappingAndOrder() {
        let link = URL(string: "https://example.com")!
        let found: [SmartDetection] = [
            .link(link), .phone("415-555-0132"), .address("1 Main St, Town"),
            .date(start: start, duration: 0, line: "Team lunch Friday"), .code("https://qr.example.com"),
        ]
        let actions = SmartActions.actions(for: found)
        XCTAssertEqual(actions.map(\.kind), [.openCode, .copyCode, .calendar, .maps, .call, .link])
        let event = actions[2].event
        XCTAssertEqual(event?.title, "Team lunch Friday")
        XCTAssertEqual(event?.end, start.addingTimeInterval(3600))
        XCTAssertEqual(event?.location, "1 Main St, Town")
        XCTAssertEqual(actions[3].url?.host, "maps.apple.com")
        XCTAssertEqual(actions[4].url?.absoluteString, "tel:4155550132")
    }

    func testDurationIsKept() {
        let a = SmartActions.actions(for: [.date(start: start, duration: 5400, line: "")])
        XCTAssertEqual(a.first?.event?.end, start.addingTimeInterval(5400))
        XCTAssertEqual(a.first?.event?.title, "Event")
    }

    func testDuplicatesAreDropped() {
        let url = URL(string: "https://example.com/")!
        let found: [SmartDetection] = [
            .link(url), .link(URL(string: "https://EXAMPLE.com")!), .phone("415 555 0132"), .phone("(415) 555-0132"),
            .address("1 Main St"), .address("1  main st"), .code("A"), .code("A"),
        ]
        let kinds = SmartActions.actions(for: found).map(\.kind)
        XCTAssertEqual(kinds, [.copyCode, .maps, .call, .link])
    }

    func testLinkInAQRCodeIsOfferedOnce() {
        let found: [SmartDetection] = [.link(URL(string: "https://example.com")!), .code("https://example.com/")]
        XCTAssertEqual(SmartActions.actions(for: found).map(\.kind), [.openCode, .copyCode])
    }

    func testPlainCodeCanOnlyBeCopied() {
        let a = SmartActions.actions(for: [.code("WIFI:S:home;T:WPA;P:secret;;")])
        XCTAssertEqual(a.map(\.kind), [.copyCode])
        XCTAssertEqual(a.first?.text, "WIFI:S:home;T:WPA;P:secret;;")
    }

    func testLimitAndNonWebLinks() {
        let many = (0..<20).map { SmartDetection.phone("415-555-01\(String(format: "%02d", $0))") }
        XCTAssertEqual(SmartActions.actions(for: many, limit: 5).count, 5)
        XCTAssertTrue(SmartActions.actions(for: [.link(URL(string: "ftp://example.com")!)]).isEmpty)
        XCTAssertEqual(SmartActions.actions(for: [.link(URL(string: "mailto:a@example.com")!)]).first?.chipTitle, "Email")
        XCTAssertTrue(SmartActions.actions(for: []).isEmpty)
    }

    // MARK: Detection in text

    func testDetectsPhoneAndLink() {
        let found = SmartActions.detections(in: "Call 415-555-0132 or visit https://example.com/menu today")
        XCTAssertTrue(found.contains { if case .phone(let p) = $0 { return p.contains("555-0132") } else { return false } }, "\(found)")
        XCTAssertTrue(found.contains(.link(URL(string: "https://example.com/menu")!)), "\(found)")
    }

    func testDetectsDateWithItsLine() {
        let found = SmartActions.detections(in: "Intro\nDinner on October 30, 2026 at 7:30 PM\nBring wine")
        var comps: DateComponents?
        var line = ""
        for case .date(let start, _, let l) in found {
            comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            line = l
        }
        XCTAssertEqual(comps?.year, 2026)
        XCTAssertEqual(comps?.month, 10)
        XCTAssertEqual(comps?.day, 30)
        XCTAssertEqual(comps?.hour, 19)
        XCTAssertEqual(comps?.minute, 30)
        XCTAssertEqual(line, "Dinner on October 30, 2026 at 7:30 PM")
    }

    func testDetectsAddress() {
        let found = SmartActions.detections(in: "Meet at 1 Infinite Loop, Cupertino, CA 95014 later")
        XCTAssertTrue(found.contains { if case .address(let a) = $0 { return a.contains("Infinite Loop") } else { return false } }, "\(found)")
    }

    func testNothingInPlainText() {
        XCTAssertTrue(SmartActions.detections(in: "").isEmpty)
        XCTAssertTrue(SmartActions.detections(in: "just a few plain words").isEmpty)
    }

    // MARK: QR codes (Vision, no screen needed)

    private func qrImage(_ text: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(out, from: out.extent)
    }

    func testReadsAQRCode() throws {
        let cg = try XCTUnwrap(qrImage("https://example.com/hello"))
        XCTAssertEqual(BarcodeScanner.payloads(in: cg), ["https://example.com/hello"])
    }

    func testNoCodeInPlainImage() async {
        let codes = await BarcodeScanner.payloads(in: TestImages.text(["No code here"]))
        XCTAssertTrue(codes.isEmpty)
    }

    func testDetectorOffersQRActions() async throws {
        let cg = try XCTUnwrap(qrImage("https://example.com/hello"))
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let actions = await SmartActionDetector.detect(in: image)
        XCTAssertEqual(actions.first?.kind, .openCode)
        XCTAssertTrue(actions.contains { $0.kind == .copyCode })
    }
}
