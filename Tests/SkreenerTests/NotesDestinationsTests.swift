import XCTest
@testable import Skreener

/// The links and scripts that hand a capture to notes apps (#275).
final class NotesDestinationsTests: XCTestCase {
    func testEncodeEscapesEverythingButUnreservedCharacters() {
        XCTAssertEqual(NoteLinks.encode("a b&c=d/e?f#g+h"), "a%20b%26c%3Dd%2Fe%3Ff%23g%2Bh")
        XCTAssertEqual(NoteLinks.encode("Az09-._~"), "Az09-._~")
        XCTAssertEqual(NoteLinks.encode("naïve ✓\n"), "na%C3%AFve%20%E2%9C%93%0A")
    }

    func testLinkLeavesOutEmptyParameters() {
        XCTAssertEqual(NoteLinks.link("x://y", [("a", "1"), ("b", nil), ("c", ""), ("d", "x y")])?.absoluteString,
                       "x://y?a=1&d=x%20y")
        XCTAssertEqual(NoteLinks.link("x://y", [("a", nil)])?.absoluteString, "x://y")
    }

    func testObsidianAppendsToANote() {
        let url = NoteLinks.obsidianNew(vault: "My Vault", file: "Skreener/Captures", content: "\n![[Shot 1.png]]\n")
        XCTAssertEqual(url?.absoluteString,
                       "obsidian://new?vault=My%20Vault&file=Skreener%2FCaptures&content=%0A%21%5B%5BShot%201.png%5D%5D%0A&append=true")
    }

    func testObsidianDailyNoteUsesAdvancedURI() {
        let url = NoteLinks.obsidianDaily(vault: "V", content: "hi")
        XCTAssertEqual(url?.absoluteString, "obsidian://advanced-uri?vault=V&daily=true&data=hi&mode=append")
    }

    func testObsidianEntryHasPictureThenText() {
        XCTAssertEqual(NoteLinks.obsidianEntry(image: "Shot.png", text: nil), "\n![[Shot.png]]\n")
        XCTAssertEqual(NoteLinks.obsidianEntry(image: "Shot.png", text: "Hello"), "\n![[Shot.png]]\n\nHello\n")
        XCTAssertEqual(NoteLinks.vaultName(path: "/Users/me/Documents/My Vault"), "My Vault")
    }

    func testBearCarriesTheFileBase64Encoded() {
        let base64 = Data([0xFB, 0xFF]).base64EncodedString()   // "+/8=": characters a link must escape
        let url = NoteLinks.bear(title: "Shot", text: "a & b", file: base64, filename: "Shot.png")
        XCTAssertEqual(url?.absoluteString,
                       "bear://x-callback-url/create?title=Shot&text=a%20%26%20b&file=%2B%2F8%3D&filename=Shot.png")
        XCTAssertEqual(NoteLinks.bear(title: "Shot", text: nil, file: nil, filename: nil)?.absoluteString,
                       "bear://x-callback-url/create?title=Shot")
    }

    func testDraftsAndThings() {
        XCTAssertEqual(NoteLinks.drafts(text: "Hello world")?.absoluteString, "drafts://x-callback-url/create?text=Hello%20world")
        XCTAssertEqual(NoteLinks.things(title: "Shot", notes: "line 1\nline 2")?.absoluteString,
                       "things:///add?title=Shot&notes=line%201%0Aline%202")
    }

    func testThingsNotesAreCutToItsLimit() {
        let long = String(repeating: "a", count: NoteLinks.thingsNotesLimit + 50)
        let url = NoteLinks.things(title: "T", notes: long)?.absoluteString ?? ""
        XCTAssertTrue(url.hasSuffix("&notes=" + String(repeating: "a", count: NoteLinks.thingsNotesLimit)))
    }

    func testAppleScriptLiteralEscapesQuotesBackslashesAndLineBreaks() {
        XCTAssertEqual(NoteLinks.literal("say \"hi\" \\ bye"), "\"say \\\"hi\\\" \\\\ bye\"")
        XCTAssertEqual(NoteLinks.literal("a\nb\r\nc"), "\"a\" & linefeed & \"b\" & linefeed & \"c\"")
        XCTAssertEqual(NoteLinks.literal(""), "\"\"")
    }

    func testNoteHTMLEscapesTextAndPutsThePictureBeforeIt() {
        let html = NoteLinks.noteHTML(title: "A <b> & C", text: "x < y\n\nz", imageType: "image/png", imageBase64: "QUJD")
        XCTAssertEqual(html, "<div><h1>A &lt;b&gt; &amp; C</h1></div><div><img src=\"data:image/png;base64,QUJD\"></div>"
                       + "<div>x &lt; y</div><div><br></div><div>z</div>")
        XCTAssertEqual(NoteLinks.noteHTML(title: "T", text: nil, imageType: nil, imageBase64: nil), "<div><h1>T</h1></div>")
    }

    func testScripts() {
        XCTAssertEqual(NoteLinks.appleNotesScript(html: "<div>x</div>"),
                       "tell application \"Notes\"\n    make new note with properties {body:\"<div>x</div>\"}\nend tell")
        XCTAssertEqual(NoteLinks.remindersScript(title: "Shot", notes: "a\nb"),
                       "tell application \"Reminders\"\n    make new reminder with properties {name:\"Shot\", body:\"a\" & linefeed & \"b\"}\nend tell")
        XCTAssertEqual(NoteLinks.remindersScript(title: "Shot", notes: nil),
                       "tell application \"Reminders\"\n    make new reminder with properties {name:\"Shot\"}\nend tell")
    }

    func testImageTypeFollowsTheExtension() {
        XCTAssertEqual(NoteLinks.imageType(of: URL(fileURLWithPath: "/a/b.png")), "image/png")
        XCTAssertEqual(NoteLinks.imageType(of: URL(fileURLWithPath: "/a/b.JPG")), "image/jpeg")
    }

    func testEveryAppHasABundleIDAndTitle() {
        for app in NotesApp.allCases {
            XCTAssertFalse(app.title.isEmpty)
            XCTAssertTrue(app.bundleID.contains("."))
        }
        XCTAssertEqual(Set(NotesApp.allCases.map(\.bundleID)).count, NotesApp.allCases.count)
    }
}
