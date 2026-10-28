import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, the way Carbon's hotkey API takes them: a virtual key code (`kVK_…`, independent of the
/// keyboard layout) and a mask of `controlKey` / `optionKey` / `shiftKey` / `cmdKey`.
struct KeyCombo: Hashable {
    let keyCode: Int
    let modifiers: Int

    static let modifierMask = controlKey | optionKey | shiftKey | cmdKey

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    /// From a key event; flags other than ⌃ ⌥ ⇧ ⌘ (Caps Lock, fn, keypad) are ignored.
    init(keyCode: Int, flags: NSEvent.ModifierFlags) {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        self.init(keyCode: keyCode, modifiers: m)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if (modifiers & controlKey) != 0 { f.insert(.control) }
        if (modifiers & optionKey) != 0 { f.insert(.option) }
        if (modifiers & shiftKey) != 0 { f.insert(.shift) }
        if (modifiers & cmdKey) != 0 { f.insert(.command) }
        return f
    }

    /// "⌃⇧4": the modifiers in the standard order (⌃ ⌥ ⇧ ⌘), then the key.
    var displayString: String { Self.symbols(for: modifiers) + keyName }

    static func symbols(for modifiers: Int) -> String {
        var s = ""
        if (modifiers & controlKey) != 0 { s += "⌃" }
        if (modifiers & optionKey) != 0 { s += "⌥" }
        if (modifiers & shiftKey) != 0 { s += "⇧" }
        if (modifiers & cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// The key's name on a US keyboard ("4", "H", "F5", "Space", "←").
    var keyName: String { Self.keys[keyCode]?.name ?? "Key \(keyCode)" }

    /// `NSMenuItem.keyEquivalent` for the key (nil for keys a menu can't show).
    var keyEquivalent: String? { Self.keys[keyCode]?.equivalent }

    var isFunctionKey: Bool { Self.functionKeys.contains(keyCode) }

    /// Global shortcuts need ⌘, ⌃ or ⌥ (Shift alone would swallow typed capitals); F-keys may stand alone.
    var hasRequiredModifier: Bool { (modifiers & (cmdKey | optionKey | controlKey)) != 0 || isFunctionKey }

    /// Why this combination may not work, or may get in the way, when it is one macOS or most apps already use.
    var systemWarning: String? {
        if let use = Self.systemShortcuts[self] { return "macOS uses \(displayString) \(use)" }
        if modifiers == cmdKey {
            return "Apps use ⌘ + a key for their own commands; Skreener would take \(displayString) over in every app."
        }
        return nil
    }

    // MARK: Storage

    /// "21:4608": key code and Carbon modifier mask, for UserDefaults.
    var storageString: String { "\(keyCode):\(modifiers)" }

    init?(storageString: String) {
        let parts = storageString.split(separator: ":")
        guard parts.count == 2, let key = Int(parts[0]), let mods = Int(parts[1]),
              (0...0xFF).contains(key), (mods & ~Self.modifierMask) == 0 else { return nil }
        self.init(keyCode: key, modifiers: mods)
    }

    // MARK: Key tables

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// Display name and menu key equivalent per key code. Function-key equivalents are AppKit's private-use
    /// characters (`NSF1FunctionKey` = U+F704, `NSUpArrowFunctionKey` = U+F700, …).
    private static let keys: [Int: (name: String, equivalent: String)] = {
        var k: [Int: (name: String, equivalent: String)] = [:]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                       kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                       kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                       kVK_ANSI_Y, kVK_ANSI_Z]
        for (code, letter) in zip(letters, "abcdefghijklmnopqrstuvwxyz") {
            k[code] = (String(letter).uppercased(), String(letter))
        }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                      kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (digit, code) in digits.enumerated() { k[code] = ("\(digit)", "\(digit)") }
        let punctuation: [(Int, String)] = [
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
        ]
        for (code, char) in punctuation { k[code] = (char, char) }
        let special: [(Int, String, String)] = [
            (kVK_Return, "↩", "\r"), (kVK_Tab, "⇥", "\t"), (kVK_Space, "Space", " "), (kVK_Delete, "⌫", "\u{8}"),
            (kVK_Escape, "⎋", "\u{1b}"), (kVK_ForwardDelete, "⌦", "\u{F728}"), (kVK_Home, "↖", "\u{F729}"),
            (kVK_End, "↘", "\u{F72B}"), (kVK_PageUp, "⇞", "\u{F72C}"), (kVK_PageDown, "⇟", "\u{F72D}"),
            (kVK_UpArrow, "↑", "\u{F700}"), (kVK_DownArrow, "↓", "\u{F701}"),
            (kVK_LeftArrow, "←", "\u{F702}"), (kVK_RightArrow, "→", "\u{F703}"),
        ]
        for (code, name, equivalent) in special { k[code] = (name, equivalent) }
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fKeys.enumerated() {
            let scalar = Unicode.Scalar(UInt32(0xF704 + i)).map { String(Character($0)) } ?? ""
            k[code] = ("F\(i + 1)", scalar)
        }
        return k
    }()

    /// Shortcuts macOS itself uses (default System Settings → Keyboard Shortcuts), with what for.
    private static let systemShortcuts: [KeyCombo: String] = {
        var r: [KeyCombo: String] = [:]
        let screenshots = "for screenshots. Turn it off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, "
            + "or macOS gets it first."
        for key in [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6] {
            r[KeyCombo(keyCode: key, modifiers: cmdKey | shiftKey)] = screenshots
        }
        for key in [kVK_ANSI_3, kVK_ANSI_4] {
            r[KeyCombo(keyCode: key, modifiers: controlKey | cmdKey | shiftKey)] = screenshots
        }
        r[KeyCombo(keyCode: kVK_Space, modifiers: cmdKey)] = "for Spotlight."
        r[KeyCombo(keyCode: kVK_Space, modifiers: optionKey | cmdKey)] = "to search in Finder."
        r[KeyCombo(keyCode: kVK_Space, modifiers: controlKey)] = "to switch input sources."
        r[KeyCombo(keyCode: kVK_Space, modifiers: controlKey | optionKey)] = "to switch input sources."
        r[KeyCombo(keyCode: kVK_Tab, modifiers: cmdKey)] = "to switch apps."
        r[KeyCombo(keyCode: kVK_Tab, modifiers: cmdKey | shiftKey)] = "to switch apps."
        r[KeyCombo(keyCode: kVK_ANSI_Grave, modifiers: cmdKey)] = "to switch windows."
        r[KeyCombo(keyCode: kVK_UpArrow, modifiers: controlKey)] = "for Mission Control."
        r[KeyCombo(keyCode: kVK_DownArrow, modifiers: controlKey)] = "for App Exposé."
        r[KeyCombo(keyCode: kVK_LeftArrow, modifiers: controlKey)] = "to switch Spaces."
        r[KeyCombo(keyCode: kVK_RightArrow, modifiers: controlKey)] = "to switch Spaces."
        r[KeyCombo(keyCode: kVK_ANSI_Q, modifiers: controlKey | cmdKey)] = "to lock the screen."
        r[KeyCombo(keyCode: kVK_ANSI_Q, modifiers: shiftKey | cmdKey)] = "to log out."
        r[KeyCombo(keyCode: kVK_ANSI_D, modifiers: optionKey | cmdKey)] = "to show or hide the Dock."
        return r
    }()
}

/// Everything that can have a global shortcut, in Settings → Shortcuts order.
enum HotKeyAction: String, CaseIterable {
    case captureArea, allInOne, capturePreviousArea, captureAreaAndPin, captureFullscreen, captureWindow, captureActiveWindow,
         captureScrolling, captureText, captureCode, scanQRCode, timedArea, timedWindow, timedFullscreen
    case recordScreen, presenter, spotlight
    case showHistory, toggleDesktopIcons, openFile, openClipboard, pinFile, pinClipboard, pinClickThrough

    /// The groups of Settings → Shortcuts.
    enum Section: CaseIterable {
        case screenshots, recording, other

        var title: String {
            switch self {
            case .screenshots: return "Screenshots"
            case .recording: return "Screen Recording"
            case .other: return "Other"
            }
        }
    }

    var section: Section {
        switch self {
        case .captureArea, .allInOne, .capturePreviousArea, .captureAreaAndPin, .captureFullscreen, .captureWindow,
             .captureActiveWindow, .captureScrolling, .captureText, .captureCode, .scanQRCode, .timedArea, .timedWindow, .timedFullscreen: return .screenshots
        case .recordScreen, .presenter, .spotlight: return .recording
        case .showHistory, .toggleDesktopIcons, .openFile, .openClipboard, .pinFile, .pinClipboard, .pinClickThrough: return .other
        }
    }

    var title: String {
        switch self {
        case .captureArea: return "Capture Area"
        case .allInOne: return "All-in-One"
        case .capturePreviousArea: return "Capture Previous Area"
        case .captureAreaAndPin: return "Capture Area & Pin"
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureWindow: return "Capture Window"
        case .captureActiveWindow: return "Capture Active Window"
        case .captureScrolling: return "Capture Scrolling"
        case .captureText: return "Capture Text (OCR)"
        case .captureCode: return "Capture Code (OCR)"
        case .scanQRCode: return "Scan QR Code"
        case .timedArea: return "Self-Timer: Area"
        case .timedWindow: return "Self-Timer: Window"
        case .timedFullscreen: return "Self-Timer: Fullscreen"
        case .recordScreen: return "Record Screen"
        case .presenter: return "Zoom & Draw on Screen"
        case .spotlight: return "Cursor Spotlight"
        case .showHistory: return "Capture History"
        case .toggleDesktopIcons: return "Show / Hide Desktop Icons"
        case .openFile: return "Open…"
        case .openClipboard: return "Open from Clipboard"
        case .pinFile: return "Pin to the Screen…"
        case .pinClipboard: return "Pin from Clipboard"
        case .pinClickThrough: return "Pin Click-Through On / Off"
        }
    }

    var subtitle: String? {
        switch self {
        case .allInOne: return "Select an area, then choose what to do with it."
        case .captureActiveWindow: return "The frontmost window, without picking it."
        case .scanQRCode: return "Select an area; the code's content is copied, and a link can be opened."
        case .captureScrolling: return "Press again to finish."
        case .captureCode: return "Copies text from a screen or video with its indentation kept."
        case .recordScreen: return "Press again to stop recording."
        case .presenter: return "Press again, or Esc twice, to leave."
        case .spotlight: return "While recording: dims all but a circle around the pointer. Press again to turn off."
        case .showHistory: return "Opens and closes the history panel."
        case .pinClickThrough: return "Off on every pin, or on for the pin under the pointer."
        default: return nil
        }
    }

    /// The shortcuts Skreener has always had (⌃⇧ + a key), plus ⌃⇧0 for pin click-through, since a click-through pin
    /// takes no clicks or keys of its own, ⌃⇧Z for presenter mode, used mid-call, and ⌃⇧S for the recording spotlight; the rest start without one.
    var defaultCombo: KeyCombo? {
        let mods = controlKey | shiftKey
        switch self {
        case .captureArea: return KeyCombo(keyCode: kVK_ANSI_4, modifiers: mods)
        case .capturePreviousArea: return KeyCombo(keyCode: kVK_ANSI_1, modifiers: mods)
        case .captureAreaAndPin: return KeyCombo(keyCode: kVK_ANSI_6, modifiers: mods)
        case .captureFullscreen: return KeyCombo(keyCode: kVK_ANSI_3, modifiers: mods)
        case .captureWindow: return KeyCombo(keyCode: kVK_ANSI_5, modifiers: mods)
        case .captureScrolling: return KeyCombo(keyCode: kVK_ANSI_8, modifiers: mods)
        case .captureText: return KeyCombo(keyCode: kVK_ANSI_2, modifiers: mods)
        case .recordScreen: return KeyCombo(keyCode: kVK_ANSI_7, modifiers: mods)
        case .allInOne: return KeyCombo(keyCode: kVK_ANSI_9, modifiers: mods)
        case .showHistory: return KeyCombo(keyCode: kVK_ANSI_H, modifiers: mods)
        case .pinClickThrough: return KeyCombo(keyCode: kVK_ANSI_0, modifiers: mods)
        case .presenter: return KeyCombo(keyCode: kVK_ANSI_Z, modifiers: mods)
        case .spotlight: return KeyCombo(keyCode: kVK_ANSI_S, modifiers: mods)
        case .captureActiveWindow, .captureCode, .scanQRCode, .timedArea, .timedWindow, .timedFullscreen, .toggleDesktopIcons, .openFile,
             .openClipboard, .pinFile, .pinClipboard: return nil
        }
    }
}

/// Why a recorded shortcut was refused.
enum ShortcutProblem: Equatable {
    case needsModifier
    case taken(by: HotKeyAction)

    func message(for combo: KeyCombo) -> String {
        switch self {
        case .needsModifier: return "Use ⌘, ⌃ or ⌥ with the key (F-keys work on their own)."
        case .taken(let other): return "\(combo.displayString) is already used by \(other.title)."
        }
    }
}

/// The user's shortcuts in UserDefaults ("shortcut.<action>"): no entry means the default, an empty string means
/// cleared, otherwise `KeyCombo.storageString`.
enum ShortcutStore {
    private static func key(_ action: HotKeyAction) -> String { "shortcut." + action.rawValue }

    static func combo(for action: HotKeyAction, in defaults: UserDefaults = .standard) -> KeyCombo? {
        guard let stored = defaults.string(forKey: key(action)) else { return action.defaultCombo }
        if stored.isEmpty { return nil }
        return KeyCombo(storageString: stored) ?? action.defaultCombo
    }

    /// nil clears the shortcut. Setting the default removes the entry, so a later change of default applies.
    static func set(_ combo: KeyCombo?, for action: HotKeyAction, in defaults: UserDefaults = .standard) {
        if combo == action.defaultCombo {
            defaults.removeObject(forKey: key(action))
        } else {
            defaults.set(combo?.storageString ?? "", forKey: key(action))
        }
    }

    static func restoreDefaults(in defaults: UserDefaults = .standard) {
        for action in HotKeyAction.allCases { defaults.removeObject(forKey: key(action)) }
    }

    /// Every action that has a shortcut.
    static func bindings(in defaults: UserDefaults = .standard) -> [HotKeyAction: KeyCombo] {
        var r: [HotKeyAction: KeyCombo] = [:]
        for action in HotKeyAction.allCases {
            if let c = combo(for: action, in: defaults) { r[action] = c }
        }
        return r
    }

    /// Whether `combo` can be given to `action`: it needs a modifier and must not belong to another action.
    static func problem(with combo: KeyCombo, for action: HotKeyAction,
                        in bindings: [HotKeyAction: KeyCombo]) -> ShortcutProblem? {
        guard combo.hasRequiredModifier else { return .needsModifier }
        if let other = HotKeyAction.allCases.first(where: { $0 != action && bindings[$0] == combo }) {
            return .taken(by: other)
        }
        return nil
    }
}

/// macOS's own screenshot shortcuts (System Settings → Keyboard → Keyboard Shortcuts → Screenshots), read from its
/// symbolic hotkeys, so Settings → Shortcuts can tell whether ⇧⌘3 / ⇧⌘4 are free for Skreener (#114). Read only.
enum MacScreenshotShortcuts {
    /// Symbolic hotkey ids and their default combinations: save the screen (28) or an area (30) as a file, copy them
    /// (29, 31), and the screenshot toolbar (184).
    static let defaults: [Int: KeyCombo] = [
        28: KeyCombo(keyCode: kVK_ANSI_3, modifiers: shiftKey | cmdKey),
        29: KeyCombo(keyCode: kVK_ANSI_3, modifiers: controlKey | shiftKey | cmdKey),
        30: KeyCombo(keyCode: kVK_ANSI_4, modifiers: shiftKey | cmdKey),
        31: KeyCombo(keyCode: kVK_ANSI_4, modifiers: controlKey | shiftKey | cmdKey),
        184: KeyCombo(keyCode: kVK_ANSI_5, modifiers: shiftKey | cmdKey),
    ]

    /// `AppleSymbolicHotKeys` from com.apple.symbolichotkeys, read fresh (System Settings may have just changed it).
    static func current() -> [String: Any]? {
        let domain = "com.apple.symbolichotkeys" as CFString
        _ = CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
    }

    /// Whether macOS still answers to shortcut `id` with its default combination. An id missing from `hotkeys` has
    /// its default: on. One that is turned off, or set to other keys, leaves the default combination free.
    static func isOn(_ id: Int, in hotkeys: [String: Any]?) -> Bool {
        guard let entry = hotkeys?[String(id)] as? [String: Any] else { return true }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return false }
        if let combo = defaults[id], let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber],
           params.count >= 3 {
            // [character, key code, modifier flags]
            return params[1].intValue == combo.keyCode && params[2].intValue == Int(combo.modifierFlags.rawValue)
        }
        return true
    }

    /// Whether either of ⇧⌘3 and ⇧⌘4 still belongs to macOS.
    static func takesShiftCommand3Or4(in hotkeys: [String: Any]?) -> Bool { isOn(28, in: hotkeys) || isOn(30, in: hotkeys) }

    /// True when `combo` is one of these shortcuts and macOS no longer uses it, so its warning can go.
    static func isFree(_ combo: KeyCombo, in hotkeys: [String: Any]?) -> Bool {
        guard let id = defaults.first(where: { $0.value == combo })?.key else { return false }
        return !isOn(id, in: hotkeys)
    }
}
