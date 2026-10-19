import Carbon.HIToolbox
import AppKit

/// Global hotkeys via Carbon (works without accessibility permission).
final class HotKeys {
    static let shared = HotKeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var installed = false

    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installIfNeeded()
        let id = nextID; nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x534B524E), id: id) // 'SKRN'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
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
