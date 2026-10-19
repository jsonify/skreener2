import AppKit

/// Floating thumbnail shown after a capture, with copy / save / annotate / close.
final class QuickAccessController {
    private var panel: NSPanel?
    private var timer: Timer?
    private var image: NSImage
    var onAnnotate: ((NSImage) -> Void)?
    var onPin: ((NSImage) -> Void)?

    init(image: NSImage) { self.image = image }

    func show() {
        let width: CGFloat = 220
        let aspect = image.size.height / max(image.size.width, 1)
        let thumbH = min(width * aspect, 160)
        let size = NSSize(width: width, height: thumbH + 40)
        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(x: screen.visibleFrame.minX + 16, y: screen.visibleFrame.minY + 16)
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = 12; bg.layer?.masksToBounds = true

        let iv = NSImageView(frame: NSRect(x: 8, y: 36, width: size.width - 16, height: thumbH - 4))
        iv.image = image; iv.imageScaling = .scaleProportionallyUpOrDown
        bg.addSubview(iv)

        let actions: [(String, Selector)] = [("Copy", #selector(copyIt)), ("Save", #selector(saveIt)),
                                             ("Edit", #selector(editIt)), ("Pin", #selector(pinIt)), ("✕", #selector(closeIt))]
        var x: CGFloat = 8
        for (title, sel) in actions {
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded; b.controlSize = .small
            b.frame = NSRect(x: x, y: 6, width: title == "✕" ? 28 : 40, height: 24)
            bg.addSubview(b); x += b.frame.width + 6
        }
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.closeIt() }
    }

    @objc private func copyIt() { Output.copy(image) }
    @objc private func saveIt() { Output.saveAs(image) }
    @objc private func pinIt() { onPin?(image); closeIt() }
    @objc private func editIt() { onAnnotate?(image); closeIt() }
    @objc func closeIt() {
        timer?.invalidate()
        panel?.orderOut(nil); panel = nil
        QuickAccessController.live.removeAll { $0 === self }
    }

    static var live: [QuickAccessController] = []
}
