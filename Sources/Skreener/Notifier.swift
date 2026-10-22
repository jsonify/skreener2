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
    private static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

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
        guard let path = response.notification.request.content.userInfo["file"] as? String else { return }
        let url = URL(fileURLWithPath: path)
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// A short message on a dark capsule (the scrolling-capture bar's style): near the pointer for problems, at the top
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

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
        icon.contentTintColor = placement == .pointer ? .systemYellow : .systemGreen
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        let text = NSStackView(views: [titleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        if let detail {
            let d = NSTextField(wrappingLabelWithString: detail)
            d.font = .systemFont(ofSize: 12)
            d.textColor = NSColor.white.withAlphaComponent(0.75)
            d.preferredMaxLayoutWidth = 320
            text.addArrangedSubview(d)
        }
        var views: [NSView] = [icon, text]
        if let button {
            views.append(PillButton(title: button.title, symbol: nil, style: .tinted) {
                button.run()
                MessageHUD.dismiss()
            })
        }
        let row = NSStackView(views: views)
        row.spacing = 12
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let bg = HUDView()
        bg.onClick = { MessageHUD.dismiss() }
        bg.wantsLayer = true
        bg.layer?.backgroundColor = PillButton.barColor.cgColor
        bg.layer?.cornerRadius = 14
        bg.layer?.cornerCurve = .continuous
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = PillButton.barBorderColor.cgColor
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
        p.appearance = NSAppearance(named: .darkAqua)
        p.contentView = bg
        p.alphaValue = 0
        p.orderFrontRegardless()
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

private final class HUDView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
