import XCTest
@testable import Skreener

/// Starting a capture must not bring an editor left behind another app to the front, over what is being captured.
final class SelectionActivationTests: XCTestCase {
    private typealias W = OverlayWindowState
    private let editor = W(isVisible: true, isNormalLevel: true, isPanel: false)
    private let pin = W(isVisible: true, isNormalLevel: false, isPanel: true)
    private let statusItem = W(isVisible: true, isNormalLevel: false, isPanel: false)

    func testAnEditorBehindAnotherAppStaysBehind() {
        XCTAssertTrue(SelectionOverlay.activationRaisesWindows(isActive: false, windows: [statusItem, editor]))
    }

    func testActivatesWhenNothingWouldComeForward() {
        XCTAssertFalse(SelectionOverlay.activationRaisesWindows(isActive: false, windows: [statusItem, pin]))
        XCTAssertFalse(SelectionOverlay.activationRaisesWindows(
            isActive: false, windows: [W(isVisible: false, isNormalLevel: true, isPanel: false)]))   // closed or minimized
    }

    func testAlreadyActiveIsLeftAlone() {
        XCTAssertFalse(SelectionOverlay.activationRaisesWindows(isActive: true, windows: [editor]))
    }
}
