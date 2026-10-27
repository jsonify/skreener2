import XCTest
@testable import Skreener

final class LibraryTests: XCTestCase {
    private func entry(_ name: String, _ kind: SavedLibrary.Kind = .image, month: Int = 3, app: String? = nil,
                       text: String? = nil, edited: Bool = false) -> SavedLibrary.Entry {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: 10))!
        let ext = kind == .video ? "mp4" : kind == .gif ? "gif" : "png"
        return SavedLibrary.Entry(url: URL(fileURLWithPath: "/tmp/\(name).\(ext)"), date: date, kind: kind,
                                  meta: SavedLibrary.Meta(app: app, edited: edited, text: text))
    }

    private lazy var all = [
        entry("Invoice", app: "Safari", text: "Total due\nPay now"),
        entry("Chat", month: 4, app: "Slack", text: "lunch at noon?", edited: true),
        entry("Demo", .video, month: 4),
        entry("Loop", .gif),
    ]

    func testSearchFindsTextInTheScreenshot() {
        XCTAssertEqual(SavedLibrary.filter(all, .init(text: "total DUE")).map(\.name), ["Invoice"])
        XCTAssertEqual(SavedLibrary.filter(all, .init(text: "slack")).map(\.name), ["Chat"])
        XCTAssertEqual(SavedLibrary.filter(all, .init(text: "demo")).map(\.name), ["Demo"])
        XCTAssertTrue(SavedLibrary.filter(all, .init(text: "nothing like this")).isEmpty)
        XCTAssertEqual(SavedLibrary.filter(all, .init()).count, 4, "an empty search shows everything")
    }

    func testFilters() {
        XCTAssertEqual(SavedLibrary.filter(all, .init(month: "2026-04")).map(\.name), ["Chat", "Demo"])
        XCTAssertEqual(SavedLibrary.filter(all, .init(app: "Safari")).map(\.name), ["Invoice"])
        XCTAssertEqual(SavedLibrary.filter(all, .init(kind: .gif)).map(\.name), ["Loop"])
        XCTAssertEqual(SavedLibrary.filter(all, .init(editedOnly: true)).map(\.name), ["Chat"])
    }

    func testCountsForTheFilterMenus() {
        let months = SavedLibrary.counts(all) { $0.month }
        XCTAssertEqual(months.map(\.value), ["2026-03", "2026-04"])
        XCTAssertEqual(months.map(\.count), [2, 2])
        XCTAssertEqual(SavedLibrary.counts(all) { $0.meta.app }.map(\.value), ["Safari", "Slack"])
    }

    func testSearchAndSiteFilterUseTheSourcePage() {
        var meta = SavedLibrary.Meta(app: "Safari")
        meta.url = "https://www.example.com/docs/page"
        meta.pageTitle = "Quarterly Report"
        let date = Date()
        let page = SavedLibrary.Entry(url: URL(fileURLWithPath: "/tmp/Page.png"), date: date, kind: .image, meta: meta)
        let plain = SavedLibrary.Entry(url: URL(fileURLWithPath: "/tmp/Plain.png"), date: date, kind: .image,
                                       meta: SavedLibrary.Meta(app: "Slack"))
        let both = [page, plain]
        XCTAssertEqual(SavedLibrary.filter(both, .init(text: "quarterly")).map(\.name), ["Page"])
        XCTAssertEqual(SavedLibrary.filter(both, .init(text: "example.com/docs")).map(\.name), ["Page"])
        XCTAssertEqual(SavedLibrary.filter(both, .init(site: "example.com")).map(\.name), ["Page"])
        XCTAssertTrue(SavedLibrary.filter(both, .init(site: "other.org")).isEmpty)
        XCTAssertEqual(SavedLibrary.counts(both) { $0.meta.host }.map(\.value), ["example.com"])
    }

    func testMetaWrittenBeforeSourcePagesStillDecodes() throws {
        let old = Data(#"{"Old.png":{"app":"Safari","edited":true,"text":"hello"}}"#.utf8)
        let decoded = try JSONDecoder().decode([String: SavedLibrary.Meta].self, from: old)
        XCTAssertEqual(decoded["Old.png"]?.app, "Safari")
        XCTAssertEqual(decoded["Old.png"]?.edited, true)
        XCTAssertNil(decoded["Old.png"]?.url)
        XCTAssertNil(decoded["Old.png"]?.pageTitle)

        var meta = SavedLibrary.Meta()
        meta.url = "https://example.com/"
        meta.pageTitle = "Example"
        let again = try JSONDecoder().decode(SavedLibrary.Meta.self, from: JSONEncoder().encode(meta))
        XCTAssertEqual(again, meta)
    }

    func testListsMediaInTheFolderNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["old.png", "notes.txt", "clip.mp4", "new.JPG"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
            Thread.sleep(forTimeInterval: 0.02)
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("folder.png"), withIntermediateDirectories: true)
        let found = SavedLibrary.list(dir)
        XCTAssertEqual(found.map(\.url.lastPathComponent), ["new.JPG", "clip.mp4", "old.png"])
        XCTAssertEqual(found.map(\.kind), [.image, .video, .image])
    }
}
