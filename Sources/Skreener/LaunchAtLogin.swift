import AppKit
import ServiceManagement

/// Open Skreener when the user logs in (System Settings → General → Login Items).
enum LaunchAtLogin {
    /// On, or registered but waiting for the user to allow it in System Settings.
    static var isOn: Bool { [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) }

    /// Registers or unregisters the app; explains in an alert when macOS refuses or wants approval first.
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let a = NSAlert()
            a.messageText = on ? "Couldn't turn on Launch at Login" : "Couldn't turn off Launch at Login"
            a.informativeText = error.localizedDescription
            a.runModal()
            return
        }
        guard on, SMAppService.mainApp.status == .requiresApproval else { return }
        let a = NSAlert()
        a.messageText = "Allow Skreener in Login Items"
        a.informativeText = "macOS needs your approval before Skreener can open at login. Turn on Skreener in System Settings → General → Login Items."
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
    }
}
