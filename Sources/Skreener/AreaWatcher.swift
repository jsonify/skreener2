import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import UserNotifications

/// Watch This Area (#240): checks an area of the screen, or one window, every few seconds with a single-frame grab
/// (no stream stays open in between) and notifies when it changes or a text appears or disappears. One watch at a time.
final class AreaWatcher {
    enum Target {
        /// An area in global (bottom-left origin) coordinates on the display `displayID`.
        case area(displayID: CGDirectDisplayID, rect: CGRect)
        /// A window, grabbed on its own so it keeps working when other windows cover it.
        case window(id: CGWindowID, name: String)

        var noun: String {
            if case .window = self { return "window" }
            return "area"
        }
    }

    private(set) var target: Target?
    var isWatching: Bool { target != nil }
    /// Called with true when a watch starts and false when it ends.
    var onStateChange: ((Bool) -> Void)?
    private var task: Task<Void, Never>?
    private var session = 0

    /// What one check saw.
    private struct Frame {
        let image: CGImage
        let gray: [UInt8]
        let hasText: Bool?
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func start(_ target: Target, settings: WatchSettings) {
        stop()
        self.target = target
        session += 1
        let current = session
        onStateChange?(true)
        let every = settings.interval.title
        MessageHUD.show("Watching the \(target.noun)", detail: "Checks every \(every). Choose Stop Watching in the Skreener menu to stop.",
                        symbol: "eye", placement: .top)
        task = Task { @MainActor [weak self] in
            var grabber: CaptureService.AreaGrabber?
            var baseline: Frame?    // "before" for the change trigger: the first frame, or the one at the last notification
            var previous: Frame?    // the last check, "before" for the text triggers
            var blind = false       // already said it can't see the target
            var wait: UInt64 = 300_000_000   // the first check waits for the picker to leave the screen
            while true {
                try? await Task.sleep(nanoseconds: wait)
                wait = UInt64(settings.interval.rawValue) * 1_000_000_000
                guard !Task.isCancelled, self?.session == current else { return }
                var image: CGImage?
                switch target {
                case .area(let id, let rect):
                    guard let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == id }),
                          screen.frame.intersects(rect) else { grabber = nil; break }
                    if grabber == nil { grabber = try? await CaptureService.AreaGrabber(screen: screen, globalRect: rect) }
                    image = try? await grabber?.grab()
                    if image == nil { grabber = nil }   // set up again next time (the display may have changed)
                case .window(let id, let name):
                    switch await Self.grabWindow(id) {
                    case .image(let cg): image = cg
                    case .failed: break
                    case .gone:
                        guard let self, self.session == current else { return }
                        Self.post(title: "The watched window closed", body: "\(name) is no longer open, so Skreener stopped watching it.")
                        self.stop()
                        return
                    }
                }
                guard !Task.isCancelled, let self, self.session == current else { return }
                guard let image else {
                    if !blind { self.cantSee(target) }
                    blind = true
                    continue
                }
                blind = false
                var hasText: Bool?
                if settings.trigger.usesText {
                    let text = await TextRecognizer.recognize(NSImage(cgImage: image, size: .zero))
                    guard !Task.isCancelled, self.session == current else { return }
                    hasText = WatchMath.textFound(settings.needle, in: text)
                }
                let frame = Frame(image: image, gray: WatchMath.grayscale(image), hasText: hasText)
                defer { previous = frame }
                guard let base = baseline, let last = previous else {
                    baseline = frame
                    if settings.trigger == .textAppears, hasText == true {
                        MessageHUD.show("“\(settings.needle)” is already showing",
                                        detail: "Skreener notifies when it appears again.", symbol: "eye", placement: .top)
                    }
                    continue
                }
                let before: Frame
                switch settings.trigger {
                case .change:
                    guard WatchMath.changed(WatchMath.meanDifference(base.gray, frame.gray), sensitivity: settings.sensitivity)
                    else { continue }
                    before = base
                case .textAppears, .textDisappears:
                    guard let now = hasText, WatchMath.textFires(settings.trigger, wasPresent: last.hasText, isPresent: now)
                    else { continue }
                    before = last
                }
                Self.notify(settings.notificationTitle(watching: target.noun), before: before.image, after: frame.image,
                            stillWatching: settings.keepWatching)
                if settings.keepWatching { baseline = frame } else { self.stop(); return }
            }
        }
    }

    func stop() {
        guard target != nil else { return }
        session += 1
        task?.cancel()
        task = nil
        target = nil
        onStateChange?(false)
    }

    private func cantSee(_ target: Target) {
        let detail: String
        if !Permission.screenRecording.isGranted {
            detail = "Skreener needs the Screen Recording permission (System Settings → Privacy & Security)."
        } else if case .window = target {
            detail = "The window may be minimized or on a hidden Space."
        } else {
            detail = "Its display may be disconnected or asleep."
        }
        Self.post(title: "Skreener can't see the watched \(target.noun)",
                  body: detail + " Skreener keeps trying; choose Stop Watching in the menu to stop.")
    }

    // MARK: Window grabs

    private enum WindowGrab { case image(CGImage), failed, gone }

    /// One frame of the window `id` on its own (as if nothing covered it), without shadow or cursor.
    private static func grabWindow(_ id: CGWindowID) async -> WindowGrab {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return .failed }
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return .gone }
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(window.frame.width * scale))
        cfg.height = max(1, Int(window.frame.height * scale))
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        cfg.captureResolution = .best
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return .failed }
        return .image(cg)
    }

    // MARK: Notifications

    /// Keys of the notification's userInfo: the before and after files, which a click opens in the editor.
    static let beforeKey = "watchBefore", afterKey = "watchAfter"

    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Skreener Watch", isDirectory: true)
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Saves before and after and posts a notification with both side by side; a click opens them in the editor.
    private static func notify(_ title: String, before: CGImage, after: CGImage, stillWatching: Bool) {
        let dir = folder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = UUID().uuidString
        let beforeURL = dir.appendingPathComponent("\(stamp)-before.png")
        let afterURL = dir.appendingPathComponent("\(stamp)-after.png")
        guard writePNG(before, to: beforeURL), writePNG(after, to: afterURL) else {
            post(title: title, body: stillWatching ? "Still watching." : "The watch has ended.")
            return
        }
        var thumbnail: URL?
        if let both = WatchMath.sideBySide(before, after) {
            let url = dir.appendingPathComponent("\(stamp)-thumbnail.png")
            if writePNG(both, to: url) { thumbnail = url }
        }
        let body = "Before and after. Click to open them in the editor." + (stillWatching ? " Still watching." : "")
        post(title: title, body: body, before: beforeURL.path, after: afterURL.path, thumbnail: thumbnail)
        Sound.play("Glass")
    }

    /// A system notification; without notifications (denied, or not run from the .app) a Skreener message instead,
    /// with a button that opens before and after.
    private static func post(title: String, body: String, before: String? = nil, after: String? = nil, thumbnail: URL? = nil) {
        guard Notifier.canNotify else { showMessage(title: title, body: body, before: before, after: after); return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                await MainActor.run { showMessage(title: title, body: body, before: before, after: after) }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let before, let after { content.userInfo = [beforeKey: before, afterKey: after] }
            if let thumbnail, let attachment = try? UNNotificationAttachment(identifier: "thumbnail", url: thumbnail, options: nil) {
                content.attachments = [attachment]
            }
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private static func showMessage(title: String, body: String, before: String?, after: String?) {
        var button: (title: String, run: () -> Void)?
        if let before, let after { button = (title: "Open", run: { openComparison(before: before, after: after) }) }
        MessageHUD.show(title, detail: body, symbol: "eye", button: button, placement: .top)
    }

    /// Opens the before and after images as two editor tabs.
    static func openComparison(before: String, after: String) {
        let pairs = [("Before", before), ("After", after)]
        let images = pairs.compactMap { title, path in NSImage(contentsOfFile: path).map { (title, $0) } }
        guard images.count == 2 else {
            Notifier.problem("The before and after images are gone", detail: "macOS clears temporary files after a while.")
            return
        }
        for (title, image) in images { EditorWindowController(image: image, title: title).present() }
    }
}

/// The Watch This Area dialog (#240): what to watch, how often and what to notify about.
enum WatchSetup {
    enum Pick: Int, CaseIterable {
        case area, window, previousArea

        var title: String {
            switch self {
            case .area: return "An area (drag to select)"
            case .window: return "A window (keeps working when covered)"
            case .previousArea: return "The previous area"
            }
        }
    }

    /// The choice, or nil when cancelled. The options are remembered for next time.
    static func run(hasPreviousArea: Bool) -> (Pick, WatchSettings)? {
        let form = WatchForm(settings: .load(), hasPreviousArea: hasPreviousArea)
        let alert = NSAlert()
        alert.messageText = "Watch This Area"
        alert.informativeText = "Skreener checks it and notifies you, with a before and after picture, when it changes."
        alert.accessoryView = form.view
        alert.addButton(withTitle: "Choose…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            let settings = form.settings
            guard settings.isValid else {
                NSSound.beep()
                alert.informativeText = "Type the text to watch for."
                continue
            }
            settings.save()
            return (form.pick, settings)
        }
        return nil
    }
}

/// The controls of the Watch This Area dialog.
private final class WatchForm: NSObject {
    let view: NSView
    private let textField = NSTextField(string: "")
    private let pickPopup = NSPopUpButton()
    private let intervalPopup = NSPopUpButton()
    private let triggerPopup = NSPopUpButton()
    private let sensitivityPopup = NSPopUpButton()
    private let keepWatching = NSButton(checkboxWithTitle: "Keep watching after it notifies", target: nil, action: nil)

    init(settings: WatchSettings, hasPreviousArea: Bool) {
        let picks = WatchSetup.Pick.allCases.filter { $0 != .previousArea || hasPreviousArea }
        pickPopup.addItems(withTitles: picks.map(\.title))
        for (menuItem, pick) in zip(pickPopup.itemArray, picks) { menuItem.tag = pick.rawValue }
        intervalPopup.addItems(withTitles: WatchSettings.Interval.allCases.map(\.title))
        intervalPopup.selectItem(at: WatchSettings.Interval.allCases.firstIndex(of: settings.interval) ?? 0)
        triggerPopup.addItems(withTitles: WatchSettings.Trigger.allCases.map(\.title))
        triggerPopup.selectItem(at: WatchSettings.Trigger.allCases.firstIndex(of: settings.trigger) ?? 0)
        sensitivityPopup.addItems(withTitles: WatchSettings.Sensitivity.allCases.map(\.title))
        sensitivityPopup.selectItem(at: WatchSettings.Sensitivity.allCases.firstIndex(of: settings.sensitivity) ?? 0)
        textField.stringValue = settings.text
        textField.placeholderString = "e.g. Build succeeded"
        keepWatching.state = settings.keepWatching ? .on : .off
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Watch:"), pickPopup],
            [NSTextField(labelWithString: "Check every:"), intervalPopup],
            [NSTextField(labelWithString: "Notify when:"), triggerPopup],
            [NSTextField(labelWithString: "Text:"), textField],
            [NSTextField(labelWithString: "Sensitivity:"), sensitivityPopup],
            [NSGridCell.emptyContentView, keepWatching],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        textField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        grid.frame.size = grid.fittingSize
        view = grid
        super.init()
        triggerPopup.target = self
        triggerPopup.action = #selector(triggerChanged)
        triggerChanged()
    }

    @objc private func triggerChanged() {
        let text = WatchSettings.Trigger.allCases[max(0, triggerPopup.indexOfSelectedItem)].usesText
        textField.isEnabled = text
        sensitivityPopup.isEnabled = !text
    }

    var pick: WatchSetup.Pick { WatchSetup.Pick(rawValue: pickPopup.selectedTag()) ?? .area }

    var settings: WatchSettings {
        var s = WatchSettings()
        s.interval = WatchSettings.Interval.allCases[max(0, intervalPopup.indexOfSelectedItem)]
        s.trigger = WatchSettings.Trigger.allCases[max(0, triggerPopup.indexOfSelectedItem)]
        s.sensitivity = WatchSettings.Sensitivity.allCases[max(0, sensitivityPopup.indexOfSelectedItem)]
        s.text = textField.stringValue
        s.keepWatching = keepWatching.state == .on
        return s
    }
}
