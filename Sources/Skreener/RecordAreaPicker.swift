import AppKit

/// What the user chose in the record-area picker.
enum RecordPick {
    case video(NSScreen, CGRect), gif(NSScreen, CGRect)        // global, bottom-left origin coordinates
    case screenshot(NSScreen, CGRect), text(NSScreen, CGRect), timer(NSScreen, CGRect)
    case fullscreenShot, window
}

private final class PickerPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { if onKey?(event) != true { super.keyDown(with: event) } }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// The panels' backgrounds: clicks on them must not start a selection drag underneath.
private final class CardView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
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

/// CleanShot-style area picker for recordings: after the first drag the selection stays adjustable (drag the
/// handles or the inside, or drag outside for a new one), with a panel in the selection (options, size, audio
/// and effect toggles, Record GIF ⌥↩ / Record Video ↩) and a mode bar at the bottom of the screen that takes
/// a screenshot of the selection instead. Esc cancels.
final class RecordAreaPicker: NSObject {
    private var panel: PickerPanel?
    private var adjust: AdjustView?
    private var controls: NSView?
    private var modeBar: NSView?
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private var toggles: [(NSButton, () -> Bool)] = []
    private var actions: [Action] = []
    private var popover: NSPopover?
    private var screen: NSScreen!
    private var completion: ((RecordPick?) -> Void)?

    var isActive: Bool { completion != nil }

    /// `rect` is the starting selection in global coordinates on `screen`.
    func begin(screen: NSScreen, rect: CGRect, completion: @escaping (RecordPick?) -> Void) {
        guard self.completion == nil else { return }
        self.screen = screen
        self.completion = completion
        actions.removeAll(); toggles.removeAll()

        let p = PickerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
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
        let c = buildControls()
        let bar = buildModeBar()
        v.addSubview(c); v.addSubview(bar)
        p.contentView = v
        panel = p; adjust = v; controls = c; modeBar = bar
        layout()
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ pick: RecordPick?) {
        guard let done = completion else { return }
        completion = nil
        popover?.close(); popover = nil
        let old = panel
        panel?.orderOut(nil); panel = nil; adjust = nil; controls = nil; modeBar = nil
        // We may be inside one of the panel's event handlers; keep it alive until that returns.
        DispatchQueue.main.async { withExtendedLifetime(old) {} }
        done(pick)
    }

    /// The selection in global coordinates.
    private var globalSelection: CGRect {
        (adjust?.selection ?? .zero).offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    private func key(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 53: finish(nil)
        case 36, 76:
            finish(e.modifierFlags.contains(.option) ? .gif(screen, globalSelection) : .video(screen, globalSelection))
        default: return false
        }
        return true
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

    private static func card(_ content: NSView) -> NSView {
        let card = CardView()
        card.material = .hudWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
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

    private static func iconButton(_ sym: String, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: sym, accessibilityDescription: tip) ?? NSImage(), target: nil, action: nil)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.toolTip = tip
        b.contentTintColor = .labelColor
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func buildControls() -> NSView {
        // Row 1: options, width × height, whole screen, size presets.
        let options = Self.iconButton("slider.vertical.3", "Recording options")
        bind(options) { [weak self] sender in self?.showOptions(sender as? NSView) }
        for f in [widthField, heightField] {
            f.alignment = .center
            f.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            f.bezelStyle = .roundedBezel
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 58).isActive = true
            bind(f) { [weak self] _ in self?.sizeTyped() }
        }
        widthField.toolTip = "Width (points)"; heightField.toolTip = "Height (points)"
        let times = NSTextField(labelWithString: "×")
        times.textColor = .secondaryLabelColor
        let whole = Self.iconButton("arrow.up.left.and.arrow.down.right", "Whole screen")
        bind(whole) { [weak self] _ in self?.setSelection { _, bounds in bounds } }
        let presets = NSPopUpButton(frame: .zero, pullsDown: true)
        presets.isBordered = false
        presets.toolTip = "Aspect ratio and size presets"
        let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        face.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "Presets")
        presets.menu?.addItem(face)
        for (title, ratio) in [("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("1:1", 1.0), ("9:16", 9.0 / 16)] {
            presets.menu?.addItem(menuItem(title) { [weak self] in
                self?.setSelection { sel, _ in
                    let h = sel.width / ratio
                    return NSRect(x: sel.minX, y: sel.midY - h / 2, width: sel.width, height: h)
                }
            })
        }
        presets.menu?.addItem(.separator())
        for (w, h) in [(1280, 720), (1920, 1080), (1080, 1080), (800, 600)] {
            presets.menu?.addItem(menuItem("\(w) × \(h)") { [weak self] in
                self?.setSelection { sel, _ in
                    NSRect(x: sel.midX - CGFloat(w) / 2, y: sel.midY - CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h))
                }
            })
        }
        let row1 = NSStackView(views: [options, widthField, times, heightField, whole, presets])
        row1.spacing = 6
        row1.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        // Row 2: audio and effect toggles, each with a check mark underneath when on.
        let micAvailable: Bool
        if #available(macOS 15.0, *) { micAvailable = true } else { micAvailable = false }
        let row2 = NSStackView(views: [
            toggle("mic", micAvailable ? "Record microphone" : "Microphone recording needs macOS 15 or later", enabled: micAvailable,
                   get: { Preferences.recordMicrophone }, set: { Preferences.recordMicrophone = $0 }),
            toggle("speaker.wave.2", "Record system audio",
                   get: { Preferences.recordSystemAudio }, set: { Preferences.recordSystemAudio = $0 }),
            toggle("cursorarrow.click.2", "Highlight clicks",
                   get: { Preferences.recordHighlightClicks }, set: { Preferences.recordHighlightClicks = $0 }),
            toggle("command", "Show keystrokes",
                   get: { Preferences.recordShowKeystrokes }, set: { [weak self] on in self?.setKeystrokes(on) }),
        ])
        row2.distribution = .fillEqually
        row2.spacing = 0
        row2.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 6, right: 6)

        let line = NSBox(); line.boxType = .separator
        let top = column([row1, line, row2], spacing: 0)

        let gif = RecordRow(symbol: "photo.stack", title: "Record GIF", shortcut: "⌥↩") { [weak self] in
            guard let self else { return }
            finish(.gif(screen, globalSelection))
        }
        let video = RecordRow(symbol: "video.fill", title: "Record Video", shortcut: "↩") { [weak self] in
            guard let self else { return }
            finish(.video(screen, globalSelection))
        }
        let line2 = NSBox(); line2.boxType = .separator
        let rows = column([gif, line2, video], spacing: 0)

        let stack = column([Self.card(top), Self.card(rows)], spacing: 10)
        stack.appearance = NSAppearance(named: .darkAqua)
        stack.widthAnchor.constraint(equalToConstant: 300).isActive = true
        refreshToggles()
        return stack
    }

    private func toggle(_ sym: String, _ tip: String, enabled: Bool = true,
                        get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(title: "", image: NSImage(systemSymbolName: sym, accessibilityDescription: tip) ?? NSImage(), target: nil, action: nil)
        b.isBordered = false
        b.imagePosition = .imageAbove
        b.font = .systemFont(ofSize: 9, weight: .bold)
        b.toolTip = tip
        b.isEnabled = enabled
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        bind(b) { [weak self] _ in set(!get()); self?.refreshToggles() }
        toggles.append((b, enabled ? get : { false }))
        return b
    }

    private func refreshToggles() {
        for (b, isOn) in toggles {
            let on = isOn()
            b.title = on ? "✓" : " "
            b.contentTintColor = on ? .labelColor : .secondaryLabelColor
            b.setAccessibilityValue(on ? "on" : "off")
        }
    }

    /// Keystrokes need Accessibility access; ask for it when the option is turned on.
    private func setKeystrokes(_ on: Bool) {
        Preferences.recordShowKeystrokes = on
        if on && !KeystrokeAccess.granted { KeystrokeAccess.request() }
    }

    private func buildModeBar() -> NSView {
        let modes: [(String, String, RecordPick?)] = [
            ("viewfinder", "Area", nil), ("display", "Fullscreen", .fullscreenShot), ("macwindow", "Window", .window),
            ("timer", "Timer", nil), ("textformat", "OCR", nil), ("video", "Recording", nil),
        ]
        var buttons: [NSView] = []
        for (sym, title, pick) in modes {
            let b = NSButton(title: title, image: NSImage(systemSymbolName: sym, accessibilityDescription: title) ?? NSImage(),
                             target: nil, action: nil)
            b.isBordered = false
            b.imagePosition = .imageAbove
            b.font = .systemFont(ofSize: 11, weight: .medium)
            b.contentTintColor = .labelColor
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 72).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            switch title {
            case "Area":
                b.toolTip = "Screenshot of the selected area"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.screenshot(screen, globalSelection)) }
            case "Timer":
                b.toolTip = "Screenshot of the selected area after a \(Preferences.selfTimerSeconds) s countdown"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.timer(screen, globalSelection)) }
            case "OCR":
                b.toolTip = "Copy the text in the selected area"
                bind(b) { [weak self] _ in guard let self else { return }; finish(.text(screen, globalSelection)) }
            case "Recording":
                b.toolTip = "Record the selected area (↩ video, ⌥↩ GIF)"
                b.wantsLayer = true
                b.layer?.cornerRadius = 8
                b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
            default:
                b.toolTip = title == "Window" ? "Screenshot of a window" : "Screenshot of the whole screen"
                bind(b) { [weak self] _ in self?.finish(pick) }
            }
            buttons.append(b)
        }
        let row = NSStackView(views: buttons)
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        let card = Self.card(row)
        card.appearance = NSAppearance(named: .darkAqua)
        return card
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
        vc.view = buildOptions()
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        popover = p
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: p, queue: .main) { [weak self] _ in
            self?.refreshToggles()
        }
    }

    private func buildOptions() -> NSView {
        var views: [NSView] = []
        func header(_ title: String) {
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 13, weight: .semibold)
            if !views.isEmpty { views.append(spacer(10)) }
            views.append(l)
        }
        func row(_ title: String, _ get: () -> Bool, options: NSMenu? = nil, _ set: @escaping (Bool) -> Void) {
            let label = NSTextField(labelWithString: title)
            let sw = NSSwitch()
            sw.state = get() ? .on : .off
            sw.controlSize = .small
            bind(sw) { [weak self] sender in set((sender as? NSSwitch)?.state == .on); self?.refreshToggles() }
            var parts: [NSView] = [label, NSView()]
            if let options {
                let b = NSPopUpButton(frame: .zero, pullsDown: true)
                b.controlSize = .small
                b.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
                options.insertItem(NSMenuItem(title: "Options…", action: nil, keyEquivalent: ""), at: 0)
                b.menu = options
                parts.append(b)
            }
            parts.append(sw)
            let r = NSStackView(views: parts)
            r.spacing = 8
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
        header("Keystrokes")
        row("Show keystrokes", { Preferences.recordShowKeystrokes }, options: keystrokeOptions()) { [weak self] in self?.setKeystrokes($0) }
        header("Video")
        let fps = NSPopUpButton(frame: .zero, pullsDown: false)
        fps.controlSize = .small
        fps.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        for rate in [30, 60] { fps.addItem(withTitle: "\(rate) fps"); fps.lastItem?.tag = rate }
        fps.selectItem(withTag: Preferences.recordFrameRate)
        bind(fps) { Preferences.recordFrameRate = ($0 as? NSPopUpButton)?.selectedTag() ?? 30 }
        let fpsRow = NSStackView(views: [NSTextField(labelWithString: "Frame rate"), NSView(), fps])
        views.append(fpsRow)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        for v in views { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true }
        stack.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return stack
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

/// "Record GIF  ⌥↩"-style row: icon, title, shortcut on the right; the whole row is clickable.
private final class RecordRow: NSView {
    private let run: () -> Void
    private var hover = false { didSet { needsDisplay = true } }

    init(symbol: String, title: String, shortcut: String, run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        let key = NSTextField(labelWithString: shortcut)
        key.textColor = .secondaryLabelColor
        let row = NSStackView(views: [icon, label, NSView(), key])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 42),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { run() }
    }
    override func accessibilityPerformPress() -> Bool { run(); return true }
    override func draw(_ dirtyRect: NSRect) {
        guard hover else { return }
        NSColor.white.withAlphaComponent(0.1).setFill()
        bounds.fill()
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
        addCursorRect(selection.insetBy(dx: Self.grab, dy: Self.grab), cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
            r.origin = NSPoint(x: min(max(p.x - offset.x, 0), bounds.maxX - r.width),
                               y: min(max(p.y - offset.y, 0), bounds.maxY - r.height))
            selection = r.integral
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
