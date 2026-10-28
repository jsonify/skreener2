import XCTest
@testable import Skreener

/// What's New's changelog parser and the launch decision (#302).
final class ChangelogNotesTests: XCTestCase {
    private let changelog = """
    # Changelog

    ## [0.14.0](https://github.com/jsonify/skreener2/compare/v0.13.0...v0.14.0) (2026-10-27)


    ### Features

    * **capture:** Greenshot-style crosshair lines ([#81](https://github.com/jsonify/skreener2/issues/81)) ([#296](https://github.com/jsonify/skreener2/issues/296)) ([d2531c0](https://github.com/jsonify/skreener2/commit/d2531c070c9a7db0d8d5bc618db16834de47436d))
    * **editor:** add TextMatcher ([#295](https://github.com/jsonify/skreener2/issues/295)) ([24e3dbf](https://github.com/jsonify/skreener2/commit/24e3dbf9075544a1af7b3af5a6b29388ddb3600e))
    * **editor:** add TextMatcher ([#295](https://github.com/jsonify/skreener2/issues/295)) ([aaaaaaa](https://github.com/jsonify/skreener2/commit/aaaaaaa))

    ### Bug Fixes

    * plain fix (#12)

    ## [0.13.0](https://github.com/jsonify/skreener2/compare/v0.12.0...v0.13.0) (2026-10-27)

    ### Features

    * **library:** auto-filing rules
    """

    func testSectionForVersion() {
        let g = ChangelogNotes.groups(for: "0.14.0", in: changelog)
        XCTAssertEqual(g?.map(\.title), ["Features", "Bug Fixes"])
        XCTAssertEqual(g?[0].items, ["Capture: Greenshot-style crosshair lines", "Editor: add TextMatcher"])
        XCTAssertEqual(g?[1].items, ["plain fix"])
    }

    func testOlderSectionStopsAtNextHeading() {
        XCTAssertEqual(ChangelogNotes.groups(for: "0.13.0", in: changelog)?.first?.items, ["Library: auto-filing rules"])
    }

    func testMissingSection() {
        XCTAssertNil(ChangelogNotes.groups(for: "9.9.9", in: changelog))
        XCTAssertNil(ChangelogNotes.groups(for: "0.14.0", in: ""))
        XCTAssertNil(ChangelogNotes.groups(for: "0.1", in: changelog))
    }

    func testReleaseVersion() {
        XCTAssertEqual(ChangelogNotes.releaseVersion(["CFBundleShortVersionString": "0.14.0"]), "0.14.0")
        XCTAssertNil(ChangelogNotes.releaseVersion(["CFBundleShortVersionString": "dev"]))
        XCTAssertNil(ChangelogNotes.releaseVersion(["CFBundleShortVersionString": "0.14.0-3-gabc"]))
        XCTAssertNil(ChangelogNotes.releaseVersion(nil))
    }

    func testReleaseURL() {
        XCTAssertEqual(ChangelogNotes.releaseURL(for: "0.14.0")?.absoluteString,
                       "https://github.com/jsonify/skreener2/releases/tag/v0.14.0")
    }

    func testNewInstallShowsWelcome() {
        XCTAssertEqual(LaunchHelp.decide(stored: nil, current: "0.14.0", hasEarlierUse: false), .welcome)
    }

    func testUpgradeShowsWhatsNew() {
        XCTAssertEqual(LaunchHelp.decide(stored: "0.13.0", current: "0.14.0", hasEarlierUse: true), .whatsNew)
        XCTAssertEqual(LaunchHelp.decide(stored: nil, current: "0.14.0", hasEarlierUse: true), .whatsNew)
    }

    func testSameVersionShowsNothing() {
        XCTAssertEqual(LaunchHelp.decide(stored: "0.14.0", current: "0.14.0", hasEarlierUse: true), .nothing)
    }

    func testDevBuildNeverShowsWhatsNew() {
        XCTAssertEqual(LaunchHelp.decide(stored: "0.14.0", current: "dev", hasEarlierUse: true), .nothing)
        XCTAssertEqual(LaunchHelp.decide(stored: nil, current: "dev", hasEarlierUse: true), .nothing)
        XCTAssertEqual(LaunchHelp.decide(stored: "dev", current: "dev", hasEarlierUse: false), .nothing)
    }

    func testEarlierUseSignals() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ChangelogNotesTests"))
        defaults.removePersistentDomain(forName: "ChangelogNotesTests")
        XCTAssertFalse(LaunchHelp.hasEarlierUse(defaults: defaults, historyHasFiles: false))
        XCTAssertTrue(LaunchHelp.hasEarlierUse(defaults: defaults, historyHasFiles: true))
    }
}
