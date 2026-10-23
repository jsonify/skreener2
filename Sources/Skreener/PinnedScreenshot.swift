import AppKit

private final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A borderless always-on-top window showing a screenshot. Drag to move, scroll to change opacity,
/// pinch/⌘+scroll to zoom, double-click or Esc to close. Hovering shows a toolbar (close, drag out as a file, edit,
/// copy, zoom); right-click for 50/100/200%, copy, edit, save, share, semi-transparent and close (#116).
final class PinnedScreenshotController: NSObject {
    private static var live: [PinnedScreenshotController] = []
    private var panel: PinnedPanel?

    /// `rect` (global coordinates) puts the pin exactly over the area it was captured from, at 100%. Otherwise it
    /// opens at 100% in the middle of the screen under the pointer, smaller if it would cover most of that screen.
    static func pin(_ image: NSImage, at rect: CGRect? = nil) {
        let c = PinnedScreenshotController()
        c.show(image, at: rect)
        live.append(c)
    }

    private func show(_ image: NSImage, at rect: CGRect?) {
        let frame: NSRect
        if let rect {
            frame = rect
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
            let maxSize = NSSize(width: screen.visibleFrame.width * 0.6, height: screen.visibleFrame.height * 0.6)
            let fit = min(1, maxSize.width / max(image.size.width, 1), maxSize.height / max(image.size.height, 1))
            let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
            frame = NSRect(origin: NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2),
                           size: size)
        }
        let p = PinnedPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.canHide = false   // stays put while Skreener hides (e.g. during a Drag Me drag)
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false

        let v = PinnedView(image: image, frame: NSRect(origin: .zero, size: frame.size))
        v.autoresizingMask = [.width, .height]
        v.onClose = { [weak self] in self?.close() }
        p.contentView = v
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v)
        panel = p
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        PinnedScreenshotController.live.removeAll { $0 === self }
    }
}

private final class PinnedView: NSView {
    let image: NSImage
    var onClose: (() -> Void)?

    private let toolbar = PinToolbar()
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private var hideToolbar: DispatchWorkItem?

    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
        buildToolbar()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let b = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); b.lineWidth = 1; b.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose?() } else { super.mouseDown(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard window?.isKeyWindow == true, mods == [.command], event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return super.performKeyEquivalent(with: event)
        }
        copyImage()
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window else { return }
        if event.modifierFlags.contains(.command) {
            resize(by: 1 + event.scrollingDeltaY * 0.01)
        } else {
            w.alphaValue = min(1, max(0.1, w.alphaValue + event.scrollingDeltaY * 0.01))
        }
    }

    override func magnify(with event: NSEvent) { resize(by: 1 + event.magnification) }

    private func resize(by factor: CGFloat) {
        guard let w = window else { return }
        setSize(NSSize(width: max(60, w.frame.width * factor), height: max(60, w.frame.height * factor)))
    }

    /// Resizes the pin around its center.
    private func setSize(_ new: NSSize) {
        guard let w = window else { return }
        let origin = NSPoint(x: w.frame.midX - new.width / 2, y: w.frame.midY - new.height / 2)
        w.setFrame(NSRect(origin: origin, size: new), display: true)
        refreshZoom()
    }

    /// The pin's size against the image's own (point) size.
    private var zoom: CGFloat { (window?.frame.width ?? bounds.width) / max(image.size.width, 1) }

    private func refreshZoom() { zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%" }

    // MARK: Hover toolbar

    private func buildToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = PillButton.barColor.cgColor
        toolbar.layer?.cornerRadius = 14
        toolbar.layer?.cornerCurve = .continuous
        toolbar.layer?.borderWidth = 0.5
        toolbar.layer?.borderColor = PillButton.barBorderColor.cgColor
        toolbar.alphaValue = 0
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        let drag = PinDragHandle(image: image)
        let row = NSStackView(views: [
            PinButton(symbol: "xmark", tip: "Close (Esc)") { [weak self] in self?.onClose?() },
            drag,
            PinButton(symbol: "pencil", tip: "Edit") { [weak self] in self?.edit() },
            PinButton(symbol: "doc.on.doc", tip: "Copy (⌘C)") { [weak self] in self?.copyImage() },
            zoomLabel,
        ])
        row.spacing = 2
        row.setCustomSpacing(6, after: row.arrangedSubviews[3])
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(row)
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        refreshZoom()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// A pin that opens under the pointer (Capture Area & Pin) gets no mouse-entered event, so show the toolbar here.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window, w.frame.contains(NSEvent.mouseLocation) { showToolbar() }
    }

    override func mouseEntered(with event: NSEvent) { showToolbar() }

    private func showToolbar() {
        hideToolbar?.cancel()
        refreshZoom()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toolbar.animator().alphaValue = 1
        }
    }

    /// The toolbar stays a moment after the pointer leaves, so it doesn't flicker at the edge.
    override func mouseExited(with event: NSEvent) {
        hideToolbar?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.toolbar.animator().alphaValue = 0
            }
        }
        hideToolbar = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let current = Int((zoom * 100).rounded())
        for percent in [50, 100, 200] {
            let i = NSMenuItem(title: "\(percent)%", action: #selector(zoomPicked(_:)), keyEquivalent: "")
            i.target = self; i.tag = percent
            i.state = percent == current ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())
        for (title, action) in [("Copy", #selector(copyItem)), ("Edit", #selector(editItem)),
                                ("Save…", #selector(saveItem)), ("Share…", #selector(shareItem))] {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        m.addItem(.separator())
        let translucent = NSMenuItem(title: "Semi-transparent", action: #selector(translucentToggled), keyEquivalent: "")
        translucent.target = self
        translucent.state = (window?.alphaValue ?? 1) < 1 ? .on : .off
        m.addItem(translucent)
        m.addItem(.separator())
        let close = NSMenuItem(title: "Close", action: #selector(closeItem), keyEquivalent: "")
        close.target = self
        m.addItem(close)
        return m
    }

    @objc private func zoomPicked(_ item: NSMenuItem) {
        let z = CGFloat(item.tag) / 100
        setSize(NSSize(width: max(1, image.size.width * z), height: max(1, image.size.height * z)))
    }
    @objc private func copyItem() { copyImage() }
    @objc private func editItem() { edit() }
    @objc private func saveItem() {
        NSApp.activate(ignoringOtherApps: true)
        Output.saveAs(image)
    }
    @objc private func shareItem() { Output.share(image, from: self) }
    @objc private func translucentToggled() { window?.alphaValue = (window?.alphaValue ?? 1) < 1 ? 1 : 0.5 }
    @objc private func closeItem() { onClose?() }

    // MARK: Actions

    /// The pinned image itself (at full resolution), never the toolbar.
    private func copyImage() {
        Output.copy(image)
        Sound.play("Pop")
    }

    private func edit() {
        EditorWindowController(image: image).present(on: window?.screen)
    }
}

/// The pin's dark toolbar strip. While faded out it lets clicks through to the pin, so they move it as usual.
private final class PinToolbar: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.5 ? nil : super.hitTest(point) }
}

/// A small white symbol button for the pin's toolbar.
private final class PinButton: NSButton {
    private let run: () -> Void

    init(symbol: String, tip: String, run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .white
        toolTip = tip
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        target = self
        action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { run() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Drag it out of the pin to drop the image as a file (into Finder, Mail, Slack…); dragging the image itself still
/// moves the pin.
private final class PinDragHandle: NSView, NSDraggingSource {
    private let image: NSImage
    private var downEvent: NSEvent?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Drag Out")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        toolTip = "Drag to drop the image as a file"
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 24),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) { downEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, let url = Output.temporaryFile(image) else { return }
        downEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let h: CGFloat = 60
        let w = max(1, h * image.size.width / max(image.size.height, 1))
        let p = convert(down.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), contents: image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
