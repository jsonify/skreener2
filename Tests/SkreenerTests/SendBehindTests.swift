import XCTest
@testable import Skreener

/// After a capture started from another app, Skreener's windows go back behind that app's front window, in their
/// own order.
final class SendBehindTests: XCTestCase {
    func testEachWindowGoesBelowTheOneBefore() {
        let order = SelectionOverlay.behindOrder([11, 12, 13], anchor: 99)
        XCTAssertEqual(order.map(\.window), [11, 12, 13])
        XCTAssertEqual(order.map(\.below), [99, 11, 12])
    }

    func testNothingToMove() {
        XCTAssertTrue(SelectionOverlay.behindOrder([], anchor: 99).isEmpty)
    }
}
