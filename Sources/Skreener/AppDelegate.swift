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
