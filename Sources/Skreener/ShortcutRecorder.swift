import AppKit
import Carbon.HIToolbox

/// Shortcut field, an LCD chip in the SK-1 look (#353) showing the shortcut ("Record Shortcut" when there is none). Click
/// it (or press Space with it focused) and type the new combination; Esc cancels, Delete clears. The × clears the
/// shortcut, or cancels while recording.
final class ShortcutRecorder: NSView {
    var combo: KeyCombo? { didSet { refresh() } }
    /// A combination was typed, or the shortcut cleared (nil). Return false to refuse it; recording then goes on.
    var onRecord: ((KeyCombo?) -> Bool)?
    /// Recording started (true) or ended (false).
    var onRecordingChange: ((Bool) -> Void)?
    private(set) var isRecording = false

    private static let size = NSSize(width: 160, height: 24)
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    /// Modifiers held while recording, shown before the key is pressed.
    private var held: NSEvent.ModifierFlags = []

    init(combo: KeyCombo?) {
        self.combo = combo
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true

        label.alignment = .center
        label.font = Retro.mono(11.5, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear Shortcut")
        clearButton.imagePosition = .imageOnly
        clearButton.isBordered = false
        clearButton.contentTintColor = Retro.color(Retro.lcdInk, alpha: 0.45)
        clearButton.refusesFirstResponder = true
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        [label, clearButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The chip's glass in a sunken bezel; while recording, ringed in glowing orange.
    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.drawWell(bounds.insetBy(dx: 0, dy: 0.5), radius: 6, top: Retro.color(p.bezelTop), bottom: Retro.color(p.bezelBottom),
                       shadow: 0.18, lip: p.wellLip, flipped: isFlipped)
        let glass = bounds.insetBy(dx: 2, dy: 2)
        Retro.drawChipGlass(glass, radius: 4, brightness: p.lcdBrightness, flipped: isFlipped)
        guard isRecording else { return }
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = Retro.color(Retro.orange)
        glow.shadowBlurRadius = 4
        glow.set()
        Retro.color(Retro.orange).setStroke()
        let ring = NSBezierPath(roundedRect: glass.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
        ring.lineWidth = 1.5
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func refresh() {
        let ink = Retro.color(Retro.lcdInk), faint = Retro.color(Retro.lcdInk, alpha: 0.55)
        if isRecording {
            label.stringValue = held.isEmpty ? "Type Shortcut…" : KeyCombo(keyCode: 0, flags: held).modifierSymbols
            label.textColor = faint
        } else if let combo {
            label.stringValue = combo.displayString
            label.textColor = ink
        } else {
            label.stringValue = "Record Shortcut"
            label.textColor = faint
        }
        clearButton.isHidden = !isRecording && combo == nil
        setAccessibilityLabel("Shortcut: \(combo?.displayString ?? "none")")
        needsDisplay = true
    }

    // MARK: Mouse

    /// Clicks anywhere but the × go to the field itself, not its label.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === clearButton ? clearButton : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording { finish() } else { startRecording() }
    }

    @objc private func clearClicked() {
        if isRecording { finish(); return }
        if onRecord?(nil) ?? true { combo = nil }
    }

    // MARK: Recording

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)),
                                                   name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    /// Switching to another app (or closing Settings) ends recording, so the global shortcuts come back.
    @objc private func windowResignedKey(_ notification: Notification) { finish() }

    private func startRecording() {
        guard !isRecording, window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        held = []
        refresh()
        onRecordingChange?(true)
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        held = []
        refresh()
        onRecordingChange?(false)
    }

    /// Ends recording and gives up focus, so later key presses go back to the window.
    private func finish() {
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        stopRecording()
    }

    // ⌘ and ⌃ combinations arrive as key equivalents (before the menus see them), the rest as key-downs.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            record(event)
        } else if Int(event.keyCode) == kVK_Space || Int(event.keyCode) == kVK_Return {
            startRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { super.flagsChanged(with: event); return }
        held = event.modifierFlags.intersection([.control, .option, .shift, .command])
        refresh()
    }

    private func record(_ event: NSEvent) {
        let code = Int(event.keyCode)
        let typed = KeyCombo(keyCode: code, flags: event.modifierFlags)
        if typed.modifiers == 0, code == kVK_Escape { finish(); return }
        let new: KeyCombo? = typed.modifiers == 0 && (code == kVK_Delete || code == kVK_ForwardDelete) ? nil : typed
        if onRecord?(new) ?? true {
            combo = new
            finish()
        } else {
            NSSound.beep()
        }
    }
}

private extension KeyCombo {
    var modifierSymbols: String { Self.symbols(for: modifiers) }
}

/// Settings → Shortcuts: a recorder per `HotKeyAction`, grouped like CleanShot X's (Screenshots, Screen Recording,
/// Other), a reset button beside any shortcut that differs from its default, and Restore Defaults at the bottom.
/// Warnings (taken by another action, a macOS shortcut, couldn't register) show under the recorder.
@MainActor final class ShortcutsPane: NSObject {
    private struct Row {
        let recorder: ShortcutRecorder
        let reset: NSButton
        let message: NSTextField
    }
    private var rows: [HotKeyAction: Row] = [:]
    /// The last refused recording, shown under its recorder until the next change.
    private var refusal: (action: HotKeyAction, message: String)?
    // "Use ⇧⌘3 and ⇧⌘4 for Skreener" (#114).
    private static let shiftCommand3 = KeyCombo(keyCode: kVK_ANSI_3, modifiers: shiftKey | cmdKey)
    private static let shiftCommand4 = KeyCombo(keyCode: kVK_ANSI_4, modifiers: shiftKey | cmdKey)
    private lazy var guideStatus = RetroLabel(text: "", tone: .ink, size: 12.5)
    private lazy var guideSteps = RetroUI.hint("""
        1. Click Open Keyboard Shortcuts (System Settings → Keyboard → Keyboard Shortcuts).
        2. Choose Screenshots and turn off “Save picture of screen as a file” (⇧⌘3) and “Save picture of selected \
        area as a file” (⇧⌘4).
        3. Come back here and click Use ⇧⌘3 and ⇧⌘4.
        """, size: 11, wraps: true)
    private lazy var assignButton = RetroUI.key("Use ⇧⌘3 and ⇧⌘4", target: self, action: #selector(assignMacShortcuts))

    /// The pane's groups; `group` and `row` are the Settings window's building blocks.
    func build(group: (String, [NSView], String?) -> NSView, row: (String, String?, NSView) -> NSView) -> [NSView] {
        var views = [group("Use ⇧⌘3 and ⇧⌘4 for Skreener", [guide()],
                           "Capture Fullscreen gets ⇧⌘3 and Capture Area ⇧⌘4. While macOS's own screenshot shortcuts are "
                           + "on, macOS gets those keys first.")]
        views += HotKeyAction.Section.allCases.map { section -> NSView in
            let actions = HotKeyAction.allCases.filter { $0.section == section }
            let note = section == .other
                ? "Shortcuts work in every app. Click a shortcut and press the new keys: Esc cancels, Delete clears." : nil
            return group(section.title, actions.map { row($0.title, $0.subtitle, control(for: $0)) }, note)
        }
        let restore = RetroUI.key("Restore Defaults", target: self, action: #selector(restoreDefaults))
        restore.translatesAutoresizingMaskIntoConstraints = false
        let footer = NSView()
        footer.addSubview(restore)
        NSLayoutConstraint.activate([
            restore.topAnchor.constraint(equalTo: footer.topAnchor),
            restore.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            restore.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
        ])
        views.append(footer)
        refresh()
        return views
    }

    /// Where the macOS shortcuts stand, the steps to turn them off (while they are on) and the buttons.
    private func guide() -> NSView {
        guideStatus.lineBreakMode = .byWordWrapping
        guideStatus.maximumNumberOfLines = 0
        guideStatus.cell?.wraps = true
        [guideStatus, guideSteps].forEach { $0.preferredMaxLayoutWidth = 500 }
        let open = RetroUI.key("Open Keyboard Shortcuts", target: self, action: #selector(openKeyboardShortcuts))
        let buttons = NSStackView(views: [open, assignButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [guideStatus, guideSteps, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        return stack
    }

    @objc private func openKeyboardShortcuts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts") {
            NSWorkspace.shared.open(url)
        }
    }

    /// ⇧⌘3 → Capture Fullscreen, ⇧⌘4 → Capture Area, taking them from any other action that has them.
    @objc private func assignMacShortcuts() {
        for (action, combo) in [(HotKeyAction.captureFullscreen, Self.shiftCommand3), (.captureArea, Self.shiftCommand4)] {
            if case .taken(let other)? = ShortcutStore.problem(with: combo, for: action, in: ShortcutStore.bindings()) {
                ShortcutCenter.shared.set(nil, for: other)
            }
            ShortcutCenter.shared.set(combo, for: action)
        }
        refusal = nil
        refresh()
    }

    /// Called when Settings comes to the front: the macOS shortcuts may have changed in System Settings meanwhile.
    func refreshMacShortcuts() { refresh() }

    private func refreshGuide(_ hotkeys: [String: Any]?, _ bindings: [HotKeyAction: KeyCombo]) {
        let macTakes = MacScreenshotShortcuts.takesShiftCommand3Or4(in: hotkeys)
        let assigned = bindings[.captureFullscreen] == Self.shiftCommand3 && bindings[.captureArea] == Self.shiftCommand4
        if macTakes {
            guideStatus.stringValue = assigned
                ? "Skreener has ⇧⌘3 and ⇧⌘4, but macOS still uses them for its own screenshots and gets them first."
                : "macOS uses ⇧⌘3 and ⇧⌘4 for its own screenshots."
        } else if assigned {
            guideStatus.stringValue = "⇧⌘3 and ⇧⌘4 start Skreener's Capture Fullscreen and Capture Area."
        } else {
            guideStatus.stringValue = "macOS's ⇧⌘3 and ⇧⌘4 are off. Click Use ⇧⌘3 and ⇧⌘4 to give them to Skreener."
        }
        guideSteps.isHidden = !macTakes
        assignButton.isEnabled = !assigned
    }

    /// Reset button, recorder and (when there is one) a warning under them.
    private func control(for action: HotKeyAction) -> NSView {
        let recorder = ShortcutRecorder(combo: ShortcutStore.combo(for: action))
        recorder.onRecord = { [weak self] combo in self?.record(combo, for: action) ?? false }
        recorder.onRecordingChange = { [weak self] recording in
            ShortcutCenter.shared.suspended = recording
            if recording { self?.refusal = nil }
            self?.refresh()
        }

        let reset = RetroUI.key(symbol: "arrow.counterclockwise",
                                tip: "Reset to default (\(action.defaultCombo?.displayString ?? "none"))",
                                height: RetroUI.textKeyHeight, target: self, action: #selector(resetClicked(_:)))
        reset.tag = HotKeyAction.allCases.firstIndex(of: action) ?? 0

        let message = NSTextField(wrappingLabelWithString: "")
        message.font = .systemFont(ofSize: 11)
        message.alignment = .right
        message.preferredMaxLayoutWidth = 260

        let line = NSStackView(views: [reset, recorder])
        line.spacing = 6
        let stack = NSStackView(views: [line, message])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 4
        rows[action] = Row(recorder: recorder, reset: reset, message: message)
        return stack
    }

    private func record(_ combo: KeyCombo?, for action: HotKeyAction) -> Bool {
        if let combo, let problem = ShortcutStore.problem(with: combo, for: action, in: ShortcutStore.bindings()) {
            refusal = (action, problem.message(for: combo))
            refresh()
            return false
        }
        refusal = nil
        ShortcutCenter.shared.set(combo, for: action)
        refresh()
        return true
    }

    @objc private func resetClicked(_ sender: NSButton) {
        let action = HotKeyAction.allCases[sender.tag]
        // The default may be in use by another action by now; it moves back here.
        if let combo = action.defaultCombo, case .taken(let other)? = ShortcutStore.problem(
            with: combo, for: action, in: ShortcutStore.bindings()) {
            ShortcutCenter.shared.set(nil, for: other)
        }
        refusal = nil
        ShortcutCenter.shared.set(action.defaultCombo, for: action)
        refresh()
    }

    @objc private func restoreDefaults() {
        refusal = nil
        ShortcutCenter.shared.restoreDefaults()
        refresh()
    }

    private func refresh() {
        let bindings = ShortcutStore.bindings()
        let hotkeys = MacScreenshotShortcuts.current()
        refreshGuide(hotkeys, bindings)
        for (action, row) in rows {
            let combo = bindings[action]
            row.recorder.combo = combo
            row.reset.isHidden = combo == action.defaultCombo
            var text: String?
            var color = Retro.color(Retro.orange)
            if let refusal, refusal.action == action {
                text = refusal.message
                color = Retro.color(Retro.recRed)
            } else if let combo, ShortcutCenter.shared.unavailable.contains(action) {
                text = "Couldn't register \(combo.displayString): another app may be using it."
                color = Retro.color(Retro.recRed)
            } else if let combo, !MacScreenshotShortcuts.isFree(combo, in: hotkeys) {
                text = combo.systemWarning
            }
            row.message.stringValue = text ?? ""
            row.message.textColor = color
            row.message.isHidden = text == nil
        }
    }
}
