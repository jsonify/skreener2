import AppKit

enum Tool: Int, CaseIterable {
    case select, arrow, rect, ellipse, line, pen, text, pixelate

    /// Single-key shortcuts in the editor (no modifiers).
    static let shortcuts: [Character: Tool] = ["v": .select, "a": .arrow, "r": .rect, "o": .ellipse,
                                               "l": .line, "p": .pen, "t": .text, "x": .pixelate]

    var usesStroke: Bool { [.arrow, .rect, .ellipse, .line, .pen].contains(self) }
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
    var style: Style

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
        points = points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
    }
}

/// Text view used to type text annotations in place. The editor window has no Edit menu, so the
/// usual ⌘C/⌘V/⌘X/⌘A/⌘Z shortcuts are wired up here; Esc or ⌘Return finishes editing.
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
    private(set) var items: [Annotation] = []
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
    }
    private var draft: Annotation?
    private var drag: Drag?
    private var beforeDrag: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var exporting = false
    private var selectedID: UUID? {
        didSet { if selectedID != oldValue { notifyContext() } }
    }
    private var selectedIndex: Int? { index(of: selectedID) }

    private var textEditor: InlineTextView?
    private var editingID: UUID?
    private var beforeEditing: [Annotation] = []

    init(image: NSImage) {
        base = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
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
        beforeDrag = items

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
        case .select: return
        case .text: addText(at: p)
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
        case nil: return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let d = drag else { return }   // text add/edit records its own undo step
        if case .draw = d, let a = draft, isMeaningful(a) {
            items.append(a)
            selectedID = a.id
        }
        recordUndo(from: beforeDrag)
        draft = nil; drag = nil
        needsDisplay = true
    }

    private func isMeaningful(_ a: Annotation) -> Bool {
        a.tool == .pen ? a.points.count > 1 : hypot(a.end.x - a.start.x, a.end.y - a.start.y) > 2
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
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

    func undo() {
        finishTextEditing()
        guard let previous = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(items)
        items = previous
        if selectedIndex == nil { selectedID = nil } else { notifyContext() }
        needsDisplay = true
    }

    func redo() {
        finishTextEditing()
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(items)
        items = next
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
        let before = items
        change()
        recordUndo(from: before)
        needsDisplay = true
    }

    private func recordUndo(from before: [Annotation]) {
        guard items != before else { return }
        undoStack.append(before)
        redoStack.removeAll()
    }

    // MARK: Inline text

    private func addText(at p: NSPoint) {
        beforeEditing = items
        // Put the click roughly on the first line's vertical center.
        let top = NSPoint(x: p.x, y: p.y + style.font.boundingRectForFont.height / 2)
        let a = Annotation(tool: .text, start: top, end: top, style: style)
        items.append(a)
        selectedID = a.id
        startEditor(for: a)
    }

    private func beginTextEditing(at i: Int) {
        beforeEditing = items
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
        case .pen:
            let xs = a.points.map(\.x), ys = a.points.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
            return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        default: return rect(a)
        }
    }

    /// The stroked outline used both for hit testing and (for most tools) drawing.
    private func outline(_ a: Annotation) -> NSBezierPath? {
        switch a.tool {
        case .rect: return NSBezierPath(roundedRect: rect(a), xRadius: 2, yRadius: 2)
        case .ellipse: return NSBezierPath(ovalIn: rect(a))
        case .line, .arrow:
            let p = NSBezierPath(); p.move(to: a.start); p.line(to: a.end); return p
        case .pen:
            guard let f = a.points.first else { return nil }
            let p = NSBezierPath(); p.move(to: f); a.points.dropFirst().forEach { p.line(to: $0) }; return p
        case .text, .pixelate, .select: return nil
        }
    }

    private func hits(_ a: Annotation, _ p: NSPoint) -> Bool {
        let slop = 5 / zoom
        if a.tool == .text || a.tool == .pixelate { return bounds(of: a).insetBy(dx: -slop, dy: -slop).contains(p) }
        guard let path = outline(a) else { return false }
        return path.cgPath.copy(strokingWithWidth: a.style.lineWidth + slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(p)
    }

    /// Resize handles: rect corners as (BL, BR, TL, TR), or the two endpoints of a line/arrow.
    private func handles(_ a: Annotation) -> [NSPoint] {
        switch a.tool {
        case .rect, .ellipse, .pixelate:
            let r = rect(a)
            return [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
                    NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)]
        case .line, .arrow: return [a.start, a.end]
        case .pen, .text, .select: return []
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
        base.draw(in: bounds)
        for a in items + (draft.map { [$0] } ?? []) where a.id != editingID { render(a) }
        if !exporting, textEditor == nil, let i = selectedIndex { drawSelection(items[i]) }
    }

    private func render(_ a: Annotation) {
        a.style.color.setStroke(); a.style.color.setFill()
        let lw = a.style.lineWidth
        switch a.tool {
        case .rect, .ellipse, .line, .pen:
            guard let p = outline(a) else { return }
            p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
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
        let scaleX = base.size.width / bounds.width, scaleY = base.size.height / bounds.height
        var y = r.minY
        while y < r.maxY {
            var x = r.minX
            while x < r.maxX {
                let cell = NSRect(x: x, y: y, width: min(block, r.maxX - x), height: min(block, r.maxY - y))
                let src = NSRect(x: cell.midX * scaleX, y: cell.midY * scaleY, width: 1, height: 1)
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
        let img = NSImage(size: base.size)
        exporting = true
        img.lockFocus(); draw(bounds); img.unlockFocus()
        exporting = false
        return img
    }
}
