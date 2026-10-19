import AppKit
import UniformTypeIdentifiers

/// Centers the document view when it is smaller than the viewport (works with scroll-view magnification).
private final class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let doc = documentView {
            if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
            if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        }
        return rect
    }
}

/// Mouse-wheel zoom: a wheel (or ⌘ + trackpad scroll) zooms around the pointer; trackpad scrolling and
/// Shift + wheel still pan, and pinch still zooms.
private final class ZoomingScrollView: NSScrollView {
    var onZoom: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let isWheel = !event.hasPreciseScrollingDeltas
        guard allowsMagnification, let doc = documentView,
              isWheel || event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift),
              event.scrollingDeltaY != 0 else { super.scrollWheel(with: event); return }
        // Wheel away from you zooms in, whatever the "natural scrolling" setting.
        let dy = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let factor = exp(dy * (isWheel ? 0.1 : 0.01))
        let target = min(maxMagnification, max(minMagnification, magnification * factor))
        setMagnification(target, centeredAt: doc.convert(event.locationInWindow, from: nil))
        onZoom?()
    }
}

/// The centered "Drag Me" pill: drag it to drop the annotated image as a PNG file anywhere.
private final class DragPill: NSView, NSDraggingSource {
    var imageProvider: () -> NSImage = { NSImage() }
    private var dragStarted = false

    override var intrinsicContentSize: NSSize { NSSize(width: 118, height: 34) }
    override func mouseDown(with event: NSEvent) { dragStarted = false }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        let image = imageProvider()
        guard let data = Output.pngData(image) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Skreener \(f.string(from: Date())).png")
        do { try data.write(to: url) } catch { NSLog("Drag export failed: \(error)"); return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let h: CGFloat = 72, w = h * image.size.width / max(image.size.height, 1)
        item.setDraggingFrame(NSRect(x: 0, y: 0, width: min(w, 160), height: h), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.controlBackgroundColor.withAlphaComponent(0.85).setFill(); pill.fill()
        NSColor.separatorColor.setStroke(); pill.lineWidth = 1; pill.stroke()

        // Grip: three short lines either side of the label.
        NSColor.tertiaryLabelColor.setStroke()
        for side in [bounds.minX + 16, bounds.maxX - 28] {
            for i in 0..<3 {
                let y = bounds.midY - 4 + CGFloat(i) * 4
                let p = NSBezierPath(); p.lineWidth = 1.2; p.lineCapStyle = .round
                p.move(to: NSPoint(x: side, y: y)); p.line(to: NSPoint(x: side + 12, y: y)); p.stroke()
            }
        }
        let text = "Drag Me" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                    .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

private extension NSToolbarItem.Identifier {
    static let cropItem = NSToolbarItem.Identifier("skreener.crop")
    static let addImageItem = NSToolbarItem.Identifier("skreener.addImage")
    static let mockupItem = NSToolbarItem.Identifier("skreener.mockup")
    static let toolsItem = NSToolbarItem.Identifier("skreener.tools")
    static let undoItem = NSToolbarItem.Identifier("skreener.undo")
    static let redoItem = NSToolbarItem.Identifier("skreener.redo")
    static let saveAsItem = NSToolbarItem.Identifier("skreener.saveAs")
    static let settingsItem = NSToolbarItem.Identifier("skreener.settings")
}

private func symbol(_ name: String, _ description: String? = nil) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: description)
        ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil) ?? NSImage()
}

/// CleanShot-style editor: unified titlebar toolbar, centered zoomable canvas, footer with zoom / Drag Me / actions.
/// The window never gets smaller than `minimumSize`.
final class EditorWindowController: NSWindowController, NSToolbarDelegate {
    static let minimumSize = NSSize(width: 990, height: 750)
    static var live: [EditorWindowController] = []

    /// Toolbar tool buttons in display order.
    private let toolButtons: [(symbol: String, tool: Tool)] = [
        ("cursorarrow", .select),
        ("rectangle", .rect),
        ("rectangle.fill", .filledRect),
        ("circle", .ellipse),
        ("line.diagonal", .line),
        ("arrow.up.right", .arrow),
        ("textformat", .text),
        ("checkerboard.rectangle", .pixelate),
        ("1.circle.fill", .counter),
        ("pencil.tip", .pen),
        ("highlighter", .highlighter),
    ]

    private let image: NSImage
    private let canvas: CanvasView
    private let scroll = ZoomingScrollView()
    private let zoomButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var toolGroup: NSToolbarItemGroup?
    // Contextual attributes bar under the toolbar: only the controls that apply to the current tool or
    // selection are shown. It lives outside the toolbar so the tool buttons always have room.
    private let attributesBar = NSStackView()
    private let attributesTitle = NSTextField(labelWithString: "")
    private let attributesHint = NSTextField(labelWithString: "Select an annotation to change its style")
    private let colorWell = NSColorWell(style: .minimal)
    private let strokePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let boldButton = NSButton()
    private let pixelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    // Crop and Background replace the tool options in the same strip while they are active.
    private enum StripMode { case tools, crop, background }
    private var stripMode = StripMode.tools {
        didSet { refreshStrip() }
    }
    private let cropBar = NSStackView()
    private let backgroundBar = NSStackView()
    private let fillPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let paddingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cornerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bgShadowBox = NSButton(checkboxWithTitle: "Shadow", target: nil, action: nil)
    private static let fontChoices = [("System", ""), ("Helvetica Neue", "Helvetica Neue"), ("Avenir Next", "Avenir Next"),
                                      ("Georgia", "Georgia"), ("Menlo", "Menlo"), ("Marker Felt", "Marker Felt"),
                                      ("Chalkboard SE", "Chalkboard SE")]
    private var fitMode = true

    init(image: NSImage) {
        self.image = image
        canvas = CanvasView(image: image)

        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let floor = EditorWindowController.minimumSize
        let size = NSSize(width: max(floor.width, min(image.size.width + 120, visible.width)),
                          height: max(floor.height, min(image.size.height + 200, visible.height)))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Skreener Editor"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.toolbarStyle = .unified
        w.minSize = floor
        super.init(window: w)

        buildContent(in: w)
        let toolbar = NSToolbar(identifier: "skreener.editor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        w.toolbar = toolbar
        w.center()

        EditorWindowController.live.append(self)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            EditorWindowController.live.removeAll { $0 === self }
            Task { @MainActor in DockPresence.update() }
        }
        nc.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in
            if self?.fitMode == true { self?.applyFit() }
        }
        nc.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in
            self?.fitMode = false; self?.refreshZoomLabel()
        }
        canvas.onExtentChange = { [weak self] old in self?.canvasExtentChanged(from: old) }
        scroll.onZoom = { [weak self] in self?.fitMode = false; self?.refreshZoomLabel() }
        canvas.onToolShortcut = { [weak self] t in self?.selectToolButton(t) }
        canvas.onContextChange = { [weak self] _, _ in self?.contextChanged() }
        canvas.onCropModeChange = { [weak self] on in self?.stripMode = on ? .crop : .tools }
        canvas.onBackgroundChange = { [weak self] in if self?.stripMode == .background { self?.refreshStrip() } }
        buildAttributesBar()
        buildCropBar()
        buildBackgroundBar()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        DockPresence.update()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.layoutIfNeeded()
        window?.makeFirstResponder(canvas)
        applyFit()
    }

    // MARK: Layout

    private func buildContent(in w: NSWindow) {
        let content = NSView()
        w.contentView = content

        scroll.contentView = CenteredClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1; scroll.maxMagnification = 8
        scroll.translatesAutoresizingMaskIntoConstraints = false
        canvas.wantsLayer = true
        canvas.layer?.shadowColor = NSColor.black.cgColor
        canvas.layer?.shadowOpacity = 0.35
        canvas.layer?.shadowRadius = 10
        canvas.layer?.shadowOffset = CGSize(width: 0, height: -3)
        canvas.layer?.masksToBounds = false

        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        let strip = buildAttributesStrip()
        strip.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll); content.addSubview(footer); content.addSubview(strip)

        let top = (w.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: top),
            strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 40),
            scroll.topAnchor.constraint(equalTo: strip.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func buildAttributesStrip() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        bar.state = .followsWindowActiveState
        attributesTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        attributesTitle.textColor = .secondaryLabelColor
        attributesHint.font = .systemFont(ofSize: 12)
        attributesHint.textColor = .tertiaryLabelColor
        let row = NSStackView(views: [attributesTitle, attributesBar, attributesHint, cropBar, backgroundBar])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox(); line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row); bar.addSubview(line)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    private func buildFooter() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        bar.state = .followsWindowActiveState

        // Zoom popup (pull-down: item 0 shows the current zoom).
        zoomButton.bezelStyle = .texturedRounded
        zoomButton.menu = NSMenu()
        zoomButton.menu?.addItem(withTitle: "100%", action: nil, keyEquivalent: "")
        for (title, tag) in [("Fit", 0), ("25%", 25), ("50%", 50), ("100%", 100), ("200%", 200), ("400%", 400)] {
            let item = NSMenuItem(title: title, action: #selector(zoomPicked(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag
            zoomButton.menu?.addItem(item)
        }
        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let pill = DragPill()
        pill.imageProvider = { [weak self] in self?.canvas.flattened() ?? NSImage() }
        pill.translatesAutoresizingMaskIntoConstraints = false

        let actions = [("square.and.arrow.up", "Share", #selector(shareIt(_:))),
                       ("pin", "Pin to Screen", #selector(pinIt)),
                       ("doc.on.doc", "Copy", #selector(copyIt)),
                       ("square.and.arrow.down", "Save", #selector(saveIt))].map { sym, tip, sel -> NSButton in
            let b = NSButton(image: symbol(sym, tip), target: self, action: sel)
            b.bezelStyle = .texturedRounded; b.imagePosition = .imageOnly; b.toolTip = tip
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 40).isActive = true
            return b
        }
        let right = NSStackView(views: actions)
        right.spacing = 6
        right.translatesAutoresizingMaskIntoConstraints = false

        [zoomButton, pill, right].forEach(bar.addSubview)
        NSLayoutConstraint.activate([
            zoomButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            zoomButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pill.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 118), pill.heightAnchor.constraint(equalToConstant: 34),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    // MARK: Zoom

    private func applyFit() {
        let vis = scroll.contentSize, size = canvas.extent.size
        guard vis.width > 0, vis.height > 0, size.width > 0, size.height > 0 else { return }
        let fit = min(vis.width / size.width, vis.height / size.height, 1)
        scroll.magnification = fit
        refreshZoomLabel()
    }

    private func refreshZoomLabel() {
        zoomButton.menu?.item(at: 0)?.title = "\(Int((scroll.magnification * 100).rounded()))%"
        zoomButton.synchronizeTitleAndSelectedItem()
    }

    /// The canvas grew or shrank around its annotations: refit, or scroll so the image stays put on screen.
    private func canvasExtentChanged(from old: NSRect) {
        if fitMode { applyFit(); return }
        let clip = scroll.contentView
        let dx = canvas.extent.minX - old.minX, dy = canvas.extent.minY - old.minY
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.minX - dx, y: clip.bounds.minY - dy))
        scroll.reflectScrolledClipView(clip)
    }

    @objc private func zoomPicked(_ item: NSMenuItem) {
        if item.tag == 0 { fitMode = true; applyFit(); return }
        fitMode = false
        scroll.magnification = CGFloat(item.tag) / 100
        refreshZoomLabel()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.cropItem, .addImageItem, .mockupItem, .space, .toolsItem, .space, .undoItem, .redoItem, .flexibleSpace, .settingsItem, .saveAsItem]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ sym: String, _ label: String, _ tip: String, _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = symbol(sym, label); item.label = label; item.toolTip = tip
            item.isBordered = true; item.target = self; item.action = action
            return item
        }
        switch id {
        case .cropItem: return button("crop", "Crop", "Crop (C)", #selector(cropIt))
        case .addImageItem: return button("plus.rectangle.on.rectangle", "Add Image", "Add Image… (or paste one with ⌘V)", #selector(addImage))
        case .mockupItem: return button("photo", "Background", "Background", #selector(backgroundIt))
        case .undoItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = symbol("arrow.uturn.backward", "Undo"); item.label = "Undo"; item.toolTip = "Undo"
            item.isBordered = true; item.target = self; item.action = #selector(undoIt)
            item.toolTip = "Undo (⌘Z)"
            return item
        case .redoItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = symbol("arrow.uturn.forward", "Redo"); item.label = "Redo"; item.toolTip = "Redo (⇧⌘Z)"
            item.isBordered = true; item.target = self; item.action = #selector(redoIt)
            return item
        case .toolsItem:
            let group = NSToolbarItemGroup(itemIdentifier: id,
                                           images: toolButtons.map { symbol($0.symbol, $0.tool.name) },
                                           selectionMode: .selectOne,
                                           labels: toolButtons.map(\.tool.name),
                                           target: self, action: #selector(toolChanged))
            for (i, b) in toolButtons.enumerated() where i < group.subitems.count {
                let key = Tool.shortcuts.first { $0.value == b.tool }.map { " (\($0.key.uppercased()))" } ?? ""
                group.subitems[i].toolTip = b.tool.name + key
            }
            group.selectedIndex = toolButtons.firstIndex { $0.tool == canvas.tool } ?? 0
            group.label = "Tools"
            // Always one button per tool; never collapse the group into a pull-down menu.
            group.controlRepresentation = .expanded
            toolGroup = group
            return group
        case .settingsItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = symbol("gearshape", "Settings"); item.label = "Settings"; item.toolTip = "Settings (⌘,)"
            item.isBordered = true; item.target = self; item.action = #selector(openSettings)
            return item
        case .saveAsItem:
            let b = NSButton(title: "Save as…", target: self, action: #selector(saveIt))
            b.bezelStyle = .rounded
            b.bezelColor = .controlAccentColor
            b.attributedTitle = NSAttributedString(string: "Save as…", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = b; item.label = "Save as…"
            return item
        default: return nil
        }
    }

    // MARK: Attributes bar

    private func buildAttributesBar() {
        attributesBar.orientation = .horizontal
        attributesBar.spacing = 6

        colorWell.target = self; colorWell.action = #selector(colorChanged(_:)); colorWell.toolTip = "Color"
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 32).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true

        func setUp(_ popup: NSPopUpButton, _ tip: String, _ choices: [(String, Int)], _ action: Selector) {
            popup.bezelStyle = .texturedRounded
            popup.toolTip = tip
            popup.target = self; popup.action = action
            for (title, tag) in choices { popup.addItem(withTitle: title); popup.lastItem?.tag = tag }
        }
        setUp(strokePopup, "Stroke width", [1, 2, 3, 5, 8, 12].map { ("\($0) pt", $0) }, #selector(strokePicked(_:)))
        setUp(sizePopup, "Font size", [12, 14, 16, 18, 22, 28, 32, 40, 48, 64, 72].map { ("\($0) pt", $0) }, #selector(sizePicked(_:)))
        setUp(pixelPopup, "Pixel size", [("Fine", 6), ("Medium", 10), ("Coarse", 18), ("Heavy", 28)], #selector(pixelPicked(_:)))
        setUp(fontPopup, "Font", [], #selector(fontPicked(_:)))
        for (title, name) in Self.fontChoices {
            fontPopup.addItem(withTitle: title)
            fontPopup.lastItem?.representedObject = name
            if let f = NSFont(name: name, size: 13) {
                fontPopup.lastItem?.attributedTitle = NSAttributedString(string: title, attributes: [.font: f])
            }
        }

        boldButton.image = symbol("bold", "Bold")
        boldButton.setButtonType(.pushOnPushOff)
        boldButton.bezelStyle = .texturedRounded
        boldButton.imagePosition = .imageOnly
        boldButton.toolTip = "Bold"
        boldButton.target = self; boldButton.action = #selector(boldToggled(_:))

        [colorWell, strokePopup, fontPopup, sizePopup, boldButton, pixelPopup].forEach(attributesBar.addArrangedSubview)
        refreshStrip()
    }

    private func buildCropBar() {
        let hint = NSTextField(labelWithString: "Drag the corners or draw a new area · Return to apply · Esc to cancel")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor
        let reset = NSButton(title: "Reset", target: self, action: #selector(cropReset))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cropCancel))
        let apply = NSButton(title: "Apply", target: self, action: #selector(cropApply))
        apply.bezelColor = .controlAccentColor
        [reset, cancel, apply].forEach { $0.bezelStyle = .texturedRounded }
        [hint, reset, cancel, apply].forEach(cropBar.addArrangedSubview)
        cropBar.spacing = 8
        cropBar.isHidden = true
    }

    private func buildBackgroundBar() {
        fillPopup.bezelStyle = .texturedRounded
        fillPopup.toolTip = "Fill"
        fillPopup.target = self; fillPopup.action = #selector(backgroundChanged)
        fillPopup.addItem(withTitle: "None"); fillPopup.lastItem?.tag = -1
        for (i, preset) in Background.presets.enumerated() {
            fillPopup.addItem(withTitle: preset.name)
            fillPopup.lastItem?.tag = i
            fillPopup.lastItem?.image = NSImage(size: NSSize(width: 26, height: 14), flipped: false) { r in
                let clip = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                clip.addClip()
                Background.draw(fill: i, in: r)
                NSColor.separatorColor.setStroke(); clip.stroke()
                return true
            }
        }
        for (popup, tip, choices) in [(paddingPopup, "Padding", [16, 32, 48, 64, 96, 128]), (cornerPopup, "Corner radius", [0, 6, 10, 16, 24])] {
            popup.bezelStyle = .texturedRounded
            popup.toolTip = tip
            popup.target = self; popup.action = #selector(backgroundChanged)
            for v in choices { popup.addItem(withTitle: "\(tip == "Padding" ? "Padding" : "Corners") \(v) pt"); popup.lastItem?.tag = v }
        }
        bgShadowBox.target = self; bgShadowBox.action = #selector(backgroundChanged)
        [fillPopup, paddingPopup, cornerPopup, bgShadowBox].forEach(backgroundBar.addArrangedSubview)
        backgroundBar.spacing = 8
        backgroundBar.isHidden = true
    }

    private func contextChanged() {
        // Clicking an annotation or picking a tool leaves the background options.
        if stripMode == .background { stripMode = .tools } else { refreshStrip() }
    }

    private func refreshStrip() {
        attributesBar.isHidden = stripMode != .tools
        cropBar.isHidden = stripMode != .crop
        backgroundBar.isHidden = stripMode != .background
        switch stripMode {
        case .tools:
            refreshAttributes(canvas.contextTool, canvas.contextStyle)
        case .crop:
            attributesTitle.stringValue = "Crop"
            attributesTitle.isHidden = false; attributesHint.isHidden = true
        case .background:
            attributesTitle.stringValue = "Background"
            attributesTitle.isHidden = false; attributesHint.isHidden = true
            let bg = canvas.background
            fillPopup.selectItem(withTag: bg?.fill ?? -1)
            paddingPopup.selectItem(withTag: Int(bg?.padding ?? Background().padding))
            cornerPopup.selectItem(withTag: Int(bg?.cornerRadius ?? Background().cornerRadius))
            bgShadowBox.state = bg?.shadow ?? true ? .on : .off
            [paddingPopup, cornerPopup, bgShadowBox].forEach { $0.isEnabled = bg != nil }
        }
    }

    /// Shows the controls for `tool` and loads them with `style`.
    private func refreshAttributes(_ tool: Tool, _ style: Style) {
        // `.select` here means nothing is selected: there is no style to edit.
        attributesTitle.stringValue = tool.name
        attributesTitle.isHidden = tool == .select
        attributesHint.isHidden = tool != .select
        colorWell.isHidden = [.select, .pixelate, .image].contains(tool)
        strokePopup.isHidden = !tool.usesStroke
        [fontPopup, boldButton].forEach { $0.isHidden = tool != .text }
        sizePopup.isHidden = tool != .text && tool != .counter
        pixelPopup.isHidden = tool != .pixelate

        colorWell.color = style.color
        strokePopup.selectItem(withTag: Int(style.lineWidth))
        sizePopup.selectItem(withTag: Int(style.fontSize))
        pixelPopup.selectItem(withTag: Int(style.pixelSize))
        if let i = fontPopup.itemArray.firstIndex(where: { $0.representedObject as? String == style.fontName }) {
            fontPopup.selectItem(at: i)
        }
        boldButton.state = style.bold ? .on : .off
    }

    @objc private func colorChanged(_ w: NSColorWell) { canvas.updateStyle { $0.color = w.color } }
    @objc private func strokePicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.lineWidth = CGFloat(p.selectedTag()) } }
    @objc private func sizePicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.fontSize = CGFloat(p.selectedTag()) } }
    @objc private func pixelPicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.pixelSize = CGFloat(p.selectedTag()) } }
    @objc private func fontPicked(_ p: NSPopUpButton) {
        let name = p.selectedItem?.representedObject as? String ?? ""
        canvas.updateStyle { $0.fontName = name }
    }
    @objc private func boldToggled(_ b: NSButton) { canvas.updateStyle { $0.bold = b.state == .on } }

    // MARK: Actions

    @objc private func toolChanged() {
        guard let i = toolGroup?.selectedIndex, toolButtons.indices.contains(i) else { return }
        canvas.applyCrop()
        canvas.tool = toolButtons[i].tool
        if stripMode == .background { stripMode = .tools }
        window?.makeFirstResponder(canvas)
    }
    private func selectToolButton(_ t: Tool) {
        if let i = toolButtons.firstIndex(where: { $0.tool == t }) { toolGroup?.selectedIndex = i }
    }
    @objc private func copyIt() { Output.copy(canvas.flattened()) }
    @objc private func saveIt() { Output.saveAs(canvas.flattened()) }
    @objc private func pinIt() { PinnedScreenshotController.pin(canvas.flattened()) }
    @objc private func shareIt(_ sender: NSButton) {
        NSSharingServicePicker(items: [canvas.flattened()]).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    @MainActor @objc private func openSettings() { SettingsWindowController.shared.present() }
    @objc private func undoIt() { canvas.undo() }
    @objc private func cropIt() {
        if canvas.isCropping { canvas.applyCrop() } else { canvas.beginCrop() }
        window?.makeFirstResponder(canvas)
    }
    @objc private func cropApply() { canvas.applyCrop(); window?.makeFirstResponder(canvas) }
    @objc private func cropCancel() { canvas.cancelCrop(); window?.makeFirstResponder(canvas) }
    @objc private func cropReset() { canvas.resetCrop(); window?.makeFirstResponder(canvas) }
    @MainActor @objc private func addImage() {
        guard let w = window else { return }
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = p.url, let img = NSImage(contentsOf: url) else { return }
            self?.canvas.insertImage(img)
        }
    }
    /// Shows the background options, adding the default background the first time.
    @objc private func backgroundIt() {
        if stripMode == .background { stripMode = .tools; return }
        canvas.applyCrop()
        canvas.clearSelection()
        if canvas.background == nil { canvas.updateBackground { $0 = Background() } }
        stripMode = .background
        window?.makeFirstResponder(canvas)
    }
    @objc private func backgroundChanged() {
        let fill = fillPopup.selectedTag()
        let padding = CGFloat(paddingPopup.selectedTag()), corner = CGFloat(cornerPopup.selectedTag())
        let shadow = bgShadowBox.state == .on
        canvas.updateBackground { bg in
            guard fill >= 0 else { bg = nil; return }
            bg = Background(fill: fill, padding: padding, cornerRadius: corner, shadow: shadow)
        }
        refreshStrip()
    }
    @objc private func redoIt() { canvas.redo() }
}
