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

/// The canvas well's rim, over the scroll view: an inner shadow under its top edge and a hairline. Clicks go through.
private final class CanvasRim: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.innerShadow(NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10), alpha: p.dark ? 0.6 : 0.2, blur: 3)
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        NSColor.black.withAlphaComponent(p.dark ? 0.5 : 0.12).setStroke()
        edge.lineWidth = 1
        edge.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
/// The editor vanishes the moment the drag starts and Skreener hides, so the drop target is visible, and a small
/// preview rides under the pointer. A drop means the screenshot is done with: the editor closes. A cancelled drag
/// (Esc, or let go where nothing takes it) brings it back as it was.
private final class DragPill: NSView, NSDraggingSource {
    var imageProvider: () -> NSImage = { NSImage() }
    /// Called after a drop that something took.
    var onDropped: () -> Void = {}
    private var dragStarted = false
    /// The drag preview's size, with the pointer over its bottom-right quadrant.
    private static let previewSize = NSSize(width: 100, height: 85)

    override var intrinsicContentSize: NSSize { NSSize(width: 112, height: 34) }
    override func mouseDown(with event: NSEvent) { dragStarted = false }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        // Gone before the image is rendered and written, which can take a moment for a big screenshot.
        window?.alphaValue = 0
        CATransaction.flush()
        let image = imageProvider()
        guard let url = Output.temporaryFile(image) else { window?.alphaValue = 1; return }
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
        if operation.isEmpty {
            window?.alphaValue = 1
            NSApp.unhide(nil)
        } else {
            // After the session is done with this view.
            DispatchQueue.main.async { [onDropped] in onDropped() }
        }
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
        // Sunken and grooved rather than raised: it is dragged, not clicked.
        let p = Retro.palette(for: self)
        let r = (bounds.height - 1) / 2
        let rect = NSRect(x: 0, y: isFlipped ? 0 : 1, width: bounds.width, height: bounds.height - 1)
        Retro.drawWell(rect, radius: r, top: Retro.color(p.wellTop), bottom: Retro.color(p.wellBottom), shadow: 0.18,
                       lip: p.wellLip, flipped: isFlipped)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).addClip()
        let grooves = NSBezierPath()
        var x = rect.minX
        while x < rect.maxX { grooves.appendRect(NSRect(x: x, y: rect.minY, width: 1, height: rect.height)); x += 4 }
        NSColor.black.withAlphaComponent(p.dark ? 0.12 : 0.05).setFill()
        grooves.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Grip: two short columns of dots either side of the label.
        let text = Retro.caption("Drag Me", color: Retro.color(p.ink), font: .systemFont(ofSize: 10, weight: .heavy))
        let size = text.size()
        Retro.color(p.inkSoft).setFill()
        for side in [bounds.midX - size.width / 2 - 14, bounds.midX + size.width / 2 + 8] {
            for col in 0..<2 {
                for row in 0..<3 {
                    let dot = NSRect(x: side + CGFloat(col) * 3.5, y: rect.midY - 4 + CGFloat(row) * 3.5, width: 1.6, height: 1.6)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
        }
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private func symbol(_ name: String, _ description: String? = nil) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: description)
        ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil) ?? NSImage()
}

/// Height of the strip's and footer's keys and readouts: small enough for everything to fit the minimum window width.
private let pillHeight: CGFloat = 24

/// Height of the toolbar's keys, skirt included: a 28 pt square face on a 2 pt skirt.
private let keyHeight: CGFloat = 30

/// A tray of keys with its caption under it.
@MainActor private func tray(_ caption: String, _ keys: [NSView]) -> KeycapTray {
    KeycapTray(keys, caption: caption)
}

/// A symbol-only key that sends `action` to `target`.
@MainActor private func iconButton(_ sym: String, _ tip: String, _ target: AnyObject?, _ action: Selector,
                                   height: CGFloat = keyHeight) -> PillButton {
    let b = PillButton(title: nil, symbol: sym, style: .keycap, height: height)
    b.target = target; b.action = action
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    return b
}

/// A titled key that sends `action` to `target`; `filled` (orange) for the main action.
@MainActor private func textButton(_ title: String, _ target: AnyObject?, _ action: Selector, filled: Bool = false,
                                   height: CGFloat = pillHeight) -> PillButton {
    let b = PillButton(title: title, symbol: nil, style: .keycap, height: height)
    if filled { b.keyVariant = .orange }
    b.target = target; b.action = action
    return b
}

/// A symbol key that opens `menu`, with the corner triangle.
@MainActor private func iconMenuButton(_ sym: String, _ tip: String, _ menu: NSMenu, height: CGFloat = keyHeight) -> PillPopUp {
    let b = PillPopUp(pullsDown: true, height: height, style: .keycap)
    menu.insertItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""), at: 0)   // the pull-down's face
    b.menu = menu
    b.setContent(title: nil, symbol: sym)
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    return b
}

/// Keys and controls side by side, with room around them for their shadows.
@MainActor private func pillRow(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
    let row = NSStackView(views: views)
    row.spacing = spacing
    row.edgeInsets = NSEdgeInsets(top: 3, left: 2, bottom: 3, right: 2)
    return row
}

/// The editor, in the SK-1 look (#344): a chassis under a transparent title bar, a row of key trays, the LCD, the
/// options strip, the canvas in its well, and a footer with zoom / Drag Me / actions. The window never gets smaller
/// than `minimumSize`.
final class EditorWindowController: NSWindowController, NSMenuDelegate, NSServicesMenuRequestor {
    /// Wide enough for the whole row of trays, captions included.
    static let minimumSize = NSSize(width: 1150, height: 750)
    /// A new editor is at least this wide when the screen has room, so the toolbar and the strip under it aren't crowded.
    static let defaultWidth: CGFloat = 1200
    static var live: [EditorWindowController] = []
    /// Set by the app: lets the user pick an area on screen and hands back the capture (nil if cancelled).
    static var captureArea: ((@escaping (NSImage?) -> Void) -> Void)?

    /// The toolbar's tools in groups of like tools, each on its own tray, in display order.
    private static let toolGroups: [(name: String, tools: [(symbol: String, tool: Tool)])] = [
        ("Select", [("cursorarrow", .select)]),
        ("Shapes", [("rectangle", .rect), ("rectangle.fill", .filledRect), ("circle", .ellipse), ("line.diagonal", .line),
                    ("arrow.up.right", .arrow)]),
        ("Text & Draw", [("textformat", .text), ("1.circle.fill", .counter), ("pencil.tip", .pen), ("highlighter", .highlighter)]),
        ("Hide", [("checkerboard.rectangle", .pixelate), ("drop.halffull", .blur), ("eraser", .erase),
                  ("text.magnifyingglass", .redactText)]),
        ("Focus", [("flashlight.on.fill", .spotlight), ("magnifyingglass", .magnifier)]),
    ]
    /// Toolbar tool buttons in display order.
    private var toolButtons: [(symbol: String, tool: Tool)] { Self.toolGroups.flatMap(\.tools) }

    private let image: NSImage
    private let canvas: CanvasView
    private let scroll = ZoomingScrollView()
    /// The canvas well: the scroll view in a sunken, rounded frame.
    private let canvasWell = NSView()
    /// The zoom: an LCD chip between − and +; a click on the chip opens the zoom menu.
    private let zoomButton = PillPopUp(pullsDown: true, height: pillHeight, style: .lcd, stepper: true, stepSymbols: ("minus", "plus"))
    /// The color under the pointer in the chosen format (#108); its menu picks the format and offers the color tools.
    private let colorReadout = PillPopUp(pullsDown: true, height: pillHeight, style: .lcd)
    /// The row of trays under the title bar (the editor's toolbar).
    private let toolRow = NSStackView()
    /// The window's title, in the title bar's strip of chassis.
    private let titleLabel = NSTextField(labelWithString: "")
    /// One key per tool, in `toolButtons` order; the current tool's is pressed. Each group has its own tray.
    private lazy var toolPills: [PillButton] = toolButtons.map { b in
        let hasVariants = b.tool == .rect || b.tool == .arrow
        let pill = iconButton(b.symbol, b.tool.tooltip(variants: hasVariants), self, #selector(toolChanged(_:)))
        pill.legend = b.tool.shortcutLetter
        pill.isOn = b.tool == canvas.tool
        // Rectangle and Arrow: a corner triangle, or a long press, opens their variants.
        if b.tool == .rect { pill.variantMenu = { [weak self] in self?.rectangleVariantMenu() } }
        if b.tool == .arrow { pill.variantMenu = { [weak self] in self?.arrowVariantMenu() } }
        return pill
    }
    // Contextual attributes bar under the toolbar: only the controls that apply to the current tool or
    // selection are shown. It lives outside the toolbar so the tool buttons always have room.
    private let attributesBar = NSStackView()
    private let attributesTitle = NSTextField(labelWithString: "")
    private let colorWell = SwatchRow(caption: "Color")
    /// Steppers: an LCD chip between ◀ ▶ (a click on the chip opens the full list).
    private let strokePopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd, stepper: true)
    private let fontPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .keycap)
    private let sizePopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd, stepper: true)
    /// The font sizes the size popup offers.
    static let fontSizes = [12, 14, 16, 18, 22, 28, 32, 40, 48, 64, 72]
    private let boldButton = PillButton(title: nil, symbol: "bold", style: .keycap, height: pillHeight)
    private let pixelPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd, stepper: true)
    private let cornerStylePopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd, stepper: true)
    private let arrowStylePopup = RetroSegmented(caption: "Style")
    private let textOnlyButton = PillButton(title: "Text Only", symbol: nil, style: .toggle, height: pillHeight)
    private let magnificationPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd, stepper: true)
    private let lensShapePopup = RetroSegmented(caption: "Lens")
    private let shapeFillPopup = RetroSegmented(caption: "Fill")
    private let textBoxPopup = RetroSegmented(caption: "Box")
    private let tailButton = PillButton(title: "Tail", symbol: nil, style: .toggle, height: pillHeight)
    private let handDrawnButton = PillButton(title: "Hand-Drawn", symbol: nil, style: .toggle, height: pillHeight)
    private let shapeCorrectionButton = PillButton(title: "Shapes", symbol: nil, style: .toggle, height: pillHeight)
    /// Fill opacity for closed pen polygons: shade an area while the text under it stays readable.
    private let opacityLabel = RetroLabel(caption: "Opacity")
    private let opacitySlider = NSSlider(value: 0.35, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let arrowLabelButton = PillButton(title: "Label", symbol: nil, style: .toggle, height: pillHeight)
    private let arrangeButton = PillPopUp(pullsDown: true, height: pillHeight, style: .keycap)
    /// Add Image → From Capture History; filled in each time it opens.
    private let historyMenu = NSMenu(title: "From Capture History")
    /// The Smart Actions submenu of the text menu (#243): the last result shows while a fresh scan runs.
    private let smartMenu = NSMenu(title: "Smart Actions")
    private var smartActions: [SmartAction]?
    private var smartTask: Task<Void, Never>?
    // Crop, Background and the area picks (Copy Text from Area, average color, contrast) replace the tool options in
    // the same strip while they are active.
    private enum StripMode { case tools, crop, areaPick, background, deviceFrame, redactText }
    private var stripMode = StripMode.tools {
        didSet {
            refreshStrip()
            if stripMode == .redactText, oldValue != .redactText { updateFind(); focusFindField() }
        }
    }
    /// What the strip shows when no other mode is on: Redact Text's find bar while that tool is on, else the tool's
    /// options.
    private var restingStrip: StripMode { canvas.tool == .redactText ? .redactText : .tools }
    // Redact Text's find bar (#295): the terms as chips, how they match, how matches are covered, and the count.
    private let findBar = NSStackView()
    private let findField = NSTokenField()
    private let findCount = NSTextField(labelWithString: "")
    private lazy var matchCaseButton = findToggle("Aa", "Match Case")
    private lazy var wholeWordButton = findToggle("Whole Word", "Whole Word: only whole words match, not parts of longer ones")
    private lazy var regexButton = findToggle(".*", "Regex: each term is a regular expression")
    private lazy var fuzzyButton = findToggle("Fuzzy", "Fuzzy: look-alike characters (0/O, 1/l/I, 5/S, 8/B, rn/m) match, spaces are ignored")
    private let coverPopup = RetroSegmented(caption: "Cover")
    private lazy var redactSelectedButton = textButton("Redact Selected", self, #selector(redactSelectedFound))
    private lazy var redactAllButton = textButton("Redact All", self, #selector(redactAllFound), filled: true)
    private let cropBar = NSStackView()
    private let areaBar = NSStackView()
    private let areaHint = RetroLabel(text: "")
    private let contrastLabel = NSTextField(labelWithString: "")
    private lazy var copyAllTextButton = textButton("Copy All Text", canvas, #selector(CanvasView.copyAllText(_:)))
    /// Edit the Text Before Copying: Copy Text and Capture Text open the scratch pad, or copy straight away. The same
    /// setting as Settings → After Capture's.
    private lazy var scratchPadSwitch: KeySwitch = {
        let s = KeySwitch(symbol: "square.and.pencil",
                          tip: "Edit the Text Before Copying: on, Copy Text here and Capture Text open the text in the scratch pad. "
                            + "Off: it is copied straight away.")
        s.target = self; s.action = #selector(scratchPadToggled)
        s.state = Preferences.textScratchPad ? .on : .off
        return s
    }()
    private lazy var contrastMethodButton = textButton("WCAG 2", self, #selector(contrastMethodToggled))
    private lazy var areaDoneButton = textButton("Cancel", self, #selector(areaPickCancel))
    private let backgroundBar = NSStackView()
    private let fillPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .keycap)
    private let paddingPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd)
    private let cornerPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd)
    private let directionPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd)
    private let gradientFrom = ColorPill()
    private let gradientTo = ColorPill()
    private lazy var chooseImageButton = textButton("Choose…", self, #selector(chooseBackgroundImage))
    private lazy var balanceButton = textButton("Balance", canvas, #selector(CanvasView.balancePadding(_:)))
    private lazy var removeBackgroundButton = textButton("Remove", self, #selector(removeBackground))
    private let blurPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd)
    private let aspectPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .lcd)
    private let framePopup = PillPopUp(pullsDown: true, height: pillHeight, style: .keycap)
    private let deviceFrameBar = NSStackView()
    private let deviceKindPopup = PillPopUp(pullsDown: false, height: pillHeight, style: .keycap)
    private let deviceLookPopup = RetroSegmented()
    private let deviceURLField = NSTextField(string: "")
    private let shadowLabel = RetroLabel(caption: "Shadow")
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
    /// The zoom levels − and + step through.
    private static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    private var thumbnailCache: (revision: Int, image: NSImage)?
    private var dockRefreshTask: Task<Void, Never>?
    /// The status display between the toolbar and the options strip: the tool or mode, how to use it, live hints.
    private let lcd = LCDDisplay()
    /// What the pointer is doing right now (`EditorHelp`), shown in place of the usage while set.
    private var liveHint: String?
    private static let cropUsage = "Drag the corners or draw a new area · Return to apply · Esc to cancel"
    private let toastBox = ChassisPlate(radius: 16, click: .swallow)
    private let toastLabel = RetroLabel(text: "", tone: .ink, size: 12)
    private var toastTask: Task<Void, Never>?
    /// Tips, the hint line under the canvas and "New" dots (#301, #303).
    private var help: EditorHelp?

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
        // One continuous chassis: the title bar is transparent over it, and the title is drawn in its strip. The keys
        // are in the content rather than an NSToolbar, whose own captions can't take the look.
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.minSize = floor
        super.init(window: w)

        buildContent(in: w)
        w.onTitleChange = { [weak self] in self?.refreshTitle() }
        refreshTitle()
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
                // May have been switched in Settings or another editor window.
                self.scratchPadSwitch.state = Preferences.textScratchPad ? .on : .off
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
        canvas.onCropModeChange = { [weak self] on in
            guard let self else { return }
            self.stripMode = on ? .crop : self.restingStrip
        }
        canvas.onFindChange = { [weak self] in self?.refreshFindCount() }
        canvas.onBackgroundChange = { [weak self] in
            if self?.stripMode == .background || self?.stripMode == .deviceFrame { self?.refreshStrip() }
        }
        canvas.onAreaPickChange = { [weak self] kind in
            guard let self else { return }
            if kind != .contrast { self.contrastLabel.stringValue = "" }
            self.stripMode = kind == nil ? self.restingStrip : .areaPick
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
        buildFindBar()
        buildBackgroundBar()
        buildDeviceFrameBar()
        setUpHelp()
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
        help?.editorShown()
    }

    /// A window fitting `imageSize` with room for the toolbar and footer (within the screen, at least `defaultWidth`
    /// wide where the screen allows, and never smaller than `minimumSize`), centered on `screen`.
    private static func frame(for imageSize: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let s = size(for: imageSize, visible: visible.size)
        return NSRect(x: visible.midX - s.width / 2, y: visible.midY - s.height / 2, width: s.width, height: s.height)
    }

    static func size(for imageSize: NSSize, visible: NSSize) -> NSSize {
        let floor = minimumSize
        return NSSize(width: max(floor.width, min(max(defaultWidth, imageSize.width + 120), visible.width)),
                      height: max(floor.height, min(imageSize.height + 200, visible.height)))
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
        let content = ChassisView()
        w.contentView = content
        content.onAppearanceChange = { [weak self] in self?.refreshTitle(); self?.refreshCanvasBackground() }

        scroll.contentView = CenteredClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        refreshCanvasBackground()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1; scroll.maxMagnification = 8
        scroll.translatesAutoresizingMaskIntoConstraints = false
        canvas.wantsLayer = true
        canvas.layer?.shadowColor = NSColor.black.cgColor
        canvas.layer?.shadowOpacity = 0.35
        canvas.layer?.shadowRadius = 10
        canvas.layer?.shadowOffset = CGSize(width: 0, height: -3)
        canvas.layer?.masksToBounds = false

        // The canvas in a sunken, rounded well, with its rim drawn over it.
        canvasWell.translatesAutoresizingMaskIntoConstraints = false
        canvasWell.wantsLayer = true
        canvasWell.layer?.cornerRadius = 10
        canvasWell.layer?.cornerCurve = .continuous
        canvasWell.layer?.masksToBounds = true
        let rim = CanvasRim()
        rim.translatesAutoresizingMaskIntoConstraints = false
        canvasWell.addSubview(scroll)
        canvasWell.addSubview(rim)
        for v in [scroll, rim] as [NSView] {
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: canvasWell.leadingAnchor), v.trailingAnchor.constraint(equalTo: canvasWell.trailingAnchor),
                v.topAnchor.constraint(equalTo: canvasWell.topAnchor), v.bottomAnchor.constraint(equalTo: canvasWell.bottomAnchor),
            ])
        }

        // The title bar's strip: the title in the middle and a grille at the right.
        let titleStrip = NSLayoutGuide()
        content.addLayoutGuide(titleStrip)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let grille = SpeakerGrille()
        content.addSubview(titleLabel)
        content.addSubview(grille)

        let tools = buildToolRow()
        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        let strip = buildAttributesStrip()
        strip.translatesAutoresizingMaskIntoConstraints = false
        lcd.translatesAutoresizingMaskIntoConstraints = false
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.isHidden = true
        let toast = buildToast()
        [tools, lcd, canvasWell, footer, strip, dock, toast].forEach(content.addSubview)

        let top = (w.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        let width = dock.widthAnchor.constraint(equalToConstant: 0)
        dockWidth = width
        let margin: CGFloat = 14
        // The dock runs from the attributes strip (which keeps the full width) to the footer, beside the canvas.
        dockSides = [
            [dock.leadingAnchor.constraint(equalTo: content.leadingAnchor),
             canvasWell.leadingAnchor.constraint(equalTo: dock.trailingAnchor, constant: margin),
             canvasWell.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin)],
            [dock.trailingAnchor.constraint(equalTo: content.trailingAnchor),
             canvasWell.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
             canvasWell.trailingAnchor.constraint(equalTo: dock.leadingAnchor, constant: -margin)],
        ]
        NSLayoutConstraint.activate(dockSides[0] + [
            titleStrip.topAnchor.constraint(equalTo: content.topAnchor),
            titleStrip.bottomAnchor.constraint(equalTo: top),
            titleLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titleStrip.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 90),   // after the window buttons
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: grille.leadingAnchor, constant: -16),
            grille.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            grille.centerYAnchor.constraint(equalTo: titleStrip.centerYAnchor),
            tools.topAnchor.constraint(equalTo: top, constant: 2),
            tools.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            tools.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            dock.topAnchor.constraint(equalTo: strip.bottomAnchor),
            dock.bottomAnchor.constraint(equalTo: footer.topAnchor),
            width,
            lcd.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 10),
            lcd.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            lcd.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            lcd.heightAnchor.constraint(equalToConstant: 46),
            strip.topAnchor.constraint(equalTo: lcd.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 44),
            canvasWell.topAnchor.constraint(equalTo: strip.bottomAnchor),
            canvasWell.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 52),
            toast.centerXAnchor.constraint(equalTo: canvasWell.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: canvasWell.bottomAnchor, constant: -16),
            toast.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    /// "SK-1 EDITOR — <title>" in the title bar's strip.
    private func refreshTitle() {
        let p = Retro.palette(for: titleLabel)
        let s = NSMutableAttributedString(attributedString: Retro.caption("SK-1", color: Retro.color(p.ink),
                                                                          font: .systemFont(ofSize: 9.5, weight: .heavy)))
        s.append(Retro.caption("  Editor — " + (window?.title ?? ""), color: Retro.color(p.inkSoft),
                               font: .systemFont(ofSize: 9.5, weight: .semibold)))
        titleLabel.attributedStringValue = s
    }

    /// The canvas well's floor: the palette's well colour with a faint grid of dots.
    private func refreshCanvasBackground() {
        let p = Retro.palette(for: scroll)
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            Retro.color(p.canvas).setFill()
            r.fill()
            (p.dark ? NSColor.white : NSColor.black).withAlphaComponent(p.canvasDot).setFill()
            NSBezierPath(ovalIn: NSRect(x: 5.4, y: 5.4, width: 1.2, height: 1.2)).fill()
            return true
        }
        scroll.backgroundColor = NSColor(patternImage: image)
    }

    /// Puts the current tool or mode, and how to use it (or the live hint), on the status display.
    private func refreshDisplay() {
        let tool = canvas.tool
        var detail = ""
        let title: String, usage: String
        switch stripMode {
        case .tools:
            title = canvas.contextTool == .select ? "Select" : canvas.contextTool.name
            usage = tool == .select && canvas.hasSelection ? "Drag to move it · drag a handle to resize · ⌫ deletes it" : tool.usage
            detail = tool.keyLabel
        case .redactText: title = Tool.redactText.name; usage = Tool.redactText.usage; detail = Tool.redactText.keyLabel
        case .crop: title = "Crop"; usage = Self.cropUsage
        case .areaPick: title = attributesTitle.stringValue; usage = areaHint.stringValue
        case .background: title = "Background"; usage = "Pick a fill, padding and corners · Remove takes the background off"
        case .deviceFrame: title = "Frame"; usage = "Pick a device or browser to frame the screenshot"
        }
        lcd.title = title
        lcd.detail = detail
        lcd.message = liveHint ?? usage
        lcd.isLive = liveHint != nil
    }

    /// A short message over the bottom of the canvas, e.g. after Copy Text: a small chassis plate, like the toasts
    /// elsewhere (`MessageHUD`), which a click dismisses.
    private func buildToast() -> NSView {
        toastBox.click = .run { [weak self] in self?.hideToast() }
        // It floats over the canvas, so it casts a shadow.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        toastBox.shadow = shadow
        toastBox.isHidden = true
        toastBox.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = .systemFont(ofSize: 12, weight: .medium)
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

    private func hideToast() {
        toastTask?.cancel()
        toastTask = nil
        toastBox.isHidden = true
    }

    private func textCopied(_ outcome: CaptureText.Outcome) {
        switch outcome {
        case .noText: showToast("No text found"); NSSound.beep()
        case .openedPad: break   // the pad is in front
        case .copied(let lines): showToast(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text")
        }
    }

    private func buildAttributesStrip() -> NSView {
        let bar = NSView()
        // The tool or mode, and how to use it, are on the status display above, leaving this row to the options.
        let row = pillRow([attributesBar, cropBar, areaBar, findBar, backgroundBar, deviceFrameBar], spacing: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func buildFooter() -> NSView {
        let bar = NSView()

        // Zoom: − and + step through `zoomSteps`; the chip (a pull-down, item 0 shows the current zoom) opens the menu.
        zoomButton.menu?.addItem(withTitle: "100%", action: nil, keyEquivalent: "")
        for (title, tag) in [("Fit", 0), ("25%", 25), ("50%", 50), ("100%", 100), ("200%", 200), ("400%", 400)] {
            let item = NSMenuItem(title: title, action: #selector(zoomPicked(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag
            zoomButton.menu?.addItem(item)
        }
        zoomButton.toolTip = "Zoom"
        zoomButton.onStep = { [weak self] by in self?.stepZoom(by) }
        buildColorReadout()
        dockButton.isHidden = true
        let zoomBar = pillRow([dockButton, zoomButton, colorReadout], spacing: 10)
        zoomBar.translatesAutoresizingMaskIntoConstraints = false

        let pill = DragPill()
        pill.imageProvider = { [weak self] in self?.canvas.flattened() ?? NSImage() }
        pill.onDropped = { [weak self] in self?.window?.close() }
        pill.translatesAutoresizingMaskIntoConstraints = false

        var actions: [NSView] = [("sparkles", "Ask Claude: explain, summarize or write alt text", #selector(askClaudeIt)),
                                 ("paperplane", "Send To: your own actions and notes apps", #selector(sendToIt(_:))),
                                 ("square.and.arrow.up", "Share", #selector(shareIt(_:))),
                                 ("pin", "Pin to Screen", #selector(pinIt))].map { sym, tip, sel in
            iconButton(sym, tip, self, sel, height: 28)
        }
        let copy = textButton("Copy", self, #selector(copyIt), height: 28)
        copy.toolTip = "Copy"
        let save = textButton("Save", self, #selector(saveIt), filled: true, height: 28)
        save.toolTip = "Save (⌘S)"
        actions += [copy, save]
        let right = pillRow(actions, spacing: 8)
        right.setCustomSpacing(14, after: actions[3])
        right.translatesAutoresizingMaskIntoConstraints = false

        [zoomBar, pill, right].forEach(bar.addSubview)
        NSLayoutConstraint.activate([
            zoomBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            zoomBar.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pill.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 150), pill.heightAnchor.constraint(equalToConstant: 27),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
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
        let percent = Int((scroll.magnification * 100).rounded())
        zoomButton.menu?.item(at: 0)?.title = "\(percent)%"
        zoomButton.synchronizeTitleAndSelectedItem()
        lcd.zoomPercent = percent
    }

    /// The zoom's − (-1) and +: the next level in `zoomSteps`, around the middle of what is showing.
    private func stepZoom(_ by: Int) {
        let now = scroll.magnification
        let next = by > 0 ? Self.zoomSteps.first { $0 > now + 0.005 } : Self.zoomSteps.last { $0 < now - 0.005 }
        guard let next else { NSSound.beep(); return }
        fitMode = false
        let visible = canvas.visibleRect
        scroll.setMagnification(next, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        refreshZoomLabel()
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

    // MARK: Tool row

    /// The row of trays under the title bar, small enough for everything to fit the minimum width: the image and
    /// text commands, the tools in groups, Undo, and at the far end Settings (charcoal) and Save as… (orange).
    private func buildToolRow() -> NSView {
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
        let crop = iconButton("crop", "Crop (C)", self, #selector(cropIt))
        crop.legend = "C"
        var trays: [NSView] = [
            tray("Image", [
                crop,
                iconMenuButton("rotate.right", "Rotate, flip, resize or cut out part of the screenshot",
                               commands(CanvasView.imageCommands, CanvasView.sizeCommands, CanvasView.snapCommands)),
                iconMenuButton("plus.rectangle.on.rectangle",
                               "Add an image from a new capture, the capture history, a file or the clipboard", buildAddImageMenu()),
                iconButton("photo", "Background", self, #selector(backgroundIt)),
            ]),
            tray("Read Text", [
                iconMenuButton("eye.slash", "Find text in the screenshot and pixelate it", commands(CanvasView.redactCommands)),
                iconMenuButton("text.viewfinder", "Copy text from the screenshot (OCR), or act on dates, addresses, links and QR codes",
                               textMenu(commands(CanvasView.textCommands))),
                scratchPadSwitch,
            ]),
        ]
        var first = 0
        for group in Self.toolGroups {
            trays.append(tray(group.name, Array(toolPills[first..<first + group.tools.count])))
            first += group.tools.count
        }
        trays.append(tray("Undo", [iconButton("arrow.uturn.backward", "Undo (⌘Z)", self, #selector(undoIt)),
                                   iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)", self, #selector(redoIt))]))
        let settings = iconButton("gearshape", "Settings (⌘,)", self, #selector(openSettings))
        settings.keyVariant = .charcoal
        // ⇧⌘S is in the File menu.
        let saveAs = PillButton(title: "Save as…", symbol: "square.and.arrow.down", style: .keycap, height: keyHeight)
        saveAs.keyVariant = .orange
        saveAs.target = self; saveAs.action = #selector(saveAsIt)
        saveAs.toolTip = "Save as… (⇧⌘S)"

        toolRow.orientation = .horizontal
        toolRow.alignment = .top
        toolRow.spacing = 8
        toolRow.translatesAutoresizingMaskIntoConstraints = false
        trays.forEach { toolRow.addView($0, in: .leading) }
        // The space between the two ends stretches.
        toolRow.addView(tray("Settings", [settings]), in: .trailing)
        toolRow.addView(tray("Save", [saveAs]), in: .trailing)
        toolRow.setHuggingPriority(.defaultLow, for: .horizontal)
        return toolRow
    }

    /// The text menu with Smart Actions (#243) added below the copy commands.
    private func textMenu(_ menu: NSMenu) -> NSMenu {
        menu.addItem(.separator())
        let smart = NSMenuItem(title: "Smart Actions", action: nil, keyEquivalent: "")
        smart.image = symbol("wand.and.stars", "Smart Actions")
        smart.submenu = smartMenu
        smartMenu.delegate = self
        menu.addItem(smart)
        return menu
    }

    /// Shows the last result at once and scans the screenshot as it is now; the menu updates when the scan is done.
    private func updateSmartMenu() {
        fillSmartMenu()
        smartTask?.cancel()
        let image = canvas.flattened()
        smartTask = Task { @MainActor [weak self] in
            let actions = await SmartActionDetector.detect(in: image)
            guard !Task.isCancelled, let self else { return }
            smartActions = actions
            fillSmartMenu()
        }
    }

    private func fillSmartMenu() {
        smartMenu.removeAllItems()
        guard let actions = smartActions, !actions.isEmpty else {
            let note = NSMenuItem(title: smartActions == nil ? "Looking for actions…" : "No dates, addresses, links or codes found",
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            smartMenu.addItem(note)
            return
        }
        SmartActionMenu.items(for: actions).forEach(smartMenu.addItem)
    }

    // MARK: Attributes bar

    private func buildAttributesBar() {
        attributesBar.orientation = .horizontal
        attributesBar.spacing = 14
        colorWell.target = self; colorWell.action = #selector(colorChanged(_:)); colorWell.toolTip = "Color"

        func setUp(_ popup: PillPopUp, _ tip: String, _ caption: String?, _ choices: [(String, Int)], _ action: Selector) {
            popup.toolTip = tip
            popup.caption = caption
            popup.target = self; popup.action = action
            for (title, tag) in choices { popup.addItem(withTitle: title); popup.lastItem?.tag = tag }
        }
        setUp(strokePopup, "Stroke width", "Stroke", [1, 2, 3, 5, 8, 12].map { ("\($0) pt", $0) }, #selector(strokePicked(_:)))
        setUp(sizePopup, "Font size", "Size", EditorWindowController.fontSizes.map { ("\($0) pt", $0) }, #selector(sizePicked(_:)))
        setUp(pixelPopup, "Strength", "Strength", [("Light", 6), ("Medium", 10), ("Strong", 18), ("Heavy", 28)], #selector(pixelPicked(_:)))
        setUp(cornerStylePopup, "Corners", "Corners", [("Sharp", 0), ("Slight", 2), ("Rounded", 8), ("Very Round", 16)],
              #selector(cornerPicked(_:)))
        // Tags are tenths: 15 is 1.5×.
        setUp(magnificationPopup, "Magnification", "Zoom", [("1.5×", 15), ("2×", 20), ("3×", 30), ("4×", 40)],
              #selector(magnificationPicked(_:)))
        setUp(fontPopup, "Font", "Font", [], #selector(fontPicked(_:)))
        for (title, name) in Self.fontChoices {
            fontPopup.addItem(withTitle: title)
            fontPopup.lastItem?.representedObject = name
            if let f = NSFont(name: name, size: NSFont.systemFontSize(for: .small)) {
                fontPopup.lastItem?.attributedTitle = NSAttributedString(string: title, attributes: [.font: f])
            }
        }

        /// A segmented control's choices: the short title on the segment, the full name as its tooltip.
        func setUpChoices(_ control: RetroSegmented, _ tip: String, _ choices: [(String, String, Int)], _ action: Selector) {
            control.toolTip = tip
            control.target = self; control.action = action
            for (title, help, tag) in choices { control.addItem(title, tag: tag, help: help) }
        }
        setUpChoices(arrowStylePopup, "Arrow style", [("Filled", "Filled Head", ArrowStyle.filled.rawValue),
                                               ("Open", "Open Head", ArrowStyle.open.rawValue),
                                               ("Double", "Double-Headed", ArrowStyle.double.rawValue),
                                               ("Tapered", "Tapered", ArrowStyle.tapered.rawValue)], #selector(arrowStylePicked(_:)))
        setUpChoices(lensShapePopup, "Lens shape", [("Circle", "Circle", LensShape.circle.rawValue),
                                             ("Rect", "Rectangle", LensShape.rectangle.rawValue)], #selector(lensShapePicked(_:)))
        setUpChoices(shapeFillPopup, "Fill", [("None", "No Fill", ShapeFill.outline.rawValue),
                                       ("Tint", "Translucent Fill", ShapeFill.translucent.rawValue),
                                       ("Solid", "Solid Fill", ShapeFill.solid.rawValue)], #selector(shapeFillPicked(_:)))
        setUpChoices(textBoxPopup, "Text background", [("None", "No Box", TextBox.plain.rawValue), ("Solid", "Solid Box", TextBox.solid.rawValue),
                                                ("Outline", "Outlined Box", TextBox.outline.rawValue)], #selector(textBoxPicked(_:)))

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

        opacitySlider.controlSize = .small
        opacitySlider.isContinuous = false
        opacitySlider.toolTip = "How opaque a closed pen polygon's fill is"
        opacitySlider.target = self; opacitySlider.action = #selector(opacityChanged)
        opacitySlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

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
         opacityLabel, opacitySlider, arrangeButton].forEach(attributesBar.addArrangedSubview)
        attributesBar.setCustomSpacing(6, after: opacityLabel)
        attributesBar.setCustomSpacing(6, after: fontPopup)
        attributesBar.setCustomSpacing(6, after: sizePopup)
        refreshStrip()
    }

    /// The strip while Redact Text is on (#295): type words (Return or a comma makes each a chip), click highlights
    /// to leave them out, then Redact Selected or Redact All.
    private func buildFindBar() {
        findField.placeholderString = "Words to redact"
        findField.toolTip = "Return or a comma after each term; what is typed after the last one matches too"
        findField.font = .systemFont(ofSize: 12)
        findField.controlSize = .small
        findField.delegate = self
        findField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        findCount.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        findCount.lineBreakMode = .byTruncatingTail
        findCount.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        coverPopup.toolTip = "How matches are covered: only Solid really removes the text"
        coverPopup.target = self; coverPopup.action = #selector(coverPicked(_:))
        for c in RedactText.Cover.allCases { coverPopup.addItem(c.title, tag: c.rawValue) }
        redactSelectedButton.toolTip = "Redact the highlighted matches (click a match to leave it out)"
        redactAllButton.toolTip = "Redact every match"
        [findField, matchCaseButton, wholeWordButton, regexButton, fuzzyButton, coverPopup, findCount, redactSelectedButton,
         redactAllButton].forEach(findBar.addArrangedSubview)
        findBar.spacing = 10
        findBar.setCustomSpacing(14, after: findField)
        findBar.setCustomSpacing(14, after: fuzzyButton)
        findBar.setCustomSpacing(14, after: coverPopup)
        findBar.setCustomSpacing(14, after: findCount)
        findBar.setCustomSpacing(6, after: redactSelectedButton)
        findBar.isHidden = true
    }

    /// An orange-square toggle for the find bar; "Aa" and ".*" keep their case.
    private func findToggle(_ title: String, _ tip: String) -> PillButton {
        let b = PillButton(title: title, symbol: nil, style: .toggle, height: pillHeight)
        b.keepsCase = title.lowercased() == title || title == "Aa"
        b.target = self; b.action = #selector(findToggled(_:))
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        return b
    }

    private func refreshFindBar() {
        let o = Preferences.redactTextOptions
        matchCaseButton.isOn = o.caseSensitive
        wholeWordButton.isOn = o.wholeWord
        regexButton.isOn = o.regex
        fuzzyButton.isOn = o.fuzzy
        coverPopup.selectItem(withTag: Preferences.redactTextCover.rawValue)
        refreshFindCount()
    }

    private func refreshFindCount() {
        guard stripMode == .redactText else { return }
        findCount.stringValue = canvas.findStatus
        let invalid = RedactText.hasInvalidPattern(findTerms, options: Preferences.redactTextOptions)
        findCount.textColor = invalid ? .systemRed : .secondaryLabelColor
    }

    /// The chips, plus the text typed after them that isn't a chip yet (it matches as it is typed).
    private var findTerms: [String] {
        if let values = findField.objectValue as? [Any] { return values.compactMap { $0 as? String } }
        return findField.stringValue.components(separatedBy: ",")
    }

    private func updateFind() { canvas.find(findTerms, options: Preferences.redactTextOptions) }

    private func focusFindField() {
        guard stripMode == .redactText else { return }
        window?.makeFirstResponder(findField)
        // After the chips, so typing adds a term instead of replacing them all.
        if let editor = findField.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }

    private func clearFindField() {
        findField.abortEditing()
        findField.objectValue = [String]()
    }

    /// Esc in the find bar, or on the canvas: back to Select, which closes the bar.
    private func endRedactText() {
        canvas.endRedactText()
        window?.makeFirstResponder(canvas)
    }

    @objc private func findToggled(_ b: PillButton) {
        var o = Preferences.redactTextOptions
        if b === matchCaseButton {
            o.caseSensitive.toggle()
        } else if b === wholeWordButton {
            o.wholeWord.toggle()
        } else if b === regexButton {
            // Fuzzy matching doesn't apply to patterns, so the two are never on together.
            o.regex.toggle()
            if o.regex { o.fuzzy = false }
        } else if b === fuzzyButton {
            o.fuzzy.toggle()
            if o.fuzzy { o.regex = false }
        }
        Preferences.redactTextOptions = o
        refreshFindBar()
        updateFind()
    }

    @objc private func coverPicked(_ p: RetroSegmented) {
        Preferences.redactTextCover = RedactText.Cover(rawValue: p.selectedTag()) ?? .solid
    }

    @objc private func redactSelectedFound() { redactFound(all: false) }
    @objc private func redactAllFound() { redactFound(all: true) }

    /// Covers the matches, then starts over with no terms; the tool stays on for more.
    private func redactFound(all: Bool) {
        let n = canvas.redactFound(all: all, cover: Preferences.redactTextCover)
        guard n > 0 else { return }
        clearFindField()
        updateFind()
        showToast(n == 1 ? "Redacted 1 match" : "Redacted \(n) matches")
        focusFindField()
    }

    private func buildCropBar() {
        let reset = textButton("Reset", self, #selector(cropReset))
        let cancel = textButton("Cancel", self, #selector(cropCancel))
        let apply = textButton("Apply", self, #selector(cropApply), filled: true)
        [reset, cancel, apply].forEach(cropBar.addArrangedSubview)
        cropBar.spacing = 6
        cropBar.isHidden = true
    }

    /// The strip while dragging out an area for Copy Text, the average color or Check Contrast.
    private func buildAreaBar() {
        contrastLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        contrastLabel.textColor = .labelColor
        contrastMethodButton.toolTip = "Switch between WCAG 2 and APCA (or ⌥-click the screenshot)"
        [contrastLabel, contrastMethodButton, copyAllTextButton, areaDoneButton].forEach(areaBar.addArrangedSubview)
        areaBar.spacing = 6
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

    @objc private func scratchPadToggled() {
        Preferences.textScratchPad = scratchPadSwitch.state == .on
        showToast(Preferences.textScratchPad ? "Text opens in the scratch pad" : "Text is copied straight away")
        window?.makeFirstResponder(canvas)
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

        shadowSlider.controlSize = .small
        shadowSlider.isContinuous = false
        shadowSlider.toolTip = "Shadow under the screenshot"
        shadowSlider.target = self; shadowSlider.action = #selector(backgroundShadowChanged)
        shadowSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        balanceButton.toolTip = "Trim uneven empty margins and center the content (crops, undoable)"
        removeBackgroundButton.toolTip = "Take the background off the screenshot (⌘Z brings it back)"
        [fillPopup, directionPopup, gradientFrom, gradientTo, chooseImageButton, blurPopup, aspectPopup, paddingPopup,
         balanceButton, cornerPopup, framePopup, shadowLabel, shadowSlider, removeBackgroundButton].forEach(backgroundBar.addArrangedSubview)
        backgroundBar.spacing = 6
        backgroundBar.setCustomSpacing(6, after: shadowLabel)
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
        // Clicking an annotation or picking a tool leaves the background options; Redact Text has its own bar.
        if canvas.tool != .redactText, !findField.stringValue.isEmpty { clearFindField() }
        let resting = restingStrip
        if [.tools, .redactText, .background, .deviceFrame].contains(stripMode), stripMode != resting {
            stripMode = resting
        } else {
            refreshStrip()
        }
    }

    private func refreshStrip() {
        attributesBar.isHidden = stripMode != .tools
        cropBar.isHidden = stripMode != .crop
        areaBar.isHidden = stripMode != .areaPick
        findBar.isHidden = stripMode != .redactText
        backgroundBar.isHidden = stripMode != .background
        deviceFrameBar.isHidden = stripMode != .deviceFrame
        // The title (the tool or mode) is on the status display.
        switch stripMode {
        case .tools: refreshAttributes(canvas.contextTool, canvas.contextStyle)
        case .crop: attributesTitle.stringValue = "Crop"
        case .areaPick: refreshAreaBar()
        case .redactText:
            attributesTitle.stringValue = Tool.redactText.name
            refreshFindBar()
        case .background:
            attributesTitle.stringValue = "Background"
            refreshBackgroundBar()
        case .deviceFrame:
            attributesTitle.stringValue = "Frame"
            refreshDeviceFrameBar()
        }
        // An empty options row would leave a double gap.
        if stripMode == .tools, attributesBar.arrangedSubviews.allSatisfy(\.isHidden) { attributesBar.isHidden = true }
        refreshDisplay()
    }

    /// Shows the controls for `tool` and loads them with `style`.
    private func refreshAttributes(_ tool: Tool, _ style: Style) {
        // `.select` here means nothing is selected: there is no style to edit.
        attributesTitle.stringValue = tool.name
        colorWell.isHidden = [.select, .pixelate, .blur, .erase, .spotlight, .image].contains(tool)
        strokePopup.isHidden = !tool.usesStroke
        ([fontPopup, boldButton, textBoxPopup, tailButton] as [NSView]).forEach { $0.isHidden = tool != .text }
        shapeFillPopup.isHidden = tool != .rect && tool != .ellipse
        handDrawnButton.isHidden = ![.arrow, .line, .rect, .ellipse].contains(tool)
        shapeCorrectionButton.isHidden = tool != .pen
        // The fill controls show for a selected closed polygon, and for the pen tool with nothing selected (to set the
        // fill used by the next polygon drawn).
        let showFill = tool == .pen && (canvas.contextIsClosedPolygon || !canvas.hasSelection)
        opacityLabel.isHidden = !showFill
        opacitySlider.isHidden = !showFill
        sizePopup.isHidden = tool != .text && tool != .counter
        pixelPopup.isHidden = !tool.hasStrength
        textOnlyButton.isHidden = !tool.obscures
        ([magnificationPopup, lensShapePopup] as [NSView]).forEach { $0.isHidden = tool != .magnifier }
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
        opacitySlider.doubleValue = Double(style.fillOpacity)
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

    @objc private func colorChanged(_ w: SwatchRow) { canvas.updateStyle { $0.color = w.color } }
    @objc private func opacityChanged() { canvas.updateStyle { $0.fillOpacity = CGFloat(opacitySlider.doubleValue) } }
    @objc private func strokePicked(_ p: PillPopUp) { canvas.updateStyle { $0.lineWidth = CGFloat(p.selectedTag()) } }
    @objc private func sizePicked(_ p: PillPopUp) { canvas.updateStyle { $0.fontSize = CGFloat(p.selectedTag()) } }
    @objc private func pixelPicked(_ p: PillPopUp) { canvas.updateStyle { $0.pixelSize = CGFloat(p.selectedTag()) } }
    @objc private func cornerPicked(_ p: PillPopUp) { canvas.updateStyle { $0.cornerRadius = CGFloat(p.selectedTag()) } }
    @objc private func arrowStylePicked(_ p: RetroSegmented) {
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
    @objc private func shapeFillPicked(_ p: RetroSegmented) {
        canvas.updateStyle { $0.fill = ShapeFill(rawValue: p.selectedTag()) ?? .outline }
    }
    @objc private func textBoxPicked(_ p: RetroSegmented) {
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
    @objc private func lensShapePicked(_ p: RetroSegmented) {
        canvas.updateStyle { $0.lensShape = LensShape(rawValue: p.selectedTag()) ?? .circle }
    }

    // MARK: Actions

    @objc private func toolChanged(_ sender: PillButton) {
        guard let i = toolPills.firstIndex(where: { $0 === sender }) else { return }
        chooseTool(toolButtons[i].tool)
    }
    fileprivate func chooseTool(_ t: Tool) {
        selectToolButton(t)
        canvas.applyCrop()
        canvas.tool = t
        if stripMode == .background || stripMode == .deviceFrame { stripMode = restingStrip }
        if canvas.tool == .redactText { focusFindField() } else { window?.makeFirstResponder(canvas) }
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
        // The file it was saved to as it is named now (renamed after what it shows, or moved by a filing rule), else
        // what the capture shows.
        let name = fileURL.map(AutoFiling.current)?.deletingPathExtension().lastPathComponent
            ?? ContentNaming.suggestedName(for: image)
        if let url = Output.saveAs(canvas.flattened(), name: name) { fileURL = url }
    }

    /// Writes the image (see `saveScreenshot`) and returns where; nil after saying why it failed.
    private func save() -> URL? {
        let image = canvas.flattened()
        // A filing rule may have moved the file since (#277).
        if let file = fileURL { fileURL = AutoFiling.current(file) }
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
        guard let url = ContentNaming.save(image, capture: self.image) else {
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
    @MainActor @objc func askClaudeIt() { AskClaudePanel.show(canvas.flattened(), from: window) }
    @objc private func shareIt(_ sender: NSButton) { Output.share(canvas.flattened(), from: sender) }
    /// The Send To menu (#276): the screenshot as the file the destination picked gets, annotations included.
    @MainActor @objc private func sendToIt(_ sender: NSButton) {
        let source = SendTo.Source(app: fileURL.flatMap(SendTo.appName(for:))) { [weak self] in
            guard let image = self?.canvas.flattened() else { return nil }
            return Output.temporaryFile(image).map { (file: $0, image: image) }
        }
        SendTo.present(source, from: sender)
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

    // MARK: Combine Screenshots (#273)

    /// The layers added to the canvas, e.g. by Combine Screenshots on the new tab.
    func addImageLayers(_ placed: [(image: NSImage, frame: NSRect)]) { canvas.insertImages(placed) }

    /// Offers this window's tabs, then the newest history captures, to combine; all the tabs start ticked.
    @objc func combineScreenshots() {
        let tabs = tabGroup.editors.map { editor in
            CombineScreenshots.Candidate(title: editor.window?.title ?? "Screenshot", thumbnail: editor.dockThumbnail,
                                         image: { editor.canvas.flattened() }, selected: true)
        }
        let history = CombineScreenshots.historyCandidates(count: 12)
        CombineScreenshots.present(tabs + history, from: window)
    }

    // MARK: Import from iPhone or iPad (#270)

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        ContinuityCamera.accepts(sendType: sendType, returnType: returnType)
            ? self : super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    /// The picture from the device: a layer here, or a new tab when the menu-bar item asked for it.
    func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let img = ContinuityCamera.image(from: pboard) else { return false }
        if ContinuityCamera.opensInNewTab { EditorWindowController(image: img).present() } else { canvas.insertImage(img) }
        return true
    }

    private func buildAddImageMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
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
        m.addItem(.separator())
        m.addItem(ContinuityCamera.menuItem(title: "Import from iPhone or iPad"))
        m.addItem(.separator())
        let combine = NSMenuItem(title: "Combine Screenshots…", action: #selector(combineScreenshots), keyEquivalent: "")
        combine.target = self
        combine.image = symbol("rectangle.split.3x1", "Combine Screenshots")
        m.addItem(combine)
        return m
    }

    /// Fills Add Image → From Capture History with the newest captures, as thumbnails.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu !== historyMenu { ContinuityCamera.opensInNewTab = false }
        if menu === smartMenu { updateSmartMenu(); return }
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
        if stripMode == .background { stripMode = restingStrip; return }
        canvas.applyCrop()
        canvas.clearSelection()
        if canvas.background == nil { canvas.updateBackground { $0 = Preferences.lastBackground } }
        stripMode = .background
        window?.makeFirstResponder(canvas)
    }

    /// Shows the frame options; the frame itself starts as None.
    @objc private func deviceFrameIt() {
        if stripMode == .deviceFrame { stripMode = restingStrip; return }
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
        for (title, tag) in [("Light", 0), ("Dark", 1)] { deviceLookPopup.addItem(title, tag: tag) }
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
        shadowLabel.alphaValue = bg != nil ? 1 : 0.45
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

    /// Takes the background off (undoable) and closes its options.
    @objc private func removeBackground() {
        canvas.updateBackground { $0 = nil }
        stripMode = restingStrip
        window?.makeFirstResponder(canvas)
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

// Redact Text's find field (#295): every keystroke matches again; Return makes a chip, Esc ends the tool.
extension EditorWindowController: NSTokenFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTokenField) === findField else { return }
        updateFind()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTokenField) === findField else { return }
        updateFind()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === findField else { return false }
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
            // After this keystroke is handled: ending the tool takes the field out of editing.
            Task { @MainActor [weak self] in self?.endRedactText() }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Return ends editing, which makes the typed text a chip; typing then goes on after the chips.
            Task { @MainActor [weak self] in self?.focusFindField() }
            return false
        default:
            return false
        }
    }
}

// MARK: Tips, the hint line and "New" dots (#301, #303)

extension EditorWindowController {
    private func setUpHelp() {
        help = EditorHelp(canvas: canvas,
                          toolPill: { [weak self] t in self?.toolPill(for: t) },
                          featurePills: { [weak self] in self?.featurePills() ?? [] },
                          showLine: { [weak self] text in self?.liveHint = text; self?.refreshDisplay() })
    }

    /// The toolbar button of tool `t`.
    private func toolPill(for t: Tool) -> NSView? {
        guard let i = toolButtons.firstIndex(where: { $0.tool == t }), toolPills.indices.contains(i) else { return nil }
        return toolPills[i]
    }

    /// The toolbar's pull-downs whose menus run a feature that can wear a "New" dot.
    private func featurePills() -> [PillPopUp] {
        func popUps(in v: NSView) -> [PillPopUp] {
            if let p = v as? PillPopUp { return [p] }
            return v.subviews.flatMap(popUps)
        }
        let pills = popUps(in: toolRow)
        return pills.filter { p in (p.menu?.items ?? []).contains { $0.action.flatMap(NewFeature.running) != nil } }
    }
}

// Variants of Rectangle and Arrow (#303): the same tool and style changes as the tool strip, from a menu on the tool button.
extension EditorWindowController {
    fileprivate func variantItem(_ title: String, _ action: Selector, tag: Int, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = on ? .on : .off
        return item
    }

    fileprivate func rectangleVariantMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(variantItem("Outline (R)", #selector(toolVariantPicked(_:)), tag: Tool.rect.rawValue, on: canvas.tool == .rect))
        m.addItem(variantItem("Filled (F)", #selector(toolVariantPicked(_:)), tag: Tool.filledRect.rawValue, on: canvas.tool == .filledRect))
        m.addItem(.separator())
        m.addItem(variantItem("Hand-Drawn", #selector(rectangleHandDrawnPicked(_:)), tag: 0, on: canvas.contextStyle.handDrawn))
        return m
    }

    fileprivate func arrowVariantMenu() -> NSMenu {
        let m = NSMenu()
        let current = canvas.tool == .arrow ? canvas.contextStyle.arrowStyle : nil
        let styles: [(String, ArrowStyle)] = [("Filled Head", .filled), ("Open Head", .open), ("Double-Headed", .double), ("Tapered", .tapered)]
        for (title, style) in styles {
            m.addItem(variantItem(title, #selector(arrowVariantPicked(_:)), tag: style.rawValue, on: current == style))
        }
        return m
    }

    @objc fileprivate func toolVariantPicked(_ item: NSMenuItem) {
        guard let t = Tool(rawValue: item.tag) else { return }
        chooseTool(t)
    }

    @objc fileprivate func rectangleHandDrawnPicked(_ item: NSMenuItem) {
        let on = item.state != .on
        chooseTool(.rect)
        canvas.updateStyle { $0.handDrawn = on }
        contextChanged()
    }

    @objc fileprivate func arrowVariantPicked(_ item: NSMenuItem) {
        let style = ArrowStyle(rawValue: item.tag) ?? .filled
        chooseTool(.arrow)
        canvas.updateStyle { $0.arrowStyle = style }
        contextChanged()
    }
}
