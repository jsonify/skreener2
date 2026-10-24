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

    func testSwipeTowardTheEdgeTheStackSitsOn() {
        XCTAssertEqual(QuickAccessGesture.classify(dx: -30, dy: 5, onRight: false), .swipe)
        XCTAssertEqual(QuickAccessGesture.classify(dx: 30, dy: -5, onRight: true), .swipe)
    }

    func testOtherDirectionsDragTheFileOut() {
        XCTAssertEqual(QuickAccessGesture.classify(dx: 30, dy: 5, onRight: false), .fileDrag)
        XCTAssertEqual(QuickAccessGesture.classify(dx: -30, dy: 5, onRight: true), .fileDrag)
        XCTAssertEqual(QuickAccessGesture.classify(dx: -10, dy: 40, onRight: false), .fileDrag)   // mostly vertical
    }

    func testSmallMovementIsStillAClick() {
        XCTAssertNil(QuickAccessGesture.classify(dx: 2, dy: -2, onRight: false))
    }

    func testDismissNeedsDistanceOrAFlick() {
        XCTAssertTrue(QuickAccessGesture.shouldDismiss(dx: -100, width: 220, velocity: 0, onRight: false))
        XCTAssertFalse(QuickAccessGesture.shouldDismiss(dx: -60, width: 220, velocity: 0, onRight: false))
        XCTAssertTrue(QuickAccessGesture.shouldDismiss(dx: -40, width: 220, velocity: -900, onRight: false))
        XCTAssertFalse(QuickAccessGesture.shouldDismiss(dx: -10, width: 220, velocity: -900, onRight: false))
        XCTAssertTrue(QuickAccessGesture.shouldDismiss(dx: 100, width: 220, velocity: 0, onRight: true))
        XCTAssertFalse(QuickAccessGesture.shouldDismiss(dx: -100, width: 220, velocity: 0, onRight: true))
    }
}
