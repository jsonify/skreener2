import XCTest
@testable import Skreener

/// The version line in About and the menu, from the Info.plist build_app.sh writes (#135).
final class VersionTests: XCTestCase {
    func testVersionBuildAndCommit() {
        let info = ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "412", "SkreenerCommit": "48db438"]
        XCTAssertEqual(SettingsWindowController.versionLine(info), "0.2.0 (412, 48db438)")
    }

    func testOlderBundleWithoutCommit() {
        XCTAssertEqual(SettingsWindowController.versionLine(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "48db438"]),
                       "0.1.0 (48db438)")
    }

    func testNoInfoPlist() {
        XCTAssertEqual(SettingsWindowController.versionLine(nil), "dev")
    }
}
