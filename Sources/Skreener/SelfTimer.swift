import AppKit

/// Shows a large countdown number in the middle of the screen, then calls `completion`.
final class SelfTimer {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var remaining = 0

    func start(seconds: Int, completion: @escaping () -> Void) {
        guard seconds > 0, let screen = NSScreen.main else { completion(); return }
        remaining = seconds
        let size = NSSize(width: 140, height: 140)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = 28; bg.layer?.masksToBounds = true
        let l = NSTextField(labelWithString: "\(remaining)")
        l.font = .systemFont(ofSize: 72, weight: .bold)
        l.alignment = .center
        l.frame = NSRect(x: 0, y: (size.height - 86) / 2, width: size.width, height: 86)
        bg.addSubview(l)
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p; label = l

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.remaining -= 1
            if self.remaining > 0 {
                self.label?.stringValue = "\(self.remaining)"
            } else {
                t.invalidate()
                self.panel?.orderOut(nil); self.panel = nil
                completion()
            }
        }
    }
}
