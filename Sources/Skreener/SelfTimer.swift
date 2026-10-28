import AppKit
import Carbon.HIToolbox

/// Shows a large countdown number in the middle of the screen, then calls `completion`.
/// Esc (from any app) or a click on the countdown cancels it and calls `cancelled` instead; nothing else stops it.
final class SelfTimer {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var deadline = Date()
    private var shown = 0
    private var escHotKey: UInt32?
    private var onCancel: (() -> Void)?
    private var activity: NSObjectProtocol?

    private static let cornerRadius: CGFloat = 28

    var isRunning: Bool { timer != nil }

    /// The whole seconds still to show at `now` for a countdown ending at `deadline` (0 once it's due).
    static func secondsLeft(until deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now) - 0.001)))
    }

    /// A running countdown keeps going: a second start is ignored rather than replacing it.
    func start(seconds: Int, completion: @escaping () -> Void, cancelled: (() -> Void)? = nil) {
        guard !isRunning else { NSSound.beep(); return }
        guard seconds > 0, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { completion(); return }
        deadline = Date().addingTimeInterval(TimeInterval(seconds))
        shown = seconds
        onCancel = cancelled
        let size = NSSize(width: 160, height: 160)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // Another app (or another capture tool) coming to the front must not hide the countdown.
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let bg = CountdownView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active
        // The blur is drawn by the window server, so a layer corner radius leaves its square corners showing;
        // a mask image rounds the blur itself, and the window shadow follows it.
        bg.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        bg.onClick = { [weak self] in self?.cancel() }
        let l = NSTextField(labelWithString: "\(seconds)")
        l.font = .monospacedDigitSystemFont(ofSize: 72, weight: .bold)
        l.alignment = .center
        l.frame = NSRect(x: 0, y: 46, width: size.width, height: 86)
        let hint = NSTextField(labelWithString: "Esc to cancel")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 18, width: size.width, height: 18)
        bg.addSubview(l); bg.addSubview(hint)
        p.contentView = bg
        p.orderFrontRegardless()
        p.invalidateShadow()
        panel = p; label = l
        // A temporary global Esc hotkey works whichever app is in front, without Accessibility access.
        escHotKey = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.cancel() }
        // Keep App Nap from throttling the timer while Skreener is in the background.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                         reason: "Self-timer countdown")

        // Ticks often and reads the clock, so a late or skipped tick never stretches or stalls the countdown;
        // the common modes keep it firing while a menu is open or another capture tool tracks the mouse.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick(completion) }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        guard isRunning else { return }
        let c = onCancel
        stop()
        Sound.play("Funk")
        c?()
    }

    private func tick(_ completion: () -> Void) {
        let left = Self.secondsLeft(until: deadline, now: Date())
        guard left > 0 else { stop(); completion(); return }
        if left != shown { shown = left; label?.stringValue = "\(left)" }
        // Something may have ordered the panel out; put it back.
        if let panel, !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        if let id = escHotKey { HotKeys.shared.unregister(id); escHotKey = nil }
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        onCancel = nil
    }

    /// A stretchable rounded-rectangle mask for an `NSVisualEffectView`.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private final class CountdownView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
