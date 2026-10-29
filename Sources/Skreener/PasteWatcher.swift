import AppKit

/// Gives a Capture Text copy clean text or Markdown as its plain text depending on where it is pasted (#327).
///
/// A standard copy goes on the clipboard with clean text and arms the watcher. While armed, an event tap sees ⌘V
/// before the app in front does: it works out the destination (`PasteDestination`), and when that wants the other
/// text it rewrites the clipboard there and then, before the paste reaches the app. A lazy pasteboard provider can't
/// do this: clipboard managers read the clipboard as soon as it changes, which would ask for the text too early.
///
/// The tap needs Accessibility; without it nothing happens and copies stay clean. It only runs while armed, and only
/// looks at ⌘V. Copying anything else disarms it. Everything here runs on the main thread: copies are made there, and
/// the tap's run loop source is on the main run loop.
final class PasteWatcher {
    static let shared = PasteWatcher()

    /// The copy on the clipboard, and which of its texts is there now.
    private struct Armed {
        let copy: TextRecognizer.TextCopy
        let html: String?
        let rtf: Data?
        var changeCount: Int
        var choice: PasteDestination.Choice
        /// Destinations the banner has been shown for, once per copy.
        var shown: Set<String> = []
    }

    private var armed: Armed?
    private var tap: CFMachPort?

    /// Marks a rewrite so clipboard managers that follow nspasteboard.org leave it out of their history: the copy is
    /// already there, and each paste would otherwise add it again.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Watches for the paste of `copy`, just written with clean text, rich text `html` and `rtf`, at `changeCount`.
    /// Does nothing when the setting is off or without Accessibility.
    func arm(_ copy: TextRecognizer.TextCopy, html: String?, rtf: Data?, changeCount: Int) {
        guard Preferences.choosePasteFormat, AccessibilityAccess.granted, startTap() else {
            disarm()
            return
        }
        armed = Armed(copy: copy, html: html, rtf: rtf, changeCount: changeCount, choice: .clean)
    }

    /// Stops watching: an explicit Copy as Markdown or Plain Text Only, another copy, or the setting turned off.
    func disarm() {
        armed = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    /// Creates the tap the first time, then enables it. False when it can't be made (no Accessibility).
    private func startTap() -> Bool {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                           callback: pasteTapCallback, userInfo: nil) else {
            NSLog("Paste destinations: couldn't create the event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }

    /// One event from the tap. It goes on to the app unchanged either way; keep this quick (no Apple Events).
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if armed != nil, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9,   // kVK_ANSI_V
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand,
              var state = armed else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == state.changeCount else {
            disarm()
            return
        }
        guard let destination = Self.destination() else { return }
        let remembered = Preferences.pasteChoices
        let choice = destination.choice(remembered: remembered)
        if choice != state.choice {
            state.changeCount = write(state, choice)
            state.choice = choice
        }
        let showBanner = remembered[destination.key] == nil && !state.shown.contains(destination.key)
        if showBanner { state.shown.insert(destination.key) }
        armed = state
        if showBanner {
            DispatchQueue.main.async { PasteWatcher.shared.showBanner(destination, choice) }
        }
    }

    /// The app in front, and for a browser the title of its front window. Nil for Skreener itself (its scratch pad).
    private static func destination() -> PasteDestination? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return nil }
        var title: String?
        if PasteDestination.browsers[id] != nil,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] {
            // Front to back: the first normal window of the app is its front one. The title needs Screen Recording.
            let front = windows.first {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
            }
            title = front?[kCGWindowName as String] as? String
        }
        return PasteDestination(bundleID: id, appName: app.localizedName ?? id, windowTitle: title)
    }

    /// Puts the copy back on the clipboard with `choice` as its plain text, and returns the new change count.
    private func write(_ state: Armed, _ choice: PasteDestination.Choice) -> Int {
        let item = NSPasteboardItem()
        item.setString(choice == .markdown ? state.copy.markdown : state.copy.clean, forType: .string)
        if let html = state.html { item.setString(html, forType: .html) }
        if let rtf = state.rtf { item.setData(rtf, forType: .rtf) }
        item.setData(Data(), forType: Self.transientType)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    /// "Pasted clean text into Chrome · GitHub", with a button that remembers the other text for that destination.
    private func showBanner(_ destination: PasteDestination, _ choice: PasteDestination.Choice) {
        let other = choice.other
        MessageHUD.show("Pasted \(choice.phrase) into \(destination.displayName)", symbol: "doc.on.clipboard",
                        button: (title: other == .markdown ? "Use Markdown here" : "Use clean text here",
                                 run: { PasteWatcher.shared.remember(other, for: destination) }),
                        placement: .top)
    }

    /// Remembers `choice` for `destination` and, while the copy is still on the clipboard, switches it there now.
    private func remember(_ choice: PasteDestination.Choice, for destination: PasteDestination) {
        Preferences.rememberPasteChoice(choice, for: destination.key, name: destination.displayName)
        var detail = "Next copy pasted here uses \(choice.phrase)"
        if var state = armed, NSPasteboard.general.changeCount == state.changeCount {
            if state.choice != choice {
                state.changeCount = write(state, choice)
                state.choice = choice
                armed = state
            }
            detail = "Next paste here uses \(choice.phrase)"
        }
        // The banner closes once its button has run, so this shows after it.
        DispatchQueue.main.async {
            MessageHUD.show("\(destination.displayName) gets \(choice.phrase)", detail: detail,
                            symbol: "checkmark.circle.fill", placement: .top)
        }
    }
}

/// The tap's callback, a C function: it can't capture anything, so it goes through `PasteWatcher.shared`. The event
/// always goes on unchanged.
private func pasteTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    PasteWatcher.shared.handle(type, event)
    return Unmanaged.passUnretained(event)
}
