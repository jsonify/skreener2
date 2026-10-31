import AppKit
import Carbon.HIToolbox

/// Shows a large countdown number in the middle of the screen, then calls `completion`.
/// Esc (from any app) or a click on the countdown cancels it and calls `cancelled` instead; nothing else stops it.
final class SelfTimer {
    private var panel: NSPanel?
    private var countdown: CountdownView?
    private var timer: Timer?
    private var deadline = Date()
    private var shown = 0
    private var escHotKey: UInt32?
    private var onCancel: (() -> Void)?
    private var activity: NSObjectProtocol?

    private static let cornerRadius: CGFloat = 22

    var isRunning: Bool { timer != nil }

    /// The whole seconds still to show at `now` for a countdown ending at `deadline` (0 once it's due).
    static func secondsLeft(until deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now) - 0.001)))
    }

    /// A running countdown keeps going: a second start is ignored rather than replacing it.
    func start(seconds: Int, completion: @escaping () -> Void, cancelled: (() -> Void)? = nil) {
        guard !isRunning else { NSSound.beep(); return }
        guard seconds > 0, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { completion(); return }
        deadline = Date().addingTimeInterval(TimeInterval(seconds))
        shown = seconds
        onCancel = cancelled
        let size = NSSize(width: 176, height: 168)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // Another app (or another capture tool) coming to the front must not hide the countdown.
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The SK-1 look (#344): seven-segment digits on the olive LCD in a chassis bezel, following the system's
        // appearance. The window shadow follows the drawn, rounded chassis.
        let bg = CountdownView(frame: NSRect(origin: .zero, size: size))
        bg.radius = Self.cornerRadius
        bg.value = seconds
        bg.onClick = { [weak self] in self?.cancel() }
        bg.onAppearanceChange = { [weak p] in p?.invalidateShadow() }
        p.contentView = bg
        p.orderFrontRegardless()
        p.display()
        p.invalidateShadow()
        panel = p; countdown = bg
        // A temporary global Esc hotkey works whichever app is in front, without Accessibility access.
        escHotKey = HotKeys.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.cancel() }
        // Keep App Nap from throttling the timer while Skreener is in the background.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                         reason: "Self-timer countdown")

        // Ticks often and reads the clock, so a late or skipped tick never stretches or stalls the countdown;
        // the common modes keep it firing while a menu is open or another capture tool tracks the mouse.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick(completion) }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        guard isRunning else { return }
        let c = onCancel
        stop()
        Sound.play("Funk")
        c?()
    }

    private func tick(_ completion: () -> Void) {
        let left = Self.secondsLeft(until: deadline, now: Date())
        guard left > 0 else { stop(); completion(); return }
        if left != shown { shown = left; countdown?.value = left }
        // Something may have ordered the panel out; put it back.
        if let panel, !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil; countdown = nil
        if let id = escHotKey { HotKeys.shared.unregister(id); escHotKey = nil }
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        onCancel = nil
    }
}

/// The countdown: a rounded chassis holding an LCD with the seconds left in big seven-segment digits, and
/// "Esc to cancel" under it. A click anywhere cancels.
private final class CountdownView: NSView {
    var onClick: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var radius: CGFloat = 22
    var value = 0 { didSet { if value != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Self-timer countdown. Esc to cancel")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }
    override func accessibilityValue() -> Any? { "\(value)" }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.drawPlate(bounds, radius: radius, palette: p, flipped: isFlipped)
        // From the top: a 14 pt margin, the LCD, then the caption in the bottom 34 pt.
        let captionBand: CGFloat = 34, side: CGFloat = 14
        let lcd = NSRect(x: bounds.minX + side, y: isFlipped ? bounds.minY + side : bounds.minY + captionBand,
                         width: bounds.width - side * 2, height: bounds.height - side - captionBand)
        let glass = Retro.drawLCD(in: lcd, radius: 12, inset: 5, palette: p, flipped: isFlipped)
        let text = SevenSegment.cells(value, count: max(String(value).count, 1))
        let digitHeight = min(72, glass.height - 18), spacing: CGFloat = 5
        let width = SevenSegment.textWidth(text, digitHeight: digitHeight, spacing: spacing)
        SevenSegment.draw(text, in: NSRect(x: glass.midX - width / 2, y: glass.midY - digitHeight / 2, width: width, height: digitHeight),
                          color: Retro.color(Retro.lcdInk), spacing: spacing, flipped: isFlipped)
        let caption = Retro.caption("Esc to cancel", color: Retro.color(p.inkSoft))
        let size = caption.size()
        let bandMid = isFlipped ? bounds.maxY - captionBand / 2 - 1 : bounds.minY + captionBand / 2 + 1
        caption.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bandMid - size.height / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onAppearanceChange?()
    }
}
