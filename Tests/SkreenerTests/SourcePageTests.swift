import XCTest
@testable import Skreener

final class SourcePageTests: XCTestCase {
    func testEveryBrowserGetsItsOwnScript() throws {
        let safari = try XCTUnwrap(SourcePage.script(forBundleID: "com.apple.Safari"))
        XCTAssertTrue(safari.contains("current tab of front window"))
        XCTAssertTrue(safari.contains("application id \"com.apple.Safari\""))
        for id in ["com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            let script = try XCTUnwrap(SourcePage.script(forBundleID: id), id)
            XCTAssertTrue(script.contains("active tab of front window"), id)
            XCTAssertTrue(script.contains("application id \"\(id)\""), id)
            XCTAssertTrue(script.contains("with timeout"), id)
        }
    }

    func testOtherAppsGetNoScript() {
        XCTAssertNil(SourcePage.script(forBundleID: "com.apple.finder"))
        XCTAssertNil(SourcePage.script(forBundleID: "org.mozilla.firefox"))
        XCTAssertNil(SourcePage.script(forBundleID: nil))
    }

    func testParsesTheBrowsersAnswer() {
        let page = SourcePage.parse(reply: "https://example.com/a?b=1\nExample: A page")
        XCTAssertEqual(page, SourcePage.Page(url: "https://example.com/a?b=1", title: "Example: A page"))
        XCTAssertNil(SourcePage.parse(reply: "https://example.com/\n")?.title, "an empty title is no title")
        XCTAssertEqual(SourcePage.parse(reply: "http://localhost:3000/")?.url, "http://localhost:3000/")
        XCTAssertEqual(SourcePage.parse(reply: "https://a.com/\nLine one\nLine two")?.title, "Line one\nLine two")
    }

    func testOnlyWebPagesCount() {
        XCTAssertNil(SourcePage.parse(reply: nil))
        XCTAssertNil(SourcePage.parse(reply: ""))
        XCTAssertNil(SourcePage.parse(reply: "missing value\nNew Tab"))
        XCTAssertNil(SourcePage.parse(reply: "chrome://settings/\nSettings"))
        XCTAssertNil(SourcePage.parse(reply: "about:blank\n"))
        XCTAssertNil(SourcePage.parse(reply: "file:///Users/me/a.html\nA"))
        XCTAssertNil(SourcePage.parse(reply: "javascript:alert(1)"))
    }

    func testHostForTheSiteFilter() {
        XCTAssertEqual(SourcePage.host(of: "https://www.Apple.com/mac"), "apple.com")
        XCTAssertEqual(SourcePage.host(of: "https://docs.github.com/en"), "docs.github.com")
        XCTAssertEqual(SourcePage.host(of: "http://localhost:3000/x"), "localhost")
        XCTAssertNil(SourcePage.host(of: "not a url"))
        XCTAssertNil(SourcePage.host(of: nil))
    }

    func testWhereFromsIsABinaryPlistOfStrings() throws {
        let data = try XCTUnwrap(SourcePage.whereFromsData(["https://example.com/a"]))
        XCTAssertTrue(data.starts(with: Data("bplist".utf8)), "Finder reads the binary format")
        XCTAssertEqual(SourcePage.addresses(inWhereFroms: data), ["https://example.com/a"])
        XCTAssertEqual(SourcePage.addresses(inWhereFroms: Data("junk".utf8)), [])
    }

    func testWhereFromsRoundTripsThroughTheFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString).png")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertNil(SourcePage.readWhereFroms(of: file))
        SourcePage.writeWhereFroms("https://example.com/page", to: file)
        XCTAssertEqual(SourcePage.readWhereFroms(of: file), "https://example.com/page")
    }
}
