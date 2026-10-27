import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private let overlay = SelectionOverlay()
    private let selfTimer = SelfTimer()
    private var lastArea: (NSScreen, CGRect)?
    private var desktopIconsItem: NSMenuItem!
    /// Menu items that show their action's global shortcut (see `updateMenuShortcuts`).
    private var shortcutItems: [HotKeyAction: NSMenuItem] = [:]
    private var iconsHiddenForCapture = false
    private let recording = RecordingController()
    private let recordPicker = RecordAreaPicker()
    private let presenter = PresenterOverlay()
    /// Whether the picker on screen was opened by Record Screen or by All-in-One (#29).
    private var pickerPurpose = PickerPurpose.record
    private let scrollCapture = ScrollCaptureController()
    /// After-capture steps a skreener:// link chose (`then=`) for the capture it started; nil uses Settings.
    /// `endCapture()` clears it, so it never carries over to a later capture.
    private var linkActions: CaptureActions?
    /// Self-timer delay a skreener:// link chose (`delay=`) for the countdown it started.
    private var linkDelay: Int?
    /// A Shortcuts action waiting for the capture it started (#274): gets the screenshot, or nil when the capture was
    /// cancelled or failed. The capture takes it when it starts, and `endCapture()` answers nil to one still waiting.
    private var shortcutResult: ((NSImage?) -> Void)?
    /// The last app other than Skreener that was in front: Capture Active Window takes its window when Skreener
    /// itself is in front (an editor or Settings is open).
    private var lastOtherApp: pid_t?

    /// The bundled template glyph (falls back to an SF Symbol when run outside the .app, e.g. `swift run`).
    private lazy var menuBarIcon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Skreener")
        }
        image.isTemplate = true
        image.accessibilityDescription = "Skreener"
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarIcon
        menu = buildMenu()
        statusItem.menu = menu
        NSApp.mainMenu = buildMainMenu()
        // Editor tabs are Skreener's own, so AppKit's Show Tab Bar / Show All Tabs menu items would do nothing.
        NSWindow.allowsAutomaticWindowTabbing = false

        // Global shortcuts (rebindable in Settings → Shortcuts, re-registered as soon as one changes).
        let shortcuts = ShortcutCenter.shared
        shortcuts.handlers = [
            .captureArea: { [weak self] in self?.captureArea() },
            .allInOne: { [weak self] in self?.allInOne() },
            .capturePreviousArea: { [weak self] in self?.capturePreviousArea() },
            .captureAreaAndPin: { [weak self] in self?.captureAreaAndPin() },
            .captureFullscreen: { [weak self] in self?.captureFullscreen() },
            .captureWindow: { [weak self] in self?.captureWindow() },
            .captureActiveWindow: { [weak self] in self?.captureActiveWindow() },
            .captureScrolling: { [weak self] in self?.captureScrolling() },
            .captureText: { [weak self] in self?.captureText() },
            .timedArea: { [weak self] in self?.timedArea() },
            .timedWindow: { [weak self] in self?.timedWindow() },
            .timedFullscreen: { [weak self] in self?.timedFullscreen() },
            .recordScreen: { [weak self] in self?.recordScreen() },
            .presenter: { [weak self] in self?.togglePresenter() },
            .showHistory: { [weak self] in self?.showHistory() },
            .toggleDesktopIcons: { [weak self] in self?.toggleDesktopIcons() },
            .openFile: { [weak self] in self?.openFile() },
            .openClipboard: { [weak self] in self?.openClipboard() },
            .pinFile: { [weak self] in self?.pinFile() },
            .pinClipboard: { [weak self] in self?.pinClipboard() },
            .pinClickThrough: { [weak self] in self?.pinClickThrough() },
        ]
        shortcuts.onChange = { [weak self] in self?.updateMenuShortcuts() }
        shortcuts.register()
        updateMenuShortcuts()
        recording.onStateChange = { [weak self] on in self?.recordingChanged(on) }
        // The presenter overlay is meant to be seen, so a recording keeps it in the video (#266).
        presenter.onWindowsChange = { [weak self] ids in self?.recording.alsoRecorded = ids }
        recording.onTick = { [weak self] time in
            self?.statusItem.button?.title = Preferences.recordTimeInMenuBar ? " " + time : ""
        }

        // The history panel's capture buttons (#117).
        CaptureHistoryPanel.captureActions = [
            ("viewfinder", "Capture Area", { [weak self] in self?.captureArea() }),
            ("arrow.counterclockwise", "Capture Previous Area", { [weak self] in self?.capturePreviousArea() }),
            ("macwindow", "Capture Window", { [weak self] in self?.captureWindow() }),
            ("display", "Capture Fullscreen", { [weak self] in self?.captureFullscreen() }),
            ("arrow.up.and.down.text.horizontal", "Capture Scrolling", { [weak self] in self?.captureScrolling() }),
            ("doc.on.clipboard", "Open from Clipboard", { [weak self] in self?.openClipboard() }),
        ]
        EditorWindowController.captureArea = { [weak self] done in
            if let self { self.captureAreaImage(done) } else { done(nil) }
        }

        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            lastOtherApp = front.processIdentifier
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            self?.lastOtherApp = app.processIdentifier
        }
        Notifier.setUp()
        Updater.start()

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        // Key equivalents come from the global shortcuts (`updateMenuShortcuts`).
        func add(_ t: String, _ s: Selector, _ shortcut: HotKeyAction) {
            let i = NSMenuItem(title: t, action: s, keyEquivalent: "")
            i.target = self; m.addItem(i)
            shortcutItems[shortcut] = i
        }
        add("Capture Area", #selector(captureArea), .captureArea)
        add("All-in-One", #selector(allInOne), .allInOne)
        add("Capture Previous Area", #selector(capturePreviousArea), .capturePreviousArea)
        add("Capture Area & Pin", #selector(captureAreaAndPin), .captureAreaAndPin)
        add("Capture Fullscreen", #selector(captureFullscreen), .captureFullscreen)
        add("Capture Window", #selector(captureWindow), .captureWindow)
        add("Capture Active Window", #selector(captureActiveWindow), .captureActiveWindow)
        add("Capture Scrolling", #selector(captureScrolling), .captureScrolling)
        add("Capture Text (OCR)", #selector(captureText), .captureText)
        let timerItem = NSMenuItem(title: "Self-Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for (title, sel, shortcut) in [("Area…", #selector(timedArea), HotKeyAction.timedArea),
                                       ("Window…", #selector(timedWindow), HotKeyAction.timedWindow),
                                       ("Fullscreen", #selector(timedFullscreen), HotKeyAction.timedFullscreen)] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; timerMenu.addItem(i)
            shortcutItems[shortcut] = i
        }
        timerMenu.addItem(.separator())
        for s in [3, 5, 10] {
            let i = NSMenuItem(title: "\(s) Second Delay", action: #selector(timerDelayPicked(_:)), keyEquivalent: "")
            i.target = self; i.tag = s; timerMenu.addItem(i)
        }
        timerMenu.delegate = self
        timerItem.submenu = timerMenu; m.addItem(timerItem)
        m.addItem(.separator())
        add("Record Screen", #selector(recordScreen), .recordScreen)
        add("Zoom & Draw on Screen", #selector(togglePresenter), .presenter)
        m.addItem(.separator())
        add("Capture History", #selector(showHistory), .showHistory)
        m.addItem(.separator())
        desktopIconsItem = NSMenuItem(title: DesktopIcons.visible ? "Hide Desktop Icons" : "Show Desktop Icons",
                                      action: #selector(toggleDesktopIcons), keyEquivalent: "")
        desktopIconsItem.target = self; m.addItem(desktopIconsItem)
        shortcutItems[.toggleDesktopIcons] = desktopIconsItem
        m.addItem(.separator())
        for (title, sel, shortcut) in [("Open…", #selector(openFile), HotKeyAction.openFile),
                                       ("Open from Clipboard", #selector(openClipboard), HotKeyAction.openClipboard),
                                       ("Pin to the Screen…", #selector(pinFile), HotKeyAction.pinFile),
                                       ("Pin from Clipboard", #selector(pinClipboard), HotKeyAction.pinClipboard),
                                       ("Pin Click-Through On / Off", #selector(pinClickThrough),
                                        HotKeyAction.pinClickThrough)] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i)
            shortcutItems[shortcut] = i
        }
        m.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]; settings.target = self; m.addItem(settings)
        m.addItem(withTitle: "About Skreener", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self; m.addItem(update)
        let version = NSMenuItem(title: "Version \(SettingsWindowController.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false; m.addItem(version)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Skreener", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @MainActor @objc private func openSettings() { SettingsWindowController.shared.present() }
    @MainActor @objc private func checkForUpdates() { Updater.check(userInitiated: true) }

    // MARK: skreener:// links

    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openLink(url) }
    }

    @MainActor private func openLink(_ url: URL) {
        switch URLCommand.parse(url) {
        case .failure(let error):
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Skreener can't run this link"
            alert.informativeText = "\(url.absoluteString)\n\n\(error.message)"
            alert.runModal()
        case .success(let command):
            guard Preferences.allowURLScheme || askToAllowLinks(url, command) else { return }
            perform(command)
        }
    }

    /// Links are off until the user says so: the first one asks, naming what it would do.
    @MainActor private func askToAllowLinks(_ url: URL, _ command: URLCommand) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow links to control Skreener?"
        alert.informativeText = "An app, perhaps on your behalf, opened \(url.absoluteString) (\(command.title)). "
            + "Allowing skreener:// links lets Raycast, Alfred, Shortcuts and scripts use Skreener. "
            + "You can turn them off in Settings → General."
        alert.addButton(withTitle: "Allow and Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        Preferences.allowURLScheme = true
        if SettingsWindowController.isOpen { SettingsWindowController.shared.refreshURLScheme() }
        return true
    }

    @MainActor private func perform(_ command: URLCommand) {
        switch command.command {
        case .settings:
            openSettings()
        case .run(let action):
            linkActions = command.then
            linkDelay = command.delay
            ShortcutCenter.shared.handlers[action]?()
        }
    }

    /// Shortcuts actions (#274): a capture command, run like a skreener:// link with no after-capture steps, returns
    /// the screenshot instead.
    @MainActor func captureForShortcut(_ action: HotKeyAction) async throws -> NSImage {
        // A second capture can't start while one is on screen, and its result would never come.
        guard shortcutResult == nil, !overlay.isActive, !recordPicker.isActive, !scrollCapture.isRunning else {
            throw ShortcutError.busy
        }
        let image = await withCheckedContinuation { continuation in
            shortcutResult = { continuation.resume(returning: $0) }
            perform(URLCommand(command: .run(action), then: []))
        }
        guard let image else { throw ShortcutError.cancelled }
        return image
    }

    /// Shortcuts actions that return nothing run like a skreener:// link.
    @MainActor func runForShortcut(_ action: HotKeyAction) { perform(URLCommand(command: .run(action))) }

    /// Hands the capture to the Shortcuts action waiting for it, if any; nil after that.
    private func takeShortcutResult() -> ((NSImage?) -> Void)? {
        defer { shortcutResult = nil }
        return shortcutResult
    }

    /// The self-timer delay for the countdown about to start: a link's `delay=` (once), else the menu's.
    private func timerSeconds() -> Int {
        defer { linkDelay = nil }
        return linkDelay ?? Preferences.selfTimerSeconds
    }

    /// Shows each action's current global shortcut in the menu. Open from Clipboard keeps its ⌘V (which only works
    /// while the menu is open) when it has no global shortcut.
    private func updateMenuShortcuts() {
        for (action, item) in shortcutItems {
            if let combo = ShortcutStore.combo(for: action), let key = combo.keyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = combo.modifierFlags
            } else if action == .openClipboard {
                item.keyEquivalent = "v"
                item.keyEquivalentModifierMask = [.command]
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }

    /// Self-Timer submenu: tick the current delay.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for i in menu.items where i.action == #selector(timerDelayPicked(_:)) {
            i.state = i.tag == Preferences.selfTimerSeconds ? .on : .off
        }
    }
    @objc private func showHistory() { CaptureHistoryPanel.shared.toggle() }

    /// The app menu bar, shown while an editor or Settings window is open (see `DockPresence`).
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: ""); holder.submenu = m
            main.addItem(holder)
            return m
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command],
                  target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods; i.target = target
            return i
        }
        _ = submenu("Skreener", [
            item("About Skreener", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            item("Check for Updates…", #selector(checkForUpdates), target: self),
            .separator(),
            item("Settings…", #selector(openSettings), ",", target: self),
            .separator(),
            item("Hide Skreener", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Skreener", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = submenu("File", [
            item("Save", #selector(EditorWindow.saveScreenshot(_:)), "s"),
            item("Save As…", #selector(EditorWindow.saveScreenshotAs(_:)), "s", [.command, .shift]),
        ])
        _ = submenu("Edit", [
            item("Undo", #selector(CanvasView.undo(_:)), "z"),
            item("Redo", #selector(CanvasView.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Duplicate", #selector(CanvasView.duplicate(_:)), "d"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        let plain: ([(String, Selector)]) -> [NSMenuItem] = { $0.map { item($0.0, $0.1, "", []) } }
        let textItems: [NSMenuItem] = [
            item("Copy Text from Area…", #selector(CanvasView.copyTextFromArea(_:)), "t", [.command, .shift]),
            item("Copy All Text", #selector(CanvasView.copyAllText(_:))),
        ]
        let sizeItems = plain(CanvasView.sizeCommands)
        if let resize = sizeItems.first(where: { $0.action == #selector(CanvasView.resizeImage(_:)) }) {
            resize.keyEquivalent = "r"; resize.keyEquivalentModifierMask = [.command, .shift]
        }
        var imageItems: [NSMenuItem] = []
        for group in [plain(CanvasView.imageCommands), sizeItems, plain(CanvasView.redactCommands), textItems,
                      plain(CanvasView.colorCommands), plain(CanvasView.snapCommands),
                      [item("Combine Screenshots…", #selector(EditorWindow.combineScreenshots(_:)), "", [])]] {
            if !imageItems.isEmpty { imageItems.append(.separator()) }   // a new separator each time: menus can't share items
            imageItems += group
        }
        _ = submenu("Image", imageItems)
        _ = submenu("Arrange", CanvasView.arrangeCommands.map { title, action, key, mods in
            item(title, action, key, mods)
        })
        NSApp.windowsMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            .separator(),
            // Editor tabs (`EditorTabGroup`; `EditorWindow` handles these).
            item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "[", [.command, .shift]),
            item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "]", [.command, .shift]),
            item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:))),
            item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:))),
            item("Show Screenshots", #selector(EditorWindow.toggleScreenshotDock(_:)), "s", [.command, .control]),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        return main
    }

    @objc private func toggleDesktopIcons() {
        let show = !DesktopIcons.visible
        DesktopIcons.setVisible(show)
        desktopIconsItem.title = show ? "Hide Desktop Icons" : "Show Desktop Icons"
    }

    // MARK: Open / pin existing images

    @MainActor @objc private func openFile() {
        NSApp.activate(ignoringOtherApps: true)
        // Saving the edited image writes over the file opened (#118).
        if let picked = ImageSource.pickFile() { EditorWindowController(image: picked.image, file: picked.url).present() }
    }

    @objc private func openClipboard() {
        guard let img = ImageSource.fromClipboard() else { noClipboardImage(); return }
        EditorWindowController(image: img).present()
    }

    @MainActor @objc private func pinFile() {
        NSApp.activate(ignoringOtherApps: true)
        if let picked = ImageSource.pickFile() { PinnedScreenshotController.pin(picked.image) }
    }

    @objc private func pinClipboard() {
        guard let img = ImageSource.fromClipboard() else { noClipboardImage(); return }
        PinnedScreenshotController.pin(img)
    }

    @objc private func pinClickThrough() { PinnedScreenshotController.toggleClickThrough() }

    private func noClipboardImage() {
        Notifier.problem("No image on the clipboard", detail: "Copy an image or a screenshot first.")
    }

    // MARK: Desktop icons during capture

    /// Runs `go` once desktop icons are hidden (if that option is on); Finder needs a moment to redraw. Quick Access
    /// previews fade away until `endCapture()`.
    private func prepareCapture(_ go: @escaping () -> Void) {
        QuickAccessController.suspend()
        guard Preferences.hideIconsWhileCapturing, !iconsHiddenForCapture, DesktopIcons.visible else { go(); return }
        iconsHiddenForCapture = true
        DesktopIcons.setVisible(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: go)
    }

    /// Every capture flow ends here, whether it captured something or was cancelled.
    private func endCapture() {
        linkActions = nil
        takeShortcutResult()?(nil)
        QuickAccessController.resume()
        guard iconsHiddenForCapture else { return }
        iconsHiddenForCapture = false
        DesktopIcons.setVisible(true)
    }

    // MARK: Capture flows

    @objc func capturePreviousArea() {
        guard let (screen, rect) = lastArea, NSScreen.screens.contains(screen) else {
            endCapture()
            Notifier.problem("No area to repeat",
                             detail: "Capture Previous Area captures the area you captured last. Capture an area first.")
            return
        }
        prepareCapture { [weak self] in
            self?.run(screen: screen) { try await CaptureService.captureScreen(screen, globalRect: rect) }
        }
    }

    @objc func captureFullscreen() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        prepareCapture { [weak self] in self?.run(screen: screen) { try await CaptureService.captureScreen(screen) } }
    }

    @objc func captureAreaAndPin() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { self?.endCapture(); return }
                lastArea = (screen, rect)
                // The pin opens at 100% exactly over the area it shows.
                run(screen: screen, areaCapture(screen, rect, frozen)) {
                    CaptureHistory.add($0)
                    PinnedScreenshotController.pin($0, at: rect)
                }
            }
        }
    }

    // MARK: Scrolling capture

    /// Pick an area, then scroll its content while Skreener stitches it into one tall image. The same command
    /// (⌃⇧8) finishes; the result goes through the usual after-capture steps.
    @objc func captureScrolling() {
        if scrollCapture.isRunning { scrollCapture.finish(); return }
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .scrolling, windows: [], hints: Self.captureHints) { [weak self] sel in self?.handle(sel) }
        }
    }

    private func startScrollCapture(_ screen: NSScreen, _ rect: CGRect) {
        scrollCapture.start(screen: screen, rect: rect) { [weak self] image in
            guard let self else { return }
            let actions = linkActions, result = takeShortcutResult()
            endCapture()
            result?(image)
            if let image { finish(image, actions: actions, screen: screen) }
        }
    }

    // MARK: Screen recording

    /// Pick an area, then record it; while recording, the same command (⌃⇧7) stops.
    /// Record Screen: drag an area (or press Space and click a window), adjust it in the record picker, then
    /// record a video or GIF, or take a screenshot from the picker's mode bar. With "Remember last selection"
    /// on, the picker opens on the previous area. While recording, the same command (⌃⇧7) stops.
    @objc func recordScreen() {
        if recording.isRecording { recording.stop(); return }
        guard !recordPicker.isActive else { return }
        pickerPurpose = .record
        prepareCapture { [weak self] in
            if Preferences.recordRememberSelection, let last = Preferences.lastRecordRect,
               let screen = NSScreen.screens.first(where: { $0.frame.contains(last) }) {
                self?.showRecordPicker(screen, last, showHint: true)
                return
            }
            self?.pickRecordTarget(.area)
        }
    }

    /// All-in-One (#29): drag an area (or press Space and click a window), then choose the action in the picker's mode
    /// bar: screenshot (↩), fullscreen, window, scrolling capture, self-timer, OCR or recording.
    @objc func allInOne() {
        guard !recordPicker.isActive, !recording.isRecording else { return }
        pickerPurpose = .allInOne
        prepareCapture { [weak self] in self?.pickRecordTarget(.area) }
    }

    /// The Record Screen overlay on every screen: drag an area, or Space and click a window.
    private func pickRecordTarget(_ mode: SelectionOverlay.Mode) {
        let allInOne = pickerPurpose == .allInOne
        let hints: [SelectionOverlay.Mode: String] = [
            .area: pickerPurpose.areaHint,
            .window: "Click a window to \(allInOne ? "choose what to do with" : "record") it. Press Space to drag an area instead.",
        ]
        Task { @MainActor [weak self] in
            let windows = mode == .window ? await CaptureService.onScreenWindows() : []
            self?.overlay.begin(mode: mode, windows: windows, hints: hints, adjustable: false) { [weak self] sel in
                guard let self else { return }
                switch sel {
                case .area(let screen, let rect, _)?, .scrolling(let screen, let rect)?:
                    showRecordPicker(screen, rect)
                case .window(let w)?:
                    let rect = Self.globalFrame(of: w)
                    guard let screen = Self.screen(containing: rect) else { endCapture(); return }
                    showRecordPicker(screen, rect.intersection(screen.frame))
                case nil:
                    endCapture()
                }
            }
        }
    }

    private func showRecordPicker(_ screen: NSScreen, _ rect: CGRect, showHint: Bool = false) {
        recordPicker.begin(screen: screen, rect: rect, showHint: showHint, purpose: pickerPurpose) { [weak self] pick in
            self?.handle(pick)
        }
    }

    private func handle(_ pick: RecordPick?) {
        switch pick {
        case nil:
            endCapture()
        case .video(let screen, let rect)?:
            Preferences.lastRecordRect = rect
            recording.start(screen: screen, rect: rect)
        case .gif(let screen, let rect)?:
            Preferences.lastRecordRect = rect
            recording.start(screen: screen, rect: rect, gif: true)
        case .screenshot(let screen, let rect)?:
            lastArea = (screen, rect)
            run(screen: screen) { try await CaptureService.captureScreen(screen, globalRect: rect) }
        case .text(let screen, let rect)?:
            run(screen: screen, { try await CaptureService.captureScreen(screen, globalRect: rect) }) { self.copyText($0, screen: screen) }
        case .timer(let screen, let rect)?:
            lastArea = (screen, rect)
            selfTimer.start(seconds: Preferences.selfTimerSeconds, completion: { [weak self] in
                self?.run(screen: screen) { try await CaptureService.captureScreen(screen, globalRect: rect) }
            }, cancelled: { [weak self] in self?.endCapture() })
        case .scrolling(let screen, let rect)?:
            startScrollCapture(screen, rect)
        case .fullscreenShot?:
            captureFullscreen()
        case .window?:
            captureWindow()
        case .selectWindow?:
            pickRecordTarget(.window)
        }
    }

    @objc private func stopRecording() { recording.stop() }

    /// Presenter mode (#266): zoom and draw on the live screen; the same command leaves.
    @objc private func togglePresenter() { presenter.toggle() }

    /// While recording, the menu bar icon becomes a stop button (⌃⇧7 also stops).
    private func recordingChanged(_ on: Bool) {
        guard let button = statusItem.button else { return }
        if on {
            statusItem.menu = nil
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording")
            button.contentTintColor = .systemRed
            button.imagePosition = .imageLeading
            button.toolTip = ShortcutStore.combo(for: .recordScreen).map { "Stop Recording (\($0.displayString))" }
                ?? "Stop Recording"
            button.target = self; button.action = #selector(stopRecording)
        } else {
            endCapture()
            button.image = menuBarIcon
            button.contentTintColor = nil
            button.title = ""
            button.toolTip = nil
            button.target = nil; button.action = nil
            statusItem.menu = menu
        }
    }

    // MARK: Self-timer: pick the area or window first, then count down, then capture it live.

    @objc private func timerDelayPicked(_ item: NSMenuItem) { Preferences.selfTimerSeconds = item.tag }

    @objc func timedFullscreen() {
        selfTimer.start(seconds: timerSeconds(), completion: { [weak self] in self?.captureFullscreen() },
                        cancelled: { [weak self] in self?.endCapture() })
    }

    @objc func timedArea() {
        let seconds = timerSeconds()
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, _)? = sel else { self?.endCapture(); return }
                lastArea = (screen, rect)
                selfTimer.start(seconds: seconds, completion: { [weak self] in
                    self?.run(screen: screen) { try await CaptureService.captureScreen(screen, globalRect: rect) }
                }, cancelled: { [weak self] in self?.endCapture() })
            }
        }
    }

    @objc func timedWindow() {
        let seconds = timerSeconds()
        prepareCapture { [weak self] in
            Task { @MainActor in
                let wins = await CaptureService.onScreenWindows()
                self?.overlay.begin(mode: .window, windows: wins) { [weak self] sel in
                    guard let self, case .window(let w)? = sel else { self?.endCapture(); return }
                    selfTimer.start(seconds: seconds, completion: { [weak self] in
                        self?.run(screen: Self.screen(for: w)) { try await CaptureService.captureWindow(w) }
                    }, cancelled: { [weak self] in self?.endCapture() })
                }
            }
        }
    }

    @objc func captureText() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { self?.endCapture(); return }
                run(screen: screen, areaCapture(screen, rect, frozen)) { self.copyText($0, screen: screen) }
            }
        }
    }

    /// Capture Text: OCR the image and copy what it says, or open it in the scratch pad to edit first (#134).
    private func copyText(_ image: NSImage, screen: NSScreen?) {
        Task { @MainActor in
            let text = await TextRecognizer.recognize(image)
            guard !text.isEmpty else {
                Notifier.problem("No text found", detail: "Skreener couldn't find any text in the area.")
                return
            }
            if Preferences.textScratchPad {
                TextScratchPad.show(text, on: screen)
                return
            }
            TextRecognizer.copyText(text)
            Sound.play("Pop")
            let lines = text.split(separator: "\n").count
            Notifier.confirm(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text")
        }
    }

    @objc func captureArea() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: [], hints: Self.captureHints) { [weak self] sel in self?.handle(sel) }
        }
    }

    /// Capture Area, Capture Window and Capture Scrolling: Space before a drag cycles area → window → scrolling (#171).
    private static let captureHints: [SelectionOverlay.Mode: String] = [
        .area: "Drag to capture an area. Press Space to pick a window.",
        .window: "Click a window to capture it. Press Space for a scrolling capture.",
        .scrolling: "Drag over the content to scroll and capture. Press Space for an area.",
    ]

    @objc func captureWindow() {
        prepareCapture { [weak self] in
            Task { @MainActor in
                let wins = await CaptureService.onScreenWindows()
                self?.pickWindow(wins)
            }
        }
    }

    /// The window picker, or a message when there is nothing to pick.
    private func pickWindow(_ windows: [SCWindow]) {
        guard !windows.isEmpty else {
            endCapture()
            Notifier.problem("No windows are present", detail: "Try a fullscreen screenshot instead.")
            return
        }
        overlay.begin(mode: .window, windows: windows, hints: Self.captureHints) { [weak self] sel in self?.handle(sel) }
    }

    /// Captures the front window of the app in front, without picking it (#110). Choosing this from Skreener's menu
    /// or with an editor in front makes Skreener the active app, so then the app that was in front before is used.
    /// When that app has no window on screen, the window picker opens instead.
    @objc func captureActiveWindow() {
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front == nil || front?.processIdentifier == getpid() ? lastOtherApp : front?.processIdentifier
        prepareCapture { [weak self] in
            Task { @MainActor in
                let wins = await CaptureService.onScreenWindows()
                self?.captureFrontWindow(of: pid, in: wins)
            }
        }
    }

    /// `windows` are frontmost first, so the first one `pid` owns is its front window.
    private func captureFrontWindow(of pid: pid_t?, in windows: [SCWindow]) {
        if let pid, let w = windows.first(where: { $0.owningApplication?.processID == pid }) {
            run(screen: Self.screen(for: w), owner: pid) { try await CaptureService.captureWindow(w) }
            return
        }
        if !windows.isEmpty {
            let name = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            Notifier.problem(name.map { "\($0) has no window on screen" } ?? "No active window",
                             detail: "Click a window to capture it.")
        }
        pickWindow(windows)
    }

    private func handle(_ sel: Selection?) {
        guard let sel else { endCapture(); return }
        switch sel {
        case .area(let screen, let rect, let frozen):
            lastArea = (screen, rect)
            run(screen: screen, areaCapture(screen, rect, frozen))
        case .window(let w): run(screen: Self.screen(for: w), owner: w.owningApplication?.processID) { try await CaptureService.captureWindow(w) }
        case .scrolling(let screen, let rect): startScrollCapture(screen, rect)
        }
    }

    /// A window's frame in global bottom-left coordinates (SCWindow frames are top-left origin).
    private static func globalFrame(of w: SCWindow) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: w.frame.minX, y: primaryH - w.frame.maxY, width: w.frame.width, height: w.frame.height)
    }

    /// The screen that shows most of `rect` (global coordinates).
    private static func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.frame.intersection(rect).width * a.frame.intersection(rect).height
                < b.frame.intersection(rect).width * b.frame.intersection(rect).height
        }
    }

    private static func screen(for w: SCWindow) -> NSScreen? { screen(containing: globalFrame(of: w)) }

    /// Area capture for the editor's Add Image → Capture Area: no Quick Access, just the image (nil if cancelled).
    private func captureAreaImage(_ completion: @escaping (NSImage?) -> Void) {
        QuickAccessController.suspend()
        let done: (NSImage?) -> Void = { QuickAccessController.resume(); completion($0) }
        // Give the hidden editor window a moment to leave the screen first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { done(nil); return }
            overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { done(nil); return }
                lastArea = (screen, rect)
                let capture = areaCapture(screen, rect, frozen)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000) // let overlay fade from the compositor
                    do {
                        let image = try await capture()
                        CaptureHistory.add(image)
                        done(image)
                    } catch {
                        Notifier.captureFailed(error)
                        done(nil)
                    }
                }
            }
        }
    }

    /// Crops the frozen still when the screen was frozen during selection, otherwise grabs the live screen.
    private func areaCapture(_ screen: NSScreen, _ rect: CGRect, _ frozen: CGImage?) -> () async throws -> NSImage {
        if let frozen { return { try CaptureService.crop(frozen, screen: screen, globalRect: rect) } }
        return { try await CaptureService.captureScreen(screen, globalRect: rect) }
    }

    /// `screen` is where the capture came from: its editor opens there (#111). `owner` is the app whose window it is, when
    /// the capture is of one window (else the app in front is taken as the source, #269).
    private func run(screen: NSScreen?, owner: pid_t? = nil, _ capture: @escaping () async throws -> NSImage,
                     then: ((NSImage) -> Void)? = nil) {
        let actions = linkActions, result = takeShortcutResult()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // let overlay fade from the compositor
            do {
                let image = try await capture()
                endCapture()
                result?(image)
                if let then { then(image) } else { self.finish(image, actions: actions, screen: screen, owner: owner) }
            } catch {
                endCapture()
                result?(nil)
                NSLog("Capture failed: \(error)")
                Notifier.captureFailed(error)
            }
        }
    }

    /// For a capture of a browser, asks it for the page in its front tab and keeps that with the saved file and the
    /// history entry (#269). Nothing happens for other apps, or when the browser doesn't answer.
    private func rememberSourcePage(of pid: pid_t?, saved: URL?, history: URL?) {
        guard saved != nil || history != nil else { return }
        let bundleID = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        SourcePage.lookup(bundleID: bundleID) { page in
            guard let page else { return }
            if let saved {
                SavedLibrary.shared.note(saved, page: page)
                SourcePage.writeWhereFroms(page.url, to: saved)
            }
            if let history { CaptureHistory.noteSource(page, for: history) }
        }
    }

    /// The after-capture steps: Settings → After Capture, or the ones a skreener:// link chose (`actions`).
    private func finish(_ image: NSImage, actions: CaptureActions? = nil, screen: NSScreen? = nil, owner: pid_t? = nil) {
        let actions = actions ?? .fromPreferences
        let historyEntry = CaptureHistory.add(image)
        if actions.contains(.copy) { Output.copy(image) }
        var saved: URL?
        let appName = lastOtherApp.flatMap { NSRunningApplication(processIdentifier: $0) }?.localizedName
        if actions.contains(.save) {
            saved = Output.save(image)
            // For the library's App filter and search (#117).
            if let saved { SavedLibrary.shared.note(saved, app: appName) }
            if saved == nil {
                Notifier.problem("Couldn't save the screenshot",
                                 detail: "Check the export location in Settings → General.")
            }
        }
        rememberSourcePage(of: owner ?? lastOtherApp, saved: saved, history: historyEntry)
        // The user's own after-capture commands (Settings → Send To), once the file is saved.
        MainActor.assumeIsolated { SendTo.runAfterCapture(image: image, saved: saved, app: appName) }
        // Area & Pin, Capture Text and the editor's own Add Image captures don't come through here.
        var editor: EditorWindowController?
        if actions.contains(.edit) {
            // An auto-saved capture is saved again over the same file (#118).
            editor = EditorWindowController(image: image, file: saved)
            if let historyEntry { editor?.attachHistory(historyEntry) }
            editor?.present(on: screen)
        }
        if actions.contains(.pin) { PinnedScreenshotController.pin(image) }
        if actions.contains(.quickAccess) { QuickAccessController.show(image, editor: editor, saved: saved) }
        // Nothing on screen shows the result, so say what happened (#113).
        guard actions.isDisjoint(with: [.edit, .pin, .quickAccess]) else { return }
        let copied = actions.contains(.copy)
        if let saved {
            Notifier.confirm(copied ? "Screenshot copied and saved" : "Screenshot saved", detail: saved.lastPathComponent,
                             file: saved)
        } else if copied {
            Notifier.confirm("Screenshot copied")
        }
    }
}

/// Skreener lives in the menu bar, but while an editor or the Settings window is open it behaves like a
/// normal app: Dock icon, ⌘-Tab, and its own menu bar.
enum DockPresence {
    @MainActor static func update() {
        let settingsOpen = SettingsWindowController.isOpen
        let policy: NSApplication.ActivationPolicy = EditorWindowController.live.isEmpty && !settingsOpen ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate(ignoringOtherApps: true) }
    }
}
