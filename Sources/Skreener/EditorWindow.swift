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

/// The centered "Drag Me" pill: drag it to drop the annotated image as a file (PNG or JPEG, per Settings) anywhere.
private final class DragPill: NSView, NSDraggingSource {
    var imageProvider: () -> NSImage = { NSImage() }
    private var dragStarted = false

    override var intrinsicContentSize: NSSize { NSSize(width: 104, height: 26) }
    override func mouseDown(with event: NSEvent) { dragStarted = false }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        let image = imageProvider()
        guard let url = Output.temporaryFile(image) else { return }
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
        for side in [bounds.minX + 12, bounds.maxX - 22] {
            for i in 0..<3 {
                let y = bounds.midY - 3 + CGFloat(i) * 3
                let p = NSBezierPath(); p.lineWidth = 1; p.lineCapStyle = .round
                p.move(to: NSPoint(x: side, y: y)); p.line(to: NSPoint(x: side + 10, y: y)); p.stroke()
            }
        }
        let text = "Drag Me" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                    .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

private extension NSToolbarItem.Identifier {
    static let imageActionsItem = NSToolbarItem.Identifier("skreener.imageActions")
    static let toolsItem = NSToolbarItem.Identifier("skreener.tools")
    static let undoRedoItem = NSToolbarItem.Identifier("skreener.undoRedo")
    static let saveAsItem = NSToolbarItem.Identifier("skreener.saveAs")
    static let settingsItem = NSToolbarItem.Identifier("skreener.settings")
}

private func symbol(_ name: String, _ description: String? = nil) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: description)
        ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil) ?? NSImage()
}

/// Small control size (with the matching font) for the editor's controls, so the toolbar, style bar and
/// footer fit the minimum window size.
@MainActor private func compact<C: NSControl>(_ c: C) -> C {
    c.controlSize = .small
    c.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
    return c
}

/// `compact`, plus a visible bezel so the button reads as a button rather than a bare icon.
@MainActor private func bordered<B: NSButton>(_ b: B) -> B {
    b.bezelStyle = .texturedRounded
    return compact(b)
}

/// An image-only bordered button, `width` points wide.
@MainActor private func iconButton(_ sym: String, _ tip: String, _ target: AnyObject?, _ action: Selector, width: CGFloat = 30) -> NSButton {
    let b = bordered(NSButton(image: symbol(sym, tip), target: target, action: action))
    b.imagePosition = .imageOnly
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: width).isActive = true
    return b
}

/// An image-only bordered pull-down button that opens `menu` (its first item is the button face).
@MainActor private func iconMenuButton(_ sym: String, _ tip: String, _ menu: NSMenu) -> NSPopUpButton {
    let b = bordered(NSPopUpButton(frame: .zero, pullsDown: true))
    let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    face.image = symbol(sym, tip)
    menu.insertItem(face, at: 0)
    b.menu = menu
    b.imagePosition = .imageOnly
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 42).isActive = true
    return b
}

/// A toolbar item that shows `views` side by side.
@MainActor private func groupItem(_ id: NSToolbarItem.Identifier, _ label: String, _ views: [NSView], spacing: CGFloat = 4) -> NSToolbarItem {
    let row = NSStackView(views: views)
    row.spacing = spacing
    let item = NSToolbarItem(itemIdentifier: id)
    item.view = row; item.label = label
    return item
}

/// CleanShot-style editor: unified titlebar toolbar, centered zoomable canvas, footer with zoom / Drag Me / actions.
/// The window never gets smaller than `minimumSize`.
final class EditorWindowController: NSWindowController, NSToolbarDelegate, NSMenuDelegate {
    static let minimumSize = NSSize(width: 990, height: 750)
    static var live: [EditorWindowController] = []
    /// Set by the app: lets the user pick an area on screen and hands back the capture (nil if cancelled).
    static var captureArea: ((@escaping (NSImage?) -> Void) -> Void)?

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
        ("drop.halffull", .blur),
        ("flashlight.on.fill", .spotlight),
        ("1.circle.fill", .counter),
        ("pencil.tip", .pen),
        ("highlighter", .highlighter),
    ]

    private let image: NSImage
    private let canvas: CanvasView
    private let scroll = ZoomingScrollView()
    private let zoomButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var toolSegments: NSSegmentedControl?
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
    private let cornerStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let arrowStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let arrangeButton = NSPopUpButton(frame: .zero, pullsDown: true)
    /// Add Image → From Capture History; filled in each time it opens.
    private let historyMenu = NSMenu(title: "From Capture History")
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

    /// `title` names the editor's tab; it defaults to the time the editor opened.
    init(image: NSImage, title: String? = nil) {
        self.image = image
        canvas = CanvasView(image: image)

        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let floor = EditorWindowController.minimumSize
        let size = NSSize(width: max(floor.width, min(image.size.width + 120, visible.width)),
                          height: max(floor.height, min(image.size.height + 200, visible.height)))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        w.title = title ?? "Screenshot \(time)"
        // Editors open as tabs of one window (Settings → Editor can turn that off).
        w.tabbingIdentifier = "skreener.editor"
        w.tabbingMode = Preferences.editorTabs ? .preferred : .disallowed
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
        if let w = window, Preferences.editorTabs, let host = Self.tabHost(excluding: w) {
            host.addTabbedWindow(w, ordered: .above)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.layoutIfNeeded()
        window?.makeFirstResponder(canvas)
        applyFit()
    }

    /// The editor window a new editor joins as a tab: the frontmost visible one.
    private static func tabHost(excluding w: NSWindow) -> NSWindow? {
        let editors = live.compactMap(\.window).filter { $0 !== w && $0.isVisible && !$0.isMiniaturized && $0.tabbingMode != .disallowed }
        if let key = NSApp.keyWindow, editors.contains(where: { $0 === key }) { return key }
        return NSApp.orderedWindows.first { win in editors.contains { $0 === win } }
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
            strip.heightAnchor.constraint(equalToConstant: 34),
            scroll.topAnchor.constraint(equalTo: strip.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func buildAttributesStrip() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .withinWindow
        bar.state = .followsWindowActiveState
        attributesTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        attributesTitle.textColor = .secondaryLabelColor
        attributesHint.font = .systemFont(ofSize: 11)
        attributesHint.textColor = .tertiaryLabelColor
        let row = NSStackView(views: [attributesTitle, attributesBar, attributesHint, cropBar, backgroundBar])
        row.spacing = 10
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
        _ = bordered(zoomButton)
        zoomButton.menu = NSMenu()
        zoomButton.menu?.addItem(withTitle: "100%", action: nil, keyEquivalent: "")
        for (title, tag) in [("Fit", 0), ("25%", 25), ("50%", 50), ("100%", 100), ("200%", 200), ("400%", 400)] {
            let item = NSMenuItem(title: title, action: #selector(zoomPicked(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag
            zoomButton.menu?.addItem(item)
        }
        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let pill = DragPill()
        pill.imageProvider = { [weak self] in self?.canvas.flattened() ?? NSImage() }
        pill.translatesAutoresizingMaskIntoConstraints = false

        let actions = [("square.and.arrow.up", "Share", #selector(shareIt(_:))),
                       ("pin", "Pin to Screen", #selector(pinIt)),
                       ("doc.on.doc", "Copy", #selector(copyIt)),
                       ("square.and.arrow.down", "Save", #selector(saveIt))].map { sym, tip, sel in
            iconButton(sym, tip, self, sel, width: 34)
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
            pill.widthAnchor.constraint(equalToConstant: 104), pill.heightAnchor.constraint(equalToConstant: 26),
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
        // Compact bordered controls (rather than standard toolbar items) so everything fits the minimum width.
        [.imageActionsItem, .toolsItem, .undoRedoItem, .flexibleSpace, .settingsItem, .saveAsItem]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        /// A menu of canvas commands.
        func commands(_ list: [(String, Selector)]) -> NSMenu {
            let m = NSMenu()
            for (title, action) in list {
                let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
                i.target = canvas
                m.addItem(i)
            }
            return m
        }
        switch id {
        case .imageActionsItem:
            return groupItem(id, "Image", [
                iconButton("crop", "Crop (C)", self, #selector(cropIt)),
                iconMenuButton("rotate.right", "Rotate or flip the screenshot and its annotations", commands(CanvasView.imageCommands)),
                iconMenuButton("plus.rectangle.on.rectangle",
                               "Add an image from a new capture, the capture history, a file or the clipboard", buildAddImageMenu()),
                iconButton("photo", "Background", self, #selector(backgroundIt)),
                iconMenuButton("eye.slash", "Find text in the screenshot and pixelate it", commands(CanvasView.redactCommands)),
            ])
        case .toolsItem:
            let seg = compact(NSSegmentedControl(images: toolButtons.map { symbol($0.symbol, $0.tool.name) },
                                                 trackingMode: .selectOne, target: self, action: #selector(toolChanged)))
            seg.segmentStyle = .separated
            for (i, b) in toolButtons.enumerated() {
                let key = Tool.shortcuts.first { $0.value == b.tool }.map { " (\($0.key.uppercased()))" } ?? ""
                seg.setToolTip(b.tool.name + key, forSegment: i)
                seg.setWidth(26, forSegment: i)
            }
            seg.selectedSegment = toolButtons.firstIndex { $0.tool == canvas.tool } ?? 0
            seg.setAccessibilityLabel("Tools")
            toolSegments = seg
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = seg; item.label = "Tools"
            return item
        case .undoRedoItem:
            return groupItem(id, "Undo", [iconButton("arrow.uturn.backward", "Undo (⌘Z)", self, #selector(undoIt)),
                                          iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)", self, #selector(redoIt))])
        case .settingsItem:
            return groupItem(id, "Settings", [iconButton("gearshape", "Settings (⌘,)", self, #selector(openSettings))])
        case .saveAsItem:
            let b = compact(NSButton(title: "Save as…", target: self, action: #selector(saveIt)))
            b.bezelStyle = .rounded
            b.bezelColor = .controlAccentColor
            b.attributedTitle = NSAttributedString(string: "Save as…", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .semibold),
                .foregroundColor: NSColor.white])
            b.keyEquivalent = "s"; b.keyEquivalentModifierMask = [.command, .shift]
            b.toolTip = "Save as… (⇧⌘S)"
            return groupItem(id, "Save as…", [b])
        default: return nil
        }
    }

    // MARK: Attributes bar

    private func buildAttributesBar() {
        attributesBar.orientation = .horizontal
        attributesBar.spacing = 6

        colorWell.target = self; colorWell.action = #selector(colorChanged(_:)); colorWell.toolTip = "Color"
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 30).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true

        func setUp(_ popup: NSPopUpButton, _ tip: String, _ choices: [(String, Int)], _ action: Selector) {
            _ = bordered(popup)
            popup.toolTip = tip
            popup.target = self; popup.action = action
            for (title, tag) in choices { popup.addItem(withTitle: title); popup.lastItem?.tag = tag }
        }
        setUp(strokePopup, "Stroke width", [1, 2, 3, 5, 8, 12].map { ("\($0) pt", $0) }, #selector(strokePicked(_:)))
        setUp(sizePopup, "Font size", [12, 14, 16, 18, 22, 28, 32, 40, 48, 64, 72].map { ("\($0) pt", $0) }, #selector(sizePicked(_:)))
        setUp(pixelPopup, "Strength", [("Light", 6), ("Medium", 10), ("Strong", 18), ("Heavy", 28)], #selector(pixelPicked(_:)))
        setUp(cornerStylePopup, "Corners", [("Sharp Corners", 0), ("Slightly Rounded", 2), ("Rounded", 8), ("Very Rounded", 16)],
              #selector(cornerPicked(_:)))
        setUp(arrowStylePopup, "Arrow style", [("Filled Head", ArrowStyle.filled.rawValue), ("Open Head", ArrowStyle.open.rawValue),
                                               ("Double-Headed", ArrowStyle.double.rawValue)], #selector(arrowStylePicked(_:)))
        setUp(fontPopup, "Font", [], #selector(fontPicked(_:)))
        for (title, name) in Self.fontChoices {
            fontPopup.addItem(withTitle: title)
            fontPopup.lastItem?.representedObject = name
            if let f = NSFont(name: name, size: NSFont.systemFontSize(for: .small)) {
                fontPopup.lastItem?.attributedTitle = NSAttributedString(string: title, attributes: [.font: f])
            }
        }

        boldButton.image = symbol("bold", "Bold")
        boldButton.setButtonType(.pushOnPushOff)
        _ = bordered(boldButton)
        boldButton.imagePosition = .imageOnly
        boldButton.toolTip = "Bold"
        boldButton.target = self; boldButton.action = #selector(boldToggled(_:))

        _ = bordered(arrangeButton)
        arrangeButton.toolTip = "Arrange: move the selection in front of or behind other annotations"
        arrangeButton.addItem(withTitle: "Arrange")
        arrangeButton.lastItem?.image = symbol("square.3.layers.3d", "Arrange")
        // Shortcuts live in the Arrange menu bar menu; repeating them here would fire twice.
        for (title, action, _, _) in CanvasView.arrangeCommands {
            arrangeButton.addItem(withTitle: title)
            arrangeButton.lastItem?.action = action
            arrangeButton.lastItem?.target = canvas
        }

        [colorWell, strokePopup, arrowStylePopup, cornerStylePopup, fontPopup, sizePopup, boldButton, pixelPopup,
         arrangeButton].forEach(attributesBar.addArrangedSubview)
        refreshStrip()
    }

    private func buildCropBar() {
        let hint = NSTextField(labelWithString: "Drag the corners or draw a new area · Return to apply · Esc to cancel")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        let reset = NSButton(title: "Reset", target: self, action: #selector(cropReset))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cropCancel))
        let apply = NSButton(title: "Apply", target: self, action: #selector(cropApply))
        apply.bezelColor = .controlAccentColor
        [reset, cancel, apply].forEach { _ = bordered($0) }
        [hint, reset, cancel, apply].forEach(cropBar.addArrangedSubview)
        cropBar.spacing = 8
        cropBar.isHidden = true
    }

    private func buildBackgroundBar() {
        _ = bordered(fillPopup)
        fillPopup.toolTip = "Fill"
        fillPopup.target = self; fillPopup.action = #selector(backgroundChanged)
        fillPopup.autoenablesItems = false
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
        fillPopup.menu?.addItem(.separator())
        fillPopup.addItem(withTitle: "Desktop Wallpaper")
        fillPopup.lastItem?.tag = Background.wallpaperFill
        refreshWallpaperItem()
        for (popup, tip, choices) in [(paddingPopup, "Padding", [16, 32, 48, 64, 96, 128]), (cornerPopup, "Corner radius", [0, 6, 10, 16, 24])] {
            _ = bordered(popup)
            popup.toolTip = tip
            popup.target = self; popup.action = #selector(backgroundChanged)
            for v in choices { popup.addItem(withTitle: "\(tip == "Padding" ? "Padding" : "Corners") \(v) pt"); popup.lastItem?.tag = v }
        }
        _ = compact(bgShadowBox)
        bgShadowBox.target = self; bgShadowBox.action = #selector(backgroundChanged)
        [fillPopup, paddingPopup, cornerPopup, bgShadowBox].forEach(backgroundBar.addArrangedSubview)
        backgroundBar.spacing = 8
        backgroundBar.isHidden = true
    }

    /// The wallpaper can change while the editor is open, so its swatch is redrawn whenever the options show.
    private func refreshWallpaperItem() {
        guard let item = fillPopup.menu?.items.first(where: { $0.tag == Background.wallpaperFill }) else { return }
        let available = Background.wallpaper != nil
        item.isEnabled = available
        item.title = available ? "Desktop Wallpaper" : "Desktop Wallpaper (unavailable)"
        item.toolTip = available ? nil : "The current wallpaper is not a still image (for example a dynamic or aerial wallpaper)."
        item.image = nil
        guard available else { return }
        item.image = NSImage(size: NSSize(width: 26, height: 14), flipped: false) { r in
            let clip = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            clip.addClip()
            Background.draw(fill: Background.wallpaperFill, in: r)
            NSColor.separatorColor.setStroke(); clip.stroke()
            return true
        }
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
            refreshWallpaperItem()
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
        colorWell.isHidden = [.select, .pixelate, .blur, .spotlight, .image].contains(tool)
        strokePopup.isHidden = !tool.usesStroke
        [fontPopup, boldButton].forEach { $0.isHidden = tool != .text }
        sizePopup.isHidden = tool != .text && tool != .counter
        pixelPopup.isHidden = !tool.obscures
        cornerStylePopup.isHidden = !tool.hasCorners
        arrowStylePopup.isHidden = tool != .arrow
        arrangeButton.isHidden = !canvas.hasSelection

        colorWell.color = style.color
        strokePopup.selectItem(withTag: Int(style.lineWidth))
        sizePopup.selectItem(withTag: Int(style.fontSize))
        pixelPopup.selectItem(withTag: Int(style.pixelSize))
        cornerStylePopup.selectItem(withTag: Int(style.cornerRadius))
        arrowStylePopup.selectItem(withTag: style.arrowStyle.rawValue)
        if let i = fontPopup.itemArray.firstIndex(where: { $0.representedObject as? String == style.fontName }) {
            fontPopup.selectItem(at: i)
        }
        boldButton.state = style.bold ? .on : .off
    }

    @objc private func colorChanged(_ w: NSColorWell) { canvas.updateStyle { $0.color = w.color } }
    @objc private func strokePicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.lineWidth = CGFloat(p.selectedTag()) } }
    @objc private func sizePicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.fontSize = CGFloat(p.selectedTag()) } }
    @objc private func pixelPicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.pixelSize = CGFloat(p.selectedTag()) } }
    @objc private func cornerPicked(_ p: NSPopUpButton) { canvas.updateStyle { $0.cornerRadius = CGFloat(p.selectedTag()) } }
    @objc private func arrowStylePicked(_ p: NSPopUpButton) {
        canvas.updateStyle { $0.arrowStyle = ArrowStyle(rawValue: p.selectedTag()) ?? .filled }
    }
    @objc private func fontPicked(_ p: NSPopUpButton) {
        let name = p.selectedItem?.representedObject as? String ?? ""
        canvas.updateStyle { $0.fontName = name }
    }
    @objc private func boldToggled(_ b: NSButton) { canvas.updateStyle { $0.bold = b.state == .on } }

    // MARK: Actions

    @objc private func toolChanged() {
        guard let i = toolSegments?.selectedSegment, toolButtons.indices.contains(i) else { return }
        canvas.applyCrop()
        canvas.tool = toolButtons[i].tool
        if stripMode == .background { stripMode = .tools }
        window?.makeFirstResponder(canvas)
    }
    private func selectToolButton(_ t: Tool) {
        if let i = toolButtons.firstIndex(where: { $0.tool == t }) { toolSegments?.selectedSegment = i }
    }
    @objc private func copyIt() { Output.copy(canvas.flattened()) }
    @objc private func saveIt() { Output.saveAs(canvas.flattened()) }
    @objc private func pinIt() { PinnedScreenshotController.pin(canvas.flattened()) }
    @objc private func shareIt(_ sender: NSButton) { Output.share(canvas.flattened(), from: sender) }
    @MainActor @objc private func openSettings() { SettingsWindowController.shared.present() }
    @objc private func undoIt() { canvas.undo() }
    @objc private func cropIt() {
        if canvas.isCropping { canvas.applyCrop() } else { canvas.beginCrop() }
        window?.makeFirstResponder(canvas)
    }
    @objc private func cropApply() { canvas.applyCrop(); window?.makeFirstResponder(canvas) }
    @objc private func cropCancel() { canvas.cancelCrop(); window?.makeFirstResponder(canvas) }
    @objc private func cropReset() { canvas.resetCrop(); window?.makeFirstResponder(canvas) }
    @MainActor @objc private func addImageFromFile() {
        guard let w = window else { return }
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = p.url, let img = NSImage(contentsOf: url) else { return }
            self?.canvas.insertImage(img)
        }
    }
    @objc private func addImageFromHistory(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL, let img = NSImage(contentsOf: url) else { NSSound.beep(); return }
        canvas.insertImage(img)
    }
    @objc private func addImageFromClipboard() { canvas.paste(nil) }
    /// Hides this editor, lets the user pick an area, then adds the capture to the canvas.
    @objc private func addImageFromCapture() {
        guard let capture = Self.captureArea, let w = window else { return }
        // Fade out rather than order out: ordering a tab out would take it out of its tab group.
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        capture { [weak self] img in
            w.alphaValue = 1
            w.ignoresMouseEvents = false
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let img { self?.canvas.insertImage(img) }
        }
    }

    private func buildAddImageMenu() -> NSMenu {
        let m = NSMenu()
        for (title, sym, sel) in [("Capture Area…", "camera.viewfinder", #selector(addImageFromCapture)),
                                  ("Open File…", "folder", #selector(addImageFromFile)),
                                  ("Paste from Clipboard", "doc.on.clipboard", #selector(addImageFromClipboard))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.image = symbol(sym, title)
            m.addItem(i)
        }
        let history = NSMenuItem(title: "From Capture History", action: nil, keyEquivalent: "")
        history.image = symbol("clock.arrow.circlepath", "Capture History")
        historyMenu.delegate = self
        history.submenu = historyMenu
        m.insertItem(history, at: 1)
        return m
    }

    /// Fills Add Image → From Capture History with the newest captures, as thumbnails.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === historyMenu else { return }
        menu.removeAllItems()
        let entries = CaptureHistory.entries().prefix(20)
        if entries.isEmpty {
            let none = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        for e in entries {
            let i = NSMenuItem(title: f.localizedString(for: e.date, relativeTo: Date()), action: #selector(addImageFromHistory(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = e.url
            if let thumb = CaptureHistory.thumbnail(e.url, maxPixels: 160) {
                let h: CGFloat = 40
                thumb.size = NSSize(width: max(1, h * thumb.size.width / max(thumb.size.height, 1)).rounded(), height: h)
                i.image = thumb
            }
            menu.addItem(i)
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
