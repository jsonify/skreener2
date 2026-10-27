import AppKit

/// What a destination tells the user once it has the capture.
struct SendResult {
    var title: String
    var detail: String?
}

/// A reason a destination couldn't take the capture, in words for the user.
struct SendError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Somewhere a capture can be sent from the Send To menu (#275, #276): one of the user's custom actions, or a notes app.
@MainActor protocol SendDestination {
    var id: String { get }
    var title: String { get }
    /// An SF Symbol for the menu.
    var symbol: String { get }
    /// Whether it can take a video or GIF, not just a screenshot.
    var acceptsRecordings: Bool { get }
    /// Whether it uses the text OCR finds in the screenshot, so that is only read for destinations that do.
    var wantsText: Bool { get }
    /// Whether it should be listed (the app is installed, the action exists).
    var isAvailable: Bool { get }
    /// Sends `file` (and `text`, when `wantsText`); `app` is the app the capture came from, when known.
    func send(file: URL, text: String?, app: String?) async throws -> SendResult
}

/// A custom action as a destination: runs its command on the capture.
struct CustomActionDestination: SendDestination {
    let action: CustomAction

    var id: String { "action.\(action.id.uuidString)" }
    var title: String { action.name }
    var symbol: String { "terminal" }
    var acceptsRecordings: Bool { true }
    var wantsText: Bool { action.wantsText }
    var isAvailable: Bool { true }

    func send(file: URL, text: String?, app: String?) async throws -> SendResult {
        let outcome = await ScriptRunner.run(command: action.command, file: file,
                                             environment: CustomActions.environment(file: file, text: text, app: app))
        let report = CustomActions.report(name: action.name, outcome: outcome, copyOutput: action.copyOutput)
        guard report.ok else { throw SendError(report.detail ?? report.title) }
        if let clipboard = report.clipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboard, forType: .string)
        }
        return SendResult(title: report.title, detail: report.detail)
    }
}

/// The Send To menu in Quick Access, the editor footer and the capture history, and what it does with a choice.
@MainActor enum SendTo {
    /// The capture to send, made when a destination is picked (the editor flattens its annotations only then).
    @MainActor struct Source {
        var isImage: Bool
        /// The app the capture came from, for SKREENER_APP.
        var app: String?
        /// The file to send and, when at hand, its image (for reading its text).
        var load: @MainActor () -> (file: URL, image: NSImage?)?

        /// A capture that is already a file.
        init(file: URL, isImage: Bool = true) {
            self.isImage = isImage
            self.app = SendTo.appName(for: file)
            self.load = { (file: file, image: nil) }
        }

        init(isImage: Bool = true, app: String? = nil, load: @escaping @MainActor () -> (file: URL, image: NSImage?)?) {
            self.isImage = isImage
            self.app = app
            self.load = load
        }
    }

    /// The destinations to list, custom actions first; a recording only goes to the ones that take one.
    static func destinations(forImage: Bool) -> [SendDestination] {
        let list: [SendDestination] = Preferences.customActions.map(CustomActionDestination.init)
        return list.filter { $0.isAvailable && (forImage || $0.acceptsRecordings) }
    }

    /// The menu of destinations for `source`. `onChoose` runs when one is picked (Quick Access closes its preview).
    static func menu(for source: Source, onChoose: (() -> Void)? = nil) -> NSMenu {
        let menu = NSMenu()
        let all = destinations(forImage: source.isImage)
        let actions = all.filter { $0 is CustomActionDestination }
        let notes = all.filter { !($0 is CustomActionDestination) }

        func add(_ destination: SendDestination) {
            let item = NSMenuItem(title: destination.title, action: #selector(MenuTarget.fire), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: destination.symbol, accessibilityDescription: nil)
            let target = MenuTarget {
                onChoose?()
                send(destination, source: source)
            }
            item.target = target; item.representedObject = target
            menu.addItem(item)
        }
        if !actions.isEmpty {
            menu.addItem(.sectionHeader(title: "Actions"))
            actions.forEach(add)
        }
        if !notes.isEmpty {
            if !actions.isEmpty { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: "Notes"))
            notes.forEach(add)
        }
        if all.isEmpty {
            let empty = NSMenuItem(title: "Nothing to send to yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Send To Settings…", action: #selector(MenuTarget.fire), keyEquivalent: "")
        let open = MenuTarget { SettingsWindowController.shared.present(sendTo: true) }
        settings.target = open; settings.representedObject = open
        menu.addItem(settings)
        return menu
    }

    /// Pops the menu up under `view` (a button).
    static func present(_ source: Source, from view: NSView, onChoose: (() -> Void)? = nil) {
        let popup = SendTo.menu(for: source, onChoose: onChoose)
        popup.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4), in: view)
    }

    /// The app a saved file was captured from, when the library knows it.
    static func appName(for file: URL) -> String? {
        SavedLibrary.shared.entries.first { $0.url.lastPathComponent == file.lastPathComponent }?.meta.app
    }

    /// Sends the capture to `destination` and says how it went; never blocks the caller.
    static func send(_ destination: SendDestination, source: Source) {
        Task { @MainActor in
            guard let loaded = source.load() else {
                Notifier.problem("Couldn't send the capture", detail: "Skreener couldn't make a file of it.")
                return
            }
            var text: String?
            if destination.wantsText, source.isImage {
                text = await recognizedText(loaded.image ?? NSImage(contentsOf: loaded.file))
            }
            await deliver(destination, file: loaded.file, text: text, app: source.app)
        }
    }

    /// Runs the actions set to run after every capture (Settings → Send To), after the capture is saved. `saved` is the
    /// saved file; without one the image goes to a temporary file.
    static func runAfterCapture(image: NSImage, saved: URL?, app: String?) {
        let actions = CustomActions.afterCapture(Preferences.customActions)
        guard !actions.isEmpty, let file = saved ?? Output.temporaryFile(image) else { return }
        Task { @MainActor in
            var text: String?
            var textRead = false   // read once, for the first action that uses it
            for action in actions {
                if action.wantsText, !textRead {
                    text = await recognizedText(image)
                    textRead = true
                }
                await deliver(CustomActionDestination(action: action), file: file, text: action.wantsText ? text : nil, app: app)
            }
        }
    }

    private static func deliver(_ destination: SendDestination, file: URL, text: String?, app: String?) async {
        do {
            let result = try await destination.send(file: file, text: text, app: app)
            // Always shown (whatever Settings → After Capture says): the user asked for this one.
            MessageHUD.show(result.title, detail: result.detail, symbol: "checkmark.circle.fill", placement: .top)
        } catch {
            Notifier.problem("\(destination.title) failed", detail: error.localizedDescription)
        }
    }

    private static func recognizedText(_ image: NSImage?) async -> String? {
        guard let image else { return nil }
        let text = await TextRecognizer.recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// A menu item's action as a closure (the item keeps it alive through `representedObject`).
@MainActor private final class MenuTarget: NSObject {
    private let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @objc func fire() { run() }
}
