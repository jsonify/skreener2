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

/// Mouse navigation: the wheel scrolls up and down, Shift + wheel scrolls sideways, ⌘ + wheel (or ⌘ + trackpad
/// scroll) zooms around the pointer, and dragging with the wheel held down (the middle button) moves the canvas.
/// Trackpad scrolling still pans and pinch still zooms.
private final class ZoomingScrollView: NSScrollView {
    var onZoom: (() -> Void)?
    /// While dragging with the middle button: the pointer's last position (window coordinates).
    private var panLast: NSPoint?

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: Self.sideways(event) ?? event)
            return
        }
        let isWheel = !event.hasPreciseScrollingDeltas
        guard allowsMagnification, let doc = documentView, event.scrollingDeltaY != 0 else { return }
        // Wheel away from you zooms in, whatever the "natural scrolling" setting.
        let dy = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let factor = exp(dy * (isWheel ? 0.1 : 0.01))
        let target = min(maxMagnification, max(minMagnification, magnification * factor))
        setMagnification(target, centeredAt: doc.convert(event.locationInWindow, from: nil))
        onZoom?()
    }

    /// A Shift + mouse-wheel event turned into a sideways scroll, for mice where macOS leaves it vertical; nil for
    /// anything else.
    private static func sideways(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.shift), !event.hasPreciseScrollingDeltas,
              event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let cg = event.cgEvent?.copy() else { return nil }
        let swaps: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
        ]
        for (vertical, horizontal) in swaps {
            cg.setIntegerValueField(horizontal, value: cg.getIntegerValueField(vertical))
            cg.setIntegerValueField(vertical, value: 0)
        }
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        return NSEvent(cgEvent: cg)
    }

    // The canvas passes middle-button events up the responder chain to here.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseDown(with: event); return }
        panLast = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let last = panLast else { super.otherMouseDragged(with: event); return }
        let p = event.locationInWindow
        panLast = p
        let clip = contentView
        let scale = max(magnification, 0.01)
        var origin = clip.bounds.origin
        origin.x -= (p.x - last.x) / scale
        origin.y += (clip.isFlipped ? 1 : -1) * (p.y - last.y) / scale
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        reflectScrolledClipView(clip)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard panLast != nil, event.buttonNumber == 2 else { super.otherMouseUp(with: event); return }
        panLast = nil
        NSCursor.pop()
    }
}

/// The centered "Drag Me" pill: drag it to drop the annotated image as a file (PNG or JPEG, per Settings) anywhere.
/// While dragging, Skreener hides so the drop target is visible, and a small preview rides under the pointer;
/// a cancelled drag brings it back. After a drop it stays hidden (Dock icon or ⌘-Tab shows the editor again).
private final class DragPill: NSView, NSDraggingSource {
    var imageProvider: () -> NSImage = { NSImage() }
    private var dragStarted = false
    /// The drag preview's size, with the pointer over its bottom-right quadrant.
    private static let previewSize = NSSize(width: 100, height: 85)

    override var intrinsicContentSize: NSSize { NSSize(width: 112, height: 34) }
    override func mouseDown(with event: NSEvent) { dragStarted = false }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        let image = imageProvider()
        guard let url = Output.temporaryFile(image) else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let size = Self.previewSize
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - size.width * 0.75, y: p.y - size.height * 0.25, width: size.width, height: size.height),
                              contents: Self.preview(image, size: size))
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        NSApp.hide(nil)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty { NSApp.unhide(nil) }
    }

    /// The screenshot filling a small rounded card (cropped to the card's shape), with a hairline border.
    private static func preview(_ image: NSImage, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            let card = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            card.addClip()
            let scale = max(r.width / max(image.size.width, 1), r.height / max(image.size.height, 1))
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.6).setStroke()
            card.lineWidth = 1
            card.stroke()
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Outlined rather than raised: it is dragged, not clicked.
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill(); pill.fill()
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
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .regular),
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

/// Height of the editor's pills: small enough for everything to fit the minimum window width.
private let pillHeight: CGFloat = 26

/// A symbol-only pill (a circle) that sends `action` to `target`.
@MainActor private func iconButton(_ sym: String, _ tip: String, _ target: AnyObject?, _ action: Selector,
                                   style: PillButton.Style = .raised, height: CGFloat = pillHeight) -> PillButton {
    let b = PillButton(title: nil, symbol: sym, style: style, height: height)
    b.target = target; b.action = action
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    return b
}

/// A titled pill that sends `action` to `target`; `filled` for the main action.
@MainActor private func textButton(_ title: String, _ target: AnyObject?, _ action: Selector, filled: Bool = false) -> PillButton {
    let b = PillButton(title: title, symbol: nil, style: filled ? .filled : .raised, height: pillHeight)
    b.target = target; b.action = action
    return b
}

/// A symbol pill with a ▾ that opens `menu`.
@MainActor private func iconMenuButton(_ sym: String, _ tip: String, _ menu: NSMenu) -> PillPopUp {
    let b = PillPopUp(pullsDown: true, height: pillHeight)
    menu.insertItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""), at: 0)   // the pull-down's face
    b.menu = menu
    b.setContent(title: nil, symbol: sym)
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    return b
}

/// Raised pills side by side, with room around them for their shadows.
@MainActor private func pillRow(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
    let row = NSStackView(views: views)
    row.spacing = spacing
    row.edgeInsets = NSEdgeInsets(top: 3, left: 2, bottom: 3, right: 2)
    return row
}

/// A toolbar item that shows `views` side by side, or on a grey group capsule (for `.plain` pills).
@MainActor private func groupItem(_ id: NSToolbarItem.Identifier, _ label: String, _ views: [NSView],
                                  grouped: Bool = false) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: id)
    item.view = grouped ? PillBar(views) : pillRow(views); item.label = label
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
        ("eraser", .erase),
        ("flashlight.on.fill", .spotlight),
        ("magnifyingglass", .magnifier),
        ("1.circle.fill", .counter),
        ("pencil.tip", .pen),
        ("highlighter", .highlighter),
    ]

    private let image: NSImage
    private let canvas: CanvasView
    private let scroll = ZoomingScrollView()
    private let zoomButton = PillPopUp(pullsDown: true, height: 28)
    /// The color under the pointer in the chosen format (#108); its menu picks the format and offers the color tools.
    private let colorReadout = PillPopUp(pullsDown: true, height: 28)
    private var toolPills: [PillButton] = []
    // Contextual attributes bar under the toolbar: only the controls that apply to the current tool or
    // selection are shown. It lives outside the toolbar so the tool buttons always have room.
    private let attributesBar = NSStackView()
    private let attributesTitle = NSTextField(labelWithString: "")
    private let attributesHint = NSTextField(labelWithString: "Select an annotation to change its style")
    private let colorWell = ColorPill(size: pillHeight)
    private let strokePopup = PillPopUp(pullsDown: false)
    private let fontPopup = PillPopUp(pullsDown: false)
    private let sizePopup = PillPopUp(pullsDown: false)
    /// The font sizes the size popup offers.
    static let fontSizes = [12, 14, 16, 18, 22, 28, 32, 40, 48, 64, 72]
    private let boldButton = PillButton(title: nil, symbol: "bold", style: .raised, height: pillHeight)
    private let pixelPopup = PillPopUp(pullsDown: false)
    private let cornerStylePopup = PillPopUp(pullsDown: false)
    private let arrowStylePopup = PillPopUp(pullsDown: false)
    private let textOnlyButton = PillButton(title: "Text Only", symbol: "text.viewfinder", style: .raised, height: pillHeight)
    private let magnificationPopup = PillPopUp(pullsDown: false)
    private let lensShapePopup = PillPopUp(pullsDown: false)
    private let shapeFillPopup = PillPopUp(pullsDown: false)
    private let textBoxPopup = PillPopUp(pullsDown: false)
    private let tailButton = PillButton(title: "Tail", symbol: "bubble.left", style: .raised, height: pillHeight)
    private let handDrawnButton = PillButton(title: "Hand-Drawn", symbol: "scribble", style: .raised, height: pillHeight)
    private let shapeCorrectionButton = PillButton(title: "Shapes", symbol: "pencil.and.outline", style: .raised, height: pillHeight)
    private let arrowLabelButton = PillButton(title: "Label", symbol: "text.bubble", style: .raised, height: pillHeight)
    private let arrangeButton = PillPopUp(pullsDown: true)
    /// Add Image → From Capture History; filled in each time it opens.
    private let historyMenu = NSMenu(title: "From Capture History")
    // Crop, Background and the area picks (Copy Text from Area, average color, contrast) replace the tool options in
    // the same strip while they are active.
    private enum StripMode { case tools, crop, areaPick, background, deviceFrame }
    private var stripMode = StripMode.tools {
        didSet { refreshStrip() }
    }
    private let cropBar = NSStackView()
    private let areaBar = NSStackView()
    private let areaHint = NSTextField(labelWithString: "")
    private let contrastLabel = NSTextField(labelWithString: "")
    private lazy var copyAllTextButton = textButton("Copy All Text", canvas, #selector(CanvasView.copyAllText(_:)))
    private lazy var contrastMethodButton = textButton("WCAG 2", self, #selector(contrastMethodToggled))
    private lazy var areaDoneButton = textButton("Cancel", self, #selector(areaPickCancel))
    private let backgroundBar = NSStackView()
    private let fillPopup = PillPopUp(pullsDown: false)
    private let paddingPopup = PillPopUp(pullsDown: false)
    private let cornerPopup = PillPopUp(pullsDown: false)
    private let directionPopup = PillPopUp(pullsDown: false)
    private let gradientFrom = ColorPill()
    private let gradientTo = ColorPill()
    private lazy var chooseImageButton = textButton("Choose…", self, #selector(chooseBackgroundImage))
    private let blurPopup = PillPopUp(pullsDown: false)
    private let aspectPopup = PillPopUp(pullsDown: false)
    private let framePopup = PillPopUp(pullsDown: true)
    private let deviceFrameBar = NSStackView()
    private let deviceKindPopup = PillPopUp(pullsDown: false)
    private let deviceLookPopup = PillPopUp(pullsDown: false)
    private let deviceURLField = NSTextField(string: "")
    private let shadowLabel = NSTextField(labelWithString: "Shadow")
    private let shadowSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    /// Tags of the Frame menu's items: an inset, or the whole image's corner radius, plus the value in points.
    private static let insetTag = 1000, outerCornerTag = 2000
    private static let fontChoices = [("System", ""), ("Helvetica Neue", "Helvetica Neue"), ("Avenir Next", "Avenir Next"),
                                      ("Georgia", "Georgia"), ("Menlo", "Menlo"), ("Marker Felt", "Marker Felt"),
                                      ("Chalkboard SE", "Chalkboard SE")]
    private var fitMode = true
    /// The editors shown as tabs with this one (just this one when it has a window to itself).
    lazy var tabGroup = EditorTabGroup(self)
    private let dock = EditorDock()
    private var dockWidth: NSLayoutConstraint?
    /// The dock on the left (`[0]`) or on the right (`[1]`) of the canvas (Settings → Annotate).
    private var dockSides: [[NSLayoutConstraint]] = [[], []]
    /// The footer's button that shows or hides the dock; only there while the window holds several screenshots.
    private lazy var dockButton = iconButton("sidebar.left", "Show Screenshots (⌃⌘S)", self, #selector(toggleDockPressed), height: 28)
    private var thumbnailCache: (revision: Int, image: NSImage)?
    private var dockRefreshTask: Task<Void, Never>?
    private let toastBox = NSView()
    private let toastLabel = NSTextField(labelWithString: "")
    private var toastTask: Task<Void, Never>?

    /// The file this screenshot was saved to or opened from: Save writes the edited image over it (#118).
    private(set) var fileURL: URL? {
        didSet {
            guard let url = fileURL, url != oldValue else { return }
            window?.title = url.deletingPathExtension().lastPathComponent
            tabGroup.refresh()
        }
    }

    /// The capture-history entry this editor keeps its document in, and what was last written there (#30).
    private var historyEntry: URL?
    private var historyBase: NSImage?
    private var historyRevision = 0
    private var historySaveTask: Task<Void, Never>?

    /// Ties the editor to a capture in the history: its annotations, crop and background are kept there as it is
    /// edited, so the capture can be reopened and edited further. `document` is the one already saved there, if any.
    func attachHistory(_ png: URL, document: EditorDocument? = nil) {
        historyEntry = png
        historyBase = document == nil ? nil : canvas.base   // a loaded screenshot is already on disk
        if let document { canvas.load(document) }
        historyRevision = canvas.revision
    }

    /// Saves about a second after the last edit, so a stream of edits makes one write.
    private func scheduleHistorySave() {
        guard historyEntry != nil else { return }
        historySaveTask?.cancel()
        historySaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            // Not in the middle of typing or choosing a crop: saving would end that.
            if self.canvas.isBusy { self.scheduleHistorySave() } else { self.saveHistoryDocument() }
        }
    }

    private func saveHistoryDocument() {
        guard let png = historyEntry, canvas.revision != historyRevision else { return }
        historySaveTask?.cancel()
        historyRevision = canvas.revision
        let base = canvas.base
        let changedBase = historyBase !== base
        historyBase = base
        CaptureHistory.saveDocument(canvas.document, base: changedBase ? base : nil, flattened: canvas.flattened(), for: png)
    }

    /// `title` names the editor's tab; it defaults to the time the editor opened, or the name of `file`, the file the
    /// screenshot was saved to or opened from.
    init(image: NSImage, title: String? = nil, file: URL? = nil) {
        self.image = image
        fileURL = file
        canvas = CanvasView(image: image)

        let floor = EditorWindowController.minimumSize
        let size = Self.frame(for: image.size, on: NSScreen.main ?? NSScreen.screens[0]).size
        let w = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        w.title = title ?? file?.deletingPathExtension().lastPathComponent ?? "Screenshot \(time)"
        // Editors open as tabs of one window (Settings → Editor can turn that off), drawn by `EditorTabGroup`
        // rather than AppKit.
        w.tabbingMode = .disallowed
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
            guard let self else { return }
            EditorWindowController.live.removeAll { $0 === self }
            // Posted on the main thread (and delivered on the main queue).
            MainActor.assumeIsolated { self.saveHistoryDocument(); self.tabGroup.remove(self) }
            Task { @MainActor in DockPresence.update() }
        }
        // Picked in the Window menu while it was a hidden tab: show it in place of the current one.
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.tabGroup.selected !== self { self.tabGroup.select(self) }
            }
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
        canvas.onBackgroundChange = { [weak self] in
            if self?.stripMode == .background || self?.stripMode == .deviceFrame { self?.refreshStrip() }
        }
        canvas.onAreaPickChange = { [weak self] kind in
            if kind != .contrast { self?.contrastLabel.stringValue = "" }
            self?.stripMode = kind == nil ? .tools : .areaPick
        }
        canvas.onTextCopied = { [weak self] text in self?.textCopied(text) }
        canvas.onEscape = { [weak self] in self?.escapePressed() }
        canvas.onColorCopied = { [weak self] text in self?.showToast("Copied \(text)") }
        canvas.onMessage = { [weak self] text in self?.showToast(text) }
        canvas.onResizeRequest = { [weak self] in self?.showResize() }
        canvas.onHoverColor = { [weak self] c in self?.hoverColor = c; self?.refreshColorReadout() }
        canvas.onContrastChange = { [weak self] line in
            self?.contrastLabel.stringValue = line ?? ""
            self?.refreshStrip()
        }
        canvas.onEdit = { [weak self] in self?.scheduleDockRefresh(); self?.scheduleHistorySave() }
        dock.onSelect = { [weak self] i in self?.selectTab(i) }
        dock.onClose = { [weak self] i in self?.closeTab(i) }
        dock.onCollapse = { [weak self] in self?.toggleDock() }
        dock.menuForItem = { [weak self] i in self?.tabMenu(i) }
        buildAttributesBar()
        buildCropBar()
        buildAreaBar()
        buildBackgroundBar()
        buildDeviceFrameBar()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows this editor again (its tab, if it is one of several), e.g. from its capture's Quick Access preview.
    func reveal() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        tabGroup.select(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens on `screen`, the display the capture came from (#111), or else the one under the pointer. A new tab
    /// joins the open editor window wherever that is.
    func present(on screen: NSScreen? = nil) {
        DockPresence.update()
        if let w = window, Preferences.editorTabs, let host = Self.tabHost(excluding: w)?.windowController as? EditorWindowController {
            host.tabGroup.add(self, after: host)
        } else {
            let mouse = NSEvent.mouseLocation
            if let target = screen ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
                window?.setFrame(Self.frame(for: image.size, on: target), display: false)
            }
            showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.layoutIfNeeded()
        window?.makeFirstResponder(canvas)
        applyFit()
    }

    /// A window fitting `imageSize` with room for the toolbar and footer (within the screen, but never smaller than
    /// `minimumSize`), centered on `screen`.
    private static func frame(for imageSize: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame, floor = minimumSize
        let size = NSSize(width: max(floor.width, min(imageSize.width + 120, visible.width)),
                          height: max(floor.height, min(imageSize.height + 200, visible.height)))
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// The editor window a new editor joins as a tab: the frontmost visible one.
    private static func tabHost(excluding w: NSWindow) -> NSWindow? {
        let editors = live.compactMap(\.window).filter { $0 !== w && $0.isVisible && !$0.isMiniaturized }
        if let key = NSApp.keyWindow, editors.contains(where: { $0 === key }) { return key }
        return NSApp.orderedWindows.first { win in editors.contains { $0 === win } }
    }

    // MARK: Tabs (shown in the side dock, #140)

    func showTabs(_ items: [EditorDock.Item], selected: Int) {
        dock.show(items, selected: selected)
        let several = items.count > 1
        dockButton.isHidden = !several
        let onRight = Preferences.editorDockOnRight
        if dock.onRight != onRight || dockSides[onRight ? 1 : 0].first?.isActive != true {
            dock.onRight = onRight
            NSLayoutConstraint.deactivate(dockSides[onRight ? 0 : 1])
            NSLayoutConstraint.activate(dockSides[onRight ? 1 : 0])
        }
        let open = several && !Preferences.editorDockCollapsed
        dockButton.toolTip = open ? "Hide Screenshots (⌃⌘S)" : "Show Screenshots (⌃⌘S)"
        dockButton.setContent(title: nil, symbol: onRight ? "sidebar.right" : "sidebar.left")
        let width = open ? EditorDock.width : 0
        if dockWidth?.constant != width {
            dockWidth?.constant = width
            dock.isHidden = !open
            if fitMode { window?.layoutIfNeeded(); applyFit() }
        }
    }

    /// Whether the dock is showing (Window menu title).
    var isDockOpen: Bool { tabGroup.editors.count > 1 && !Preferences.editorDockCollapsed }

    /// Shows or hides the dock in every editor window, sliding it in or out of this one.
    func toggleDock() {
        guard tabGroup.editors.count > 1 else { return }
        Preferences.editorDockCollapsed.toggle()
        let open = !Preferences.editorDockCollapsed
        dock.isHidden = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            // The constant changes at once (so `showTabs` below finds it set); the layout pass animates the frames.
            dockWidth?.constant = open ? EditorDock.width : 0
            window?.contentView?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dock.isHidden = Preferences.editorDockCollapsed
                if self.fitMode { self.applyFit() }
            }
        })
        EditorTabGroup.refreshAll()
    }
    @objc private func toggleDockPressed() { toggleDock() }

    /// A small picture of the screenshot with its annotations for the dock, made again only after an edit.
    var dockThumbnail: NSImage {
        if let c = thumbnailCache, c.revision == canvas.revision { return c.image }
        let img = canvas.thumbnail(maxSide: 240)
        thumbnailCache = (canvas.revision, img)
        return img
    }

    /// Updates the dock's thumbnail of this screenshot shortly after edits stop.
    private func scheduleDockRefresh() {
        guard tabGroup.editors.count > 1 else { return }
        dockRefreshTask?.cancel()
        dockRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled, let self else { return }
            self.tabGroup.refresh()
        }
    }

    private func selectTab(_ i: Int) {
        let editors = tabGroup.editors
        if editors.indices.contains(i) { tabGroup.select(editors[i]) }
    }

    private func closeTab(_ i: Int) {
        let editors = tabGroup.editors
        if editors.indices.contains(i) { editors[i].window?.close() }
    }

    private func tabMenu(_ i: Int) -> NSMenu {
        let m = NSMenu()
        let many = tabGroup.editors.count > 1
        for (title, sel, enabled) in [("Close", #selector(closeTabItem(_:)), true),
                                      ("Close Others", #selector(closeOtherTabsItem(_:)), many),
                                      ("Move to New Window", #selector(moveTabItem(_:)), many)] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self; item.tag = i; item.isEnabled = enabled
            m.addItem(item)
        }
        m.autoenablesItems = false
        return m
    }
    @objc private func closeTabItem(_ item: NSMenuItem) { closeTab(item.tag) }
    @objc private func closeOtherTabsItem(_ item: NSMenuItem) {
        let editors = tabGroup.editors
        guard editors.indices.contains(item.tag) else { return }
        let keep = editors[item.tag]
        tabGroup.select(keep)
        for e in editors where e !== keep { e.window?.close() }
    }
    @objc private func moveTabItem(_ item: NSMenuItem) {
        let editors = tabGroup.editors
        if editors.indices.contains(item.tag) { tabGroup.moveToNewWindow(editors[item.tag]) }
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
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.isHidden = true
        let toast = buildToast()
        content.addSubview(scroll); content.addSubview(footer); content.addSubview(strip); content.addSubview(dock)
        content.addSubview(toast)

        let top = (w.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        let width = dock.widthAnchor.constraint(equalToConstant: 0)
        dockWidth = width
        // The dock runs from the attributes strip (which keeps the full width) to the footer, beside the canvas.
        dockSides = [
            [dock.leadingAnchor.constraint(equalTo: content.leadingAnchor),
             scroll.leadingAnchor.constraint(equalTo: dock.trailingAnchor),
             scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor)],
            [dock.trailingAnchor.constraint(equalTo: content.trailingAnchor),
             scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
             scroll.trailingAnchor.constraint(equalTo: dock.leadingAnchor)],
        ]
        NSLayoutConstraint.activate(dockSides[0] + [
            dock.topAnchor.constraint(equalTo: strip.bottomAnchor),
            dock.bottomAnchor.constraint(equalTo: footer.topAnchor),
            width,
            strip.topAnchor.constraint(equalTo: top),
            strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 42),
            scroll.topAnchor.constraint(equalTo: strip.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 50),
            toast.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -16),
            toast.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    /// A short message over the bottom of the canvas (a dark capsule like the tab row), e.g. after Copy Text.
    private func buildToast() -> NSView {
        toastBox.wantsLayer = true
        toastBox.layer?.backgroundColor = PillButton.barColor.cgColor
        toastBox.layer?.cornerRadius = 16
        toastBox.layer?.cornerCurve = .continuous
        toastBox.layer?.borderWidth = 0.5
        toastBox.layer?.borderColor = PillButton.barBorderColor.cgColor
        toastBox.isHidden = true
        toastBox.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = .systemFont(ofSize: 12, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastBox.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.leadingAnchor.constraint(equalTo: toastBox.leadingAnchor, constant: 16),
            toastLabel.trailingAnchor.constraint(equalTo: toastBox.trailingAnchor, constant: -16),
            toastLabel.centerYAnchor.constraint(equalTo: toastBox.centerYAnchor),
        ])
        return toastBox
    }

    private func showToast(_ text: String) {
        toastLabel.stringValue = text
        toastBox.alphaValue = 1
        toastBox.isHidden = false
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.toastBox.animator().alphaValue = 0   // fades over the default animation duration
            // Hidden once faded, so it stops taking clicks meant for the canvas.
            try? await Task.sleep(for: .seconds(0.4))
            if !Task.isCancelled { self.toastBox.isHidden = true }
        }
    }

    private func textCopied(_ text: String) {
        guard !text.isEmpty else { showToast("No text found"); NSSound.beep(); return }
        let lines = text.split(separator: "\n").count
        showToast(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text")
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
        let row = pillRow([attributesTitle, attributesBar, attributesHint, cropBar, areaBar, backgroundBar, deviceFrameBar], spacing: 10)
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
        zoomButton.menu?.addItem(withTitle: "100%", action: nil, keyEquivalent: "")
        for (title, tag) in [("Fit", 0), ("25%", 25), ("50%", 50), ("100%", 100), ("200%", 200), ("400%", 400)] {
            let item = NSMenuItem(title: title, action: #selector(zoomPicked(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag
            zoomButton.menu?.addItem(item)
        }
        zoomButton.toolTip = "Zoom"
        buildColorReadout()
        dockButton.isHidden = true
        let zoomBar = pillRow([dockButton, zoomButton, colorReadout])
        zoomBar.translatesAutoresizingMaskIntoConstraints = false

        let pill = DragPill()
        pill.imageProvider = { [weak self] in self?.canvas.flattened() ?? NSImage() }
        pill.translatesAutoresizingMaskIntoConstraints = false

        let actions = [("sparkles", "Ask Claude: explain, summarize or write alt text", #selector(askClaudeIt)),
                       ("square.and.arrow.up", "Share", #selector(shareIt(_:))),
                       ("pin", "Pin to Screen", #selector(pinIt)),
                       ("doc.on.doc", "Copy", #selector(copyIt)),
                       ("square.and.arrow.down", "Save (⌘S)", #selector(saveIt))].map { sym, tip, sel in
            iconButton(sym, tip, self, sel, height: 28)
        }
        let right = pillRow(actions, spacing: 8)
        right.translatesAutoresizingMaskIntoConstraints = false

        [zoomBar, pill, right].forEach(bar.addSubview)
        NSLayoutConstraint.activate([
            zoomBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            zoomBar.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pill.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 112), pill.heightAnchor.constraint(equalToConstant: 34),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    // MARK: Color readout

    private var hoverColor: RGBColor?

    private func buildColorReadout() {
        colorReadout.toolTip = "The color under the pointer: Tab copies it, ⇧Tab copies the darkest color near it"
        guard let m = colorReadout.menu else { return }
        m.addItem(withTitle: "Color", action: nil, keyEquivalent: "")   // the pull-down's face
        for (title, action) in CanvasView.colorCommands {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = canvas
            m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(.sectionHeader(title: "Color Format"))
        for (n, f) in ColorFormat.allCases.enumerated() {
            let i = NSMenuItem(title: f.title, action: #selector(colorFormatPicked(_:)), keyEquivalent: "")
            i.target = self; i.tag = n
            m.addItem(i)
        }
        m.addItem(.separator())
        m.addItem(.sectionHeader(title: "Keys"))
        for hint in ["Tab: copy the color under the pointer", "⇧Tab: copy the darkest color near the pointer",
                     "⇧C: copy an area's average color", "⇧K: check the contrast of an area",
                     "Hold 1 or 2 (or an arrow key): measure", "Shift while measuring: include the border",
                     "Click while measuring: keep the measurement"] {
            let i = NSMenuItem(title: hint, action: nil, keyEquivalent: "")
            i.isEnabled = false
            m.addItem(i)
        }
        m.autoenablesItems = false
        refreshColorReadout()
    }

    /// Shows the last color the pointer was over (or a placeholder) and ticks the chosen format.
    private func refreshColorReadout() {
        guard let face = colorReadout.menu?.items.first else { return }
        let title = hoverColor.map { Preferences.colorFormat.display(for: $0) } ?? "Color"
        guard face.title != title || face.image == nil else { return }
        face.title = title
        face.image = hoverColor.map(Self.swatch) ?? symbol("eyedropper", "Color")
        colorReadout.synchronizeTitleAndSelectedItem()
        let chosen = ColorFormat.allCases.firstIndex(of: Preferences.colorFormat)
        for item in colorReadout.itemArray where item.action == #selector(colorFormatPicked(_:)) {
            item.state = item.tag == chosen ? .on : .off
        }
    }

    /// A small rounded square of `c`, with a hairline edge so white shows on white.
    private static func swatch(_ c: RGBColor) -> NSImage {
        let color = NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            color.setFill(); p.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke(); p.lineWidth = 1; p.stroke()
            return true
        }
    }

    @objc private func colorFormatPicked(_ item: NSMenuItem) {
        guard ColorFormat.allCases.indices.contains(item.tag) else { return }
        Preferences.colorFormat = ColorFormat.allCases[item.tag]
        // Force the face to redraw even when its text is the same in the new format.
        colorReadout.menu?.items.first?.image = nil
        refreshColorReadout()
        canvas.refreshContrast()
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
        // Pill bars (rather than standard toolbar items), small enough for everything to fit the minimum width.
        [.imageActionsItem, .toolsItem, .undoRedoItem, .flexibleSpace, .settingsItem, .saveAsItem]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        /// A menu of canvas commands, a separator between each list.
        func commands(_ lists: [(String, Selector)]...) -> NSMenu {
            let m = NSMenu()
            for list in lists {
                if m.numberOfItems > 0 { m.addItem(.separator()) }
                for (title, action) in list {
                    let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    i.target = canvas
                    m.addItem(i)
                }
            }
            return m
        }
        switch id {
        case .imageActionsItem:
            return groupItem(id, "Image", [
                iconButton("crop", "Crop (C)", self, #selector(cropIt)),
                iconMenuButton("rotate.right", "Rotate, flip, resize or cut out part of the screenshot",
                               commands(CanvasView.imageCommands, CanvasView.sizeCommands, CanvasView.snapCommands)),
                iconMenuButton("plus.rectangle.on.rectangle",
                               "Add an image from a new capture, the capture history, a file or the clipboard", buildAddImageMenu()),
                iconButton("photo", "Background", self, #selector(backgroundIt)),
                iconButton("macwindow", "Device or browser frame", self, #selector(deviceFrameIt)),
                iconMenuButton("eye.slash", "Find text in the screenshot and pixelate it", commands(CanvasView.redactCommands)),
                iconMenuButton("text.viewfinder", "Copy text from the screenshot (OCR)", commands(CanvasView.textCommands)),
            ])
        case .toolsItem:
            // One pill per tool; the current one is filled.
            toolPills = toolButtons.map { b in
                let key = Tool.shortcuts.first { $0.value == b.tool }.map { " (\($0.key.uppercased()))" } ?? ""
                let pill = iconButton(b.symbol, b.tool.name + key, self, #selector(toolChanged(_:)), style: .plain)
                pill.isOn = b.tool == canvas.tool
                return pill
            }
            let item = groupItem(id, "Tools", toolPills, grouped: true)
            item.view?.setAccessibilityLabel("Tools")
            return item
        case .undoRedoItem:
            return groupItem(id, "Undo", [iconButton("arrow.uturn.backward", "Undo (⌘Z)", self, #selector(undoIt)),
                                          iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)", self, #selector(redoIt))])
        case .settingsItem:
            return groupItem(id, "Settings", [iconButton("gearshape", "Settings (⌘,)", self, #selector(openSettings))])
        case .saveAsItem:
            // ⇧⌘S is in the File menu.
            let b = textButton("Save as…", self, #selector(saveAsIt), filled: true)
            b.toolTip = "Save as… (⇧⌘S)"
            return groupItem(id, "Save as…", [b])
        default: return nil
        }
    }

    // MARK: Attributes bar

    private func buildAttributesBar() {
        attributesBar.orientation = .horizontal
        attributesBar.spacing = 6

        attributesBar.spacing = 6
        colorWell.target = self; colorWell.action = #selector(colorChanged(_:)); colorWell.toolTip = "Color"

        func setUp(_ popup: PillPopUp, _ tip: String, _ choices: [(String, Int)], _ action: Selector) {
            popup.toolTip = tip
            popup.target = self; popup.action = action
            for (title, tag) in choices { popup.addItem(withTitle: title); popup.lastItem?.tag = tag }
        }
        setUp(strokePopup, "Stroke width", [1, 2, 3, 5, 8, 12].map { ("\($0) pt", $0) }, #selector(strokePicked(_:)))
        setUp(sizePopup, "Font size", EditorWindowController.fontSizes.map { ("\($0) pt", $0) }, #selector(sizePicked(_:)))
        setUp(pixelPopup, "Strength", [("Light", 6), ("Medium", 10), ("Strong", 18), ("Heavy", 28)], #selector(pixelPicked(_:)))
        setUp(cornerStylePopup, "Corners", [("Sharp Corners", 0), ("Slightly Rounded", 2), ("Rounded", 8), ("Very Rounded", 16)],
              #selector(cornerPicked(_:)))
        setUp(arrowStylePopup, "Arrow style", [("Filled Head", ArrowStyle.filled.rawValue), ("Open Head", ArrowStyle.open.rawValue),
                                               ("Double-Headed", ArrowStyle.double.rawValue), ("Tapered", ArrowStyle.tapered.rawValue)],
              #selector(arrowStylePicked(_:)))
        // Tags are tenths: 15 is 1.5×.
        setUp(magnificationPopup, "Magnification", [("1.5×", 15), ("2×", 20), ("3×", 30), ("4×", 40)],
              #selector(magnificationPicked(_:)))
        setUp(lensShapePopup, "Lens shape", [("Circle", LensShape.circle.rawValue), ("Rectangle", LensShape.rectangle.rawValue)],
              #selector(lensShapePicked(_:)))
        setUp(shapeFillPopup, "Fill", [("No Fill", ShapeFill.outline.rawValue), ("Translucent Fill", ShapeFill.translucent.rawValue),
                                        ("Solid Fill", ShapeFill.solid.rawValue)], #selector(shapeFillPicked(_:)))
        setUp(textBoxPopup, "Text background", [("No Box", TextBox.plain.rawValue), ("Solid Box", TextBox.solid.rawValue),
                                                ("Outlined Box", TextBox.outline.rawValue)], #selector(textBoxPicked(_:)))
        setUp(fontPopup, "Font", [], #selector(fontPicked(_:)))
        for (title, name) in Self.fontChoices {
            fontPopup.addItem(withTitle: title)
            fontPopup.lastItem?.representedObject = name
            if let f = NSFont(name: name, size: NSFont.systemFontSize(for: .small)) {
                fontPopup.lastItem?.attributedTitle = NSAttributedString(string: title, attributes: [.font: f])
            }
        }

        boldButton.toolTip = "Bold"
        boldButton.setAccessibilityLabel("Bold")
        boldButton.target = self; boldButton.action = #selector(boldToggled(_:))
        textOnlyButton.toolTip = "Hide only the text found in the box (OCR), not all of it"
        textOnlyButton.target = self; textOnlyButton.action = #selector(textOnlyToggled(_:))
        tailButton.toolTip = "Speech-bubble tail: drag its tip to point it. Drag the label's right-hand handle to wrap it."
        tailButton.target = self; tailButton.action = #selector(tailToggled(_:))
        handDrawnButton.toolTip = "Draw with a slight hand-drawn wobble. Drag an arrow's or line's middle handle to bend it."
        handDrawnButton.target = self; handDrawnButton.action = #selector(handDrawnToggled(_:))
        shapeCorrectionButton.toolTip = "Shape correction: a stroke drawn as a line, circle or box becomes one. Shift keeps a stroke straight."
        shapeCorrectionButton.target = self; shapeCorrectionButton.action = #selector(shapeCorrectionToggled(_:))
        arrowLabelButton.toolTip = "Label: type a note at the arrow's tail as soon as it is drawn, in the last text style. Esc without typing keeps just the arrow."
        arrowLabelButton.target = self; arrowLabelButton.action = #selector(arrowLabelToggled(_:))

        arrangeButton.toolTip = "Arrange: move the selection in front of or behind other annotations"
        arrangeButton.addItem(withTitle: "Arrange")
        arrangeButton.lastItem?.image = symbol("square.3.layers.3d", "Arrange")
        arrangeButton.synchronizeTitleAndSelectedItem()
        // Shortcuts live in the Arrange menu bar menu; repeating them here would fire twice.
        for (title, action, _, _) in CanvasView.arrangeCommands {
            arrangeButton.addItem(withTitle: title)
            arrangeButton.lastItem?.action = action
            arrangeButton.lastItem?.target = canvas
        }

        [colorWell, strokePopup, shapeFillPopup, arrowStylePopup, arrowLabelButton, handDrawnButton, shapeCorrectionButton, cornerStylePopup,
         fontPopup, sizePopup, boldButton, textBoxPopup, tailButton, pixelPopup, textOnlyButton, magnificationPopup, lensShapePopup,
         arrangeButton].forEach(attributesBar.addArrangedSubview)
        refreshStrip()
    }

    private func buildCropBar() {
        let hint = NSTextField(labelWithString: "Drag the corners or draw a new area · Return to apply · Esc to cancel")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor
        let reset = textButton("Reset", self, #selector(cropReset))
        let cancel = textButton("Cancel", self, #selector(cropCancel))
        let apply = textButton("Apply", self, #selector(cropApply), filled: true)
        [hint, reset, cancel, apply].forEach(cropBar.addArrangedSubview)
        cropBar.spacing = 6
        cropBar.setCustomSpacing(10, after: hint)
        cropBar.isHidden = true
    }

    /// The strip while dragging out an area for Copy Text, the average color or Check Contrast.
    private func buildAreaBar() {
        areaHint.font = .systemFont(ofSize: 12)
        areaHint.textColor = .tertiaryLabelColor
        contrastLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        contrastLabel.textColor = .labelColor
        contrastMethodButton.toolTip = "Switch between WCAG 2 and APCA (or ⌥-click the screenshot)"
        [areaHint, contrastLabel, contrastMethodButton, copyAllTextButton, areaDoneButton].forEach(areaBar.addArrangedSubview)
        areaBar.spacing = 6
        areaBar.setCustomSpacing(10, after: areaHint)
        areaBar.setCustomSpacing(10, after: contrastLabel)
        areaBar.isHidden = true
    }

    private func refreshAreaBar() {
        let kind = canvas.areaPick
        let measured = !contrastLabel.stringValue.isEmpty
        switch kind {
        case .averageColor?:
            attributesTitle.stringValue = "Average Color"
            areaHint.stringValue = "Drag over an area to copy its average color · Esc to cancel"
        case .contrast?:
            attributesTitle.stringValue = "Contrast"
            areaHint.stringValue = "Drag over text and its background · Esc when done"
        case .cutOut?:
            attributesTitle.stringValue = "Cut Out"
            areaHint.stringValue = "Drag across the part to remove · ⌥-drag for a vertical strip · Esc to cancel"
        default:
            attributesTitle.stringValue = "Copy Text"
            areaHint.stringValue = "Drag over the text to copy it · Esc to cancel"
        }
        // Once a contrast is measured its result takes the hint's place, so the strip fits the window.
        areaHint.isHidden = kind == .contrast && measured
        contrastLabel.isHidden = kind != .contrast || !measured
        contrastMethodButton.isHidden = kind != .contrast
        contrastMethodButton.setContent(title: Preferences.contrastMethod == .wcag ? "WCAG 2" : "APCA", symbol: nil)
        copyAllTextButton.isHidden = kind != .text
        areaDoneButton.setContent(title: kind == .contrast ? "Done" : "Cancel", symbol: nil)
    }

    private func buildBackgroundBar() {
        fillPopup.toolTip = "Fill"
        fillPopup.target = self; fillPopup.action = #selector(backgroundFillPicked)
        fillPopup.menu?.autoenablesItems = false
        fillPopup.addItem(withTitle: "None"); fillPopup.lastItem?.tag = -1
        for (i, preset) in Background.presets.enumerated() {
            fillPopup.addItem(withTitle: preset.name)
            fillPopup.lastItem?.tag = i
            var b = Background()
            b.fill = i
            fillPopup.lastItem?.image = b.swatch()
        }
        fillPopup.menu?.addItem(.separator())
        for (title, tag) in [("Custom Gradient", Background.customFill), ("Desktop Wallpaper", Background.wallpaperFill),
                             ("Image…", Background.imageFill)] {
            fillPopup.addItem(withTitle: title); fillPopup.lastItem?.tag = tag
        }
        refreshPictureItems(nil)

        func setUp(_ popup: PillPopUp, _ tip: String, _ choices: [(String, Int)]) {
            popup.toolTip = tip
            popup.target = self; popup.action = #selector(backgroundOptionPicked(_:))
            for (title, tag) in choices { popup.addItem(withTitle: title); popup.lastItem?.tag = tag }
        }
        setUp(directionPopup, "Gradient direction", Background.GradientDirection.allCases.map { ($0.name, $0.rawValue) })
        setUp(blurPopup, "Blur", [("No Blur", 0), ("Light Blur", 6), ("Blur", 15), ("Strong Blur", 35)])
        setUp(aspectPopup, "Aspect ratio of the whole image",
              [("Any Ratio", -1)] + Background.aspects.enumerated().map { ($1.name, $0) })
        setUp(paddingPopup, "Padding", [0, 16, 32, 48, 64, 96, 128].map { ("Padding \($0) pt", $0) })
        setUp(cornerPopup, "Corner radius", [0, 6, 10, 16, 24].map { ("Corners \($0) pt", $0) })
        for (pill, tip) in [(gradientFrom, "Gradient start color"), (gradientTo, "Gradient end color")] {
            pill.toolTip = tip
            pill.target = self; pill.action = #selector(gradientColorChanged)
        }
        chooseImageButton.toolTip = "Choose the picture for the background"

        framePopup.toolTip = "Inset: a frame in the screenshot's edge color · Outer corners: round the whole image"
        framePopup.addItem(withTitle: "Frame")
        framePopup.menu?.autoenablesItems = false
        func section(_ title: String, _ values: [Int], base: Int, _ name: (Int) -> String) {
            framePopup.addItem(withTitle: title); framePopup.lastItem?.isEnabled = false
            for v in values {
                framePopup.addItem(withTitle: name(v))
                framePopup.lastItem?.tag = base + v
                framePopup.lastItem?.indentationLevel = 1
                framePopup.lastItem?.action = #selector(backgroundFramePicked(_:))
                framePopup.lastItem?.target = self
            }
        }
        section("Inset", [0, 4, 8, 16, 24], base: Self.insetTag) { $0 == 0 ? "None" : "\($0) pt" }
        framePopup.menu?.addItem(.separator())
        section("Outer Corners", [0, 12, 24, 40], base: Self.outerCornerTag) { $0 == 0 ? "Square" : "\($0) pt" }

        shadowLabel.font = .systemFont(ofSize: 12)
        shadowLabel.textColor = .secondaryLabelColor
        shadowSlider.controlSize = .small
        shadowSlider.isContinuous = false
        shadowSlider.toolTip = "Shadow under the screenshot"
        shadowSlider.target = self; shadowSlider.action = #selector(backgroundShadowChanged)
        shadowSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        [fillPopup, directionPopup, gradientFrom, gradientTo, chooseImageButton, blurPopup, aspectPopup, paddingPopup,
         cornerPopup, framePopup, shadowLabel, shadowSlider].forEach(backgroundBar.addArrangedSubview)
        backgroundBar.spacing = 6
        backgroundBar.setCustomSpacing(4, after: shadowLabel)
        backgroundBar.isHidden = true
    }

    /// The wallpaper can change while the editor is open, and the custom gradient and picture with the background, so
    /// those items are redrawn whenever the options show.
    private func refreshPictureItems(_ bg: Background?) {
        let items = fillPopup.menu?.items ?? []
        if let item = items.first(where: { $0.tag == Background.wallpaperFill }) {
            let available = Background.wallpaper != nil
            item.isEnabled = available
            item.title = available ? "Desktop Wallpaper" : "Desktop Wallpaper (unavailable)"
            item.toolTip = available ? nil : "The current wallpaper is not a still image (for example a dynamic or aerial wallpaper)."
            var b = bg ?? Background()
            b.fill = Background.wallpaperFill
            item.image = available ? b.swatch() : nil
        }
        if let item = items.first(where: { $0.tag == Background.customFill }) {
            var b = bg ?? Preferences.lastBackground
            b.fill = Background.customFill
            item.image = b.swatch()
        }
        if let item = items.first(where: { $0.tag == Background.imageFill }) {
            let url = bg?.imageURL
            let name = url?.deletingPathExtension().lastPathComponent ?? ""
            item.title = name.isEmpty ? "Image…" : "Image: " + (name.count > 16 ? name.prefix(15) + "…" : name)
            var b = bg ?? Background()
            b.fill = Background.imageFill
            item.image = url == nil ? nil : b.swatch()
        }
        fillPopup.synchronizeTitleAndSelectedItem()
    }

    private func contextChanged() {
        // Clicking an annotation or picking a tool leaves the background options.
        if stripMode == .background || stripMode == .deviceFrame { stripMode = .tools } else { refreshStrip() }
    }

    private func refreshStrip() {
        attributesBar.isHidden = stripMode != .tools
        cropBar.isHidden = stripMode != .crop
        areaBar.isHidden = stripMode != .areaPick
        backgroundBar.isHidden = stripMode != .background
        deviceFrameBar.isHidden = stripMode != .deviceFrame
        switch stripMode {
        case .tools:
            refreshAttributes(canvas.contextTool, canvas.contextStyle)
        case .crop:
            attributesTitle.stringValue = "Crop"
            attributesTitle.isHidden = false; attributesHint.isHidden = true
        case .areaPick:
            refreshAreaBar()
            attributesTitle.isHidden = false; attributesHint.isHidden = true
        case .background:
            attributesTitle.stringValue = "Background"
            attributesTitle.isHidden = false; attributesHint.isHidden = true
            refreshBackgroundBar()
        case .deviceFrame:
            attributesTitle.stringValue = "Frame"
            attributesTitle.isHidden = false; attributesHint.isHidden = true
            refreshDeviceFrameBar()
        }
        // An empty options row would leave a double gap.
        if stripMode == .tools, attributesBar.arrangedSubviews.allSatisfy(\.isHidden) { attributesBar.isHidden = true }
    }

    /// Shows the controls for `tool` and loads them with `style`.
    private func refreshAttributes(_ tool: Tool, _ style: Style) {
        // `.select` here means nothing is selected: there is no style to edit.
        attributesTitle.stringValue = tool.name
        attributesTitle.isHidden = tool == .select
        attributesHint.isHidden = tool != .select
        colorWell.isHidden = [.select, .pixelate, .blur, .erase, .spotlight, .image].contains(tool)
        strokePopup.isHidden = !tool.usesStroke
        [fontPopup, boldButton, textBoxPopup, tailButton].forEach { $0.isHidden = tool != .text }
        shapeFillPopup.isHidden = tool != .rect && tool != .ellipse
        handDrawnButton.isHidden = ![.arrow, .line, .rect, .ellipse].contains(tool)
        shapeCorrectionButton.isHidden = tool != .pen
        sizePopup.isHidden = tool != .text && tool != .counter
        pixelPopup.isHidden = !tool.hasStrength
        textOnlyButton.isHidden = !tool.obscures
        [magnificationPopup, lensShapePopup].forEach { $0.isHidden = tool != .magnifier }
        cornerStylePopup.isHidden = !tool.hasCorners
        arrowStylePopup.isHidden = tool != .arrow
        arrowLabelButton.isHidden = tool != .arrow
        arrangeButton.isHidden = !canvas.hasSelection

        colorWell.color = style.color
        strokePopup.selectItem(withTag: Int(style.lineWidth))
        showSize(Int(style.fontSize.rounded()))
        pixelPopup.selectItem(withTag: Int(style.pixelSize))
        cornerStylePopup.selectItem(withTag: Int(style.cornerRadius))
        arrowStylePopup.selectItem(withTag: style.arrowStyle.rawValue)
        textOnlyButton.isOn = style.textOnly
        magnificationPopup.selectItem(withTag: Int((style.magnification * 10).rounded()))
        lensShapePopup.selectItem(withTag: style.lensShape.rawValue)
        if let i = fontPopup.itemArray.firstIndex(where: { $0.representedObject as? String == style.fontName }) {
            fontPopup.selectItem(at: i)
        }
        boldButton.isOn = style.bold
        shapeFillPopup.selectItem(withTag: style.fill.rawValue)
        textBoxPopup.selectItem(withTag: style.textBox.rawValue)
        tailButton.isOn = style.tail && style.textBox != .plain
        handDrawnButton.isOn = style.handDrawn
        shapeCorrectionButton.isOn = style.shapeCorrection
        arrowLabelButton.isOn = style.arrowLabel
    }

    /// The usual font sizes, plus `size` when a label's corner handle scaled it to another one.
    private func showSize(_ size: Int) {
        let sizes = Set(EditorWindowController.fontSizes + [size]).sorted()
        if sizePopup.itemArray.map(\.tag) != sizes {
            sizePopup.menu?.removeAllItems()
            for s in sizes { sizePopup.addItem(withTitle: "\(s) pt"); sizePopup.lastItem?.tag = s }
        }
        sizePopup.selectItem(withTag: size)
    }

    @objc private func colorChanged(_ w: ColorPill) { canvas.updateStyle { $0.color = w.color } }
    @objc private func strokePicked(_ p: PillPopUp) { canvas.updateStyle { $0.lineWidth = CGFloat(p.selectedTag()) } }
    @objc private func sizePicked(_ p: PillPopUp) { canvas.updateStyle { $0.fontSize = CGFloat(p.selectedTag()) } }
    @objc private func pixelPicked(_ p: PillPopUp) { canvas.updateStyle { $0.pixelSize = CGFloat(p.selectedTag()) } }
    @objc private func cornerPicked(_ p: PillPopUp) { canvas.updateStyle { $0.cornerRadius = CGFloat(p.selectedTag()) } }
    @objc private func arrowStylePicked(_ p: PillPopUp) {
        canvas.updateStyle { $0.arrowStyle = ArrowStyle(rawValue: p.selectedTag()) ?? .filled }
    }
    @objc private func fontPicked(_ p: PillPopUp) {
        let name = p.selectedItem?.representedObject as? String ?? ""
        canvas.updateStyle { $0.fontName = name }
    }
    @objc private func boldToggled(_ b: PillButton) {
        b.isOn.toggle()
        canvas.updateStyle { $0.bold = b.isOn }
    }
    @objc private func textOnlyToggled(_ b: PillButton) {
        b.isOn.toggle()
        canvas.updateStyle { $0.textOnly = b.isOn }
    }
    @objc private func shapeFillPicked(_ p: PillPopUp) {
        canvas.updateStyle { $0.fill = ShapeFill(rawValue: p.selectedTag()) ?? .outline }
    }
    @objc private func textBoxPicked(_ p: PillPopUp) {
        let box = TextBox(rawValue: p.selectedTag()) ?? .plain
        canvas.updateStyle { $0.textBox = box; if box == .plain { $0.tail = false } }
        refreshStrip()
    }
    /// A tail needs a box: turning it on gives a label without one a solid box.
    @objc private func tailToggled(_ b: PillButton) {
        let on = !b.isOn
        canvas.updateStyle { s in
            s.tail = on
            if on, s.textBox == .plain { s.textBox = .solid }
        }
        refreshStrip()
    }
    @objc private func handDrawnToggled(_ b: PillButton) {
        b.isOn.toggle()
        canvas.updateStyle { $0.handDrawn = b.isOn }
    }
    @objc private func shapeCorrectionToggled(_ b: PillButton) {
        b.isOn.toggle()
        canvas.updateStyle { $0.shapeCorrection = b.isOn }
    }
    @objc private func arrowLabelToggled(_ b: PillButton) {
        b.isOn.toggle()
        canvas.updateStyle { $0.arrowLabel = b.isOn }
    }
    @objc private func magnificationPicked(_ p: PillPopUp) {
        canvas.updateStyle { $0.magnification = CGFloat(p.selectedTag()) / 10 }
    }
    @objc private func lensShapePicked(_ p: PillPopUp) {
        canvas.updateStyle { $0.lensShape = LensShape(rawValue: p.selectedTag()) ?? .circle }
    }

    // MARK: Actions

    @objc private func toolChanged(_ sender: PillButton) {
        guard let i = toolPills.firstIndex(where: { $0 === sender }) else { return }
        selectToolButton(toolButtons[i].tool)
        canvas.applyCrop()
        canvas.tool = toolButtons[i].tool
        if stripMode == .background || stripMode == .deviceFrame { stripMode = .tools }
        window?.makeFirstResponder(canvas)
    }
    private func selectToolButton(_ t: Tool) {
        for (pill, b) in zip(toolPills, toolButtons) { pill.isOn = b.tool == t }
    }
    @objc private func copyIt() { Output.copy(canvas.flattened()) }

    /// Esc with nothing selected: copy or save the image and close, as Settings → Annotate says (#115).
    private func escapePressed() {
        switch Preferences.editorEscAction {
        case .nothing:
            return
        case .copyAndClose:
            Output.copy(canvas.flattened())
            Sound.play("Pop")
            Notifier.confirm("Screenshot copied")
        case .saveAndClose:
            guard let url = save() else { return }
            Notifier.confirm("Screenshot saved", detail: url.lastPathComponent, file: url)
        }
        window?.close()
    }

    /// Save (⌘S): over the file the screenshot was saved to or opened from, when there is one and Settings allows it,
    /// else a new file in the export location, which later saves then update (#118).
    func saveScreenshot() {
        guard let url = save() else { return }
        showToast("Saved \(url.lastPathComponent)")
    }

    /// Save As… (⇧⌘S): the save panel; later saves go to the file picked there.
    func saveScreenshotAs() {
        let name = fileURL?.deletingPathExtension().lastPathComponent
        if let url = Output.saveAs(canvas.flattened(), name: name) { fileURL = url }
    }

    /// Writes the image (see `saveScreenshot`) and returns where; nil after saying why it failed.
    private func save() -> URL? {
        let image = canvas.flattened()
        if Preferences.saveOverExisting, let url = fileURL, ImageFormat(fileExtension: url.pathExtension) != nil,
           FileManager.default.fileExists(atPath: url.path) {
            if Output.overwrite(image, at: url) {
                SavedLibrary.shared.note(url, edited: canvas.isEdited)
                return url
            }
            showToast("Couldn't save over \(url.lastPathComponent)")
            NSSound.beep()
            return nil
        }
        guard let url = Output.save(image) else {
            showToast("Couldn't save: check the export location in Settings")
            NSSound.beep()
            return nil
        }
        fileURL = url
        SavedLibrary.shared.note(url, edited: canvas.isEdited)
        return url
    }

    @objc private func saveIt() { saveScreenshot() }
    @objc private func saveAsIt() { saveScreenshotAs() }
    @objc private func pinIt() { PinnedScreenshotController.pin(canvas.flattened()) }
    @MainActor @objc private func askClaudeIt() { AskClaudePanel.show(canvas.flattened(), from: window) }
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
    @objc private func areaPickCancel() { canvas.endAreaPick(); window?.makeFirstResponder(canvas) }
    @objc private func contrastMethodToggled() { canvas.toggleContrastMethod(); window?.makeFirstResponder(canvas) }
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
    @objc private func addImageFromClipboard() {
        guard let img = ImageSource.fromClipboard() else { NSSound.beep(); return }
        canvas.insertImage(img)
    }
    /// Hides this editor, lets the user pick an area, then adds the capture to the canvas.
    @objc private func addImageFromCapture() {
        guard let capture = Self.captureArea, let w = window else { return }
        // Fade out rather than order out, so the window keeps its place and its tab stays the one showing.
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
    /// Shows the background options, adding the last background used the first time.
    @objc private func backgroundIt() {
        if stripMode == .background { stripMode = .tools; return }
        canvas.applyCrop()
        canvas.clearSelection()
        if canvas.background == nil { canvas.updateBackground { $0 = Preferences.lastBackground } }
        stripMode = .background
        window?.makeFirstResponder(canvas)
    }

    /// Shows the frame options; the frame itself starts as None.
    @objc private func deviceFrameIt() {
        if stripMode == .deviceFrame { stripMode = .tools; return }
        canvas.applyCrop()
        canvas.clearSelection()
        stripMode = .deviceFrame
        window?.makeFirstResponder(canvas)
    }

    private func buildDeviceFrameBar() {
        deviceKindPopup.toolTip = "Frame around the screenshot, inside the background"
        deviceKindPopup.target = self; deviceKindPopup.action = #selector(deviceKindPicked)
        for kind in DeviceFrame.Kind.allCases {
            deviceKindPopup.addItem(withTitle: kind.name); deviceKindPopup.lastItem?.tag = kind.rawValue
        }
        deviceLookPopup.toolTip = "Light or dark frame"
        deviceLookPopup.target = self; deviceLookPopup.action = #selector(deviceLookPicked)
        for (title, tag) in [("Light", 0), ("Dark", 1)] { deviceLookPopup.addItem(withTitle: title); deviceLookPopup.lastItem?.tag = tag }
        deviceURLField.placeholderString = "Address shown in the browser bar"
        deviceURLField.toolTip = "Address shown in the browser bar"
        deviceURLField.controlSize = .small
        deviceURLField.font = .systemFont(ofSize: 12)
        deviceURLField.target = self; deviceURLField.action = #selector(deviceURLEdited)
        deviceURLField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        [deviceKindPopup, deviceLookPopup, deviceURLField].forEach(deviceFrameBar.addArrangedSubview)
        deviceFrameBar.spacing = 6
        deviceFrameBar.isHidden = true
    }

    private func refreshDeviceFrameBar() {
        let f = canvas.deviceFrame
        deviceKindPopup.selectItem(withTag: f.kind.rawValue)
        deviceLookPopup.selectItem(withTag: f.dark ? 1 : 0)
        deviceLookPopup.isEnabled = !f.isNone
        deviceURLField.isHidden = f.kind != .browser
        // Not while it is being typed in, as the change that ends the typing refreshes the bar too.
        if deviceURLField.currentEditor() == nil { deviceURLField.stringValue = f.url }
    }

    /// Changes the frame (one undo step) and remembers its look for the next one.
    private func changeDeviceFrame(_ change: (inout DeviceFrame) -> Void) {
        canvas.updateDeviceFrame(change)
        if !canvas.deviceFrame.isNone { Preferences.lastDeviceFrame = canvas.deviceFrame }
        refreshStrip()
    }

    @objc private func deviceKindPicked() {
        let kind = DeviceFrame.Kind(rawValue: deviceKindPopup.selectedTag()) ?? .none
        let last = Preferences.lastDeviceFrame
        changeDeviceFrame { f in
            // The first frame picked takes the light or dark look and address used last.
            if f.isNone { f.dark = last.dark; f.url = last.url }
            f.kind = kind
        }
    }

    @objc private func deviceLookPicked() {
        let dark = deviceLookPopup.selectedTag() == 1
        changeDeviceFrame { $0.dark = dark }
    }

    @objc private func deviceURLEdited() {
        let url = deviceURLField.stringValue
        changeDeviceFrame { $0.url = url }
        window?.makeFirstResponder(canvas)
    }

    /// Loads the background options from the canvas's background, showing only those that apply to its fill.
    private func refreshBackgroundBar() {
        let bg = canvas.background
        refreshPictureItems(bg)
        let fill = bg?.fill ?? -1
        fillPopup.selectItem(withTag: fill)
        let custom = fill == Background.customFill
        let picture = fill == Background.wallpaperFill || fill == Background.imageFill
        let gradient = custom || (Background.presets.indices.contains(fill) && Background.presets[fill].colors.count > 1)
        directionPopup.isHidden = !gradient
        gradientFrom.isHidden = !custom; gradientTo.isHidden = !custom
        chooseImageButton.isHidden = fill != Background.imageFill
        blurPopup.isHidden = !picture
        let b = bg ?? Preferences.lastBackground
        directionPopup.selectItem(withTag: b.direction.rawValue)
        if b.colors.count == 2 { gradientFrom.color = b.colors[0]; gradientTo.color = b.colors[1] }
        blurPopup.selectItem(withTag: Int(b.imageBlur))
        aspectPopup.selectItem(withTag: Background.aspects.firstIndex { $0.aspect == b.aspect } ?? -1)
        paddingPopup.selectItem(withTag: Int(b.padding))
        cornerPopup.selectItem(withTag: Int(b.cornerRadius))
        for item in framePopup.itemArray.dropFirst() where item.action != nil {
            let value = item.tag >= Self.outerCornerTag ? b.outerRadius : b.inset
            item.state = item.tag % 1000 == Int(value) ? .on : .off
        }
        shadowSlider.doubleValue = Double(b.shadow)
        let controls: [NSControl] = [directionPopup, gradientFrom, gradientTo, chooseImageButton, blurPopup, aspectPopup,
                                     paddingPopup, cornerPopup, framePopup, shadowSlider]
        controls.forEach { $0.isEnabled = bg != nil }
        shadowLabel.textColor = bg != nil ? .secondaryLabelColor : .tertiaryLabelColor
    }

    /// Changes the background (one undo step) and remembers it for the next screenshot.
    private func changeBackground(_ change: (inout Background) -> Void) {
        canvas.updateBackground { bg in
            var b = bg ?? Preferences.lastBackground
            change(&b)
            bg = b
        }
        if let bg = canvas.background { Preferences.lastBackground = bg }
        refreshStrip()
    }

    @objc private func backgroundFillPicked() {
        let fill = fillPopup.selectedTag()
        if fill < 0 { canvas.updateBackground { $0 = nil }; refreshStrip(); return }
        if fill == Background.imageFill, canvas.background?.imageURL == nil, Preferences.lastBackground.imageURL == nil {
            chooseBackgroundImage()
            return
        }
        changeBackground { b in
            b.fill = fill
            if fill == Background.imageFill, b.imageURL == nil { b.imageURL = Preferences.lastBackground.imageURL }
        }
    }

    @objc private func backgroundOptionPicked(_ popup: PillPopUp) {
        let tag = popup.selectedTag()
        let change: (inout Background) -> Void
        switch popup {
        case directionPopup: change = { $0.direction = Background.GradientDirection(rawValue: tag) ?? .diagonal }
        case blurPopup: change = { $0.imageBlur = CGFloat(tag) }
        case aspectPopup: change = { $0.aspect = Background.aspects.indices.contains(tag) ? Background.aspects[tag].aspect : nil }
        case paddingPopup: change = { $0.padding = CGFloat(tag) }
        case cornerPopup: change = { $0.cornerRadius = CGFloat(tag) }
        default: return
        }
        changeBackground(change)
    }

    @objc private func backgroundFramePicked(_ item: NSMenuItem) {
        let value = CGFloat(item.tag % 1000)
        changeBackground { b in
            if item.tag >= Self.outerCornerTag { b.outerRadius = value } else { b.inset = value }
        }
    }

    @objc private func gradientColorChanged() {
        let colors = [gradientFrom.color, gradientTo.color]
        changeBackground { b in
            b.fill = Background.customFill
            b.colors = colors
        }
    }

    @objc private func backgroundShadowChanged() {
        let v = CGFloat(shadowSlider.doubleValue)
        changeBackground { $0.shadow = v }
    }

    /// Picks the picture for the background; cancelling leaves the background as it was.
    @MainActor @objc private func chooseBackgroundImage() {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture for the background"
        panel.beginSheetModal(for: w) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url {
                self.changeBackground { b in
                    b.fill = Background.imageFill
                    b.imageURL = url
                }
            } else {
                self.refreshStrip()
            }
            self.window?.makeFirstResponder(self.canvas)
        }
    }

    @objc private func redoIt() { canvas.redo() }

    // MARK: Resize (#122)

    /// The Resize Image sheet: width × height in pixels or points, with Keep proportions and percent presets.
    private func showResize() {
        guard let w = window, w.attachedSheet == nil else { return }
        let original = canvas.pixelSize
        let form = ResizeForm(original: original, density: canvas.pixelDensity)
        let alert = NSAlert()
        alert.messageText = "Resize Image"
        alert.informativeText = "Now \(original.width) × \(original.height) px. Annotations are resized with the image."
        alert.accessoryView = form
        let resize = alert.addButton(withTitle: "Resize")
        alert.addButton(withTitle: "Cancel")
        form.onValidityChange = { resize.isEnabled = $0 }
        alert.window.initialFirstResponder = form.widthField
        alert.beginSheetModal(for: w) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let size = form.pixels
            if size.width != original.width || size.height != original.height {
                self.canvas.resize(toWidth: size.width, height: size.height)
            }
            self.window?.makeFirstResponder(self.canvas)
        }
    }
}
