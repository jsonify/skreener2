import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = SelectionOverlay()
    private let selfTimer = SelfTimer()
    private var lastArea: (NSScreen, CGRect)?
    private var desktopIconsItem: NSMenuItem!
    private var iconsHiddenForCapture = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Skreener")
        statusItem.menu = buildMenu()

        let mods = controlKey | shiftKey
        HotKeys.shared.register(keyCode: kVK_ANSI_1, modifiers: mods) { [weak self] in self?.capturePreviousArea() }
        HotKeys.shared.register(keyCode: kVK_ANSI_2, modifiers: mods) { [weak self] in self?.captureText() }
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: mods) { [weak self] in self?.captureFullscreen() }
        HotKeys.shared.register(keyCode: kVK_ANSI_4, modifiers: mods) { [weak self] in self?.captureArea() }
        HotKeys.shared.register(keyCode: kVK_ANSI_5, modifiers: mods) { [weak self] in self?.captureWindow() }
        HotKeys.shared.register(keyCode: kVK_ANSI_6, modifiers: mods) { [weak self] in self?.captureAreaAndPin() }

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
        let timerItem = NSMenuItem(title: "Self-Timer Fullscreen", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for s in [3, 5, 10] {
            let i = NSMenuItem(title: "\(s) seconds", action: #selector(captureTimed(_:)), keyEquivalent: "")
            i.target = self; i.tag = s; timerMenu.addItem(i)
        }
        timerItem.submenu = timerMenu; m.addItem(timerItem)
        m.addItem(windowOptionsItem())
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
        let clip = NSMenuItem(title: "Copy to Clipboard", action: #selector(toggleClipboard(_:)), keyEquivalent: "")
        clip.target = self; clip.state = Preferences.copyToClipboard ? .on : .off; m.addItem(clip)
        let save = NSMenuItem(title: "Auto-save to Folder", action: #selector(toggleAutoSave(_:)), keyEquivalent: "")
        save.target = self; save.state = Preferences.autoSave ? .on : .off; m.addItem(save)
        let cur = NSMenuItem(title: "Show Cursor", action: #selector(toggleCursor(_:)), keyEquivalent: "")
        cur.target = self; cur.state = Preferences.showCursor ? .on : .off; m.addItem(cur)
        let freeze = NSMenuItem(title: "Freeze Screen While Selecting", action: #selector(toggleFreeze(_:)), keyEquivalent: "")
        freeze.target = self; freeze.state = Preferences.freezeScreen ? .on : .off; m.addItem(freeze)
        let icons = NSMenuItem(title: "Hide Desktop Icons While Capturing", action: #selector(toggleHideIcons(_:)), keyEquivalent: "")
        icons.target = self; icons.state = Preferences.hideIconsWhileCapturing ? .on : .off; m.addItem(icons)
        let folder = NSMenuItem(title: "Choose Save Folder…", action: #selector(chooseFolder), keyEquivalent: "")
        folder.target = self; m.addItem(folder)
        m.addItem(.separator())
        m.addItem(withTitle: "About Skreener", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        m.addItem(withTitle: "Quit Skreener", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc private func toggleClipboard(_ i: NSMenuItem) { Preferences.copyToClipboard.toggle(); i.state = Preferences.copyToClipboard ? .on : .off }
    @objc private func toggleAutoSave(_ i: NSMenuItem) { Preferences.autoSave.toggle(); i.state = Preferences.autoSave ? .on : .off }
    @objc private func toggleCursor(_ i: NSMenuItem) { Preferences.showCursor.toggle(); i.state = Preferences.showCursor ? .on : .off }
    @objc private func toggleFreeze(_ i: NSMenuItem) { Preferences.freezeScreen.toggle(); i.state = Preferences.freezeScreen ? .on : .off }
    @objc private func toggleHideIcons(_ i: NSMenuItem) {
        Preferences.hideIconsWhileCapturing.toggle(); i.state = Preferences.hideIconsWhileCapturing ? .on : .off
    }

    // MARK: Window capture options

    private func windowOptionsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Window Capture", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let shadow = NSMenuItem(title: "Shadow", action: #selector(toggleWindowShadow(_:)), keyEquivalent: "")
        shadow.target = self; shadow.state = Preferences.windowShadow ? .on : .off; menu.addItem(shadow)
        let clear = NSMenuItem(title: "Transparent Background", action: #selector(toggleWindowTransparent(_:)), keyEquivalent: "")
        clear.target = self; clear.state = Preferences.windowTransparentBackground ? .on : .off; menu.addItem(clear)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Padding", action: nil, keyEquivalent: "").isEnabled = false
        for pts in [0, 16, 32, 64] {
            let i = NSMenuItem(title: pts == 0 ? "None" : "\(pts) pt", action: #selector(pickWindowPadding(_:)), keyEquivalent: "")
            i.target = self; i.tag = pts; i.indentationLevel = 1
            i.state = Preferences.windowPadding == pts ? .on : .off
            menu.addItem(i)
        }
        item.submenu = menu
        return item
    }
    @objc private func toggleWindowShadow(_ i: NSMenuItem) { Preferences.windowShadow.toggle(); i.state = Preferences.windowShadow ? .on : .off }
    @objc private func toggleWindowTransparent(_ i: NSMenuItem) {
        Preferences.windowTransparentBackground.toggle(); i.state = Preferences.windowTransparentBackground ? .on : .off
    }
    @objc private func pickWindowPadding(_ i: NSMenuItem) {
        Preferences.windowPadding = i.tag
        i.menu?.items.filter { $0.action == #selector(pickWindowPadding(_:)) }.forEach { $0.state = $0.tag == i.tag ? .on : .off }
    }
    @objc private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { Preferences.saveDirectory = u }
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
                run(areaCapture(screen, rect, frozen)) { PinnedScreenshotController.pin($0) }
            }
        }
    }

    @objc func captureTimed(_ item: NSMenuItem) {
        selfTimer.start(seconds: item.tag) { [weak self] in self?.captureFullscreen() }
    }

    @objc func captureText() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in
                guard let self, case .area(let screen, let rect, let frozen)? = sel else { self?.restoreIcons(); return }
                run(areaCapture(screen, rect, frozen)) { image in
                    Task { @MainActor in
                        let text = await TextRecognizer.recognize(image)
                        if text.isEmpty { NSSound.beep() } else { TextRecognizer.copyText(text); NSSound(named: "Pop")?.play() }
                    }
                }
            }
        }
    }

    @objc func captureArea() {
        prepareCapture { [weak self] in
            self?.overlay.begin(mode: .area, windows: []) { [weak self] sel in self?.handle(sel) }
        }
    }

    @objc func captureWindow() {
        prepareCapture {
            Task { @MainActor [weak self] in
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
        if Preferences.copyToClipboard { Output.copy(image) }
        if Preferences.autoSave { Output.save(image) }
        let qa = QuickAccessController(image: image)
        qa.onAnnotate = { EditorWindowController(image: $0).present() }
        qa.onPin = { PinnedScreenshotController.pin($0) }
        QuickAccessController.live.append(qa)
        qa.show()
    }
}
