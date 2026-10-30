import XCTest
@testable import Skreener

final class AppearanceTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(AppAppearance.allCases.map(\.rawValue), ["system", "light", "dark"])
        for a in AppAppearance.allCases { XCTAssertEqual(AppAppearance(rawValue: a.rawValue), a) }
        XCTAssertNil(AppAppearance(rawValue: "sepia"))
    }

    func testDefaultIsLightAndRoundTrips() {
        let saved = UserDefaults.standard.object(forKey: "appearance")
        defer { UserDefaults.standard.set(saved, forKey: "appearance") }
        UserDefaults.standard.removeObject(forKey: "appearance")
        XCTAssertEqual(Preferences.appearance, .light)
        XCTAssertEqual(Preferences.appearance.nsAppearance?.name, .aqua)
        Preferences.appearance = .dark
        XCTAssertEqual(Preferences.appearance, .dark)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
        Preferences.appearance = .system
        XCTAssertEqual(Preferences.appearance, .system)
        XCTAssertNil(AppAppearance.system.nsAppearance)
    }
}
