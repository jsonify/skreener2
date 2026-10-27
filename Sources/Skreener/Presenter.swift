import AppKit
import Carbon.HIToolbox

/// The zoom of one screen in presenter mode (#266): how far it is magnified and which part of the screen fills it.
/// Points are the overlay view's (bottom-left origin, the screen's size in points).
struct PresenterZoom: Equatable {
    static let range: ClosedRange<CGFloat> = 1...8
    /// ⌘+ / ⌘- multiply or divide the zoom by this.
    static let step: CGFloat = 1.5

    let size: CGSize
    private(set) var scale: CGFloat = 1
    /// The bottom-left corner of the part of the screen that shows, in screen points.
    private(set) var origin: CGPoint = .zero

    init(size: CGSize) { self.size = size }

    var isZoomed: Bool { scale > 1 }

    /// The part of the screen that fills the view.
    var visibleRect: CGRect {
        CGRect(origin: origin, size: CGSize(width: size.width / scale, height: size.height / scale))
    }

    /// Maps screen points to view points: what the overlay concatenates before drawing the still and the marks.
    var transform: CGAffineTransform {
        CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -origin.x, y: -origin.y)
    }

    /// The screen point that shows at view point `p`.
    func screenPoint(at p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x / scale, y: origin.y + p.y / scale) }

    /// Zooms to `newScale` (within `range`), keeping the screen point under view point `anchor` where it is. Close to
    /// 1 snaps to 1, so zooming out ends on the live screen rather than a barely magnified still.
    mutating func zoom(to newScale: CGFloat, anchor: CGPoint) {
        var s = min(max(newScale, Self.range.lowerBound), Self.range.upperBound)
        if s < 1.02 { s = 1 }
        let under = screenPoint(at: anchor)
        scale = s
        origin = clamped(CGPoint(x: under.x - anchor.x / s, y: under.y - anchor.y / s))
    }

    /// Pans with the pointer at view point `p`, ZoomIt-style: the screen point under the pointer is the one really
    /// there, so moving the pointer to an edge of the screen shows that edge.
    mutating func follow(_ p: CGPoint) {
        origin = clamped(CGPoint(x: p.x * (1 - 1 / scale), y: p.y * (1 - 1 / scale)))
    }

    mutating func reset() { scale = 1; origin = .zero }

    /// Keeps the visible part inside the screen.
    private func clamped(_ o: CGPoint) -> CGPoint {
        let w = size.width / scale, h = size.height / scale
        return CGPoint(x: min(max(o.x, 0), size.width - w), y: min(max(o.y, 0), size.height - h))
    }

    /// The zoom factor for a scroll: wheel away from you (or two fingers up) zooms in, whatever the natural scrolling
    /// setting. A wheel notch is a line, a trackpad reports points, hence the two rates (as in the editor).
    static func factor(scrollDelta d: CGFloat, inverted: Bool, precise: Bool) -> CGFloat {
        exp((inverted ? -d : d) * (precise ? 0.01 : 0.1))
    }
}

/// A mark drawn in presenter mode, in screen points (so it zooms with the still).
struct PresenterMark {
    enum Tool { case pen, arrow, rect }

    /// The colors on keys 1–5.
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white]
    /// Line width on screen, whatever the zoom when the mark was drawn.
    static let lineWidth: CGFloat = 4

    var tool: Tool
    /// The stroke for the pen; start and end for an arrow or a rectangle.
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat

    /// Whether the mark is worth keeping: an arrow or rectangle needs some length, a pen click leaves a dot.
    var isVisible: Bool {
        guard tool != .pen else { return !points.isEmpty }
        guard let a = points.first, let b = points.last else { return false }
        return hypot(b.x - a.x, b.y - a.y) >= width * 2
    }

    func draw() {
        guard let start = points.first, let end = points.last else { return }
        color.set()
        switch tool {
        case .pen:
            let path = StrokeShapes.smoothPath(points.count == 1 ? [start, start] : points)
            stroke(path)
        case .rect:
            stroke(NSBezierPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                             width: abs(end.x - start.x), height: abs(end.y - start.y))))
        case .arrow:
            let head = Self.arrowHead(from: start, to: end, length: width * 4.5)
            let line = NSBezierPath(); line.move(to: start); line.line(to: head.base)
            stroke(line)
            let tip = NSBezierPath()
            tip.move(to: end); tip.line(to: head.left); tip.line(to: head.right); tip.close()
            tip.fill()
        }
    }

    private func stroke(_ path: NSBezierPath) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// An arrowhead at `end`: its two back corners and the middle of its back, where the shaft stops (so the round cap
    /// doesn't poke through the tip). Short arrows get a smaller head, at most half their length.
    static func arrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat) -> (left: CGPoint, right: CGPoint, base: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y, len = hypot(dx, dy)
        guard len > 0 else { return (end, end, end) }
        let l = min(length, len / 2), ux = dx / len, uy = dy / len
        let base = CGPoint(x: end.x - ux * l, y: end.y - uy * l)
        let half = l * 0.55
        return (CGPoint(x: base.x - uy * half, y: base.y + ux * half), CGPoint(x: base.x + uy * half, y: base.y - ux * half), base)
    }
}

/// What a key does in presenter mode.
enum PresenterCommand: Equatable {
    case zoomIn, zoomOut, resetZoom, undo, escape
    case tool(PresenterMark.Tool)
    case color(Int)

    /// `command`: ⌘ is held. Zoom works with or without ⌘; undo needs it, so a stray Z does nothing.
    static func from(keyCode: Int, command: Bool) -> PresenterCommand? {
        switch keyCode {
        case kVK_Escape: return .escape
        case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus: return .zoomIn
        case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus: return .zoomOut
        case kVK_ANSI_0, kVK_ANSI_Keypad0: return .resetZoom
        case kVK_ANSI_Z: return command ? .undo : nil
        default: break
        }
        guard !command else { return nil }
        switch keyCode {
        case kVK_ANSI_P: return .tool(.pen)
        case kVK_ANSI_A: return .tool(.arrow)
        case kVK_ANSI_R: return .tool(.rect)
        case kVK_ANSI_1: return .color(0)
        case kVK_ANSI_2: return .color(1)
        case kVK_ANSI_3: return .color(2)
        case kVK_ANSI_4: return .color(3)
        case kVK_ANSI_5: return .color(4)
        default: return nil
        }
    }
}

private final class PresenterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Presenter mode (#266): a click-capturing overlay on every screen to draw on (pen, arrow, rectangle) and zoom into
/// around the pointer, for calls, screen shares and recordings. At 100% the overlay is clear and the live screen shows
/// through; zooming in magnifies a still of that screen taken at that moment. Unlike Skreener's other windows the
/// overlay is meant to be seen, so `onWindowsChange` lets an ongoing recording put it in the video.
final class PresenterOverlay {
    private var panels: [PresenterPanel] = []
    /// Screens that got a mark, oldest first, for ⌘Z across screens.
    private var markOrder: [PresenterView] = []
    fileprivate private(set) var tool = PresenterMark.Tool.pen
    fileprivate private(set) var color = PresenterMark.colors[0]
    private var hintTimer: Timer?

    var isActive: Bool { !panels.isEmpty }
    /// Called with the overlay's window numbers when it opens, and with [] when it closes.
    var onWindowsChange: (([CGWindowID]) -> Void)?

    fileprivate var windowIDs: [CGWindowID] { panels.map { CGWindowID($0.windowNumber) } }

    func toggle() { isActive ? close() : open() }

    func open() {
        guard panels.isEmpty else { return }
        tool = .pen; color = PresenterMark.colors[0]
        for screen in NSScreen.screens {
            let p = PresenterPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            p.level = .screenSaver
            p.animationBehavior = Preferences.windowAnimation
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            // Clear areas take the clicks too: everything goes to the drawing, nothing to the apps below.
            p.ignoresMouseEvents = false
            p.acceptsMouseMovedEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = PresenterView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.screen = screen
            v.owner = self
            p.contentView = v
            p.makeFirstResponder(v)
            p.orderFrontRegardless()
            panels.append(p)
        }
        // Keys go to the screen under the pointer, which also shows the hint.
        let front = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first
        if let front, let v = front.contentView as? PresenterView {
            front.makeKeyAndOrderFront(nil)
            front.makeFirstResponder(v)
            v.hint = "Draw: P pen · A arrow · R box · 1–5 color · Scroll or ⌘+ ⌘− zoom · ⌘Z undo · Esc clears, again leaves"
        }
        NSApp.activate(ignoringOtherApps: true)
        hintTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.hideHint() }
        onWindowsChange?(windowIDs)
    }

    func close() {
        guard !panels.isEmpty else { return }
        hintTimer?.invalidate(); hintTimer = nil
        let old = panels
        panels.removeAll()
        markOrder.removeAll()
        for p in old {
            (p.contentView as? PresenterView)?.owner = nil
            p.close()
        }
        // We may be inside one of these panels' event handlers; keep them alive until it returns.
        DispatchQueue.main.async { withExtendedLifetime(old) {} }
        onWindowsChange?([])
    }

    private var views: [PresenterView] { panels.compactMap { $0.contentView as? PresenterView } }

    private func hideHint() {
        hintTimer?.invalidate(); hintTimer = nil
        for v in views where v.hint != nil { v.hint = nil }
    }

    fileprivate func didStartMark() { hideHint() }

    fileprivate func didAddMark(in v: PresenterView) { markOrder.append(v) }

    /// The overlay on the screen under the pointer, and the pointer in its coordinates.
    private func viewUnderPointer() -> (view: PresenterView, point: CGPoint)? {
        let mouse = NSEvent.mouseLocation
        guard let p = panels.first(where: { $0.frame.contains(mouse) }) ?? panels.first,
              let v = p.contentView as? PresenterView else { return nil }
        return (v, v.convert(p.convertPoint(fromScreen: mouse), from: nil))
    }

    /// Handles a key; false leaves it to AppKit.
    fileprivate func handle(_ event: NSEvent) -> Bool {
        guard let command = PresenterCommand.from(keyCode: Int(event.keyCode),
                                                  command: event.modifierFlags.contains(.command)) else { return false }
        switch command {
        case .escape:
            // The first Esc clears the marks and the zoom, the next one (with nothing left) leaves.
            if views.contains(where: { $0.hasContent }) {
                views.forEach { $0.clear() }
                markOrder.removeAll()
            } else {
                close()
            }
        case .undo:
            markOrder.popLast()?.removeLastMark()
        case .zoomIn, .zoomOut:
            guard let hit = viewUnderPointer() else { break }
            hit.view.zoom(by: command == .zoomIn ? PresenterZoom.step : 1 / PresenterZoom.step, at: hit.point)
        case .resetZoom:
            viewUnderPointer()?.view.resetZoom()
        case .tool(let t):
            tool = t
        case .color(let i):
            color = PresenterMark.colors[i]
        }
        hideHint()
        return true
    }
}

/// One screen of the presenter overlay.
private final class PresenterView: NSView {
    weak var owner: PresenterOverlay?
    var screen: NSScreen!
    var hint: String? { didSet { needsDisplay = true } }

    private var marks: [PresenterMark] = []
    private var current: PresenterMark?
    private lazy var lens = PresenterZoom(size: bounds.size)
    /// The still the zoomed view magnifies (nil at 100%).
    private var still: CGImage?
    /// Zoom asked for while the still is being taken; applied once it arrives.
    private var pendingZoom: CGFloat?
    /// Drawing while zoomed holds the view still, so the marks stay under the pointer; zooming back out lets go.
    private var panLocked = false

    var hasContent: Bool { !marks.isEmpty || current != nil || lens.isZoomed || pendingZoom != nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    // MARK: Marks

    func clear() {
        marks.removeAll()
        current = nil
        resetZoom()
        needsDisplay = true
    }

    func removeLastMark() {
        guard !marks.isEmpty else { return }
        marks.removeLast()
        needsDisplay = true
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        owner.didStartMark()
        if lens.isZoomed { panLocked = true }
        let p = lens.screenPoint(at: point(event))
        current = PresenterMark(tool: owner.tool, points: [p], color: owner.color,
                                width: PresenterMark.lineWidth / lens.scale)
        if owner.tool != .pen { current?.points.append(p) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var m = current else { return }
        let p = lens.screenPoint(at: point(event))
        if m.tool == .pen {
            if m.points.last != p { m.points.append(p) }
        } else {
            m.points[m.points.count - 1] = p
        }
        current = m
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var m = current else { return }
        current = nil
        if m.tool == .pen { m.points = StrokeShapes.simplify(m.points, epsilon: 0.75 / lens.scale) }
        if m.isVisible {
            marks.append(m)
            owner?.didAddMark(in: self)
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard lens.isZoomed, !panLocked else { return }
        lens.follow(point(event))
        needsDisplay = true
    }

    // MARK: Zoom

    override func scrollWheel(with event: NSEvent) {
        let d = event.scrollingDeltaY
        guard d != 0, current == nil else { return }
        zoom(by: PresenterZoom.factor(scrollDelta: d, inverted: event.isDirectionInvertedFromDevice,
                                      precise: event.hasPreciseScrollingDeltas), at: point(event))
    }

    func zoom(by factor: CGFloat, at p: CGPoint) {
        if let pending = pendingZoom { pendingZoom = pending * factor; return }
        guard lens.isZoomed || factor > 1 else { return }
        guard lens.isZoomed else {
            // Zooming in from 100%: take a still of this screen as it is now (without the overlay), then magnify it.
            pendingZoom = factor
            freeze()
            return
        }
        lens.zoom(to: lens.scale * factor, anchor: p)
        if !lens.isZoomed { resetZoom() }
        needsDisplay = true
    }

    func resetZoom() {
        lens.reset()
        still = nil
        pendingZoom = nil
        panLocked = false
        needsDisplay = true
    }

    private func freeze() {
        let ids = owner?.windowIDs ?? []
        Task { @MainActor [weak self] in
            guard let screen = self?.screen else { return }
            let image: CGImage?
            do {
                image = try await CaptureService.captureScreenImage(screen, showsCursor: false, excludingWindows: ids)
            } catch {
                NSLog("Presenter zoom: couldn't capture the screen: \(error)")
                image = nil
            }
            self?.frozen(image)
        }
    }

    private func frozen(_ image: CGImage?) {
        // Esc or ⌘0 while the still was on its way: stay at 100%.
        guard let factor = pendingZoom, owner != nil else { return }
        pendingZoom = nil
        guard let image else { return }
        still = image
        let mouse = window.map { convert($0.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }
            ?? CGPoint(x: bounds.midX, y: bounds.midY)
        lens.zoom(to: lens.scale * factor, anchor: mouse)
        if !lens.isZoomed { resetZoom() } else if !panLocked { lens.follow(mouse) }
        needsDisplay = true
    }

    // MARK: Keys and drawing

    override func keyDown(with event: NSEvent) {
        if owner?.handle(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘Z and ⌘+ / ⌘−, before the main menu's Undo gets them.
        guard event.type == .keyDown, event.modifierFlags.contains(.command), let owner else {
            return super.performKeyEquivalent(with: event)
        }
        return owner.handle(event) || super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.concatenate(lens.transform)
        if lens.isZoomed, let still {
            ctx.interpolationQuality = .high
            ctx.draw(still, in: CGRect(origin: .zero, size: bounds.size))
        }
        for m in marks { m.draw() }
        current?.draw()
        ctx.restoreGState()
        if let hint { drawHintBanner(hint, centeredAt: NSPoint(x: bounds.midX, y: bounds.minY + 120)) }
    }
}
