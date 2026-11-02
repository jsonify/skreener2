import XCTest
@testable import Skreener

/// Closing a capture panel with Skreener in the background must not let an editor take key (and come forward).
@MainActor final class CapturePanelHandOffTests: XCTestCase {
    func testHeldWhileClosingInTheBackgroundUntilTheNextTurn() async {
        var heldInside = false
        CapturePanelHandOff.closing(isActive: false) { heldInside = CapturePanelHandOff.isHeld }
        XCTAssertTrue(heldInside)
        XCTAssertTrue(CapturePanelHandOff.isHeld, "still held for AppKit's hand-off")
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        XCTAssertFalse(CapturePanelHandOff.isHeld)
    }

    func testNotHeldWhenSkreenerIsActive() {
        var heldInside = true
        CapturePanelHandOff.closing(isActive: true) { heldInside = CapturePanelHandOff.isHeld }
        XCTAssertFalse(heldInside)
        XCTAssertFalse(CapturePanelHandOff.isHeld)
    }
}
