import Carbon.HIToolbox
import XCTest
@testable import Skreener

final class ShortcutCatalogTests: XCTestCase {
    func testEveryToolShortcutIsListedByName() {
        let entries = ShortcutCatalog.toolSection().entries
        XCTAssertEqual(entries.count, Tool.shortcuts.count)
        for (key, tool) in Tool.shortcuts {
            let entry = entries.first { $0.title == tool.name }
            XCTAssertEqual(entry?.keys, [String(key).uppercased()], tool.name)
        }
    }

    @MainActor func testGlobalShortcutsFollowTheUsersSettings() {
        let custom = KeyCombo(keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey)
        let sections = ShortcutCatalog.sections(bindings: [.captureFullscreen: custom])
        let global = sections.first { $0.title == "Global: Screenshots" }
        XCTAssertEqual(global?.entries, [ShortcutEntry("Capture Fullscreen", keys: ["⌃", "⌥", "K"])])
        XCTAssertNil(sections.first { $0.title == "Global: Screen Recording" }, "a group without shortcuts is left out")
    }

    func testKeysSplitModifiersIntoCaps() {
        XCTAssertEqual(ShortcutCatalog.keys(for: KeyCombo(keyCode: kVK_ANSI_4, modifiers: controlKey | shiftKey)), ["⌃", "⇧", "4"])
        XCTAssertEqual(ShortcutCatalog.keys(for: KeyCombo(keyCode: kVK_Space, modifiers: optionKey)), ["⌥", "Space"])
        XCTAssertEqual(ShortcutCatalog.keys(for: KeyCombo(keyCode: kVK_F5, modifiers: 0)), ["F5"])
    }

    @MainActor func testEditorCommandsIncludeArrangeAndMeasure() {
        let titles = ShortcutCatalog.editorCommands().entries.map(\.title)
        XCTAssertTrue(titles.contains("Bring to Front"))
        XCTAssertTrue(titles.contains("Measure Across"))
        XCTAssertTrue(titles.contains("Crop"))
        let front = ShortcutCatalog.editorCommands().entries.first { $0.title == "Bring to Front" }
        XCTAssertEqual(front?.keys, ["⌥", "⌘", "]"])
    }

    func testSearchByToolName() {
        let found = ShortcutCatalog.filter([ShortcutCatalog.toolSection()], matching: "blur")
        XCTAssertEqual(found.first?.entries.map(\.title), ["Blur"])
    }

    @MainActor func testSearchByModifierName() {
        let sections = ShortcutCatalog.sections(bindings: [:])
        let found = ShortcutCatalog.filter(sections, matching: "shift")
        let area = found.first { $0.title == "Selecting an Area" }
        XCTAssertTrue(area?.entries.contains { $0.title == "Square Selection" } ?? false)
        XCTAssertFalse(area?.entries.contains { $0.title == "Cancel" } ?? true)
    }

    func testSearchNeedsEveryWordAndIgnoresCase() {
        let sections = [ShortcutCatalog.areaSelection()]
        XCTAssertEqual(ShortcutCatalog.filter(sections, matching: "  SQUARE shift ").first?.entries.map(\.title), ["Square Selection"])
        XCTAssertTrue(ShortcutCatalog.filter(sections, matching: "square option").isEmpty)
    }

    func testBlankQueryKeepsEverything() {
        let sections = [ShortcutCatalog.toolSection()]
        XCTAssertEqual(ShortcutCatalog.filter(sections, matching: "   "), sections)
    }

    func testSearchFindsKeysByName() {
        let sections = [ShortcutCatalog.areaSelection()]
        XCTAssertEqual(ShortcutCatalog.filter(sections, matching: "escape").first?.entries.map(\.title), ["Cancel"])
        XCTAssertEqual(ShortcutCatalog.filter(sections, matching: "return").first?.entries.map(\.title), ["Capture"])
    }

    func testColumnsKeepOrderAndBalance() {
        let sections = (1...4).map { ShortcutSection(title: "S\($0)", entries: Array(repeating: ShortcutEntry("x", keys: ["X"]), count: 5)) }
        let (left, right) = ShortcutCatalog.columns(sections)
        XCTAssertEqual(left.map(\.title), ["S1", "S2"])
        XCTAssertEqual(right.map(\.title), ["S3", "S4"])
        XCTAssertEqual(ShortcutCatalog.columns([sections[0]]).right.count, 0)
    }

    func testTooltips() {
        XCTAssertEqual(Tool.arrow.tooltip(), "Arrow (A)")
        XCTAssertEqual(Tool.pen.tooltip(), "Pen (P) · ⇧ for a straight line")
        XCTAssertEqual(Tool.blur.tooltip(), "Blur (B) · ⌘ skips snapping")
        XCTAssertEqual(Tool.rect.tooltip(variants: true), "Rectangle (R) · hold for variants")
        XCTAssertTrue(Tool.redactText.tooltip().hasPrefix("Redact Text"))
    }
}
