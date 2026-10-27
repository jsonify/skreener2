import AppKit
import ApplicationServices

/// Click-highlight ring colors offered in the recording options.
enum ClickStyle {
    static let colors: [(String, NSColor)] = [("Yellow", .systemYellow), ("Red", .systemRed), ("Blue", .systemBlue),
                                              ("Green", .systemGreen), ("White", .white)]
    static var color: NSColor { colors.indices.contains(Preferences.clickHighlightColor) ? colors[Preferences.clickHighlightColor].1 : .systemYellow }
}

/// The cursor spotlight's pure parts: setting limits, coordinate conversion, the dim layout and the gradient.
enum Spotlight {
    /// Radius presets in points, and dim presets in percent, for the recording options.
    static let radii: [(String, Int)] = [("Small", 80), ("Medium", 120), ("Large", 180)]
    static let dims: [(String, Int)] = [("Light", 30), ("Medium", 50), ("Strong", 70)]
    static let radiusRange = 40...400
    static let dimRange = 10...90

    static func clampedRadius(_ r: Int) -> Int { min(max(r, radiusRange.lowerBound), radiusRange.upperBound) }
    static func clampedDim(_ percent: Int) -> Int { min(max(percent, dimRange.lowerBound), dimRange.upperBound) }

    /// A global point (bottom-left origin) in the overlay's own coordinates; it may lie outside the overlay.
    static func localPoint(global p: CGPoint, areaOrigin o: CGPoint) -> CGPoint { CGPoint(x: p.x - o.x, y: p.y - o.y) }

    /// The square that holds the soft circle around `center`.
    static func square(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// The rectangles of `bounds` outside `square`, which get a flat dim (they never overlap). The whole of
    /// `bounds` when the square is off it.
    static func surround(of square: CGRect, in bounds: CGRect) -> [CGRect] {
        let s = square.intersection(bounds)
        guard !s.isNull, s.width > 0, s.height > 0 else { return [bounds] }
        let rects = [
            CGRect(x: bounds.minX, y: bounds.minY, width: s.minX - bounds.minX, height: bounds.height),
            CGRect(x: s.maxX, y: bounds.minY, width: bounds.maxX - s.maxX, height: bounds.height),
            CGRect(x: s.minX, y: bounds.minY, width: s.width, height: s.minY - bounds.minY),
            CGRect(x: s.minX, y: s.maxY, width: s.width, height: bounds.maxY - s.maxY),
        ]
        return rects.filter { $0.width > 0 && $0.height > 0 }
    }

    /// Black alpha along the radius (0 = center, 1 = edge): clear in the middle, easing to the full dim.
    static func stops(dim: CGFloat) -> [(location: CGFloat, alpha: CGFloat)] {
        let d = min(max(dim, 0), 1)
        return [(0, 0), (0.65, 0), (0.85, d * 0.45), (1, d)]
    }
}

/// Accessibility access: keystroke display needs it to see key presses in other apps, auto-scroll to post scroll events.
enum AccessibilityAccess {
    static var granted: Bool { AXIsProcessTrusted() }
    /// Shows the system prompt (once per app identity) that leads to Privacy & Security → Accessibility.
    @discardableResult static func request() -> Bool {
        // "AXTrustedCheckOptionPrompt" is kAXTrustedCheckOptionPrompt's value; the constant is an unsafe C global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// A transparent, click-through window over the recorded area that draws click rings and the keystroke pill.
/// Unlike Skreener's other windows it is *included* in the recording, so the effects end up in the video.
final class RecordingEffects {
    private(set) var panel: NSPanel?
    private var view: EffectsView?
    private var monitors: [Any] = []
    private var moveMonitors: [Any] = []
    private(set) var spotlightOn = false

    /// Shows the overlay over `area` (global coordinates). It is always made, so the spotlight can be turned on
    /// mid-recording (its window has to be in the recording from the start).
    func start(area: CGRect, clicks: Bool, keys: Bool, spotlight: Bool) {
        let p = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = EffectsView(frame: NSRect(origin: .zero, size: area.size))
        p.contentView = v
        p.orderFrontRegardless()
        panel = p; view = v
        setSpotlight(spotlight)

        if clicks {
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.click() }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.click(); return e }) { monitors.append(m) }
        }
        if keys {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.key(e) }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.key(e); return e }) { monitors.append(m) }
        }
    }

    /// Turns the spotlight on or off. Does nothing while the overlay isn't showing.
    func setSpotlight(_ on: Bool) {
        guard view != nil else { return }
        spotlightOn = on
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors.removeAll()
        guard on else { view?.spotlight(at: nil); return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.moveSpotlight() }) { moveMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.moveSpotlight(); return e }) { moveMonitors.append(m) }
        moveSpotlight()
    }

    private func moveSpotlight() {
        guard let p = panel, spotlightOn else { return }
        view?.spotlight(at: Spotlight.localPoint(global: NSEvent.mouseLocation, areaOrigin: p.frame.origin))
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors.removeAll()
        spotlightOn = false
        panel?.orderOut(nil); panel = nil; view = nil
    }

    private func click() {
        guard let p = panel, let v = view else { return }
        let m = NSEvent.mouseLocation
        guard p.frame.contains(m) else { return }
        v.ring(at: NSPoint(x: m.x - p.frame.minX, y: m.y - p.frame.minY))
    }

    private func key(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.control, .option, .shift, .command])
        let isShortcut = !mods.intersection([.control, .option, .command]).isEmpty
        if Preferences.keystrokesOnlyShortcuts && !isShortcut { return }
        let name = Self.keyName(e)
        guard !name.isEmpty else { return }
        if isShortcut || mods == .shift && name.count > 1 {
            var s = ""
            if mods.contains(.control) { s += "⌃" }
            if mods.contains(.option) { s += "⌥" }
            if mods.contains(.shift) { s += "⇧" }
            if mods.contains(.command) { s += "⌘" }
            view?.show(s + name.uppercased(), append: false)
        } else {
            // Plain typing runs together in one pill until a pause.
            view?.show(mods.contains(.shift) ? name.uppercased() : name, append: name.count == 1)
        }
    }

    private static func keyName(_ e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case 36, 76: return "↩"
        case 48: return "⇥"
        case 49: return "␣"
        case 51: return "⌫"
        case 117: return "⌦"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return e.charactersIgnoringModifiers?.trimmingCharacters(in: .controlCharacters) ?? ""
        }
    }
}

private final class EffectsView: NSView {
    private let pill = NSTextField(labelWithString: "")
    private let pillBox = NSView()
    private var hideTimer: Timer?
    /// Behind everything else: four flat dim rectangles around a radial gradient that follows the pointer.
    private let spotlightRoot = CALayer()
    private let spotlightGlow = CAGradientLayer()
    private let spotlightFlat = (0..<4).map { _ in CALayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        spotlightRoot.frame = bounds
        spotlightRoot.isHidden = true
        spotlightGlow.type = .radial
        spotlightGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        spotlightGlow.endPoint = CGPoint(x: 1, y: 1)
        spotlightRoot.addSublayer(spotlightGlow)
        spotlightFlat.forEach(spotlightRoot.addSublayer)
        layer?.addSublayer(spotlightRoot)
        pillBox.wantsLayer = true
        pillBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        pillBox.layer?.cornerRadius = 10
        pillBox.isHidden = true
        pill.textColor = .white
        pill.alignment = .center
        pillBox.addSubview(pill)
        addSubview(pillBox)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Moves the spotlight to `p` (this view's coordinates), or hides it for nil.
    func spotlight(at p: NSPoint?) {
        guard let p else { spotlightRoot.isHidden = true; return }
        let radius = CGFloat(Spotlight.clampedRadius(Preferences.spotlightRadius))
        let dim = CGFloat(Spotlight.clampedDim(Preferences.spotlightDim)) / 100
        let square = Spotlight.square(center: p, radius: radius)
        let flats = Spotlight.surround(of: square, in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spotlightRoot.frame = bounds
        spotlightRoot.isHidden = false
        let black = NSColor.black
        spotlightGlow.frame = square
        let stops = Spotlight.stops(dim: dim)
        spotlightGlow.locations = stops.map { NSNumber(value: Double($0.location)) }
        spotlightGlow.colors = stops.map { black.withAlphaComponent($0.alpha).cgColor }
        for (i, l) in spotlightFlat.enumerated() {
            l.isHidden = i >= flats.count
            if i < flats.count { l.frame = flats[i]; l.backgroundColor = black.withAlphaComponent(dim).cgColor }
        }
        CATransaction.commit()
    }

    /// An expanding, fading ring.
    func ring(at p: NSPoint) {
        guard let root = layer else { return }
        let d = CGFloat(Preferences.clickHighlightSize)
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)
        let color = ClickStyle.color
        ring.fillColor = color.withAlphaComponent(0.3).cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 3
        root.addSublayer(ring)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4; scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.opacity = 0
        ring.add(group, forKey: "click")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ring.removeFromSuperlayer() }
    }

    /// Shows `text` in the pill (or adds it to what is showing), then hides it after a pause.
    func show(_ text: String, append: Bool) {
        let current = pillBox.isHidden ? "" : pill.stringValue
        var s = append ? current + text : text
        if s.count > 40 { s = String(s.suffix(40)) }
        pill.stringValue = s
        pill.font = .systemFont(ofSize: CGFloat(Preferences.keystrokeSize), weight: .semibold)
        pill.sizeToFit()
        let pad = CGFloat(Preferences.keystrokeSize) * 0.6
        let size = NSSize(width: pill.frame.width + pad * 2, height: pill.frame.height + pad)
        let y = Preferences.keystrokesAtTop ? bounds.maxY - size.height - 24 : 24
        pillBox.frame = NSRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
        pill.frame.origin = NSPoint(x: pad, y: pad / 2)
        pillBox.isHidden = false
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in self?.pillBox.isHidden = true }
    }
}
