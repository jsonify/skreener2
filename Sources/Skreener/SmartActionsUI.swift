import AppKit

/// Carries out a smart action (#243).
@MainActor enum SmartActionRunner {
    static func perform(_ action: SmartAction) {
        switch action.kind {
        case .copyCode:
            guard let text = action.text else { return }
            TextRecognizer.copyText(text)
            Sound.play("Pop")
            Notifier.confirm("Copied QR code content", detail: SmartActions.short(text, 80))
        case .calendar:
            guard let event = action.event else { return }
            addToCalendar(event)
        case .openCode, .maps, .call, .link, .flight:
            if let url = action.url { NSWorkspace.shared.open(url) }
        }
    }

    /// Opens a prefilled event: a temporary .ics file that Calendar imports, so no Calendar access is needed.
    private static func addToCalendar(_ event: CalendarEvent) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Skreener Event \(UUID().uuidString.prefix(8)).ics")
        do { try ICalendar.file(for: event).write(to: file, atomically: true, encoding: .utf8) } catch {
            Notifier.problem("Couldn't add the event", detail: error.localizedDescription)
            return
        }
        if let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open([file], withApplicationAt: calendar, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }
}

/// Menu items for smart actions, in the editor and in Quick Access's overflow menu (#243).
@MainActor final class SmartActionMenu: NSObject {
    private static let shared = SmartActionMenu()

    static func items(for actions: [SmartAction]) -> [NSMenuItem] {
        actions.map { a in
            let item = NSMenuItem(title: a.title, action: #selector(run(_:)), keyEquivalent: "")
            item.target = shared
            item.representedObject = a
            item.image = NSImage(systemSymbolName: a.symbol, accessibilityDescription: nil)
            return item
        }
    }

    static func menu(for actions: [SmartAction]) -> NSMenu {
        let menu = NSMenu()
        items(for: actions).forEach(menu.addItem)
        return menu
    }

    @objc private func run(_ item: NSMenuItem) {
        if let action = item.representedObject as? SmartAction { SmartActionRunner.perform(action) }
    }
}
