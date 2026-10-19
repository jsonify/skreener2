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
        guard mode == .area else { show(snapshots: [:]); return }
        // Grab a clean frame of every display first so the magnifier can show real pixels (not the dim overlay).
        Task { @MainActor [weak self] in
            var snaps: [ObjectIdentifier: CGImage] = [:]
            for screen in NSScreen.screens {
                let img = try? await CaptureService.captureScreen(screen, showsCursor: false)
                if let cg = img?.cgImage(forProposedRect: nil, context: nil, hints: nil) { snaps[ObjectIdentifier(screen)] = cg }
            }
            self?.show(snapshots: snaps)
        }
    }

    private func show(snapshots: [ObjectIdentifier: CGImage]) {
        guard completion != nil else { return }
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
            v.snapshot = snapshots[ObjectIdentifier(screen)]
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
    var snapshot: CGImage?
    var onFinish: ((Selection?) -> Void)?

    private var cursorPoint: NSPoint?
    private var start: NSPoint?
    private var current: NSPoint?
    private var hoverWindow: SCWindow?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        let p = w.mouseLocationOutsideOfEventStream
        cursorPoint = bounds.contains(p) ? p : nil
    }

    override func mouseExited(with event: NSEvent) { cursorPoint = nil; needsDisplay = true }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursorPoint = p
        guard mode == .window else { needsDisplay = true; return }
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
        cursorPoint = current
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
        if mode == .area, let c = cursorPoint { drawCrosshair(at: c) }
        defer { if mode == .area, let c = cursorPoint { drawLoupe(at: c) } }
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

    private func drawCrosshair(at p: NSPoint) {
        let x = floor(p.x) + 0.5, y = floor(p.y) + 0.5
        for (color, width) in [(NSColor.black.withAlphaComponent(0.25), CGFloat(3)), (NSColor.white.withAlphaComponent(0.6), CGFloat(1))] {
            color.setStroke()
            let line = NSBezierPath(); line.lineWidth = width
            line.move(to: NSPoint(x: bounds.minX, y: y)); line.line(to: NSPoint(x: bounds.maxX, y: y))
            line.move(to: NSPoint(x: x, y: bounds.minY)); line.line(to: NSPoint(x: x, y: bounds.maxY))
            line.stroke()
        }
    }

    /// Pixel magnifier with the cursor's position (points, top-left origin) underneath.
    private func drawLoupe(at p: NSPoint) {
        guard let snap = snapshot, bounds.width > 0, bounds.height > 0 else { return }
        let cells = 15, zoom: CGFloat = 9, side = CGFloat(cells) * zoom, labelH: CGFloat = 22, gap: CGFloat = 26
        let sx = CGFloat(snap.width) / bounds.width, sy = CGFloat(snap.height) / bounds.height
        let ix = Int(floor(p.x * sx)), iy = Int(floor((bounds.height - p.y) * sy))
        // NSImage uses a bottom-left origin, so flip the row index.
        let src = NSRect(x: CGFloat(ix - cells / 2), y: CGFloat(snap.height - iy - 1 - cells / 2),
                         width: CGFloat(cells), height: CGFloat(cells))

        var box = NSRect(x: p.x + gap, y: p.y - gap - side - labelH, width: side, height: side + labelH)
        if box.maxX > bounds.maxX - 4 { box.origin.x = p.x - gap - side }
        if box.minY < 4 { box.origin.y = p.y + gap }
        let img = NSRect(x: box.minX, y: box.minY + labelH, width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        let shape = NSBezierPath(roundedRect: img, xRadius: 10, yRadius: 10)
        shape.addClip()
        NSColor.black.setFill(); img.fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: snap, size: NSSize(width: snap.width, height: snap.height))
            .draw(in: img, from: src, operation: .copy, fraction: 1)
        let cell = NSRect(x: img.midX - zoom / 2, y: img.midY - zoom / 2, width: zoom, height: zoom)
        NSColor.black.setStroke(); NSBezierPath(rect: cell.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.white.setStroke(); NSBezierPath(rect: cell).stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.setStroke(); shape.lineWidth = 2; shape.stroke()

        let label = "\(Int(p.x)), \(Int(bounds.height - p.y))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        let pill = NSRect(x: img.midX - (size.width + 12) / 2, y: box.minY, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
        label.draw(at: NSPoint(x: pill.minX + 6, y: pill.minY + 2), withAttributes: attrs)
    }
}
