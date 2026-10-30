import XCTest
@testable import Skreener

final class EditorDisplayTests: XCTestCase {
    func testEveryToolHasUsage() {
        for tool in Tool.allCases { XCTAssertFalse(tool.usage.isEmpty, "\(tool)") }
    }

    func testUsageAddsModifierTipAndVariants() {
        XCTAssertEqual(Tool.pen.usage, "Drag to draw freehand · ⇧ for a straight line")
        XCTAssertTrue(Tool.rect.usage.hasSuffix("press and hold its button for variants"))
        XCTAssertEqual(Tool.text.usage, "Click to place text, then type")
    }

    func testKeyLabel() {
        XCTAssertEqual(Tool.rect.keyLabel, "KEY R")
        XCTAssertEqual(Tool.select.keyLabel, "KEY V")
    }
}
