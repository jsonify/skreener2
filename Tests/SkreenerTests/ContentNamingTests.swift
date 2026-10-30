import XCTest
@testable import Skreener

/// Saved screenshots named after what they show: the line picked as the title, and how it goes into the file name.
final class ContentNamingTests: XCTestCase {
    private typealias Line = ContentNaming.Line
    /// 7 March 2026, 09:05:02 local time.
    private let date: Date = {
        let c = DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 5, second: 2)
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    func testTallestWordsWin() {
        let lines = [Line(text: "12:41", height: 0.05, top: 0.01),
                     Line(text: "Pricing plans for teams", height: 0.04, top: 0.2),
                     Line(text: "Start your free trial today", height: 0.02, top: 0.3)]
        XCTAssertEqual(ContentNaming.title(from: lines), "Pricing plans for teams")
    }

    func testNearlyAsTallAndHigherWins() {
        let lines = [Line(text: "Sidebar item", height: 0.030, top: 0.5),
                     Line(text: "Main heading", height: 0.031, top: 0.1)]
        XCTAssertEqual(ContentNaming.title(from: lines), "Main heading")
    }

    func testNoWordsNoTitle() {
        let lines = [Line(text: "$12.99", height: 0.05, top: 0.1), Line(text: "10:30", height: 0.04, top: 0.2)]
        XCTAssertNil(ContentNaming.title(from: lines))
        XCTAssertNil(ContentNaming.title(from: []))
    }

    func testLongTitlesAreCutAtAWord() {
        let long = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
        XCTAssertEqual(ContentNaming.shorten(long), "alpha beta gamma delta epsilon zeta eta theta iota kappa")
    }

    func testTitlesAreSafeFileNames() {
        XCTAssertEqual(ContentNaming.clean("Build\nFailed: main/app"), "Build Failed - main-app")
    }

    func testTitleGoesIntoTheName() {
        XCTAssertEqual(Output.filename(for: date, template: Preferences.defaultFilenameTemplate, title: "Pricing · Stripe"),
                       "Pricing · Stripe 2026-03-07 at 09.05.02")
    }

    func testAppGoesIntoTheName() {
        XCTAssertEqual(Output.filename(for: date, template: "%a - %t %Y", app: "Safari", title: "Inbox"), "Safari - Inbox 2026")
    }

    func testUnknownAppTakesItsSeparatorWithIt() {
        XCTAssertEqual(Output.filename(for: date, template: "%a - %t %Y", title: "Inbox"), "Inbox 2026")
        XCTAssertEqual(Output.filename(for: date, template: "%t - %a - %Y", title: "Inbox"), "Inbox - 2026")
    }

    func testOnlyTemplatesWithTheTokenAreRenamed() {
        XCTAssertTrue(ContentNaming.usesTitle(Preferences.defaultFilenameTemplate))
        XCTAssertFalse(ContentNaming.usesTitle("Skreener %Y-%m-%d"))
        XCTAssertFalse(ContentNaming.usesTitle("100%%t"))
    }
}
