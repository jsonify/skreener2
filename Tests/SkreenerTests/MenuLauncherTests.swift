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

    // MARK: Small keys (#371)

    @MainActor func testCompactIsTheEverydayTray() {
        let groups = MenuLauncher.keyGroups(for: .compact)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].keys.map(\.command), [.showHistory, .openClipboard, .pinClipboard, .settings, .quit])
        XCTAssertNil(groups[0].title)
    }

    @MainActor func testExpandedAddsCaptionedTraysOverTheEverydayOne() {
        let groups = MenuLauncher.keyGroups(for: .expanded)
        XCTAssertEqual(groups.last?.keys.map(\.command), MenuLauncher.everyday.keys.map(\.command))
        XCTAssertEqual(groups.dropLast().map(\.title), ["Open & Pin", "Tools", "Help"])
        let commands = groups.flatMap(\.keys).map(\.command)
        XCTAssertEqual(Set(commands).count, commands.count, "no key twice")
        for c: MenuCommand in [.openFile, .pinFile, .pinClickThrough, .fromDevice, .stepGuide, .watchArea, .stepRecorder,
                               .presenter, .keyboardShortcuts, .welcomeGuide, .whatsNew, .checkForUpdates, .about] {
            XCTAssertTrue(commands.contains(c), "\(c)")
        }
        XCTAssertFalse(commands.contains(.showUpdate), "the LCD shows the update, not a key")
    }

    @MainActor func testTraysFitTheirWidth() {
        for mode in MenuBarMode.allCases {
            for group in MenuLauncher.keyGroups(for: mode, active: [.watchArea, .stepRecorder]) {
                XCTAssertFalse(group.keys.isEmpty)
                XCTAssertLessThanOrEqual(group.keys.count, MenuLauncher.maxKeysPerTray)
            }
        }
    }

    @MainActor func testCompactShowsARunningWatchSoItCanBeStopped() {
        let groups = MenuLauncher.keyGroups(for: .compact, active: [.watchArea])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Running")
        XCTAssertEqual(groups[0].keys.map(\.command), [.watchArea])
        XCTAssertEqual(groups[0].keys[0].active?.name, "Stop Watching")
        // Expanded has the key anyway.
        XCTAssertEqual(MenuLauncher.keyGroups(for: .expanded, active: [.watchArea]).count, 4)
    }

    func testMenuShortcutsAreTheMenusOwn() {
        XCTAssertEqual(MenuCommand.quit.menuShortcut, "⌘Q")
        XCTAssertEqual(MenuCommand.settings.menuShortcut, "⌘,")
        XCTAssertEqual(MenuCommand.showHistory.hotKey, .showHistory)
        XCTAssertNil(MenuCommand.about.hotKey)
    }

    // MARK: The LCD at rest (#371)

    func testRestingLCDBeforeAnyCheckShowsTheVersion() {
        let r = MenuLauncher.resting(version: "1.11.2", status: .unknown)
        XCTAssertEqual(r, .init(left: "Skreener", right: "v1.11.2", update: false))
    }

    func testRestingLCDUpToDate() {
        XCTAssertEqual(MenuLauncher.resting(version: "1.11.2", status: .upToDate).right, "v1.11.2 · UP TO DATE")
        XCTAssertFalse(MenuLauncher.resting(version: "1.11.2", status: .upToDate).update)
    }

    func testRestingLCDOffersTheUpdate() {
        let r = MenuLauncher.resting(version: "1.11.2", status: .available(version: "1.12.0"))
        XCTAssertEqual(r.right, "UPDATE 1.12.0")
        XCTAssertTrue(r.update)
    }

    func testRestingLCDForADevBuild() {
        XCTAssertEqual(MenuLauncher.resting(version: "dev", status: .unknown).right, "DEV")
    }

    // MARK: Settings → Menu Bar

    func testMenuBarModeDefaultsToCompactAndRoundTrips() {
        let saved = UserDefaults.standard.object(forKey: "menuBarMode")
        defer { UserDefaults.standard.set(saved, forKey: "menuBarMode") }
        UserDefaults.standard.removeObject(forKey: "menuBarMode")
        XCTAssertEqual(Preferences.menuBarMode, .compact)
        Preferences.menuBarMode = .expanded
        XCTAssertEqual(Preferences.menuBarMode, .expanded)
        UserDefaults.standard.set("huge", forKey: "menuBarMode")
        XCTAssertEqual(Preferences.menuBarMode, .compact)
        XCTAssertEqual(MenuBarMode.allCases.map(\.rawValue), ["compact", "expanded"])
    }
}
