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
    private var iconsHiddenForCapture = false
    private let recording = RecordingController()
    private let recordPicker = RecordAreaPicker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Skreener")
        menu = buildMenu()
        statusItem.menu = menu
        NSApp.mainMenu = buildMainMenu()

        let mods = controlKey | shiftKey
        HotKeys.shared.register(keyCode: kVK_ANSI_1, modifiers: mods) { [weak self] in self?.capturePreviousArea() }
        HotKeys.shared.register(keyCode: kVK_ANSI_2, modifiers: mods) { [weak self] in self?.captureText() }
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: mods) { [weak self] in self?.captureFullscreen() }
        HotKeys.shared.register(keyCode: kVK_ANSI_4, modifiers: mods) { [weak self] in self?.captureArea() }
        HotKeys.shared.register(keyCode: kVK_ANSI_5, modifiers: mods) { [weak self] in self?.captureWindow() }
        HotKeys.shared.register(keyCode: kVK_ANSI_6, modifiers: mods) { [weak self] in self?.captureAreaAndPin() }
        HotKeys.shared.register(keyCode: kVK_ANSI_7, modifiers: mods) { [weak self] in self?.recordScreen() }
        HotKeys.shared.register(keyCode: kVK_ANSI_H, modifiers: mods) { [weak self] in self?.showHistory() }
        recording.onStateChange = { [weak self] on in self?.recordingChanged(on) }
        recording.onTick = { [weak self] time in
            self?.statusItem.button?.title = Preferences.recordTimeInMenuBar ? " " + time : ""
        }

        EditorWindowController.captureArea = { [weak self] done in
            if let self { self.captureAreaImage(done) } else { done(nil) }
        }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ t: String, _ s: Selector, _ key: String = "") {
            let i = NSMenuItem(title: t, action: s, keyEquivalent: key)
            i.keyEquivalentModifierMask = [.control, .shift]; i.target = self; m.addItem(i)
        }
        add("Capture Area", #selector(captureArea), "4")
        add("Capture Previous Area", #selector(capturePreviousArea), "1")
        add("Capture Area & Pin", #selector(captureAreaAndPin), "6")
        add("Capture Fullscreen", #selector(captureFullscreen), "3")
        add("Capture Window", #selector(captureWindow), "5")
        add("Capture Text (OCR)", #selector(captureText), "2")
        let timerItem = NSMenuItem(title: "Self-Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for (title, sel) in [("Area…", #selector(timedArea)), ("Window…", #selector(timedWindow)),
                             ("Fullscreen", #selector(timedFullscreen))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; timerMenu.addItem(i)
        }
        timerMenu.addItem(.separator())
        for s in [3, 5, 10] {
            let i = NSMenuItem(title: "\(s) Second Delay", action: #selector(timerDelayPicked(_:)), keyEquivalent: "")
            i.target = self; i.tag = s; timerMenu.addItem(i)
        }
        timerMenu.delegate = self
        timerItem.submenu = timerMenu; m.addItem(timerItem)
        m.addItem(.separator())
        add("Record Screen", #selector(recordScreen), "7")
        m.addItem(.separator())
        add("Capture History", #selector(showHistory), "h")
        m.addItem(.separator())
        desktopIconsItem = NSMenuItem(title: DesktopIcons.visible ? "Hide Desktop Icons" : "Show Desktop Icons",
                                      action: #selector(toggleDesktopIcons), keyEquivalent: "")
        desktopIconsItem.target = self; m.addItem(desktopIconsItem)
        m.addItem(.separator())
        for (title, sel, key) in [("Open…", #selector(openFile), ""), ("Open from Clipboard", #selector(openClipboard), "v"),
                                  ("Pin to the Screen…", #selector(pinFile), ""),
                                  ("Pin from Clipboard", #selector(pinClipboard), "")] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = key.isEmpty ? [] : [.command]; i.target = self; m.addItem(i)
        }
        m.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]; settings.target = self; m.addItem(settings)
        m.addItem(withTitle: "About Skreener", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let version = NSMenuItem(title: "Version \(SettingsWindowController.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false; m.addItem(version)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Skreener", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @MainActor @objc private func openSettings() { SettingsWindowController.shared.present() }

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
            .separator(),
            item("Settings…", #selector(openSettings), ",", target: self),
            .separator(),
            item("Hide Skreener", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Skreener", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = submenu("Edit", [
            item("Undo", #selector(CanvasView.undo(_:)), "z"),
            item("Redo", #selector(CanvasView.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        _ = submenu("Image", CanvasView.imageCommands.map { item($0.0, $0.1, "", []) } + [.separator()]
            + CanvasView.redactCommands.map { item($0.0, $0.1, "", []) })
        _ = submenu("Arrange", CanvasView.arrangeCommands.map { title, action, key, mods in
            item(title, action, key, mods)
        })
        NSApp.windowsMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            .separator(),
            // Editor tabs (AppKit also adds Show Tab Bar / Show All Tabs here).
            item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "[", [.command, .shift]),
            item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "]", [.command, .shift]),
            item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:))),
            item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:))),
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
        if let img = ImageSource.pickFile() { EditorWindowController(image: img).present() }
    }

    @objc private func openClipboard() {
        guard let img = ImageSource.fromClipboard() else { NSSound.beep(); return }
        EditorWindowController(image: img).present()
    }

    @MainActor @objc private func pinFile() {
        NSApp.activate(ignoringOtherApps: true)
        if let img = ImageSource.pickFile() { PinnedScreenshotController.pin(img) }
    }

    @objc private func pinClipboard() {
        guard let img = ImageSource.fromClipboard() else { NSSound.beep(); return }
        PinnedScreenshotController.pin(img)
    }

    // MARK: Desktop icons during capture

    /// Runs `go` once desktop icons are hidden (if that option is on); Finder needs a moment to redraw.
    private func prepareCapture(_ go: @escaping () -> Void) {
        guard Preferences.hideIconsWhileCapturing, !iconsHiddenForCapture, DesktopIcons.visible else { go(); return }
        iconsHiddenForCapture = true
        DesktopIcons.setVisible(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: go)
    }

    private func restoreIcons() {
        guard iconsHiddenForCapture else { return }
        iconsHiddenForCapture = false
        DesktopIcons.setVisible(true)
    }

    // MARK: Capture flows

    @objc func capturePreviousArea() {
        guard let (screen, rect) = lastArea, NSScreen.screens.contains(screen) else { NSSound.beep(); return }
        prepareCapture { [weak self] in self?.run { try await CaptureService.captureScreen(screen, globalRect: rect) } }
    }

    @objc func captureFullscreen() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        prepareCapture { [weak self] in self?.run { try await CaptureService.captureScreen(screen) } }
    }

    @objc func captureAreaAndPin() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { self?.restoreIcons(); return }
                lastArea = (screen, rect)
                run(areaCapture(screen, rect, frozen)) { CaptureHistory.add($0); PinnedScreenshotController.pin($0) }
            }
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
        prepareCapture { [weak self] in
            if Preferences.recordRememberSelection, let last = Preferences.lastRecordRect,
               let screen = NSScreen.screens.first(where: { $0.frame.contains(last) }) {
                self?.showRecordPicker(screen, last, showHint: true)
                return
            }
            self?.pickRecordTarget(.area)
        }
    }

    /// The Record Screen overlay on every screen: drag an area, or Space and click a window.
    private func pickRecordTarget(_ mode: SelectionOverlay.Mode) {
        let hints: [SelectionOverlay.Mode: String] = [
            .area: recordAreaHint,
            .window: "Click a window to record it. Press Space to drag an area instead.",
        ]
        Task { @MainActor [weak self] in
            let windows = mode == .window ? await CaptureService.onScreenWindows() : []
            self?.overlay.begin(mode: mode, windows: windows, hints: hints) { [weak self] sel in
                guard let self else { return }
                switch sel {
                case .area(let screen, let rect, _)?:
                    showRecordPicker(screen, rect)
                case .window(let w)?:
                    // SCWindow frames are top-left origin; the picker works in bottom-left global coordinates.
                    let primaryH = NSScreen.screens.first?.frame.height ?? 0
                    let rect = CGRect(x: w.frame.minX, y: primaryH - w.frame.maxY, width: w.frame.width, height: w.frame.height)
                    let screen = NSScreen.screens.max { a, b in
                        a.frame.intersection(rect).width * a.frame.intersection(rect).height
                            < b.frame.intersection(rect).width * b.frame.intersection(rect).height
                    }
                    guard let screen else { restoreIcons(); return }
                    showRecordPicker(screen, rect.intersection(screen.frame))
                case nil:
                    restoreIcons()
                }
            }
        }
    }

    private func showRecordPicker(_ screen: NSScreen, _ rect: CGRect, showHint: Bool = false) {
        recordPicker.begin(screen: screen, rect: rect, showHint: showHint) { [weak self] pick in self?.handle(pick) }
    }

    private func handle(_ pick: RecordPick?) {
        switch pick {
        case nil:
            restoreIcons()
        case .video(let screen, let rect)?:
            Preferences.lastRecordRect = rect
            recording.start(screen: screen, rect: rect)
        case .gif(let screen, let rect)?:
            Preferences.lastRecordRect = rect
            recording.start(screen: screen, rect: rect, gif: true)
        case .screenshot(let screen, let rect)?:
            lastArea = (screen, rect)
            run { try await CaptureService.captureScreen(screen, globalRect: rect) }
        case .text(let screen, let rect)?:
            run({ try await CaptureService.captureScreen(screen, globalRect: rect) }, then: copyText)
        case .timer(let screen, let rect)?:
            lastArea = (screen, rect)
            selfTimer.start(seconds: Preferences.selfTimerSeconds, completion: { [weak self] in
                self?.run { try await CaptureService.captureScreen(screen, globalRect: rect) }
            }, cancelled: { [weak self] in self?.restoreIcons() })
        case .fullscreenShot?:
            captureFullscreen()
        case .window?:
            captureWindow()
        case .selectWindow?:
            pickRecordTarget(.window)
        }
    }

    @objc private func stopRecording() { recording.stop() }

    /// While recording, the menu bar icon becomes a stop button (⌃⇧7 also stops).
    private func recordingChanged(_ on: Bool) {
        guard let button = statusItem.button else { return }
        if on {
            statusItem.menu = nil
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording")
            button.contentTintColor = .systemRed
            button.imagePosition = .imageLeading
            button.toolTip = "Stop Recording (⌃⇧7)"
            button.target = self; button.action = #selector(stopRecording)
        } else {
            restoreIcons()
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Skreener")
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
        selfTimer.start(seconds: Preferences.selfTimerSeconds, completion: { [weak self] in self?.captureFullscreen() })
    }

    @objc func timedArea() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, _)? = sel else { self?.restoreIcons(); return }
                lastArea = (screen, rect)
                selfTimer.start(seconds: Preferences.selfTimerSeconds, completion: { [weak self] in
                    self?.run { try await CaptureService.captureScreen(screen, globalRect: rect) }
                }, cancelled: { [weak self] in self?.restoreIcons() })
            }
        }
    }

    @objc func timedWindow() {
        prepareCapture { [weak self] in
            Task { @MainActor in
                let wins = await CaptureService.onScreenWindows()
                self?.overlay.begin(mode: .window, windows: wins) { [weak self] sel in
                    guard let self, case .window(let w)? = sel else { self?.restoreIcons(); return }
                    selfTimer.start(seconds: Preferences.selfTimerSeconds, completion: { [weak self] in
                        self?.run { try await CaptureService.captureWindow(w) }
                    }, cancelled: { [weak self] in self?.restoreIcons() })
                }
            }
        }
    }

    @objc func captureText() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { self?.restoreIcons(); return }
                run(areaCapture(screen, rect, frozen), then: copyText)
            }
        }
    }

    /// Capture Text: OCR the image and copy what it says.
    private func copyText(_ image: NSImage) {
        Task { @MainActor in
            let text = await TextRecognizer.recognize(image)
            if text.isEmpty { NSSound.beep() } else { TextRecognizer.copyText(text); NSSound(named: "Pop")?.play() }
        }
    }

    @objc func captureArea() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in self?.handle(sel) }
        }
    }

    @objc func captureWindow() {
        prepareCapture { [weak self] in
            Task { @MainActor in
                let wins = await CaptureService.onScreenWindows()
                self?.overlay.begin(mode: .window, windows: wins) { [weak self] sel in self?.handle(sel) }
            }
        }
    }

    private func handle(_ sel: Selection?) {
        guard let sel else { restoreIcons(); return }
        switch sel {
        case .area(let screen, let rect, let frozen):
            lastArea = (screen, rect)
            run(areaCapture(screen, rect, frozen))
        case .window(let w): run { try await CaptureService.captureWindow(w) }
        }
    }

    /// Area capture for the editor's Add Image → Capture Area: no Quick Access, just the image (nil if cancelled).
    private func captureAreaImage(_ done: @escaping (NSImage?) -> Void) {
        // Give the hidden editor window a moment to leave the screen first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { done(nil); return }
            overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { done(nil); return }
                lastArea = (screen, rect)
                let capture = areaCapture(screen, rect, frozen)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000) // let overlay fade from the compositor
                    let image = try? await capture()
                    if let image { CaptureHistory.add(image) } else { NSSound.beep() }
                    done(image)
                }
            }
        }
    }

    /// Crops the frozen still when the screen was frozen during selection, otherwise grabs the live screen.
    private func areaCapture(_ screen: NSScreen, _ rect: CGRect, _ frozen: CGImage?) -> () async throws -> NSImage {
        if let frozen { return { try CaptureService.crop(frozen, screen: screen, globalRect: rect) } }
        return { try await CaptureService.captureScreen(screen, globalRect: rect) }
    }

    private func run(_ capture: @escaping () async throws -> NSImage, then: ((NSImage) -> Void)? = nil) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // let overlay fade from the compositor
            do {
                let image = try await capture()
                restoreIcons()
                (then ?? self.finish)(image)
            } catch {
                restoreIcons()
                NSLog("Capture failed: \(error)")
                NSSound.beep()
            }
        }
    }

    private func finish(_ image: NSImage) {
        CaptureHistory.add(image)
        if Preferences.copyToClipboard { Output.copy(image) }
        if Preferences.autoSave { Output.save(image) }
        // Area & Pin, Capture Text and the editor's own Add Image captures don't come through here.
        if Preferences.openEditorAfterCapture {
            EditorWindowController(image: image).present()
            return
        }
        let qa = QuickAccessController(image: image)
        qa.onAnnotate = { EditorWindowController(image: $0).present() }
        qa.onPin = { PinnedScreenshotController.pin($0) }
        QuickAccessController.live.append(qa)
        qa.show()
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
