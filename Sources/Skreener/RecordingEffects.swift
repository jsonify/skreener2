import AppKit
import ApplicationServices

/// Click-highlight ring colors offered in the recording options.
enum ClickStyle {
    static let colors: [(String, NSColor)] = [("Yellow", .systemYellow), ("Red", .systemRed), ("Blue", .systemBlue),
                                              ("Green", .systemGreen), ("White", .white)]
    static var color: NSColor { colors.indices.contains(Preferences.clickHighlightColor) ? colors[Preferences.clickHighlightColor].1 : .systemYellow }
}

/// Keystroke display needs Accessibility access to see key presses in other apps.
enum KeystrokeAccess {
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

    /// Shows the overlay over `area` (global coordinates). Nothing is shown when both effects are off.
    func start(area: CGRect, clicks: Bool, keys: Bool) {
        guard clicks || keys else { return }
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

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
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
