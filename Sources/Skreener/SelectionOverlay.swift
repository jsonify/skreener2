import AppKit
import ScreenCaptureKit

/// CleanShot-style instruction pill ("Drag to record a part of the screen…"), drawn in the current view.
func drawHintBanner(_ text: String, centeredAt c: NSPoint) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .regular),
                                                .foregroundColor: NSColor.black.withAlphaComponent(0.85)]
    let s = text as NSString
    let size = s.size(withAttributes: attrs)
    let box = NSRect(x: c.x - size.width / 2 - 28, y: c.y - size.height / 2 - 18, width: size.width + 56, height: size.height + 36)
    NSColor.white.withAlphaComponent(0.88).setFill()
    NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
    s.draw(at: NSPoint(x: box.minX + 28, y: box.minY + 18), withAttributes: attrs)
}

enum Selection {
    case area(NSScreen, CGRect, frozen: CGImage?)   // global bottom-left coordinates; `frozen` = full-display still to crop from
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
    private var cursorPushed = false
    /// Banner text shown in the middle of every screen, per mode (nil = no banner). With both set, Space
    /// (before a drag starts) switches between picking an area and picking a window.
    private var hints: [Mode: String] = [:]
    /// The selection stays adjustable after the drag; Return or a double-click takes it (#102).
    private var adjustable = false

    /// `adjustable` keeps the dragged area on screen to refine it before it is taken (Settings → General).
    func begin(mode: Mode, windows: [SCWindow], hints: [Mode: String] = [:],
               adjustable: Bool = Preferences.adjustAreaBeforeCapture, completion: @escaping (Selection?) -> Void) {
        // One selection at a time: a second hotkey press while picking would stack another set of panels.
        guard self.completion == nil else { return }
        self.mode = mode
        self.windows = windows
        self.hints = hints
        self.adjustable = adjustable
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
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.screen = screen
            v.mode = mode
            v.windows = windows
            v.snapshot = snapshots[ObjectIdentifier(screen)]
            v.frozen = mode == .area && Preferences.freezeScreen && v.snapshot != nil
            v.onFinish = { [weak self] sel in self?.finish(sel) }
            v.adjustable = adjustable
            v.onSelectionStarted = { [weak self, weak v] in self?.selectionStarted(in: v) }
            v.keyHeldElsewhere = { [weak self, weak v] in self?.isAdjusting(besides: v) ?? false }
            v.hint = hints[mode]
            if hints.count == 2 { v.onToggleMode = { [weak self] in self?.toggleMode() } }
            p.contentView = v
            p.makeKeyAndOrderFront(nil)
            p.makeFirstResponder(v)
            panels.append(p)
        }
        // Keyboard (Space, arrows, Esc) goes to the display under the pointer.
        if let p = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            p.makeKeyAndOrderFront(nil)
        }
        SelectionView.cursor(for: mode).push(); cursorPushed = true
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A new selection on one screen replaces one waiting to be adjusted on another.
    private func selectionStarted(in view: SelectionView?) {
        for p in panels {
            guard let v = p.contentView as? SelectionView, v !== view else { continue }
            v.clearSelection()
        }
    }

    /// Whether a screen other than `view`'s holds a selection being adjusted (its keys stay with it).
    private func isAdjusting(besides view: SelectionView?) -> Bool {
        panels.contains { p in
            guard let v = p.contentView as? SelectionView, v !== view else { return false }
            return v.isAdjusting
        }
    }

    /// Space: area ⇄ window. The window list is fetched the first time it's needed.
    private func toggleMode() {
        let next: Mode = mode == .area ? .window : .area
        mode = next
        if cursorPushed { NSCursor.pop(); SelectionView.cursor(for: next).push() }
        let apply = { [weak self] in
            guard let self, completion != nil, mode == next else { return }
            for p in panels {
                guard let v = p.contentView as? SelectionView else { continue }
                v.windows = windows
                v.mode = next
                v.hint = hints[next]
                v.updateHoverWindow()
                v.needsDisplay = true
            }
        }
        guard next == .window, windows.isEmpty else { apply(); return }
        Task { @MainActor [weak self] in
            self?.windows = await CaptureService.onScreenWindows()
            apply()
        }
    }

    private func finish(_ sel: Selection?) {
        guard completion != nil else { return }
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        let old = panels
        panels.removeAll()
        for p in old {
            // Disarm the view first: a late mouseEntered used to re-order a dismissed panel to the
            // front, leaving an orphaned screen-saver-level overlay that nothing could remove.
            (p.contentView as? SelectionView)?.dismantle()
            p.close()
        }
        // We may be inside one of these panels' mouseUp; keep them alive until that returns.
        DispatchQueue.main.async { withExtendedLifetime(old) {} }
        let c = completion; completion = nil
        c?(sel)
    }
}

private final class SelectionView: NSView {
    /// The crosshair for areas, a camera for windows (#129).
    static func cursor(for mode: SelectionOverlay.Mode) -> NSCursor { mode == .window ? cameraCursor : .crosshair }

    /// A black camera with a white outline, so it shows on light and dark windows alike.
    static let cameraCursor: NSCursor = {
        let side: CGFloat = 26
        let symbol = { (color: NSColor) -> NSImage? in
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium).applying(.init(paletteColors: [color]))
            return NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Capture window")?.withSymbolConfiguration(config)
        }
        guard let outline = symbol(.white), let body = symbol(.black) else { return .crosshair }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let origin = NSPoint(x: (side - body.size.width) / 2, y: (side - body.size.height) / 2)
            for dx in [-1.5, 0, 1.5] as [CGFloat] {
                for dy in [-1.5, 0, 1.5] as [CGFloat] where dx != 0 || dy != 0 {
                    outline.draw(at: NSPoint(x: origin.x + dx, y: origin.y + dy), from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
            body.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }()

    var screen: NSScreen!
    var mode: SelectionOverlay.Mode = .area
    var windows: [SCWindow] = []
    var snapshot: CGImage? {
        didSet { snapshotImage = snapshot.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } }
    }
    /// Built once; wrapping the full-display frame on every mouse move made the loupe lag.
    private var snapshotImage: NSImage?
    /// Draw `snapshot` as a still background and hand it back for cropping.
    var frozen = false
    var onFinish: ((Selection?) -> Void)?
    /// Centered instruction banner, hidden while dragging.
    var hint: String?
    /// Set when Space (before a drag) switches between area and window picking.
    var onToggleMode: (() -> Void)?

    /// Keep the selection after the drag, adjustable, until Return or a double-click (#102).
    var adjustable = false
    /// Called when a new selection drag starts here, so other screens drop theirs.
    var onSelectionStarted: (() -> Void)?
    /// True while another screen holds a selection being adjusted: the pointer passing over this one mustn't take
    /// the keyboard from it.
    var keyHeldElsewhere: (() -> Bool)?

    private enum Drag { case new, move(NSPoint), resize(Int, NSRect) }
    private var cursorPoint: NSPoint?
    private var start: NSPoint?
    private var current: NSPoint?
    private var drag: Drag?
    /// The selection once the drag has ended, while it is being adjusted.
    private var adjusted: NSRect?
    private var hoverWindow: SCWindow?
    private var spaceDown = false
    private var dismantled = false
    /// Scrolling not yet applied: the selection changes by whole points.
    private var scrollRemainder: CGFloat = 0
    private static let grab: CGFloat = 8

    var isAdjusting: Bool { adjusted != nil }

    func clearSelection() {
        guard adjusted != nil || start != nil else { return }
        adjusted = nil; start = nil; current = nil; drag = nil
        needsDisplay = true
    }

    /// Called when the overlay closes: stops all further event handling and drawing.
    func dismantle() {
        dismantled = true
        onFinish = nil
        onSelectionStarted = nil
        keyHeldElsewhere = nil
        trackingAreas.forEach(removeTrackingArea)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard !dismantled else { return }
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    /// The rect being dragged out (Shift: square, ⌥: from the center), or the one being adjusted.
    private var selectionRect: NSRect? {
        if case .new? = drag, let s = start, let c = current {
            let mods = NSEvent.modifierFlags
            return SelectionGeometry.dragRect(from: s, to: c, square: mods.contains(.shift), fromCenter: mods.contains(.option), in: bounds)
        }
        return adjusted
    }

    /// Handle positions, counter-clockwise from bottom-left: corners at even indexes, edge midpoints at odd ones.
    private func handles(of r: NSRect) -> [NSPoint] {
        [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.midX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
         NSPoint(x: r.maxX, y: r.midY), NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.midX, y: r.maxY),
         NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.minX, y: r.midY)]
    }

    private func handle(at p: NSPoint, of r: NSRect) -> Int? {
        handles(of: r).firstIndex { abs($0.x - p.x) <= Self.grab && abs($0.y - p.y) <= Self.grab }
    }

    /// Resize arrows over the handles, an open hand inside the selection, the crosshair elsewhere.
    private func updateCursor(at p: NSPoint) {
        guard mode == .area, let r = adjusted, drag == nil else { return }
        if let i = handle(at: p, of: r) {
            (i % 2 == 0 ? NSCursor.crosshair : (i == 1 || i == 5 ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight)).set()
        } else if r.contains(p) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
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
        // Highlight the window under the pointer straight away, not only after the first mouse move.
        updateHoverWindow()
    }

    /// The frontmost window under the pointer: `windows` is in stacking order, front to back.
    func updateHoverWindow() {
        guard mode == .window else { hoverWindow = nil; return }
        hoverWindow = cursorPoint.flatMap { p in windows.first { viewRect(for: $0).contains(p) } }
    }

    override func mouseExited(with event: NSEvent) { cursorPoint = nil; hoverWindow = nil; needsDisplay = true }
    override func mouseEntered(with event: NSEvent) {
        guard !dismantled, window?.isVisible == true, keyHeldElsewhere?() != true else { return }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursorPoint = p
        updateCursor(at: p)
        guard mode == .window else { needsDisplay = true; return }
        // Re-assert the camera: another app's cursor rects can reset it while the pointer moves.
        Self.cameraCursor.set()
        let old = hoverWindow
        updateHoverWindow()
        if old?.windowID != hoverWindow?.windowID { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        // Only the primary button selects; mice can report other buttons through the primary-button events too.
        guard event.buttonNumber == 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if mode == .window {
            // Hit-test at the click itself: after Space switched modes there may have been no mouse move yet.
            if let w = windows.first(where: { viewRect(for: $0).contains(p) }) ?? hoverWindow { onFinish?(.window(w)) }
            return
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        if let r = adjusted {
            if event.clickCount >= 2, r.contains(p) { take(r); return }
            if let i = handle(at: p, of: r) { drag = .resize(i, r); return }
            if r.contains(p) {
                drag = .move(NSPoint(x: p.x - r.minX, y: p.y - r.minY))
                NSCursor.closedHand.set()
                return
            }
        }
        // Outside any selection: drag out a new one.
        adjusted = nil
        drag = .new
        start = p
        current = p
        onSelectionStarted?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursorPoint = p
        switch drag {
        case .move(let offset)?:
            if let r = adjusted {
                // Whole-point origin, same size: `integral` grew the selection by a point on fractional positions.
                let o = NSPoint(x: (p.x - offset.x).rounded(), y: (p.y - offset.y).rounded())
                adjusted = SelectionGeometry.move(r, to: o, in: bounds)
            }
        case .resize(let i, let r)?:
            let n = SelectionGeometry.resize(r, handle: i, to: p, in: bounds)
            let e = SelectionGeometry.rounded(n)
            if e.width >= 1, e.height >= 1 { adjusted = e }
        case .new?:
            // Holding Space moves the whole selection instead of resizing it.
            if spaceDown, let s = start, let c = current {
                start = NSPoint(x: s.x + p.x - c.x, y: s.y + p.y - c.y)
            }
            current = p
        case nil: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard case .new? = drag else {
            drag = nil
            updateCursor(at: convert(event.locationInWindow, from: nil))
            return
        }
        let rect = selectionRect
        drag = nil; start = nil; current = nil
        needsDisplay = true
        guard mode == .area, let r = rect, r.width > 3, r.height > 3 else { return }
        if adjustable {
            adjusted = SelectionGeometry.rounded(r)
            updateCursor(at: convert(event.locationInWindow, from: nil))
        } else {
            take(r)
        }
    }

    // The middle and other buttons do nothing here.
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}

    /// Wheel (or two-finger scroll) up grows every side of the selection being adjusted, down shrinks it.
    override func scrollWheel(with event: NSEvent) {
        guard mode == .area, let r = adjusted, drag == nil else { return }
        // Shift turns a mouse wheel into horizontal scrolling. Natural scrolling flips the sign; undo that so
        // up always grows.
        var d = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        if event.isDirectionInvertedFromDevice { d = -d }
        // A wheel notch is a line: two points per line; a trackpad reports points already.
        scrollRemainder += event.hasPreciseScrollingDeltas ? d : d * 2
        let step = scrollRemainder.rounded(.towardZero)
        guard step != 0 else { return }
        scrollRemainder -= step
        adjusted = SelectionGeometry.rounded(SelectionGeometry.resizeAllSides(r, by: step, in: bounds))
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        // Shift (square) and ⌥ (from the center) apply as soon as they are pressed or let go mid-drag.
        if case .new? = drag { needsDisplay = true }
        super.flagsChanged(with: event)
    }

    private func take(_ r: NSRect) {
        onFinish?(.area(screen, r.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), frozen: frozen ? snapshot : nil))
    }

    override func keyDown(with event: NSEvent) {
        if let r = adjusted, drag == nil {
            switch event.keyCode {
            case 53: onFinish?(nil)
            case 36, 76: take(r)
            case 49: break   // no switching to window picking with a selection on screen
            default:
                guard let key = SelectionGeometry.key(keyCode: event.keyCode) else {
                    super.keyDown(with: event); return
                }
                let mods = event.modifierFlags
                adjusted = SelectionGeometry.apply(key, command: mods.contains(.command), shift: mods.contains(.shift), to: r, in: bounds)
                needsDisplay = true
            }
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53: onFinish?(nil)
        case 49:
            if let toggle = onToggleMode, start == nil, !event.isARepeat { hoverWindow = nil; toggle() } else { spaceDown = true }
        case 123: nudgePointer(dx: -step, dy: 0)
        case 124: nudgePointer(dx: step, dy: 0)
        case 125: nudgePointer(dx: 0, dy: -step)
        case 126: nudgePointer(dx: 0, dy: step)
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown = false } else { super.keyUp(with: event) }
    }

    /// Arrow keys move the pointer (and the selection corner while dragging) one point at a time, ten with Shift.
    private func nudgePointer(dx: CGFloat, dy: CGFloat) {
        guard mode == .area, let w = window else { return }
        let from = cursorPoint ?? w.mouseLocationOutsideOfEventStream
        let p = NSPoint(x: min(max(from.x + dx, bounds.minX), bounds.maxX - 1),
                        y: min(max(from.y + dy, bounds.minY), bounds.maxY - 1))
        if spaceDown, let s = start, let c = current { start = NSPoint(x: s.x + p.x - c.x, y: s.y + p.y - c.y) }
        if start != nil { current = p }
        cursorPoint = p
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: screen.frame.minX + p.x, y: primaryH - (screen.frame.minY + p.y)))
        CGAssociateMouseAndMouseCursorPosition(1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if frozen, let snap = snapshot {
            NSGraphicsContext.current?.cgContext.draw(snap, in: bounds)
        }
        if mode == .window { drawWindowHighlight(); return }
        let dim = NSColor.black.withAlphaComponent(0.35)
        let hole: NSRect? = selectionRect
        let path = NSBezierPath(rect: bounds)
        if let h = hole { path.append(NSBezierPath(rect: h)); path.windingRule = .evenOdd }
        dim.setFill(); path.fill()
        // While a selection waits to be adjusted, the crosshair and loupe only show while dragging it.
        let pointerAids = mode == .area && (adjusted == nil || drag != nil)
        if pointerAids, let c = cursorPoint { drawCrosshair(at: c) }
        defer { if pointerAids, let c = cursorPoint { drawLoupe(at: c) } }
        if let hint, start == nil, adjusted == nil { drawHintBanner(hint, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY)) }
        guard let h = hole else { return }
        NSColor.white.setStroke()
        let b = NSBezierPath(rect: h); b.lineWidth = 1; b.stroke()
        // A new drag clears `adjusted`, so handles show only on a selection being adjusted.
        if adjusted != nil { drawHandles(around: h) }
        do {
            let dims = "\(Int(h.width)) × \(Int(h.height))"
            let label = (adjusted != nil && drag == nil ? dims + "   ↩ Capture · Esc Cancel" : dims) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                        .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            let box = NSRect(x: h.minX, y: max(h.minY - size.height - 8, 2), width: size.width + 10, height: size.height + 4)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            label.draw(at: NSPoint(x: box.minX + 5, y: box.minY + 2), withAttributes: attrs)
        }
    }

    /// Window picking (#129): the screen stays as it is; the window under the pointer gets a tint (blue unless Settings
    /// says otherwise) over its whole frame, also the parts other windows cover, so it's clear which window a click
    /// takes. Nothing is reordered: the window is captured on its own wherever it sits in the stack.
    private func drawWindowHighlight() {
        if let w = hoverWindow {
            let r = viewRect(for: w), tint = Preferences.windowHighlightColor
            tint.withAlphaComponent(0.28).setFill()
            r.fill()
            tint.withAlphaComponent(0.85).setStroke()
            let b = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1)); b.lineWidth = 2; b.stroke()
        }
        if let hint, hoverWindow == nil { drawHintBanner(hint, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY)) }
    }

    /// Small square handles on the corners and edge midpoints of the selection being adjusted.
    private func drawHandles(around r: NSRect) {
        for p in handles(of: r) {
            let box = NSRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            NSColor.white.setFill(); box.fill()
            NSColor.black.withAlphaComponent(0.5).setStroke(); NSBezierPath(rect: box).stroke()
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
        snapshotImage?.draw(in: img, from: src, operation: .copy, fraction: 1)
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
