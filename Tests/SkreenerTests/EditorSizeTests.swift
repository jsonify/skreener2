import AppKit
import XCTest
@testable import Skreener

final class EditorSizeTests: XCTestCase {
    @MainActor func testEditorOpensAtLeastTheDefaultWidth() {
        let big = NSSize(width: 2560, height: 1400)
        XCTAssertEqual(EditorWindowController.size(for: NSSize(width: 400, height: 300), visible: big).width, 1200)
        XCTAssertEqual(EditorWindowController.size(for: NSSize(width: 1600, height: 300), visible: big).width, 1720)
        // A small screen: no wider than it, but never below the minimum.
        XCTAssertEqual(EditorWindowController.size(for: NSSize(width: 400, height: 300), visible: NSSize(width: 1100, height: 800)).width, 1100)
        XCTAssertEqual(EditorWindowController.size(for: NSSize(width: 400, height: 300), visible: NSSize(width: 900, height: 800)).width,
                       EditorWindowController.minimumSize.width)
    }
}
