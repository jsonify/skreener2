import XCTest
@testable import Skreener

/// The launcher at the top of the menu-bar menu: one tile per everyday capture mode.
final class MenuLauncherTests: XCTestCase {
    @MainActor func testTilesFillTheGrid() {
        XCTAssertEqual(MenuLauncher.tiles.count % MenuLauncher.columns, 0)
        XCTAssertEqual(MenuLauncher.tiles.count, 6)
    }

    @MainActor func testEachTileIsADifferentMode() {
        let actions = MenuLauncher.tiles.map(\.action)
        XCTAssertEqual(Set(actions).count, actions.count)
    }

    @MainActor func testTilesStartWithCaptureArea() {
        XCTAssertEqual(MenuLauncher.tiles.first?.action, .captureArea)
    }
}
