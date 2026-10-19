import AppKit

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
    static let colorItem = NSToolbarItem.Identifier("skreener.color")
    static let strokeItem = NSToolbarItem.Identifier("skreener.stroke")
    static let saveAsItem = NSToolbarItem.Identifier("skreener.saveAs")
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

    /// Toolbar tool buttons in display order. `tool == nil` entries are placeholders for tools that are not built yet.
    private let toolButtons: [(symbol: String, label: String, tool: Tool?)] = [
        ("cursorarrow", "Select", .select),
        ("rectangle", "Rectangle", .rect),
        ("rectangle.fill", "Filled Rectangle", nil),
        ("circle", "Ellipse", .ellipse),
        ("line.diagonal", "Line", .line),
        ("arrow.up.right", "Arrow", .arrow),
        ("textformat", "Text", .text),
        ("checkerboard.rectangle", "Pixelate", .pixelate),
        ("1.circle.fill", "Counter", nil),
        ("pencil.tip", "Pen", .pen),
        ("highlighter", "Highlighter", nil),
    ]

    private let image: NSImage
    private let canvas: CanvasView
    private let scroll = ZoomingScrollView()
    private let zoomButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var toolGroup: NSToolbarItemGroup?
    private var colorWell: NSColorWell?
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
        }
        nc.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in
            if self?.fitMode == true { self?.applyFit() }
        }
        nc.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in
            self?.fitMode = false; self?.refreshZoomLabel()
        }
        scroll.onZoom = { [weak self] in self?.fitMode = false; self?.refreshZoomLabel() }
        canvas.onToolShortcut = { [weak self] t in self?.selectToolButton(t) }
        canvas.onSelectionChange = { [weak self] a in
            if let a { self?.colorWell?.color = a.color }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
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
        content.addSubview(scroll); content.addSubview(footer)

        let top = (w.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: top),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 56),
        ])
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
        let vis = scroll.contentSize
        guard vis.width > 0, vis.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        let fit = min(vis.width / image.size.width, vis.height / image.size.height, 1)
        scroll.magnification = fit
        refreshZoomLabel()
    }

    private func refreshZoomLabel() {
        zoomButton.menu?.item(at: 0)?.title = "\(Int((scroll.magnification * 100).rounded()))%"
        zoomButton.synchronizeTitleAndSelectedItem()
    }

    @objc private func zoomPicked(_ item: NSMenuItem) {
        if item.tag == 0 { fitMode = true; applyFit(); return }
        fitMode = false
        scroll.magnification = CGFloat(item.tag) / 100
        refreshZoomLabel()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.cropItem, .addImageItem, .mockupItem, .space, .toolsItem, .space, .colorItem, .strokeItem, .undoItem, .redoItem, .flexibleSpace, .saveAsItem]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func placeholder(_ sym: String, _ label: String) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = symbol(sym, label); item.label = label; item.toolTip = "\(label) (coming soon)"
            item.isBordered = true; item.isEnabled = false
            return item
        }
        switch id {
        case .cropItem: return placeholder("crop", "Crop")
        case .addImageItem: return placeholder("plus.rectangle.on.rectangle", "Add Image")
        case .mockupItem: return placeholder("photo", "Background")
        case .strokeItem: return placeholder("lineweight", "Stroke")
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
                                           images: toolButtons.map { symbol($0.symbol, $0.label) },
                                           selectionMode: .selectOne,
                                           labels: toolButtons.map(\.label),
                                           target: self, action: #selector(toolChanged))
            for (i, b) in toolButtons.enumerated() where i < group.subitems.count {
                let key = Tool.shortcuts.first { $0.value == b.tool }.map { " (\($0.key.uppercased()))" } ?? ""
                group.subitems[i].toolTip = b.tool == nil ? "\(b.label) (coming soon)" : b.label + key
                group.subitems[i].isEnabled = b.tool != nil
            }
            group.selectedIndex = toolButtons.firstIndex { $0.tool == canvas.tool } ?? 0
            group.label = "Tools"
            toolGroup = group
            return group
        case .colorItem:
            let well = NSColorWell(style: .minimal)
            well.color = canvas.color
            well.target = self; well.action = #selector(colorChanged(_:))
            colorWell = well
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 32).isActive = true
            well.heightAnchor.constraint(equalToConstant: 28).isActive = true
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = well; item.label = "Color"; item.toolTip = "Color"
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

    // MARK: Actions

    @objc private func toolChanged() {
        guard let i = toolGroup?.selectedIndex, toolButtons.indices.contains(i), let t = toolButtons[i].tool else { return }
        canvas.tool = t
        window?.makeFirstResponder(canvas)
    }
    private func selectToolButton(_ t: Tool) {
        if let i = toolButtons.firstIndex(where: { $0.tool == t }) { toolGroup?.selectedIndex = i }
    }
    @objc private func colorChanged(_ w: NSColorWell) { canvas.applyColor(w.color) }
    @objc private func copyIt() { Output.copy(canvas.flattened()) }
    @objc private func saveIt() { Output.saveAs(canvas.flattened()) }
    @objc private func pinIt() { PinnedScreenshotController.pin(canvas.flattened()) }
    @objc private func shareIt(_ sender: NSButton) {
        NSSharingServicePicker(items: [canvas.flattened()]).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    @objc private func undoIt() { canvas.undo() }
    @objc private func redoIt() { canvas.redo() }
}
