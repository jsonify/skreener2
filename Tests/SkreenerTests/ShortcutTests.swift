import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Skreener

final class ShortcutTests: XCTestCase {
    private let suite = "SkreenerTests.Shortcuts"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let ctrlShift = controlKey | shiftKey

    // MARK: Display

    func testDisplayStringOrdersModifiers() {
        let all = KeyCombo(keyCode: kVK_ANSI_A, modifiers: cmdKey | shiftKey | optionKey | controlKey)
        XCTAssertEqual(all.displayString, "⌃⌥⇧⌘A")
        XCTAssertEqual(KeyCombo(keyCode: kVK_ANSI_4, modifiers: ctrlShift).displayString, "⌃⇧4")
    }

    func testKeyNames() {
        XCTAssertEqual(KeyCombo(keyCode: kVK_F5, modifiers: 0).displayString, "F5")
        XCTAssertEqual(KeyCombo(keyCode: kVK_F20, modifiers: 0).displayString, "F20")
        XCTAssertEqual(KeyCombo(keyCode: kVK_Space, modifiers: optionKey).displayString, "⌥Space")
        XCTAssertEqual(KeyCombo(keyCode: kVK_LeftArrow, modifiers: cmdKey).displayString, "⌘←")
        XCTAssertEqual(KeyCombo(keyCode: kVK_ANSI_Slash, modifiers: cmdKey).displayString, "⌘/")
    }

    func testMenuKeyEquivalent() {
        let history = KeyCombo(keyCode: kVK_ANSI_H, modifiers: ctrlShift)
        XCTAssertEqual(history.keyEquivalent, "h")
        XCTAssertEqual(history.modifierFlags, [.control, .shift])
        XCTAssertEqual(KeyCombo(keyCode: kVK_F1, modifiers: 0).keyEquivalent, "\u{F704}")
        XCTAssertEqual(KeyCombo(keyCode: kVK_F12, modifiers: 0).keyEquivalent, "\u{F70F}")
    }

    func testEventFlagsIgnoreCapsLockAndFunction() {
        let combo = KeyCombo(keyCode: kVK_ANSI_4, flags: [.control, .shift, .capsLock, .function])
        XCTAssertEqual(combo.modifiers, ctrlShift)
        XCTAssertEqual(combo.modifierFlags, [.control, .shift])
    }

    // MARK: Storage

    func testStorageRoundTrip() {
        let combo = KeyCombo(keyCode: kVK_ANSI_8, modifiers: cmdKey | optionKey)
        XCTAssertEqual(KeyCombo(storageString: combo.storageString), combo)
    }

    func testMalformedStorageIsRejected() {
        for s in ["", "12", "a:b", "12:4608:1", "-1:256", "300:256", "21:1"] {
            XCTAssertNil(KeyCombo(storageString: s), s)
        }
    }

    func testDefaultsAreTheOriginalHotkeys() {
        let expected: [HotKeyAction: String] = [
            .captureArea: "⌃⇧4", .capturePreviousArea: "⌃⇧1", .captureAreaAndPin: "⌃⇧6", .captureFullscreen: "⌃⇧3",
            .captureWindow: "⌃⇧5", .captureScrolling: "⌃⇧8", .captureText: "⌃⇧2", .recordScreen: "⌃⇧7",
            .showHistory: "⌃⇧H", .allInOne: "⌃⇧9", .pinClickThrough: "⌃⇧0",
        ]
        for action in HotKeyAction.allCases {
            XCTAssertEqual(ShortcutStore.combo(for: action, in: defaults)?.displayString, expected[action], action.rawValue)
        }
    }

    func testDefaultsDoNotConflict() {
        let defaults = HotKeyAction.allCases.compactMap(\.defaultCombo)
        XCTAssertEqual(Set(defaults).count, defaults.count)
    }

    func testSetClearAndRestore() {
        let new = KeyCombo(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey)
        ShortcutStore.set(new, for: .captureArea, in: defaults)
        XCTAssertEqual(ShortcutStore.combo(for: .captureArea, in: defaults), new)

        ShortcutStore.set(nil, for: .captureArea, in: defaults)
        XCTAssertNil(ShortcutStore.combo(for: .captureArea, in: defaults))
        XCTAssertNil(ShortcutStore.bindings(in: defaults)[.captureArea])

        ShortcutStore.set(new, for: .timedArea, in: defaults)
        ShortcutStore.restoreDefaults(in: defaults)
        XCTAssertEqual(ShortcutStore.combo(for: .captureArea, in: defaults), HotKeyAction.captureArea.defaultCombo)
        XCTAssertNil(ShortcutStore.combo(for: .timedArea, in: defaults))
    }

    func testSettingTheDefaultRemovesTheEntry() {
        ShortcutStore.set(HotKeyAction.captureText.defaultCombo, for: .captureText, in: defaults)
        XCTAssertNil(defaults.object(forKey: "shortcut.captureText"))
    }

    // MARK: Conflicts

    func testNeedsModifier() {
        let bindings = ShortcutStore.bindings(in: defaults)
        XCTAssertEqual(ShortcutStore.problem(with: KeyCombo(keyCode: kVK_ANSI_A, modifiers: 0), for: .openFile, in: bindings),
                       .needsModifier)
        XCTAssertEqual(ShortcutStore.problem(with: KeyCombo(keyCode: kVK_ANSI_A, modifiers: shiftKey), for: .openFile,
                                             in: bindings), .needsModifier)
        XCTAssertNil(ShortcutStore.problem(with: KeyCombo(keyCode: kVK_F6, modifiers: 0), for: .openFile, in: bindings))
    }

    func testTakenByAnotherAction() {
        let bindings = ShortcutStore.bindings(in: defaults)
        let area = KeyCombo(keyCode: kVK_ANSI_4, modifiers: ctrlShift)
        XCTAssertEqual(ShortcutStore.problem(with: area, for: .captureWindow, in: bindings), .taken(by: .captureArea))
        // Re-recording an action's own shortcut is fine.
        XCTAssertNil(ShortcutStore.problem(with: area, for: .captureArea, in: bindings))
        // A cleared shortcut no longer blocks its combination.
        ShortcutStore.set(nil, for: .captureArea, in: defaults)
        XCTAssertNil(ShortcutStore.problem(with: area, for: .captureWindow, in: ShortcutStore.bindings(in: defaults)))
    }

    func testSystemWarnings() {
        XCTAssertNotNil(KeyCombo(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey).systemWarning)
        XCTAssertNotNil(KeyCombo(keyCode: kVK_ANSI_3, modifiers: cmdKey | shiftKey | controlKey).systemWarning)
        XCTAssertNotNil(KeyCombo(keyCode: kVK_Space, modifiers: cmdKey).systemWarning)
        XCTAssertNotNil(KeyCombo(keyCode: kVK_ANSI_K, modifiers: cmdKey).systemWarning) // plain ⌘ + key
        XCTAssertNil(KeyCombo(keyCode: kVK_ANSI_4, modifiers: ctrlShift).systemWarning)
        XCTAssertNil(KeyCombo(keyCode: kVK_ANSI_7, modifiers: cmdKey | shiftKey).systemWarning)
    }

    // MARK: macOS screenshot shortcuts (#114)

    private let shiftCmd3 = KeyCombo(keyCode: kVK_ANSI_3, modifiers: cmdKey | shiftKey)
    private let shiftCmd4 = KeyCombo(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey)

    /// An AppleSymbolicHotKeys entry as macOS writes it: [character, key code, modifier flags].
    private func entry(enabled: Bool, keyCode: Int, flags: Int) -> [String: Any] {
        let value: [String: Any] = ["parameters": [65535, keyCode, flags], "type": "standard"]
        return ["enabled": enabled, "value": value]
    }

    func testMacScreenshotShortcutsDefaultToOn() {
        XCTAssertTrue(MacScreenshotShortcuts.takesShiftCommand3Or4(in: nil))
        XCTAssertTrue(MacScreenshotShortcuts.takesShiftCommand3Or4(in: [:]))
        XCTAssertFalse(MacScreenshotShortcuts.isFree(shiftCmd4, in: nil))
    }

    func testMacScreenshotShortcutsTurnedOff() {
        let off: [String: Any] = ["28": entry(enabled: false, keyCode: kVK_ANSI_3, flags: 0x120000),
                                  "30": entry(enabled: false, keyCode: kVK_ANSI_4, flags: 0x120000)]
        XCTAssertFalse(MacScreenshotShortcuts.takesShiftCommand3Or4(in: off))
        XCTAssertTrue(MacScreenshotShortcuts.isFree(shiftCmd3, in: off))
        XCTAssertTrue(MacScreenshotShortcuts.isFree(shiftCmd4, in: off))
        // ⌃⇧⌘4 (31) is not in the list, so macOS still has it.
        XCTAssertFalse(MacScreenshotShortcuts.isFree(KeyCombo(keyCode: kVK_ANSI_4, modifiers: controlKey | shiftKey | cmdKey),
                                                     in: off))
    }

    func testMacScreenshotShortcutsOneStillOn() {
        let one: [String: Any] = ["28": entry(enabled: false, keyCode: kVK_ANSI_3, flags: 0x120000),
                                  "30": entry(enabled: true, keyCode: kVK_ANSI_4, flags: 0x120000)]
        XCTAssertTrue(MacScreenshotShortcuts.takesShiftCommand3Or4(in: one))
        XCTAssertTrue(MacScreenshotShortcuts.isFree(shiftCmd3, in: one))
        XCTAssertFalse(MacScreenshotShortcuts.isFree(shiftCmd4, in: one))
    }

    func testMacScreenshotShortcutMovedToOtherKeys() {
        // ⇧⌘4's job moved to ⌃⌥4: ⇧⌘4 is free.
        let moved: [String: Any] = ["30": entry(enabled: true, keyCode: kVK_ANSI_4, flags: 0xC0000)]
        XCTAssertTrue(MacScreenshotShortcuts.isFree(shiftCmd4, in: moved))
        XCTAssertFalse(MacScreenshotShortcuts.isFree(KeyCombo(keyCode: kVK_ANSI_K, modifiers: cmdKey), in: moved))
    }

    func testActiveWindowHasNoDefaultShortcut() {
        XCTAssertNil(HotKeyAction.captureActiveWindow.defaultCombo)
        XCTAssertEqual(HotKeyAction.captureActiveWindow.section, .screenshots)
    }
}
