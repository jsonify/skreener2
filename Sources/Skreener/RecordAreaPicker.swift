import AppKit

/// What the user chose in the record-area picker.
enum RecordPick {
    case video(NSScreen, CGRect), gif(NSScreen, CGRect)        // global, bottom-left origin coordinates
    case screenshot(NSScreen, CGRect), text(NSScreen, CGRect), timer(NSScreen, CGRect)
    case scrolling(NSScreen, CGRect), livePin(NSScreen, CGRect)
    case fullscreenShot, window
    /// Space in the picker: pick a window to record instead.
    case selectWindow
}

/// The instruction shown on every screen while picking what to record.
let recordAreaHint = "Drag to record a part of the screen. Press Space to select a window."
/// The same for the all-in-one picker, where the action comes after the selection (#29).
let allInOneAreaHint = "Drag to select an area, then choose what to do with it. Press Space to select a window."

/// What opened the picker: Record Screen, or the all-in-one capture mode, which takes a screenshot on Return (#29).
enum PickerPurpose {
    case record, allInOne

    var areaHint: String { self == .allInOne ? allInOneAreaHint : recordAreaHint }
}

/// Another screen while the picker is open: dimmed, with the instruction banner. Dragging there starts a new
/// selection on that screen.
private final class OtherScreenView: NSView {
    var onSelect: ((NSRect) -> Void)?
    var hint = recordAreaHint
    private var start: NSPoint?
    private var current: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var dragRect: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); current = start }
    override func mouseDragged(with event: NSEvent) { current = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        let r = dragRect
        start = nil; current = nil; needsDisplay = true
        if let r, r.width >= 8, r.height >= 8 { onSelect?(r.integral) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let r = dragRect { path.append(NSBezierPath(rect: r)); path.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.4).setFill()
        path.fill()
        if let r = dragRect {
            NSColor.white.setStroke()
            NSBezierPath(rect: r).stroke()
        } else {
            drawHintBanner(hint, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        }
    }
}

private final class PickerPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { if onKey?(event) != true { super.keyDown(with: event) } }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// A vertical stack whose rows all take its full width.
private func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .vertical
    s.alignment = .leading
    s.spacing = spacing
    for v in views { v.widthAnchor.constraint(equalTo: s.widthAnchor, constant: -(s.edgeInsets.left + s.edgeInsets.right)).isActive = true }
    return s
}

/// Target for a control or menu item whose action is a closure (targets are held weakly, so keep these).
private final class Action: NSObject {
    let run: (Any?) -> Void
    init(_ run: @escaping (Any?) -> Void) { self.run = run }
    @objc func fire(_ sender: Any?) { run(sender) }
}

/// CleanShot-style picker shown once an area is chosen for Record Screen: the selection stays adjustable (drag
/// the handles or the inside, or drag outside for a new one) and a mode bar at the bottom of the screen offers
/// Area / Fullscreen / Window / Timer / OCR screenshots or Recording, next to the size fields. Recording (or
/// Return) shows the recording panel in the selection: options, audio and effect toggles, Record GIF ⌥↩ /
/// Record Video ↩. Esc cancels. The bar and the panel are SK-1 chassis plates with keys in trays (#344), following
/// the system's appearance.
final class RecordAreaPicker: NSObject {
    private var panel: PickerPanel?
    /// Dimmed panels with the instruction banner on the other screens.
    private var others: [NSPanel] = []
    private var adjust: AdjustView?
    private var controls: NSView?
    private var modeBar: NSView?
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private var toggles: [(PillButton, () -> Bool)] = []
    private var actions: [Action] = []
    private var popover: NSPopover?
    private var screen: NSScreen!
    private var completion: ((RecordPick?) -> Void)?
    private var purpose = PickerPurpose.record

    var isActive: Bool { completion != nil }

    /// `rect` is the starting selection in global coordinates on `screen`. `showHint` also shows the
    /// instruction banner on this screen (when the picker opens on a remembered area, with no drag first).
    func begin(screen: NSScreen, rect: CGRect, showHint: Bool = false, purpose: PickerPurpose = .record,
               completion: @escaping (RecordPick?) -> Void) {
        guard self.completion == nil else { return }
        self.screen = screen
        self.purpose = purpose
        actions.removeAll(); toggles.removeAll()

        let p = PickerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.animationBehavior = Preferences.windowAnimation
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.onKey = { [weak self] e in self?.key(e) ?? false }
        p.onCancel = { [weak self] in self?.finish(nil) }

        let v = AdjustView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.selection = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).intersection(v.bounds)
        v.onChange = { [weak self] in self?.layout() }
        v.onKey = { [weak self] e in self?.key(e) ?? false }
        v.hint = showHint ? purpose.areaHint : nil
        let c = buildControls()
        let bar = buildModeBar()
        v.addSubview(c); v.addSubview(bar)
        p.contentView = v
        c.isHidden = true
        panel = p; adjust = v; controls = c; modeBar = bar
        // Set last, so a failure while building the picker can't leave it marked active (which blocked
        // every later Record Screen).
        self.completion = completion
        layout()
        showOtherScreens()
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ pick: RecordPick?) {
        guard let done = completion else { return }
        completion = nil
        popover?.close(); popover = nil
        tearDown()
        done(pick)
    }

    private func tearDown() {
        let old = [panel].compactMap { $0 } + others
        old.forEach { $0.orderOut(nil) }
        panel = nil; adjust = nil; controls = nil; modeBar = nil; others = []
        // We may be inside one of these panels' event handlers; keep them alive until that returns.
        DispatchQueue.main.async { withExtendedLifetime(old) {} }
    }

    private func showOtherScreens() {
        for s in NSScreen.screens where s != screen {
            let p = NSPanel(contentRect: s.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.animationBehavior = Preferences.windowAnimation
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = OtherScreenView(frame: NSRect(origin: .zero, size: s.frame.size))
            v.hint = purpose.areaHint
            v.onSelect = { [weak self] r in self?.moveSelection(to: s, rect: r.offsetBy(dx: s.frame.minX, dy: s.frame.minY)) }
            p.contentView = v
            p.orderFrontRegardless()
            others.append(p)
        }
    }

    /// A new selection dragged on another screen: the picker moves there.
    private func moveSelection(to s: NSScreen, rect: CGRect) {
        guard let done = completion else { return }
        let wasRecording = controls?.isHidden == false
        completion = nil
        popover?.close(); popover = nil
        tearDown()
        begin(screen: s, rect: rect, purpose: purpose, completion: done)
        if wasRecording { showRecording() }
    }

    /// The selection in global coordinates.
    private var globalSelection: CGRect {
        (adjust?.selection ?? .zero).offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    private func key(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 53: finish(nil)
        case 49: finish(.selectWindow)
        case 36, 76:
            // All-in-one: Return takes the screenshot, unless Recording was picked first.
            if purpose == .allInOne, controls?.isHidden != false { finish(.screenshot(screen, globalSelection)); return true }
            // The first Return picks Recording (shows the panel); the next one starts it.
            guard controls?.isHidden == false else { showRecording(); return true }
            finish(e.modifierFlags.contains(.option) ? .gif(screen, globalSelection) : .video(screen, globalSelection))
        default: return false
        }
        return true
    }

    private var recordingButton: TileButton?

    /// Recording picked in the mode bar: highlight it and show the recording panel in the selection.
    private func showRecording() {
        guard let c = controls else { return }
        c.isHidden = false
        recordingButton?.isOn = true
        layout()
    }

    // MARK: Layout

    /// The panel goes inside the selection when it fits, else below, else above it; the mode bar sits at the bottom.
    private func layout() {
        guard let v = adjust, let c = controls, let bar = modeBar else { return }
        let sel = v.selection, size = c.fittingSize
        var origin: NSPoint
        if sel.width >= size.width + 24, sel.height >= size.height + 24 {
            origin = NSPoint(x: sel.midX - size.width / 2, y: sel.midY - size.height / 2)
        } else if sel.minY - size.height - 16 >= 0 {
            origin = NSPoint(x: sel.midX - size.width / 2, y: sel.minY - size.height - 16)
        } else if sel.maxY + size.height + 16 <= v.bounds.maxY - 30 {
            origin = NSPoint(x: sel.midX - size.width / 2, y: sel.maxY + 16)
        } else {
            origin = NSPoint(x: v.bounds.midX - size.width / 2, y: v.bounds.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, 8), v.bounds.maxX - size.width - 8)
        c.frame = NSRect(origin: origin, size: size)
        let barSize = bar.fittingSize
        let bottom = screen.visibleFrame.minY - screen.frame.minY
        bar.frame = NSRect(x: v.bounds.midX - barSize.width / 2, y: bottom + 24, width: barSize.width, height: barSize.height)
        guard sel.width.isFinite, sel.height.isFinite else { return }
        if widthField.currentEditor() == nil { widthField.integerValue = Int(sel.width.rounded()) }
        if heightField.currentEditor() == nil { heightField.integerValue = Int(sel.height.rounded()) }
    }

    // MARK: Controls

    private func bind(_ control: NSControl, _ run: @escaping (Any?) -> Void) {
        let a = Action(run)
        actions.append(a)
        control.target = a; control.action = #selector(Action.fire(_:))
    }

    private func menuItem(_ title: String, checked: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action { _ in run() }
        actions.append(a)
        let i = NSMenuItem(title: title, action: #selector(Action.fire(_:)), keyEquivalent: "")
        i.target = a
        i.state = checked ? .on : .off
        return i
    }

    /// `content` on a chassis plate. Clicks on bare chassis are swallowed: they must not start a selection drag
    /// underneath.
    private static func card(_ content: NSView, radius: CGFloat = 14) -> NSView {
        let card = RetroPlate(radius: radius, click: .swallow)
        card.translatesAutoresizingMaskIntoConstraints = false
        if radius > 0 {
            // It floats over the screen like a window, so it casts a shadow like one.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            card.shadow = shadow
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return card
    }

    /// A symbol-only SK-1 key; its action is set with `bind`.
    private static func iconButton(_ sym: String, _ tip: String, height: CGFloat = 30) -> PillButton {
        let b = PillButton(title: nil, symbol: sym, style: .keycap, height: height)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        return b
    }

    /// Width × height on LCD chips, whole screen and the aspect/size presets as keys: the right-hand plate of the
    /// mode bar.
    private func buildSizeControls() -> NSView {
        var boxes: [NSView] = []
        for f in [widthField, heightField] {
            f.alignment = .center
            f.widthAnchor.constraint(equalToConstant: 52).isActive = true
            bind(f) { [weak self] _ in self?.sizeTyped() }
            boxes.append(LCDFieldBox(f))
        }
        widthField.toolTip = "Width (points)"; heightField.toolTip = "Height (points)"
        widthField.setAccessibilityLabel("Width"); heightField.setAccessibilityLabel("Height")
        let times = RetroLabel(text: "×", tone: .soft, size: 13)
        let whole = Self.iconButton("arrow.up.left.and.arrow.down.right", "Whole screen")
        bind(whole) { [weak self] _ in self?.setSelection { _, bounds in bounds } }
        let presets = PillPopUp(pullsDown: true, height: 30, style: .keycap)
        presets.toolTip = "Aspect ratio and size presets"
        presets.setAccessibilityLabel("Presets")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))   // the pull-down's face
        for (title, ratio) in [("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("1:1", 1.0), ("9:16", 9.0 / 16)] {
            menu.addItem(menuItem(title) { [weak self] in
                self?.setSelection { sel, _ in
                    let h = sel.width / ratio
                    return NSRect(x: sel.minX, y: sel.midY - h / 2, width: sel.width, height: h)
                }
            })
        }
        menu.addItem(.separator())
        for (w, h) in [(1280, 720), (1920, 1080), (1080, 1080), (800, 600)] {
            menu.addItem(menuItem("\(w) × \(h)") { [weak self] in
                self?.setSelection { sel, _ in
                    NSRect(x: sel.midX - CGFloat(w) / 2, y: sel.midY - CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h))
                }
            })
        }
        presets.menu = menu
        presets.setContent(title: nil, symbol: "crop")
        let keys = KeycapTray([whole, presets])
        let row = NSStackView(views: [RetroLabel(caption: "Size"), boxes[0], times, boxes[1], keys])
        row.spacing = 6
        row.setCustomSpacing(10, after: boxes[1])
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 12)
        return row
    }

    /// The recording panel shown in the selection once Recording is picked: the Options key, the audio and effect
    /// toggles (orange squares, lit when on), then the Record GIF and Record Video keys (Video orange, the main
    /// action), each with its shortcut printed on it.
    private func buildControls() -> NSView {
        let options = Self.iconButton("slider.vertical.3", "Recording options", height: 34)
        bind(options) { [weak self] sender in self?.showOptions(sender as? NSView) }
        let micAvailable: Bool
        if #available(macOS 15.0, *) { micAvailable = true } else { micAvailable = false }
        let mic = toggle("Mic", micAvailable ? "Record microphone" : "Microphone recording needs macOS 15 or later", enabled: micAvailable,
                         get: { Preferences.recordMicrophone }, set: { Preferences.recordMicrophone = $0 })
        let audio = toggle("Audio", "Record system audio",
                           get: { Preferences.recordSystemAudio }, set: { Preferences.recordSystemAudio = $0 })
        let clicks = toggle("Clicks", "Highlight clicks",
                            get: { Preferences.recordHighlightClicks }, set: { Preferences.recordHighlightClicks = $0 })
        let keys = toggle("Keys", "Show keystrokes",
                          get: { Preferences.recordShowKeystrokes }, set: { [weak self] on in self?.setKeystrokes(on) })
        func pair(_ views: [NSView]) -> NSStackView {
            let s = NSStackView(views: views)
            s.orientation = .vertical
            s.alignment = .leading
            s.spacing = 6
            return s
        }
        let switches = NSStackView(views: [pair([mic, audio]), pair([clicks, keys])])
        switches.spacing = 22
        switches.alignment = .top
        let top = NSStackView(views: [KeycapTray([options], caption: "Options"), switches])
        top.spacing = 22
        top.alignment = .centerY

        let gif = PillButton(title: "Record GIF", symbol: "photo.stack", style: .keycap, height: 36) { [weak self] in
            guard let self else { return }
            finish(.gif(screen, globalSelection))
        }
        gif.legend = "⌥↩"
        gif.toolTip = "Record a GIF (⌥↩)"
        let video = PillButton(title: "Record Video", symbol: "video.fill", style: .keycap, height: 36) { [weak self] in
            guard let self else { return }
            finish(.video(screen, globalSelection))
        }
        video.keyVariant = .orange
        video.legend = "↩"
        video.toolTip = "Record a video (↩)"
        let record = KeycapTray([gif, video], caption: "Record", spacing: 5)

        let groove = Groove()
        let content = NSStackView(views: [top, groove, record])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        groove.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28).isActive = true

        let stack = column([Self.card(content)], spacing: 0)
        stack.widthAnchor.constraint(equalToConstant: 300).isActive = true
        refreshToggles()
        return stack
    }

    /// An SK-1 toggle for the recording panel; a click flips the setting.
    private func toggle(_ title: String, _ tip: String, enabled: Bool = true,
                        get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> PillButton {
        let b = PillButton(title: title, symbol: nil, style: .toggle, height: 22)
        b.toolTip = tip
        b.isEnabled = enabled
        bind(b) { [weak self] _ in set(!get()); self?.refreshToggles() }
        toggles.append((b, enabled ? get : { false }))
        return b
    }

    /// The toggles show the settings (which the options popover can change too).
    private func refreshToggles() {
        for (b, isOn) in toggles { b.isOn = isOn() }
    }

    /// Keystrokes need Accessibility access; ask for it when the option is turned on.
    private func setKeystrokes(_ on: Bool) {
        Preferences.recordShowKeystrokes = on
        if on && !AccessibilityAccess.granted { AccessibilityAccess.request() }
    }

    private func buildModeBar() -> NSView {
        let modes: [(String, String, RecordPick?)] = [
            ("viewfinder", "Area", nil), ("display", "Fullscreen", .fullscreenShot), ("macwindow", "Window", .window),
            ("arrow.down", "Scrolling", nil), ("timer", "Timer", nil), ("textformat", "OCR", nil),
            ("pip", "Live Pin", nil), ("video", "Recording", nil),
        ]
        var buttons: [TileButton] = []
        for (sym, title, pick) in modes {
            let b = TileButton(symbol: sym, title: title, width: 66)
            switch title {
            case "Area":
                b.toolTip = purpose == .allInOne ? "Screenshot of the selected area (↩)" : "Screenshot of the selected area"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.screenshot(screen, globalSelection)) }
            case "Timer":
                b.toolTip = "Screenshot of the selected area after a \(Preferences.selfTimerSeconds) s countdown"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.timer(screen, globalSelection)) }
            case "OCR":
                b.toolTip = "Copy the text in the selected area"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.text(screen, globalSelection)) }
            case "Scrolling":
                b.toolTip = "Scrolling capture of the selected area"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.scrolling(screen, globalSelection)) }
            case "Live Pin":
                b.toolTip = "Pin the selected area, updating as it changes"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.livePin(screen, globalSelection)) }
            case "Recording":
                b.toolTip = "Record the selected area (↩)"
                bind(b) { [weak self] _ in self?.showRecording() }
                recordingButton = b
            default:
                b.toolTip = title == "Window" ? "Screenshot of a window" : "Screenshot of the whole screen"
                bind(b) { [weak self] _ in self?.finish(pick) }
            }
            buttons.append(b)
        }
        // Three trays, split where CleanShot puts its dividers: the screenshots, text and pins, recording.
        let row = NSStackView(views: [KeycapTray(Array(buttons[0..<5]), caption: "Capture"),
                                      KeycapTray(Array(buttons[5..<7]), caption: "Text & Pin"),
                                      KeycapTray(Array(buttons[7...]), caption: "Record")])
        row.spacing = 10
        row.alignment = .top
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        row.setClippingResistancePriority(.required, for: .vertical)
        let modesCard = Self.card(row), sizeCard = Self.card(buildSizeControls())
        let bar = NSStackView(views: [modesCard, sizeCard])
        // Only once both cards are in the stack: a constraint between views with no common ancestor throws.
        sizeCard.heightAnchor.constraint(equalTo: modesCard.heightAnchor).isActive = true
        bar.spacing = 10
        bar.alignment = .centerY
        return bar
    }

    // MARK: Selection changes

    /// Applies `change` (given the selection and the screen bounds, local coordinates), kept on the screen.
    private func setSelection(_ change: (NSRect, NSRect) -> NSRect) {
        guard let v = adjust else { return }
        var r = change(v.selection, v.bounds).integral
        r.size.width = min(max(r.width, 8), v.bounds.width)
        r.size.height = min(max(r.height, 8), v.bounds.height)
        r.origin.x = min(max(r.minX, 0), v.bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, 0), v.bounds.maxY - r.height)
        v.selection = r
        panel?.makeFirstResponder(v)
    }

    /// Width/height typed in: the top-left corner stays put.
    private func sizeTyped() {
        let w = CGFloat(widthField.integerValue), h = CGFloat(heightField.integerValue)
        guard w > 0, h > 0 else { layout(); return }
        setSelection { sel, _ in NSRect(x: sel.minX, y: sel.maxY - h, width: w, height: h) }
    }

    // MARK: Options popover

    private func showOptions(_ anchor: NSView?) {
        guard let anchor else { return }
        if let p = popover, p.isShown { p.close(); return }
        let vc = NSViewController()
        let content = buildOptions()
        // Sized by its constraints; the popover takes the view's frame.
        content.frame = NSRect(origin: .zero, size: content.fittingSize)
        content.translatesAutoresizingMaskIntoConstraints = true
        vc.view = content
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        popover = p
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: p, queue: .main) { [weak self] _ in
            self?.refreshToggles()
        }
    }

    /// The options popover, on the SK-1 chassis: a caption over each group, an orange-square toggle per setting (with
    /// an Options key for its choices) and the frame rate as a segmented control.
    private func buildOptions() -> NSView {
        var views: [NSView] = []
        func header(_ title: String) {
            if !views.isEmpty { views.append(spacer(6)) }
            views.append(RetroLabel(caption: title, tone: .soft))
        }
        func row(_ title: String, _ get: () -> Bool, options: NSMenu? = nil, _ set: @escaping (Bool) -> Void) {
            let toggle = PillButton(title: title, symbol: nil, style: .toggle, height: 22)
            toggle.isOn = get()
            bind(toggle) { [weak self] sender in
                guard let b = sender as? PillButton else { return }
                b.isOn.toggle()
                set(b.isOn)
                self?.refreshToggles()
            }
            var parts: [NSView] = [toggle, NSView()]
            if let options {
                let b = PillPopUp(pullsDown: true, height: 22, style: .keycap)
                options.insertItem(NSMenuItem(title: "Options", action: nil, keyEquivalent: ""), at: 0)   // the face
                b.menu = options
                b.synchronizeTitleAndSelectedItem()
                b.toolTip = "\(title): options"
                parts.append(b)
            }
            let r = NSStackView(views: parts)
            r.spacing = 8
            r.alignment = .centerY
            views.append(r)
        }
        header("General")
        row("Show controls while recording", { Preferences.recordShowControls }) { Preferences.recordShowControls = $0 }
        row("Remember last selection", { Preferences.recordRememberSelection }) { Preferences.recordRememberSelection = $0 }
        row("Display recording time in menu bar", { Preferences.recordTimeInMenuBar }) { Preferences.recordTimeInMenuBar = $0 }
        row("Dim screen while recording", { Preferences.recordDimScreen }) { Preferences.recordDimScreen = $0 }
        row("Show countdown", { Preferences.recordCountdown }) { Preferences.recordCountdown = $0 }
        header("Cursor")
        row("Show cursor", { Preferences.recordShowsCursor }) { Preferences.recordShowsCursor = $0 }
        row("Highlight clicks", { Preferences.recordHighlightClicks }, options: clickOptions()) { Preferences.recordHighlightClicks = $0 }
        row("Cursor spotlight", { Preferences.recordSpotlight }, options: spotlightOptions()) { Preferences.recordSpotlight = $0 }
        header("Keystrokes")
        row("Show keystrokes", { Preferences.recordShowKeystrokes }, options: keystrokeOptions()) { [weak self] in self?.setKeystrokes($0) }
        header("Video")
        let fps = RetroSegmented(caption: "Frame rate", height: 22)
        for rate in [30, 60] { fps.addItem("\(rate) fps", tag: rate, help: "\(rate) frames per second") }
        fps.selectItem(withTag: Preferences.recordFrameRate)
        let fpsAction = Action { Preferences.recordFrameRate = ($0 as? RetroSegmented)?.selectedTag() ?? 30 }
        actions.append(fpsAction)
        fps.target = fpsAction
        fps.action = #selector(Action.fire(_:))
        let fpsRow = NSStackView(views: [fps, NSView()])
        views.append(fpsRow)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        for v in views { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true }
        stack.widthAnchor.constraint(equalToConstant: 360).isActive = true
        // A square plate: the popover rounds its own edge.
        return Self.card(stack, radius: 0)
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    private func clickOptions() -> NSMenu {
        let m = NSMenu()
        for (i, (name, _)) in ClickStyle.colors.enumerated() {
            m.addItem(menuItem(name, checked: Preferences.clickHighlightColor == i) { Preferences.clickHighlightColor = i })
        }
        m.addItem(.separator())
        for (name, size) in [("Small", 32), ("Medium", 48), ("Large", 64)] {
            m.addItem(menuItem(name, checked: Preferences.clickHighlightSize == size) { Preferences.clickHighlightSize = size })
        }
        return m
    }

    private func spotlightOptions() -> NSMenu {
        let m = NSMenu()
        for (name, r) in Spotlight.radii {
            m.addItem(menuItem(name + " Circle", checked: Preferences.spotlightRadius == r) { Preferences.spotlightRadius = r })
        }
        m.addItem(.separator())
        for (name, pct) in Spotlight.dims {
            m.addItem(menuItem(name + " Dim", checked: Preferences.spotlightDim == pct) { Preferences.spotlightDim = pct })
        }
        return m
    }

    private func keystrokeOptions() -> NSMenu {
        let m = NSMenu()
        m.addItem(menuItem("All Keys", checked: !Preferences.keystrokesOnlyShortcuts) { Preferences.keystrokesOnlyShortcuts = false })
        m.addItem(menuItem("Only Shortcuts (⌘ ⌃ ⌥)", checked: Preferences.keystrokesOnlyShortcuts) { Preferences.keystrokesOnlyShortcuts = true })
        m.addItem(.separator())
        for (name, size) in [("Small Text", 18), ("Medium Text", 24), ("Large Text", 32)] {
            m.addItem(menuItem(name, checked: Preferences.keystrokeSize == size) { Preferences.keystrokeSize = size })
        }
        m.addItem(.separator())
        m.addItem(menuItem("Bottom of Area", checked: !Preferences.keystrokesAtTop) { Preferences.keystrokesAtTop = false })
        m.addItem(menuItem("Top of Area", checked: Preferences.keystrokesAtTop) { Preferences.keystrokesAtTop = true })
        return m
    }
}

/// An SK-1 key with a symbol above a short title in small capitals: the picker's mode bar. The symbol and title are
/// laid out here rather than by the button cell, which clips an image placed above a title in a fixed-height button.
/// It goes down while pressed, and stays down with the orange light while `isOn` (the chosen mode).
private final class TileButton: NSButton {
    static let height: CGFloat = 50
    private static let radius: CGFloat = 7
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let tileTitle: String
    private var contentCenterY: NSLayoutConstraint?
    private var pressed = false { didSet { refresh() } }

    var isOn = false { didSet { refresh() } }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.4; refresh() }
    }

    init(symbol: String, title: String, width: CGFloat) {
        tileTitle = title
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        wantsLayer = true
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.imageScaling = .scaleNone
        label.alignment = .center
        label.lineBreakMode = .byClipping
        let content = NSStackView(views: [icon, label])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        translatesAutoresizingMaskIntoConstraints = false
        let centerY = content.centerYAnchor.constraint(equalTo: centerYAnchor)
        contentCenterY = centerY
        NSLayoutConstraint.activate([
            // A fixed symbol box, so titles line up whatever each symbol's shape.
            icon.heightAnchor.constraint(equalToConstant: 20),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerY,
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        setAccessibilityLabel(title)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Clicks on the symbol or title belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        super.mouseDown(with: event)   // tracks the click until the button is released
        pressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = Retro.keyColors(.cream, Retro.palette(for: self))
        let face = Retro.drawKey(in: bounds, radius: Self.radius, colors: colors, down: isOn || pressed,
                                 skirt: PillButton.keycapSkirt, flipped: isFlipped)
        if isOn { Retro.drawOnBar(in: face, flipped: isFlipped) }
    }

    override func layout() {
        super.layout()
        updateShadow()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    /// The ink, where the content sits (on the face, sinking with it) and the shadow the key casts.
    private func refresh() {
        needsDisplay = true
        let p = Retro.palette(for: self)
        let ink = Retro.keyColors(.cream, p).ink
        icon.contentTintColor = ink
        label.attributedStringValue = Retro.caption(tileTitle, color: ink, kern: 0.6)
        let down = isOn || pressed
        // Clear of the orange light at the bottom of the face.
        contentCenterY?.constant = down ? 0 : -2
        updateShadow()
    }

    private func updateShadow() {
        let p = Retro.palette(for: self)
        let down = isOn || pressed
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = Float(p.keyShadow) * (down ? 1.3 : 1)
        layer?.shadowRadius = down ? 1 : 2
        layer?.shadowOffset = CGSize(width: 0, height: down ? -1 : -2)
        let rect = down ? bounds.insetBy(dx: 0, dy: PillButton.keycapSkirt / 2) : bounds
        guard rect.width > 1, rect.height > 1 else { layer?.shadowPath = nil; return }
        let r = min(Self.radius, rect.width / 2, rect.height / 2)
        layer?.shadowPath = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }
}

/// A groove in the chassis between two groups of controls, with the light line under it.
private final class Groove: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 2).isActive = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let top = isFlipped ? bounds.minY : bounds.maxY - 1, lip = isFlipped ? bounds.minY + 1 : bounds.maxY - 2
        Retro.color(p.groove).setFill()
        NSRect(x: bounds.minX, y: top, width: bounds.width, height: 1).fill()
        NSColor.white.withAlphaComponent(p.grooveLip).setFill()
        NSRect(x: bounds.minX, y: lip, width: bounds.width, height: 1).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A text field on an LCD chip: the size fields, typed in mono ink on the olive glass.
private final class LCDFieldBox: NSView {
    init(_ field: NSTextField) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Retro.mono(13, weight: .semibold)
        field.textColor = Retro.color(Retro.lcdInk)
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.drawGlass(bounds, radius: 4, top: Retro.chipTop, middle: 0xc7cdb1, bottom: Retro.chipBottom,
                        brightness: p.lcdBrightness, grid: false, shadowBlur: 2, shadowOffset: 1, flipped: isFlipped)
    }

    /// A click on the chip around the field edits it.
    override func mouseDown(with event: NSEvent) {
        if let field = subviews.first as? NSTextField { window?.makeFirstResponder(field) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Dims the screen outside the selection and lets the user move it, resize it by its eight handles, or drag
/// out a new one; arrow keys nudge it (Shift = 10 pt).
private final class AdjustView: NSView {
    var selection = NSRect.zero {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            onChange?()
        }
    }
    var onChange: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    /// Instruction banner near the top of the screen, until the first click.
    var hint: String? { didSet { needsDisplay = true } }

    private enum Drag { case move(NSPoint), resize(Int, NSRect), new(NSPoint) }
    private var drag: Drag?
    private static let grab: CGFloat = 10

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Handle positions, counter-clockwise from bottom-left: corners at even indexes, edge midpoints at odd ones.
    private var handles: [NSPoint] {
        let r = selection
        return [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.midX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
                NSPoint(x: r.maxX, y: r.midY), NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.midX, y: r.maxY),
                NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.minX, y: r.midY)]
    }

    private func handleRect(_ p: NSPoint) -> NSRect {
        NSRect(x: p.x - Self.grab, y: p.y - Self.grab, width: Self.grab * 2, height: Self.grab * 2)
    }

    override func resetCursorRects() {
        for (i, p) in handles.enumerated() {
            let cursor: NSCursor = i % 2 == 0 ? .crosshair : (i == 1 || i == 5 ? .resizeUpDown : .resizeLeftRight)
            addCursorRect(handleRect(p), cursor: cursor)
        }
        // A new selection starts at 8 × 8: inset by the grab margin it would be a null rect (infinite origin),
        // which crashes as a cursor rect. Only add the move cursor when there is an inside left.
        let inside = selection.insetBy(dx: Self.grab, dy: Self.grab)
        if !inside.isNull, !inside.isEmpty { addCursorRect(inside, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        hint = nil
        let p = convert(event.locationInWindow, from: nil)
        if let i = handles.firstIndex(where: { handleRect($0).contains(p) }) {
            drag = .resize(i, selection)
        } else if selection.contains(p) {
            drag = .move(NSPoint(x: p.x - selection.minX, y: p.y - selection.minY))
            NSCursor.closedHand.push()
        } else {
            drag = .new(p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let q = NSPoint(x: min(max(p.x, 0), bounds.maxX), y: min(max(p.y, 0), bounds.maxY))
        switch drag {
        case .move(let offset)?:
            var r = selection
            // Whole-point origin, same size: `integral` grew the selection by a point on fractional positions.
            r.origin = NSPoint(x: min(max((p.x - offset.x).rounded(), 0), bounds.maxX - r.width),
                               y: min(max((p.y - offset.y).rounded(), 0), bounds.maxY - r.height))
            selection = r
        case .resize(let i, let start)?:
            var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
            if [0, 6, 7].contains(i) { minX = q.x }
            if [2, 3, 4].contains(i) { maxX = q.x }
            if [0, 1, 2].contains(i) { minY = q.y }
            if [4, 5, 6].contains(i) { maxY = q.y }
            let r = NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
            if r.width >= 8, r.height >= 8 { selection = r.integral }
        case .new(let s)?:
            let r = NSRect(x: min(s.x, q.x), y: min(s.y, q.y), width: abs(q.x - s.x), height: abs(q.y - s.y))
            if r.width >= 8, r.height >= 8 { selection = r.integral }
        case nil: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .move? = drag { NSCursor.pop() }
        drag = nil
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var r = selection
        switch event.keyCode {
        case 123: r.origin.x -= step
        case 124: r.origin.x += step
        case 125: r.origin.y -= step
        case 126: r.origin.y += step
        default: super.keyDown(with: event); return
        }
        r.origin.x = min(max(r.minX, 0), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, 0), bounds.maxY - r.height)
        selection = r
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: selection))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill()
        path.fill()
        if let hint { drawHintBanner(hint, centeredAt: NSPoint(x: bounds.midX, y: bounds.maxY - 110)) }
        NSColor.white.withAlphaComponent(0.7).setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        // CleanShot-style handles: L-shaped corners and short bars on the edges, just outside the selection.
        NSColor.white.setStroke()
        let r = selection.insetBy(dx: -2, dy: -2), arm: CGFloat = 16, bar: CGFloat = 10
        let corners: [(NSPoint, CGFloat, CGFloat)] = [(NSPoint(x: r.minX, y: r.minY), 1, 1), (NSPoint(x: r.maxX, y: r.minY), -1, 1),
                                                      (NSPoint(x: r.maxX, y: r.maxY), -1, -1), (NSPoint(x: r.minX, y: r.maxY), 1, -1)]
        for (p, dx, dy) in corners {
            let l = NSBezierPath()
            l.lineWidth = 4; l.lineCapStyle = .round
            l.move(to: NSPoint(x: p.x + dx * arm, y: p.y)); l.line(to: p); l.line(to: NSPoint(x: p.x, y: p.y + dy * arm))
            l.stroke()
        }
        for (a, b) in [(NSPoint(x: r.midX - bar, y: r.minY), NSPoint(x: r.midX + bar, y: r.minY)),
                       (NSPoint(x: r.midX - bar, y: r.maxY), NSPoint(x: r.midX + bar, y: r.maxY)),
                       (NSPoint(x: r.minX, y: r.midY - bar), NSPoint(x: r.minX, y: r.midY + bar)),
                       (NSPoint(x: r.maxX, y: r.midY - bar), NSPoint(x: r.maxX, y: r.midY + bar))] {
            let l = NSBezierPath()
            l.lineWidth = 4; l.lineCapStyle = .round
            l.move(to: a); l.line(to: b)
            l.stroke()
        }
    }
}
