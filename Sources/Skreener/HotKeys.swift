import Carbon.HIToolbox
import AppKit

/// Global hotkeys via Carbon (works without accessibility permission).
final class HotKeys {
    static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    /// Returns an id for `unregister`, or nil if macOS refused the combination (e.g. another app registered it).
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> UInt32? {
        installIfNeeded()
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x534B524E), id: id) // 'SKRN'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == OSStatus(noErr), let ref else { return nil }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    /// Releases a hotkey, e.g. the temporary Esc used to cancel the self-timer.
    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { HotKeys.shared.handlers[hkID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Skreener's rebindable global shortcuts (`HotKeyAction`): registers each action's current shortcut from
/// `ShortcutStore`, again whenever one changes, so a new shortcut works straight away.
@MainActor final class ShortcutCenter {
    static let shared = ShortcutCenter()

    /// What each action does (set up by the app delegate).
    var handlers: [HotKeyAction: () -> Void] = [:]
    /// Called after a shortcut changed, e.g. to update the menu's key equivalents.
    var onChange: (() -> Void)?
    /// Actions whose shortcut macOS refused to register (another app may be using it).
    private(set) var unavailable: Set<HotKeyAction> = []
    /// While a shortcut recorder is listening, nothing is registered: a registered combination never reaches the
    /// app as a key press, so it could not be recorded (or re-recorded) otherwise.
    var suspended = false {
        didSet { if suspended != oldValue { register() } }
    }
    private var ids: [HotKeyAction: UInt32] = [:]

    private init() {}

    /// (Re-)registers every action's current shortcut.
    func register() {
        for id in ids.values { HotKeys.shared.unregister(id) }
        ids = [:]
        unavailable = []
        guard !suspended else { return }
        for (action, combo) in ShortcutStore.bindings() {
            guard let handler = handlers[action] else { continue }
            if let id = HotKeys.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers, handler: handler) {
                ids[action] = id
            } else {
                unavailable.insert(action)
            }
        }
    }

    /// nil clears the action's shortcut.
    func set(_ combo: KeyCombo?, for action: HotKeyAction) {
        ShortcutStore.set(combo, for: action)
        changed()
    }

    func restoreDefaults() {
        ShortcutStore.restoreDefaults()
        changed()
    }

    private func changed() {
        register()
        onChange?()
    }
}
