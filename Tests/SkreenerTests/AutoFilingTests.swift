import XCTest
@testable import Skreener

/// Filing rules (#277): which rule wins, when the text is needed, storage, and the names moved files get.
final class AutoFilingTests: XCTestCase {
    private func rule(_ condition: FilingRule.Condition, _ value: String, to folder: String = "/tmp/Filed",
                      enabled: Bool = true) -> FilingRule {
        FilingRule(enabled: enabled, condition: condition, value: value, folder: folder)
    }

    func testAppRuleMatchesIgnoringCase() {
        let figma = rule(.appIs, "Figma", to: "/tmp/Design")
        XCTAssertEqual(AutoFiling.decide(app: "figma", text: nil, rules: [figma]), .move(figma))
        XCTAssertEqual(AutoFiling.decide(app: "FIGMA ", text: nil, rules: [figma]), .move(figma))
        XCTAssertEqual(AutoFiling.decide(app: "Figma Beta", text: nil, rules: [figma]), .stay, "the whole name has to match")
        XCTAssertEqual(AutoFiling.decide(app: nil, text: nil, rules: [figma]), .stay)
    }

    func testTextRuleMatchesIgnoringCase() {
        let invoice = rule(.textContains, "invoice", to: "/tmp/Receipts")
        XCTAssertEqual(AutoFiling.decide(app: "Mail", text: "Your INVOICE #12\nTotal", rules: [invoice]), .move(invoice))
        XCTAssertEqual(AutoFiling.decide(app: "Mail", text: "Receipt", rules: [invoice]), .stay)
    }

    func testFirstMatchingRuleWins() {
        let a = rule(.appIs, "Safari", to: "/tmp/A")
        let b = rule(.textContains, "total", to: "/tmp/B")
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: "Total", rules: [a, b]), .move(a))
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: "Total", rules: [b, a]), .move(b))
    }

    func testTextRuleBeforeTheMatchNeedsTheText() {
        let text = rule(.textContains, "Invoice", to: "/tmp/Receipts")
        let app = rule(.appIs, "Safari", to: "/tmp/Web")
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: nil, rules: [text, app]), .needsText)
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: nil, rules: [app, text]), .move(app),
                       "an app rule that matches first decides without the text")
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: "", rules: [text, app]), .move(app),
                       "a recording has no text: text rules just don't match")
    }

    func testDisabledAndEmptyRulesAreSkipped() {
        let off = rule(.appIs, "Safari", to: "/tmp/Off", enabled: false)
        let empty = rule(.textContains, "  ", to: "/tmp/Empty")
        let noFolder = rule(.appIs, "Safari", to: "")
        let last = rule(.appIs, "Safari", to: "/tmp/Last")
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: nil, rules: [off, empty, noFolder, last]), .move(last),
                       "an empty text rule doesn't wait for the text either")
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: "x", rules: [off, empty, noFolder]), .stay)
        XCTAssertEqual(AutoFiling.decide(app: "", text: nil, rules: [rule(.appIs, "", to: "/tmp/X")]), .stay,
                       "an empty value matches no app, not even an unknown one")
        XCTAssertEqual(AutoFiling.decide(app: "Safari", text: "x", rules: []), .stay)
    }

    func testRulesRoundTripThroughDefaultsInOrder() {
        let name = "SkreenerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AutoFiling.load(from: defaults), [])
        let rules = [rule(.appIs, "Figma", to: "/tmp/Design"), rule(.textContains, "Invoice", to: "/tmp/R", enabled: false)]
        AutoFiling.save(rules, to: defaults)
        XCTAssertEqual(AutoFiling.load(from: defaults), rules)
        defaults.set(Data("not json".utf8), forKey: AutoFiling.defaultsKey)
        XCTAssertEqual(AutoFiling.load(from: defaults), [])
    }

    func testMovedFilesGetAFreeName() {
        let file = URL(fileURLWithPath: "/tmp/Shots/Skreener 2026-03-10.png")
        let folder = URL(fileURLWithPath: "/tmp/Receipts", isDirectory: true)
        var taken: Set<String> = []
        XCTAssertEqual(AutoFiling.destination(for: file, in: folder) { taken.contains($0.path) }.path,
                       "/tmp/Receipts/Skreener 2026-03-10.png")
        taken = ["/tmp/Receipts/Skreener 2026-03-10.png", "/tmp/Receipts/Skreener 2026-03-10 2.png"]
        XCTAssertEqual(AutoFiling.destination(for: file, in: folder) { taken.contains($0.path) }.path,
                       "/tmp/Receipts/Skreener 2026-03-10 3.png")
    }

    func testMoveCreatesTheFolderAndNeverReplacesAFile() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("Shot.png")
        try Data("new".utf8).write(to: file)
        let folder = base.appendingPathComponent("Receipts/2026", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: folder.appendingPathComponent("Shot.png"))

        let moved = try XCTUnwrap(AutoFiling.relocate(file, to: folder.path))
        XCTAssertEqual(moved.lastPathComponent, "Shot 2.png")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Shot.png")), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: moved), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let other = base.appendingPathComponent("Other.png")
        try Data().write(to: other)
        let fresh = base.appendingPathComponent("New Folder", isDirectory: true)
        XCTAssertEqual(try AutoFiling.relocate(other, to: fresh.path)?.lastPathComponent, "Other.png")
        XCTAssertNil(try AutoFiling.relocate(moved, to: folder.path), "already in the folder")
    }

    func testMovedFilesAreFollowed() {
        let a = URL(fileURLWithPath: "/tmp/SkreenerTests-\(UUID().uuidString)/a.png")
        let b = URL(fileURLWithPath: "/tmp/Receipts/a.png"), c = URL(fileURLWithPath: "/tmp/Receipts/2026/a.png")
        XCTAssertEqual(AutoFiling.current(a), a)
        AutoFiling.remember(a, movedTo: b)
        AutoFiling.remember(b, movedTo: c)
        XCTAssertEqual(AutoFiling.current(a), c, "a preview holding the old place finds the file")
    }

    func testCommentIsABinaryPlistString() throws {
        let data = try XCTUnwrap(AutoFiling.commentData("Total due"))
        XCTAssertTrue(data.starts(with: Array("bplist".utf8)))
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: data, format: nil) as? String, "Total due")
    }
}
