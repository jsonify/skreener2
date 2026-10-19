import AppKit
import ScreenCaptureKit

enum Selection {
    case area(NSScreen, CGRect)   // global bottom-left coordinates
    case window(SCWindow)
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Full-screen dimmed overlay (one per display) for picking an area or a window.
final class SelectionOverlay {
    enum Mode { case area, window }
    private var panels: [OverlayPanel] = []
    private var completion: ((Selection?) -> Void)?
    private var windows: [SCWindow] = []
    private(set) var mode: Mode = .area

    func begin(mode: Mode, windows: [SCWindow], completion: @escaping (Selection?) -> Void) {
        self.mode = mode
        self.windows = windows
        self.completion = completion
        for screen in NSScreen.screens {
            let p = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.screen = screen
            v.mode = mode
            v.windows = windows
            v.onFinish = { [weak self] sel in self?.finish(sel) }
            p.contentView = v
            p.makeKeyAndOrderFront(nil)
            p.makeFirstResponder(v)
            panels.append(p)
        }
        NSCursor.crosshair.push()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ sel: Selection?) {
        NSCursor.pop()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        let c = completion; completion = nil
        c?(sel)
    }
}

private final class SelectionView: NSView {
    var screen: NSScreen!
    var mode: SelectionOverlay.Mode = .area
    var windows: [SCWindow] = []
    var onFinish: ((Selection?) -> Void)?

    private var start: NSPoint?
    private var current: NSPoint?
    private var hoverWindow: SCWindow?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private var selectionRect: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    /// SCWindow.frame is top-left origin in global space; convert to this view's coordinates.
    private func viewRect(for w: SCWindow) -> NSRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let globalBL = CGRect(x: w.frame.minX, y: primaryH - w.frame.maxY, width: w.frame.width, height: w.frame.height)
        return globalBL.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let p = convert(event.locationInWindow, from: nil)
        hoverWindow = windows.first { viewRect(for: $0).contains(p) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .window {
            if let w = hoverWindow { onFinish?(.window(w)) }
            return
        }
        start = convert(event.locationInWindow, from: nil)
        current = start
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area, let r = selectionRect, r.width > 3, r.height > 3 else { start = nil; current = nil; needsDisplay = true; return }
        onFinish?(.area(screen, r.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.35)
        let hole: NSRect? = mode == .area ? selectionRect : hoverWindow.map(viewRect(for:))
        let path = NSBezierPath(rect: bounds)
        if let h = hole { path.append(NSBezierPath(rect: h)); path.windingRule = .evenOdd }
        dim.setFill(); path.fill()
        guard let h = hole else { return }
        NSColor.white.setStroke()
        let b = NSBezierPath(rect: h); b.lineWidth = 1; b.stroke()
        if mode == .area {
            let label = "\(Int(h.width)) × \(Int(h.height))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                        .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            let box = NSRect(x: h.minX, y: max(h.minY - size.height - 8, 2), width: size.width + 10, height: size.height + 4)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            label.draw(at: NSPoint(x: box.minX + 5, y: box.minY + 2), withAttributes: attrs)
        }
    }
}
