import AppKit
import UserNotifications

/// How Skreener says a capture is done when nothing else shows it (no editor, Quick Access preview or pin) (#113).
enum ConfirmationStyle: String, CaseIterable {
    case none, notification, hud

    var title: String {
        switch self {
        case .none: return "None"
        case .notification: return "System Notification"
        case .hud: return "Skreener Message"
        }
    }
}

/// Skreener's sounds (copied, recording saved, cancelled); Settings → After Capture can turn them off.
enum Sound {
    static func play(_ name: String) {
        if Preferences.playSounds { NSSound(named: name)?.play() }
    }
}

/// Confirmations after a capture (in the chosen `ConfirmationStyle`) and messages that explain why something didn't
/// work (always shown, as a `MessageHUD` near the pointer, #112).
enum Notifier {
    /// Says `title` (e.g. "Screenshot saved") in the chosen style. Clicking a system notification about a saved
    /// `file` shows it in Finder. Without permission for notifications it falls back to the Skreener message.
    static func confirm(_ title: String, detail: String? = nil, file: URL? = nil) {
        switch Preferences.confirmationStyle {
        case .none:
            return
        case .hud:
            MessageHUD.show(title, detail: detail, symbol: "checkmark.circle.fill", placement: .top)
        case .notification:
            guard canNotify else {
                MessageHUD.show(title, detail: detail, symbol: "checkmark.circle.fill", placement: .top)
                return
            }
            let path = file?.path
            Task {
                let center = UNUserNotificationCenter.current()
                // Asks the first time; afterwards it answers straight away with the user's choice.
                guard (try? await center.requestAuthorization(options: [.alert])) == true else {
                    await MainActor.run {
                        MessageHUD.show(title, detail: detail, symbol: "checkmark.circle.fill", placement: .top)
                    }
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                if let detail { content.body = detail }
                if let path {
                    if detail == nil { content.body = "Click to show it in Finder." }
                    content.userInfo = ["file": path]
                }
                try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }

    /// The result of a Compress action (#279), always shown (the user just asked for it): "1.2 MB → 310 KB", or that
    /// the file couldn't get any smaller. `name` is the file, or a count for several.
    static func compressed(_ savings: Compressor.Savings?, name: String) {
        if let savings {
            MessageHUD.show("Compressed", detail: "\(name)\n\(savings.summary)", symbol: "checkmark.circle.fill", placement: .top)
        } else {
            MessageHUD.show("Already as small as it gets", detail: name, symbol: "checkmark.circle.fill", placement: .top)
        }
    }

    /// Why something didn't work, near the pointer. `permission` adds a button that opens its Privacy pane.
    static func problem(_ title: String, detail: String? = nil, permission: Permission? = nil) {
        let button = permission.map { p in (title: "Open System Settings", run: { p.openSettings() }) }
        MessageHUD.show(title, detail: detail, symbol: "exclamationmark.triangle.fill", button: button, placement: .pointer)
    }

    /// A capture (or a recording: `what`) failed: explains a missing Screen Recording permission, or names the error.
    static func captureFailed(_ error: Error, what: String = "Capture") {
        if !Permission.screenRecording.isGranted {
            problem("Skreener needs permission to record the screen",
                    detail: "Turn on Skreener in System Settings → Privacy & Security → Screen Recording, then quit "
                        + "and reopen Skreener.",
                    permission: .screenRecording)
        } else {
            problem("\(what) failed", detail: error.localizedDescription)
        }
    }

    /// Notifications only work from the .app bundle (not `swift run`), where the notification center exists.
    static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private static let delegate = NotificationDelegate()

    /// Lets a click on a notification show its file. Called at launch, so a click after a relaunch works too.
    static func setUp() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Skreener is usually in the background, but show the banner when it isn't (e.g. with an editor open).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        // A Watch This Area notification opens its before and after pictures (#240).
        if let before = info[AreaWatcher.beforeKey] as? String, let after = info[AreaWatcher.afterKey] as? String {
            await MainActor.run { AreaWatcher.openComparison(before: before, after: after) }
            return
        }
        guard let path = info["file"] as? String else { return }
        let url = URL(fileURLWithPath: path)
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// A short message on the SK-1 chassis (the capture bars' style): near the pointer for problems, at the top
/// of the screen for confirmations. It fades after a few seconds; a click on it dismisses it. One at a time.
final class MessageHUD {
    enum Placement { case pointer, top }

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ title: String, detail: String? = nil, symbol: String, button: (title: String, run: () -> Void)? = nil,
                     placement: Placement) {
        dismiss()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }

        // The SK-1 look (#344): the symbol on a small LCD (an orange lamp beside it for a problem), the text in the
        // chassis' ink, on a rounded chassis that follows the system's appearance.
        let icon = HUDIcon(symbol: symbol, warning: placement == .pointer)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let text = NSStackView(views: [titleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let detailLabel = detail.map { detail in
            let d = NSTextField(wrappingLabelWithString: detail)
            d.font = .systemFont(ofSize: 12)
            d.preferredMaxLayoutWidth = 320
            return d
        }
        if let detailLabel { text.addArrangedSubview(detailLabel) }
        var views: [NSView] = [icon, text]
        if let button {
            let key = PillButton(title: button.title, symbol: nil, style: .keycap, height: 26) {
                button.run()
                MessageHUD.dismiss()
            }
            key.keyVariant = .orange
            views.append(key)
        }
        let row = NSStackView(views: views)
        row.spacing = 12
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 16)

        let bg = ChassisPlate(radius: 14, click: .run({ MessageHUD.dismiss() }))
        // The labels' ink follows the chassis' appearance.
        let ink = { [weak bg, weak titleLabel, weak detailLabel] in
            guard let bg else { return }
            let p = Retro.palette(dark: Retro.isDark(bg.effectiveAppearance))
            titleLabel?.textColor = Retro.color(p.ink)
            detailLabel?.textColor = Retro.color(p.inkSoft)
        }
        bg.onAppearanceChange = { [weak bg] in ink(); bg?.window?.invalidateShadow() }
        ink()
        row.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bg.leadingAnchor), row.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            row.topAnchor.constraint(equalTo: bg.topAnchor), row.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        let size = row.fittingSize

        let visible = screen.visibleFrame
        var origin: NSPoint
        switch placement {
        case .pointer: origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 24)
        case .top: origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        let p = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = bg
        p.alphaValue = 0
        p.orderFrontRegardless()
        // The shadow follows the rounded chassis once it has been drawn.
        p.display()
        p.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        panel = p

        let seconds: Double = button != nil ? 8 : detail != nil ? 4 : 2
        let work = DispatchWorkItem { MessageHUD.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    static func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func fadeOut() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            // A newer message may have replaced this one in the meantime.
            DispatchQueue.main.async { if MessageHUD.panel === p { MessageHUD.dismiss() } }
        })
    }
}

/// The toast's symbol on a small square of LCD glass in a bezel; for a problem, an orange lamp in its corner.
private final class HUDIcon: NSView {
    private let image: NSImage?
    private let warning: Bool
    private static let side: CGFloat = 34

    init(symbol: String, warning: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(.init(paletteColors: [Retro.color(Retro.lcdInk)]))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        self.warning = warning
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.side).isActive = true
        heightAnchor.constraint(equalToConstant: Self.side).isActive = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks go to the chassis, which dismisses the toast.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let outer = NSRect(x: 0, y: isFlipped ? 0 : 1, width: bounds.width, height: bounds.height - 1)
        let glass = Retro.drawLCD(in: outer, radius: 8, inset: 3, palette: p, flipped: isFlipped)
        if let image {
            let s = image.size
            image.draw(in: NSRect(x: glass.midX - s.width / 2, y: glass.midY - s.height / 2, width: s.width, height: s.height))
        }
        guard warning else { return }
        let lamp = NSRect(x: glass.maxX - 7, y: isFlipped ? glass.minY + 3 : glass.maxY - 7, width: 4, height: 4)
        Retro.drawLamp(in: lamp, color: Retro.color(Retro.orange), lit: true, glow: 3)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
