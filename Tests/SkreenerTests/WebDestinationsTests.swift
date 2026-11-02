import XCTest
@testable import Skreener

/// The links that open Gmail and Google Chat, for Send To and the Email smart action.
final class WebDestinationsTests: XCTestCase {
    func testGmailComposeLeavesOutMissingFields() {
        XCTAssertEqual(WebLinks.gmailCompose(subject: "Skreener 2026-11-02 at 10.00.00")?.absoluteString,
                       "https://mail.google.com/mail/?view=cm&fs=1&su=Skreener%202026-11-02%20at%2010.00.00")
        XCTAssertEqual(WebLinks.gmailCompose()?.absoluteString, "https://mail.google.com/mail/?view=cm&fs=1")
    }

    func testMailtoBecomesGmailCompose() {
        let url = WebLinks.gmailCompose(mailto: URL(string: "mailto:a@example.com")!)
        XCTAssertEqual(url?.absoluteString, "https://mail.google.com/mail/?view=cm&fs=1&to=a%40example.com")
    }

    func testMailtoCarriesSubjectBodyAndCopies() {
        let mailto = URL(string: "mailto:a@example.com?Subject=Hi%20there&body=Line%201&cc=b@example.com&cc=c@example.com")!
        XCTAssertEqual(WebLinks.gmailCompose(mailto: mailto)?.absoluteString,
                       "https://mail.google.com/mail/?view=cm&fs=1&to=a%40example.com&cc=b%40example.com%2Cc%40example.com"
                       + "&su=Hi%20there&body=Line%201")
    }

    func testOtherLinksAreNotMail() {
        XCTAssertNil(WebLinks.gmailCompose(mailto: URL(string: "https://example.com")!))
        XCTAssertNil(WebLinks.gmailCompose(mailto: URL(string: "mailto:")!))
    }

    func testEmailLinkFollowsTheSetting() {
        let mailto = URL(string: "mailto:a@example.com")!
        XCTAssertEqual(WebLinks.emailLink(mailto, inGmail: false), mailto)
        XCTAssertEqual(WebLinks.emailLink(mailto, inGmail: true).host, "mail.google.com")
        let web = URL(string: "https://example.com")!
        XCTAssertEqual(WebLinks.emailLink(web, inGmail: true), web)
    }

    func testGoogleChatAndIDs() {
        XCTAssertEqual(WebLinks.googleChat?.absoluteString, "https://mail.google.com/chat/")
        XCTAssertEqual(WebApp.googleChat.url(subject: "x"), WebLinks.googleChat)
        XCTAssertEqual(WebApp.allCases.map { $0.title }, ["Gmail", "Google Chat"])
    }
}
