import AppKit

enum Tool: Int, CaseIterable {
    /// `.image` is not a toolbar tool: it marks pictures added with Add Image or pasted with ⌘V.
    case select, arrow, rect, filledRect, ellipse, line, pen, highlighter, text, counter, pixelate, image

    /// Single-key shortcuts in the editor (no modifiers).
    static let shortcuts: [Character: Tool] = ["v": .select, "a": .arrow, "r": .rect, "f": .filledRect, "o": .ellipse,
                                               "l": .line, "p": .pen, "h": .highlighter, "t": .text, "n": .counter,
                                               "x": .pixelate]

    var usesStroke: Bool { [.arrow, .rect, .ellipse, .line, .pen, .highlighter].contains(self) }
    /// Freehand tools keep every point of the drag.
    var isFreehand: Bool { self == .pen || self == .highlighter }

    var name: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .rect: return "Rectangle"
        case .filledRect: return "Filled Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .counter: return "Counter"
        case .pixelate: return "Pixelate"
        case .image: return "Image"
        }
    }
}

/// Per-annotation look. New annotations copy the canvas's current style; editing the style of a
/// selected annotation changes only that annotation.
struct Style: Equatable {
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 22
    /// Font family name; empty means the system font.
    var fontName: String = ""
    var bold = true
    /// Mosaic cell size for the pixelate tool.
    var pixelSize: CGFloat = 10

    var font: NSFont {
        if fontName.isEmpty { return .systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular) }
        let f = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        return bold ? NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) : f
    }

    var textAttributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: color] }

    /// Highlighter strokes are much wider than the chosen stroke width.
    var highlighterWidth: CGFloat { max(12, lineWidth * 5) }
    /// Counter badges scale with the font size.
    var counterRadius: CGFloat { max(10, fontSize * 0.75) }
}

/// Backdrop drawn around the whole screenshot (CleanShot's "Background" tool): a gradient or solid fill,
/// padding, rounded corners and a shadow under the screenshot.
struct Background: Equatable {
    var fill = 0
    var padding: CGFloat = 48
    var cornerRadius: CGFloat = 10
    var shadow = true

    static let presets: [(name: String, colors: [NSColor])] = [
        ("Sky", [hex(0x4FACFE), hex(0x00F2FE)]),
        ("Sunset", [hex(0xF093FB), hex(0xF5576C)]),
        ("Peach", [hex(0xFFECD2), hex(0xFCB69F)]),
        ("Mint", [hex(0x43E97B), hex(0x38F9D7)]),
        ("Violet", [hex(0x667EEA), hex(0x764BA2)]),
        ("Graphite", [hex(0x434343), hex(0x111111)]),
        ("White", [.white]),
        ("Black", [.black]),
    ]

    private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func draw(fill: Int, in r: NSRect) {
        let colors = presets[min(max(fill, 0), presets.count - 1)].colors
        if colors.count == 1 { colors[0].setFill(); r.fill() } else { NSGradient(colors: colors)?.draw(in: r, angle: -45) }
    }
}

/// One annotation, kept as an editable object (never baked into the image until export).
/// For text, `start` is the top-left corner of the text.
struct Annotation: Equatable {
    var id = UUID()
    var tool: Tool
    var start: NSPoint
    var end: NSPoint
    var points: [NSPoint] = []
    var text: String = ""
    var image: NSImage? = nil
    var style: Style

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
        points = points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
    }
}

/// Text view used to type text annotations in place. The usual ⌘C/⌘V/⌘X/⌘A/⌘Z shortcuts are handled
/// here so they act on the text box, not the canvas; Esc or ⌘Return finishes editing.
private final class InlineTextView: NSTextView {
    var onFinish: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (mods, key) {
        case ([.command], "c"): copy(nil)
        case ([.command], "v"): pasteAsPlainText(nil)
        case ([.command], "x"): cut(nil)
        case ([.command], "a"): selectAll(nil)
        case ([.command], "z"): undoManager?.undo()
        case ([.command, .shift], "z"): undoManager?.redo()
        case ([.command], "\r"): onFinish?()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) { onFinish?() }
}

/// Drawing surface in image coordinates. Click an annotation to select it, drag to move it, drag a handle
/// to resize it, double-click text to edit it in place; ⌫ deletes, arrows nudge, ⌘Z / ⇧⌘Z undo and redo.
final class CanvasView: NSView, NSTextViewDelegate {
    let base: NSImage
    private(set) var items: [Annotation] = [] {
        didSet { updateExtent() }
    }
    /// Area kept by the Crop tool (image coordinates); nil keeps the image plus every annotation.
    private(set) var crop: NSRect? {
        didSet { updateExtent() }
    }
    /// While cropping, the area being chosen; the canvas then shows everything and dims what falls outside.
    private var cropDraft: NSRect? {
        didSet { updateExtent(); needsDisplay = true }
    }
    var isCropping: Bool { cropDraft != nil }
    /// Called when crop mode starts (true) or ends (false).
    var onCropModeChange: ((Bool) -> Void)?
    private(set) var background: Background? {
        didSet { updateExtent(); onBackgroundChange?() }
    }
    var onBackgroundChange: (() -> Void)?
    /// The background is hidden while cropping so the whole screenshot can be seen.
    private var activeBackground: Background? { isCropping ? nil : background }
    /// The screenshot area: the captured image plus any annotations that stick out past it, or the crop
    /// (image coordinates). The part outside the image is filled with `backdrop`.
    private(set) var contentRect: NSRect
    /// What the canvas and the export cover: `contentRect` plus the background padding.
    private(set) var extent: NSRect
    /// Called after `extent` changes, with the previous extent.
    var onExtentChange: ((NSRect) -> Void)?
    private var imageRect: NSRect { NSRect(origin: .zero, size: base.size) }
    /// Fill for the grown area: the color of the image's top-left pixel.
    private lazy var backdrop: NSColor = bitmap()?.colorAt(x: 0, y: 0) ?? .white
    var tool: Tool = .arrow {
        didSet { if tool != oldValue { finishTextEditing(); notifyContext() } }
    }
    /// Style given to new annotations.
    private(set) var style = Style()
    /// Called when a single-key shortcut switches the tool.
    var onToolShortcut: ((Tool) -> Void)?
    /// Called whenever the attributes bar should change: the tool whose options apply and the style to show.
    var onContextChange: ((Tool, Style) -> Void)?

    private enum Drag {
        case draw
        case move(last: NSPoint)
        case resizeCorner(anchor: NSPoint)
        case resizeEnd(isStart: Bool)
        case cropCorner(anchor: NSPoint)
        case cropMove(last: NSPoint)
    }
    /// Everything one undo step restores.
    private struct Snapshot: Equatable {
        var items: [Annotation]
        var crop: NSRect?
        var background: Background?
    }
    private var snapshot: Snapshot {
        get { Snapshot(items: items, crop: crop, background: background) }
        set { items = newValue.items; crop = newValue.crop; background = newValue.background }
    }
    private var draft: Annotation? {
        didSet { updateExtent() }
    }
    private var drag: Drag?
    private var beforeDrag = Snapshot(items: [])
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var exporting = false
    private var selectedID: UUID? {
        didSet { if selectedID != oldValue { notifyContext() } }
    }
    private var selectedIndex: Int? { index(of: selectedID) }

    private var textEditor: InlineTextView?
    private var editingID: UUID?
    private var beforeEditing = Snapshot(items: [])

    init(image: NSImage) {
        base = image
        extent = NSRect(origin: .zero, size: image.size)
        contentRect = extent
        super.init(frame: NSRect(origin: .zero, size: image.size))
        NotificationCenter.default.addObserver(forName: .skreenerPreferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    /// Screen-space sizes (handles, hit slop) divided by the zoom so they feel the same at any magnification.
    private var zoom: CGFloat { max(enclosingScrollView?.magnification ?? 1, 0.01) }

    private func index(of id: UUID?) -> Int? { id.flatMap { id in items.firstIndex { $0.id == id } } }

    /// The tool whose options the attributes bar shows: the selected annotation's, else the current tool's.
    var contextTool: Tool { selectedIndex.map { items[$0].tool } ?? tool }
    var contextStyle: Style { selectedIndex.map { items[$0].style } ?? style }

    private func notifyContext() { onContextChange?(contextTool, contextStyle) }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if textEditor != nil { finishTextEditing(); return }   // a click outside the text box ends typing
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if let r = cropDraft { drag = cropDrag(in: r, at: p); return }
        beforeDrag = snapshot

        if let i = selectedIndex, let d = handleDrag(for: items[i], at: p) { drag = d; return }
        if let i = items.indices.reversed().first(where: { hits(items[$0], p) }) {
            selectedID = items[i].id
            if event.clickCount == 2, items[i].tool == .text { beginTextEditing(at: i); return }
            drag = .move(last: p); needsDisplay = true
            return
        }
        selectedID = nil
        needsDisplay = true
        switch tool {
        case .select, .image: return
        case .text: addText(at: p)
        case .counter:
            // Placed on mouse down; dragging before release moves it, and both are one undo step.
            let a = Annotation(tool: .counter, start: p, end: p, style: style)
            items.append(a)
            selectedID = a.id
            drag = .move(last: p)
        default:
            draft = Annotation(tool: tool, start: p, end: p, points: [p], style: style)
            drag = .draw
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .draw?:
            draft?.end = p; draft?.points.append(p)
        case .move(let last)?:
            guard let i = selectedIndex else { return }
            items[i].translate(dx: p.x - last.x, dy: p.y - last.y)
            drag = .move(last: p)
        case .resizeCorner(let anchor)?:
            guard let i = selectedIndex else { return }
            items[i].start = anchor; items[i].end = p
        case .resizeEnd(let isStart)?:
            guard let i = selectedIndex else { return }
            if isStart { items[i].start = p } else { items[i].end = p }
        case .cropCorner(let anchor)?:
            let full = fullContentRect()
            let q = NSPoint(x: min(max(p.x, full.minX), full.maxX), y: min(max(p.y, full.minY), full.maxY))
            cropDraft = NSRect(x: min(anchor.x, q.x), y: min(anchor.y, q.y), width: abs(q.x - anchor.x), height: abs(q.y - anchor.y))
        case .cropMove(let last)?:
            guard var r = cropDraft else { return }
            let full = fullContentRect()
            r.origin.x = min(max(r.minX + p.x - last.x, full.minX), full.maxX - r.width)
            r.origin.y = min(max(r.minY + p.y - last.y, full.minY), full.maxY - r.height)
            cropDraft = r
            drag = .cropMove(last: p)
        case nil: return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let d = drag else { return }   // text add/edit records its own undo step
        if isCropping { drag = nil; return }  // the crop is recorded when it is applied
        if case .draw = d, let a = draft, isMeaningful(a) {
            items.append(a)
            selectedID = a.id
        }
        recordUndo(from: beforeDrag)
        draft = nil; drag = nil
        needsDisplay = true
    }

    private func isMeaningful(_ a: Annotation) -> Bool {
        a.tool.isFreehand ? a.points.count > 1 : hypot(a.end.x - a.start.x, a.end.y - a.start.y) > 2
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if isCropping {
            switch event.keyCode {
            case 36, 76: applyCrop()     // Return / Enter
            case 53: cancelCrop()        // Esc
            default: break
            }
            return
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117: deleteSelection(); return                         // ⌫, ⌦
        case 53: selectedID = nil; needsDisplay = true; return          // Esc
        case 36, 76:                                                    // Return / Enter edits selected text
            if let i = selectedIndex, items[i].tool == .text { beginTextEditing(at: i) }
            return
        case 123: nudge(dx: -step, dy: 0); return
        case 124: nudge(dx: step, dy: 0); return
        case 125: nudge(dx: 0, dy: -step); return
        case 126: nudge(dx: 0, dy: step); return
        default: break
        }
        if mods.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "c" { beginCrop(); return }
        if mods.isEmpty, let c = event.charactersIgnoringModifiers?.lowercased().first, let t = Tool.shortcuts[c] {
            tool = t
            onToolShortcut?(t)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard textEditor == nil, window?.isKeyWindow == true, event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return super.performKeyEquivalent(with: event)
        }
        switch mods {
        case [.command]: undo(); return true
        case [.command, .shift]: redo(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: Editing

    // Edit menu → Undo / Redo
    @objc func undo(_ sender: Any?) { undo() }
    @objc func redo(_ sender: Any?) { redo() }

    func undo() {
        finishTextEditing()
        cancelCrop()
        guard let previous = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(snapshot)
        snapshot = previous
        if selectedIndex == nil { selectedID = nil } else { notifyContext() }
        needsDisplay = true
    }

    func redo() {
        finishTextEditing()
        cancelCrop()
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(snapshot)
        snapshot = next
        if selectedIndex == nil { selectedID = nil } else { notifyContext() }
        needsDisplay = true
    }

    /// Changes the style for new annotations and, if one is selected (or being typed), restyles it too.
    func updateStyle(_ change: (inout Style) -> Void) {
        change(&style)
        if let i = selectedIndex {
            var s = items[i].style
            change(&s)
            if s != items[i].style {
                if editingID == items[i].id { items[i].style = s } else { mutate { items[i].style = s } }
            }
        }
        if let editor = textEditor, let i = index(of: editingID) { styleEditor(editor, items[i].style); layoutEditor() }
        needsDisplay = true
    }

    func clearSelection() {
        selectedID = nil
        needsDisplay = true
    }

    /// Changes (or with nil, removes) the background; one undo step per change.
    func updateBackground(_ change: (inout Background?) -> Void) {
        finishTextEditing()
        mutate { change(&background) }
    }

    /// Adds a picture as a movable, resizable annotation, centered in view and scaled down to fit the screenshot.
    func insertImage(_ img: NSImage) {
        guard img.size.width > 0, img.size.height > 0 else { NSSound.beep(); return }
        finishTextEditing()
        cancelCrop()
        let scale = min(1, contentRect.width * 0.6 / img.size.width, contentRect.height * 0.6 / img.size.height)
        let w = img.size.width * scale, h = img.size.height * scale
        let c = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        let a = Annotation(tool: .image, start: NSPoint(x: c.x - w / 2, y: c.y - h / 2),
                           end: NSPoint(x: c.x + w / 2, y: c.y + h / 2), image: img, style: style)
        mutate { items.append(a) }
        selectedID = a.id
        window?.makeFirstResponder(self)
    }

    // Edit menu → Paste (⌘V): pastes an image from the clipboard onto the canvas.
    @objc func paste(_ sender: Any?) {
        guard let img = ImageSource.fromClipboard() else { NSSound.beep(); return }
        insertImage(img)
    }

    // MARK: Crop

    /// Enters crop mode with the current crop (or everything) chosen.
    func beginCrop() {
        guard !isCropping else { return }
        finishTextEditing()
        clearSelection()
        cropDraft = crop ?? fullContentRect()
        onCropModeChange?(true)
    }

    /// Keeps the chosen area. Choosing everything removes the crop; a tiny area is ignored.
    func applyCrop() {
        guard let r = cropDraft?.integral else { return }
        let before = snapshot
        let full = fullContentRect()
        cropDraft = nil
        if r.contains(full) { crop = nil } else if r.width >= 4, r.height >= 4 { crop = r }
        recordUndo(from: before)
        onCropModeChange?(false)
    }

    func cancelCrop() {
        guard isCropping else { return }
        cropDraft = nil
        onCropModeChange?(false)
    }

    /// While cropping, chooses everything again.
    func resetCrop() {
        if isCropping { cropDraft = fullContentRect() }
    }

    private func cropDrag(in r: NSRect, at p: NSPoint) -> Drag {
        let corners = [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
                       NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)]
        if let h = corners.indices.first(where: { hypot(corners[$0].x - p.x, corners[$0].y - p.y) <= 10 / zoom }) {
            return .cropCorner(anchor: corners[3 - h])
        }
        if r.contains(p) { return .cropMove(last: p) }
        let full = fullContentRect()
        return .cropCorner(anchor: NSPoint(x: min(max(p.x, full.minX), full.maxX), y: min(max(p.y, full.minY), full.maxY)))
    }

    func deleteSelection() {
        guard let i = selectedIndex else { return }
        mutate { _ = items.remove(at: i) }
        selectedID = nil
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let i = selectedIndex else { return }
        mutate { items[i].translate(dx: dx, dy: dy) }
    }

    private func mutate(_ change: () -> Void) {
        let before = snapshot
        change()
        recordUndo(from: before)
        needsDisplay = true
    }

    private func recordUndo(from before: Snapshot) {
        guard snapshot != before else { return }
        undoStack.append(before)
        redoStack.removeAll()
    }

    // MARK: Inline text

    private func addText(at p: NSPoint) {
        beforeEditing = snapshot
        // Put the click roughly on the first line's vertical center.
        let top = NSPoint(x: p.x, y: p.y + style.font.boundingRectForFont.height / 2)
        let a = Annotation(tool: .text, start: top, end: top, style: style)
        items.append(a)
        selectedID = a.id
        startEditor(for: a)
    }

    private func beginTextEditing(at i: Int) {
        beforeEditing = snapshot
        selectedID = items[i].id
        startEditor(for: items[i])
    }

    private func startEditor(for a: Annotation) {
        let tv = InlineTextView(frame: NSRect(origin: a.start, size: .zero))
        tv.delegate = self
        tv.onFinish = { [weak self] in self?.finishTextEditing() }
        tv.string = a.text
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.wantsLayer = true
        tv.layer?.masksToBounds = false
        styleEditor(tv, a.style)
        editingID = a.id
        textEditor = tv
        addSubview(tv)
        layoutEditor()
        tv.setSelectedRange(NSRange(location: (a.text as NSString).length, length: 0))
        window?.makeFirstResponder(tv)
        notifyContext()
        needsDisplay = true
    }

    private func styleEditor(_ tv: NSTextView, _ s: Style) {
        tv.font = s.font
        tv.textColor = s.color
        tv.insertionPointColor = s.color
        tv.typingAttributes = s.textAttributes
        tv.textStorage?.setAttributes(s.textAttributes, range: NSRange(location: 0, length: (tv.string as NSString).length))
    }

    /// Sizes the text box to its content, keeping the top-left corner fixed, and frames it like a selection.
    private func layoutEditor() {
        guard let tv = textEditor, let i = index(of: editingID),
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).size
        let font = items[i].style.font
        let size = NSSize(width: max(used.width, font.pointSize * 0.6) + 2,
                          height: max(used.height, lm.defaultLineHeight(for: font)))
        tv.minSize = size
        tv.frame = NSRect(x: items[i].start.x, y: items[i].start.y - size.height, width: size.width, height: size.height)
        let px = 1 / zoom
        tv.layer?.borderColor = NSColor.controlAccentColor.cgColor
        tv.layer?.borderWidth = 1.5 * px
        tv.layer?.cornerRadius = 4 * px
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = textEditor, let i = index(of: editingID) else { return }
        items[i].text = tv.string
        layoutEditor()
    }

    /// Ends in-place typing: keeps the text (or drops an empty box) and records one undo step.
    func finishTextEditing() {
        guard let tv = textEditor else { return }
        textEditor = nil
        tv.delegate = nil
        tv.removeFromSuperview()
        if let i = index(of: editingID) {
            items[i].text = tv.string
            if items[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.remove(at: i)
                selectedID = nil
            }
        }
        editingID = nil
        recordUndo(from: beforeEditing)
        window?.makeFirstResponder(self)
        notifyContext()
        needsDisplay = true
    }

    // MARK: Extent

    /// The image plus every annotation, ignoring the crop.
    private func fullContentRect() -> NSRect {
        var r = imageRect
        for a in items + (draft.map { [$0] } ?? []) where !(a.tool == .text && a.text.isEmpty) {
            r = r.union(bounds(of: a).insetBy(dx: -inkPadding(a), dy: -inkPadding(a)))
        }
        return r.integral
    }

    /// Grows (or shrinks back) the canvas to cover the image and every annotation, like CleanShot, or just the
    /// crop, plus the background padding. Annotations keep image coordinates: only the view's bounds change.
    private func updateExtent() {
        let content = cropDraft == nil ? (crop ?? fullContentRect()) : fullContentRect()
        let pad = activeBackground?.padding ?? 0
        let r = content.insetBy(dx: -pad, dy: -pad)
        contentRect = content
        needsDisplay = true
        guard r != extent else { return }
        let old = extent
        extent = r
        setFrameSize(r.size)
        setBoundsOrigin(r.origin)
        onExtentChange?(old)
    }

    /// How far the drawn ink reaches past an annotation's geometric bounds (half the stroke, or the arrowhead).
    private func inkPadding(_ a: Annotation) -> CGFloat {
        switch a.tool {
        case .text, .pixelate, .select, .filledRect, .counter, .image: return 0
        case .highlighter: return a.style.highlighterWidth / 2
        case .arrow: return max(a.style.lineWidth / 2, max(12, a.style.lineWidth * 5) * 0.45)
        default: return a.style.lineWidth / 2
        }
    }

    // MARK: Geometry & hit testing

    private func rect(_ a: Annotation) -> NSRect {
        NSRect(x: min(a.start.x, a.end.x), y: min(a.start.y, a.end.y),
               width: abs(a.start.x - a.end.x), height: abs(a.start.y - a.end.y))
    }

    private func textSize(_ a: Annotation) -> NSSize {
        (a.text as NSString).size(withAttributes: a.style.textAttributes)
    }

    private func bounds(of a: Annotation) -> NSRect {
        switch a.tool {
        case .text:
            let s = textSize(a)
            return NSRect(x: a.start.x, y: a.start.y - s.height, width: s.width, height: s.height)
        case .counter:
            let r = a.style.counterRadius
            return NSRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
        case .pen, .highlighter:
            let xs = a.points.map(\.x), ys = a.points.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
            return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        default: return rect(a)
        }
    }

    /// The stroked outline used both for hit testing and (for most tools) drawing.
    private func outline(_ a: Annotation) -> NSBezierPath? {
        switch a.tool {
        case .rect, .filledRect: return NSBezierPath(roundedRect: rect(a), xRadius: 2, yRadius: 2)
        case .ellipse: return NSBezierPath(ovalIn: rect(a))
        case .line, .arrow:
            let p = NSBezierPath(); p.move(to: a.start); p.line(to: a.end); return p
        case .pen, .highlighter:
            guard let f = a.points.first else { return nil }
            let p = NSBezierPath(); p.move(to: f); a.points.dropFirst().forEach { p.line(to: $0) }; return p
        case .text, .pixelate, .select, .counter, .image: return nil
        }
    }

    private func hits(_ a: Annotation, _ p: NSPoint) -> Bool {
        let slop = 5 / zoom
        if [.text, .pixelate, .filledRect, .counter, .image].contains(a.tool) {
            return bounds(of: a).insetBy(dx: -slop, dy: -slop).contains(p)
        }
        guard let path = outline(a) else { return false }
        let width = a.tool == .highlighter ? a.style.highlighterWidth : a.style.lineWidth
        return path.cgPath.copy(strokingWithWidth: width + slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(p)
    }

    /// Resize handles: rect corners as (BL, BR, TL, TR), or the two endpoints of a line/arrow.
    private func handles(_ a: Annotation) -> [NSPoint] {
        switch a.tool {
        case .rect, .filledRect, .ellipse, .pixelate, .image:
            let r = rect(a)
            return [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
                    NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)]
        case .line, .arrow: return [a.start, a.end]
        case .pen, .highlighter, .text, .counter, .select: return []
        }
    }

    private func handleDrag(for a: Annotation, at p: NSPoint) -> Drag? {
        let hs = handles(a), radius = 8 / zoom
        guard let h = hs.indices.first(where: { hypot(hs[$0].x - p.x, hs[$0].y - p.y) <= radius }) else { return nil }
        if a.tool == .line || a.tool == .arrow { return .resizeEnd(isStart: h == 0) }
        return .resizeCorner(anchor: hs[3 - h])   // the diagonally opposite corner stays put
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        if let bg = activeBackground {
            Background.draw(fill: bg.fill, in: bounds)
            let card = NSBezierPath(roundedRect: contentRect, xRadius: bg.cornerRadius, yRadius: bg.cornerRadius)
            if bg.shadow {
                ctx?.saveGState()
                ctx?.setShadow(offset: CGSize(width: 0, height: -8), blur: 28, color: NSColor.black.withAlphaComponent(0.4).cgColor)
                backdrop.setFill(); card.fill()
                ctx?.restoreGState()
            }
            card.addClip()
        } else {
            NSBezierPath(rect: contentRect).addClip()
        }
        if contentRect != imageRect { backdrop.setFill(); contentRect.fill() }
        base.draw(in: imageRect)
        for a in items + (draft.map { [$0] } ?? []) where a.id != editingID { render(a) }
        ctx?.restoreGState()
        if let r = cropDraft { drawCropOverlay(r) }
        if !exporting, textEditor == nil, let i = selectedIndex { drawSelection(items[i]) }
    }

    /// Dims everything outside the crop and draws its frame, thirds and corner handles.
    private func drawCropOverlay(_ r: NSRect) {
        let px = 1 / zoom
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: r))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill(); dim.fill()
        let thirds = NSBezierPath()
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
            thirds.move(to: NSPoint(x: x, y: r.minY)); thirds.line(to: NSPoint(x: x, y: r.maxY))
            thirds.move(to: NSPoint(x: r.minX, y: y)); thirds.line(to: NSPoint(x: r.maxX, y: y))
        }
        thirds.lineWidth = px
        NSColor.white.withAlphaComponent(0.45).setStroke(); thirds.stroke()
        let frame = NSBezierPath(rect: r)
        frame.lineWidth = 1.5 * px
        NSColor.white.setStroke(); frame.stroke()
        for c in [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)] {
            let s = 5 * px
            let dot = NSBezierPath(rect: NSRect(x: c.x - s, y: c.y - s, width: s * 2, height: s * 2))
            NSColor.white.setFill(); dot.fill()
            dot.lineWidth = px; NSColor.black.withAlphaComponent(0.4).setStroke(); dot.stroke()
        }
    }

    private func render(_ a: Annotation) {
        // The shadow goes on a transparency layer so overlapping parts (an arrow's shaft and head) cast one shadow.
        guard Preferences.annotationShadow, a.tool != .pixelate, a.tool != .highlighter, let ctx = NSGraphicsContext.current?.cgContext else {
            renderShape(a); return
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 4, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        // Bounded to the annotation (plus arrowhead and shadow room) so it stays cheap on large images.
        let pad = max(a.style.lineWidth * 5, 12) + 12
        ctx.beginTransparencyLayer(in: bounds(of: a).insetBy(dx: -pad, dy: -pad), auxiliaryInfo: nil)
        renderShape(a)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func renderShape(_ a: Annotation) {
        a.style.color.setStroke(); a.style.color.setFill()
        let lw = a.style.lineWidth
        switch a.tool {
        case .rect, .ellipse, .line, .pen:
            guard let p = outline(a) else { return }
            p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .filledRect:
            outline(a)?.fill()
        case .highlighter:
            // Multiply keeps text under the stroke readable, like a real marker.
            guard let p = outline(a), let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            a.style.color.withAlphaComponent(0.45).setStroke()
            p.lineWidth = a.style.highlighterWidth; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
            ctx.restoreGState()
        case .counter:
            drawCounter(a)
        case .image:
            a.image?.draw(in: rect(a))
        case .arrow:
            let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
            let len = hypot(dx, dy); guard len > 2 else { return }
            let ang = atan2(dy, dx), head: CGFloat = max(12, lw * 5)
            let line = NSBezierPath(); line.lineWidth = lw; line.lineCapStyle = .round
            line.move(to: a.start)
            line.line(to: NSPoint(x: a.end.x - cos(ang) * head * 0.6, y: a.end.y - sin(ang) * head * 0.6)); line.stroke()
            let tri = NSBezierPath(); tri.move(to: a.end)
            tri.line(to: NSPoint(x: a.end.x - head * cos(ang - .pi / 7), y: a.end.y - head * sin(ang - .pi / 7)))
            tri.line(to: NSPoint(x: a.end.x - head * cos(ang + .pi / 7), y: a.end.y - head * sin(ang + .pi / 7)))
            tri.close(); tri.fill()
        case .text:
            (a.text as NSString).draw(at: bounds(of: a).origin, withAttributes: a.style.textAttributes)
        case .pixelate:
            drawPixelated(rect(a), block: a.style.pixelSize)
        case .select:
            break
        }
    }

    /// Filled badge with the counter's number: its position among the counters, so deleting one renumbers the rest.
    private func drawCounter(_ a: Annotation) {
        let box = bounds(of: a)
        NSBezierPath(ovalIn: box).fill()
        let n = (items.filter { $0.tool == .counter }.firstIndex { $0.id == a.id } ?? 0) + 1
        let light = (a.style.color.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.85
            && (a.style.color.usingColorSpace(.sRGB)?.saturationComponent ?? 0) < 0.5
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: a.style.counterRadius * 1.1, weight: .bold),
                                                    .foregroundColor: light ? NSColor.black : NSColor.white]
        let s = "\(n)" as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawSelection(_ a: Annotation) {
        let px = 1 / zoom
        let box = NSBezierPath(rect: bounds(of: a).insetBy(dx: -4 * px, dy: -4 * px))
        box.lineWidth = px
        box.setLineDash([4 * px, 3 * px], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke(); box.stroke()
        for h in handles(a) {
            let r = 5 * px
            let dot = NSBezierPath(ovalIn: NSRect(x: h.x - r, y: h.y - r, width: r * 2, height: r * 2))
            NSColor.white.setFill(); dot.fill()
            dot.lineWidth = 1.5 * px; NSColor.controlAccentColor.setStroke(); dot.stroke()
        }
    }

    /// Blocky mosaic of the underlying base image inside `r`.
    private func drawPixelated(_ r: NSRect, block: CGFloat) {
        guard r.width > 2, r.height > 2, block >= 1 else { return }
        var y = r.minY
        while y < r.maxY {
            var x = r.minX
            while x < r.maxX {
                let cell = NSRect(x: x, y: y, width: min(block, r.maxX - x), height: min(block, r.maxY - y))
                let src = NSRect(x: cell.midX, y: cell.midY, width: 1, height: 1)
                if let rep = base.bestRepresentation(for: .zero, context: nil, hints: nil) as? NSBitmapImageRep ?? bitmap(),
                   let c = rep.colorAt(x: Int(src.minX * CGFloat(rep.pixelsWide) / base.size.width),
                                       y: Int((base.size.height - src.minY) * CGFloat(rep.pixelsHigh) / base.size.height)) {
                    c.setFill(); cell.fill()
                }
                x += block
            }
            y += block
        }
    }
    private lazy var cachedRep: NSBitmapImageRep? = base.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    private func bitmap() -> NSBitmapImageRep? { cachedRep }

    func flattened() -> NSImage {
        finishTextEditing()
        applyCrop()
        let img = NSImage(size: extent.size)
        exporting = true
        img.lockFocus()
        NSGraphicsContext.current?.cgContext.translateBy(x: -extent.minX, y: -extent.minY)
        draw(extent)
        img.unlockFocus()
        exporting = false
        return img
    }
}
