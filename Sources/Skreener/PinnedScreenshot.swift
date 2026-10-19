import AppKit

private final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A borderless always-on-top window showing a screenshot. Drag to move, scroll to change opacity,
/// pinch/⌘+scroll to zoom, double-click or Esc to close.
final class PinnedScreenshotController: NSObject {
    private static var live: [PinnedScreenshotController] = []
    private var panel: PinnedPanel?

    static func pin(_ image: NSImage) {
        let c = PinnedScreenshotController()
        c.show(image)
        live.append(c)
    }

    private func show(_ image: NSImage) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxSize = NSSize(width: screen.visibleFrame.width * 0.6, height: screen.visibleFrame.height * 0.6)
        let fit = min(1, maxSize.width / max(image.size.width, 1), maxSize.height / max(image.size.height, 1))
        let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
        let p = PinnedPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false

        let v = PinnedView(frame: NSRect(origin: .zero, size: size))
        v.image = image
        v.onClose = { [weak self] in self?.close() }
        p.contentView = v
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
        panel = p
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        PinnedScreenshotController.live.removeAll { $0 === self }
    }
}

private final class PinnedView: NSView {
    var image: NSImage?
    var onClose: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let b = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); b.lineWidth = 1; b.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose?() } else { super.mouseDown(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window else { return }
        if event.modifierFlags.contains(.command) {
            resize(by: 1 + event.scrollingDeltaY * 0.01)
        } else {
            w.alphaValue = min(1, max(0.1, w.alphaValue + event.scrollingDeltaY * 0.01))
        }
    }

    override func magnify(with event: NSEvent) { resize(by: 1 + event.magnification) }

    private func resize(by factor: CGFloat) {
        guard let w = window else { return }
        let new = NSSize(width: max(60, w.frame.width * factor), height: max(60, w.frame.height * factor))
        let origin = NSPoint(x: w.frame.midX - new.width / 2, y: w.frame.midY - new.height / 2)
        w.setFrame(NSRect(origin: origin, size: new), display: true)
    }
}
