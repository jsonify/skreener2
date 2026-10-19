import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = SelectionOverlay()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Skreener")
        statusItem.menu = buildMenu()

        let mods = controlKey | shiftKey
        HotKeys.shared.register(keyCode: kVK_ANSI_3, modifiers: mods) { [weak self] in self?.captureFullscreen() }
        HotKeys.shared.register(keyCode: kVK_ANSI_4, modifiers: mods) { [weak self] in self?.captureArea() }
        HotKeys.shared.register(keyCode: kVK_ANSI_5, modifiers: mods) { [weak self] in self?.captureWindow() }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ t: String, _ s: Selector, _ key: String = "") {
            let i = NSMenuItem(title: t, action: s, keyEquivalent: key)
            i.keyEquivalentModifierMask = [.control, .shift]; i.target = self; m.addItem(i)
        }
        add("Capture Area", #selector(captureArea), "4")
        add("Capture Fullscreen", #selector(captureFullscreen), "3")
        add("Capture Window", #selector(captureWindow), "5")
        m.addItem(.separator())
        let clip = NSMenuItem(title: "Copy to Clipboard", action: #selector(toggleClipboard(_:)), keyEquivalent: "")
        clip.target = self; clip.state = Preferences.copyToClipboard ? .on : .off; m.addItem(clip)
        let save = NSMenuItem(title: "Auto-save to Folder", action: #selector(toggleAutoSave(_:)), keyEquivalent: "")
        save.target = self; save.state = Preferences.autoSave ? .on : .off; m.addItem(save)
        let cur = NSMenuItem(title: "Show Cursor", action: #selector(toggleCursor(_:)), keyEquivalent: "")
        cur.target = self; cur.state = Preferences.showCursor ? .on : .off; m.addItem(cur)
        let folder = NSMenuItem(title: "Choose Save Folder…", action: #selector(chooseFolder), keyEquivalent: "")
        folder.target = self; m.addItem(folder)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Skreener", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc private func toggleClipboard(_ i: NSMenuItem) { Preferences.copyToClipboard.toggle(); i.state = Preferences.copyToClipboard ? .on : .off }
    @objc private func toggleAutoSave(_ i: NSMenuItem) { Preferences.autoSave.toggle(); i.state = Preferences.autoSave ? .on : .off }
    @objc private func toggleCursor(_ i: NSMenuItem) { Preferences.showCursor.toggle(); i.state = Preferences.showCursor ? .on : .off }
    @objc private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { Preferences.saveDirectory = u }
    }

    // MARK: Capture flows

    @objc func captureFullscreen() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        run { try await CaptureService.captureScreen(screen) }
    }

    @objc func captureArea() {
        overlay.begin(mode: .area, windows: []) { [weak self] sel in self?.handle(sel) }
    }

    @objc func captureWindow() {
        Task { @MainActor in
            let wins = await CaptureService.onScreenWindows()
            overlay.begin(mode: .window, windows: wins) { [weak self] sel in self?.handle(sel) }
        }
    }

    private func handle(_ sel: Selection?) {
        guard let sel else { return }
        switch sel {
        case .area(let screen, let rect): run { try await CaptureService.captureScreen(screen, globalRect: rect) }
        case .window(let w): run { try await CaptureService.captureWindow(w) }
        }
    }

    private func run(_ capture: @escaping () async throws -> NSImage) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // let overlay fade from the compositor
            do {
                let image = try await capture()
                finish(image)
            } catch {
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
        QuickAccessController.live.append(qa)
        qa.show()
    }
}
