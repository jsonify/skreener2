import XCTest
@testable import Skreener

final class PasteDestinationTests: XCTestCase {
    func testReadsTheSiteFromTheEndOfTheTitle() {
        XCTAssertEqual(PasteDestination.site(fromTitle: "Paste destinations · Issue #327 · jsonify/skreener2 · GitHub"), "GitHub")
        XCTAssertEqual(PasteDestination.site(fromTitle: "Meeting notes - Google Docs"), "Google Docs")
        XCTAssertEqual(PasteDestination.site(fromTitle: "Inbox (3) – Gmail"), "Gmail")
        XCTAssertEqual(PasteDestination.site(fromTitle: "Roadmap — Notion"), "Notion")
        XCTAssertEqual(PasteDestination.site(fromTitle: "a - b · c - Slack"), "Slack", "the last separator counts")
    }

    func testLeavesOutTheBrowsersOwnName() {
        XCTAssertEqual(PasteDestination.site(fromTitle: "Meeting notes - Google Docs - Google Chrome"), "Google Docs")
        XCTAssertEqual(PasteDestination.site(fromTitle: "Pull requests · GitHub — Mozilla Firefox"), "GitHub")
        XCTAssertNil(PasteDestination.site(fromTitle: "Docs - Microsoft\u{200B} Edge"))
    }

    func testTitlesWithoutASiteGiveNone() {
        XCTAssertNil(PasteDestination.site(fromTitle: "GitHub"))
        XCTAssertNil(PasteDestination.site(fromTitle: ""))
        XCTAssertNil(PasteDestination.site(fromTitle: "well-known-name"), "a hyphen without spaces isn't a separator")
        XCTAssertNil(PasteDestination.site(fromTitle: "Score - 3"), "no letters")
        XCTAssertNil(PasteDestination.site(fromTitle: "Title - " + String(repeating: "word ", count: 12)), "too long")
    }

    func testBrowsersAreKeyedBySite() {
        let github = PasteDestination(bundleID: "com.google.Chrome", appName: "Google Chrome",
                                      windowTitle: "Issues · jsonify/skreener2 · GitHub")
        XCTAssertEqual(github.site, "GitHub")
        XCTAssertEqual(github.key, "com.google.Chrome|github")
        XCTAssertEqual(github.displayName, "Chrome · GitHub")

        let bare = PasteDestination(bundleID: "com.apple.Safari", appName: "Safari", windowTitle: "Start Page")
        XCTAssertNil(bare.site)
        XCTAssertEqual(bare.key, "com.apple.Safari")
        XCTAssertEqual(bare.displayName, "Safari")

        let noTitle = PasteDestination(bundleID: "company.thebrowser.Browser", appName: "Arc", windowTitle: nil)
        XCTAssertEqual(noTitle.key, "company.thebrowser.Browser")
        XCTAssertEqual(noTitle.displayName, "Arc")
    }

    func testOtherAppsIgnoreTheirTitle() {
        let notes = PasteDestination(bundleID: "com.apple.Notes", appName: "Notes", windowTitle: "Shopping - list")
        XCTAssertNil(notes.site)
        XCTAssertEqual(notes.key, "com.apple.Notes")
        XCTAssertEqual(notes.displayName, "Notes")
    }

    func testBuiltInRules() {
        for id in ["com.microsoft.VSCode", "com.apple.dt.Xcode", "md.obsidian", "com.apple.Terminal",
                   "com.googlecode.iterm2", "dev.zed.Zed", "com.sublimetext.4"] {
            XCTAssertEqual(PasteDestination(bundleID: id, appName: id).builtInChoice, .markdown, id)
        }
        for id in PasteDestination.browsers.keys {
            let github = PasteDestination(bundleID: id, appName: id, windowTitle: "Pull requests · GitHub")
            XCTAssertEqual(github.builtInChoice, .markdown, id)
            let docs = PasteDestination(bundleID: id, appName: id, windowTitle: "Notes - Google Docs")
            XCTAssertNil(docs.builtInChoice, id)
        }
        XCTAssertNil(PasteDestination(bundleID: "com.apple.TextEdit", appName: "TextEdit").builtInChoice)
        XCTAssertNil(PasteDestination(bundleID: "com.apple.Safari", appName: "Safari").builtInChoice)
        // GitHub in a window title outside a browser is just a title.
        XCTAssertNil(PasteDestination(bundleID: "com.apple.Notes", appName: "Notes", windowTitle: "x · GitHub").builtInChoice)
    }

    func testRememberedChoiceWinsThenTheRuleThenClean() {
        let github = PasteDestination(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "PR · GitHub")
        XCTAssertEqual(github.choice(remembered: [:]), .markdown)
        XCTAssertEqual(github.choice(remembered: ["com.google.Chrome|github": "clean"]), .clean)
        XCTAssertEqual(github.choice(remembered: ["com.google.Chrome": "clean"]), .markdown, "another key")

        let textEdit = PasteDestination(bundleID: "com.apple.TextEdit", appName: "TextEdit")
        XCTAssertEqual(textEdit.choice(remembered: [:]), .clean)
        XCTAssertEqual(textEdit.choice(remembered: ["com.apple.TextEdit": "markdown"]), .markdown)
        XCTAssertEqual(textEdit.choice(remembered: ["com.apple.TextEdit": "rot13"]), .clean, "an unknown value is ignored")
    }

    func testChoices() {
        XCTAssertEqual(PasteDestination.Choice.clean.other, .markdown)
        XCTAssertEqual(PasteDestination.Choice.markdown.other, .clean)
        XCTAssertEqual(PasteDestination.Choice.clean.phrase, "clean text")
    }
}
