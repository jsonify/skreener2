import AppKit
import Carbon.HIToolbox

/// Shows a large countdown number in the middle of the screen, then calls `completion`.
/// Esc (from any app) or a click on the countdown cancels it and calls `cancelled` instead.
final class SelfTimer {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var remaining = 0
    private var escHotKey: UInt32?
    private var onCancel: (() -> Void)?

    var isRunning: Bool { timer != nil }

    func start(seconds: Int, completion: @escaping () -> Void, cancelled: (() -> Void)? = nil) {
        stop()
        guard seconds > 0, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { completion(); return }
        remaining = seconds
        onCancel = cancelled
        let size = NSSize(width: 160, height: 160)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let bg = CountdownView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = 28; bg.layer?.masksToBounds = true
        bg.onClick = { [weak self] in self?.cancel() }
        let l = NSTextField(labelWithString: "\(remaining)")
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
        panel = p; label = l
        // A temporary global Esc hotkey works whichever app is in front, without Accessibility access.
        escHotKey = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.cancel() }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remaining -= 1
            if self.remaining > 0 {
                self.label?.stringValue = "\(self.remaining)"
            } else {
                self.stop()
                completion()
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        let c = onCancel
        stop()
        NSSound(named: "Funk")?.play()
        c?()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        if let id = escHotKey { HotKeys.shared.unregister(id); escHotKey = nil }
        onCancel = nil
    }
}

private final class CountdownView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
