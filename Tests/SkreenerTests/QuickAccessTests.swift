import XCTest
@testable import Skreener

/// Quick Access position (#32): the corner the previews stack up from.
final class QuickAccessTests: XCTestCase {
    @MainActor func testBottomLeftAndBottomRight() {
        let frame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(QuickAccessController.x(width: 220, in: frame, onRight: false), 16)
        XCTAssertEqual(QuickAccessController.x(width: 220, in: frame, onRight: true), 1440 - 16 - 220)
    }

    @MainActor func testSecondScreenToTheLeft() {
        let frame = NSRect(x: -1920, y: 0, width: 1920, height: 1055)
        XCTAssertEqual(QuickAccessController.x(width: 220, in: frame, onRight: false), -1920 + 16)
        XCTAssertEqual(QuickAccessController.x(width: 220, in: frame, onRight: true), -16 - 220)
    }
}
