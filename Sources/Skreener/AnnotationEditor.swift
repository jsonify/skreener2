import AppKit

enum Tool: Int, CaseIterable {
    case select, arrow, rect, ellipse, line, pen, text, pixelate

    /// Single-key shortcuts in the editor (no modifiers).
    static let shortcuts: [Character: Tool] = ["v": .select, "a": .arrow, "r": .rect, "o": .ellipse,
                                               "l": .line, "p": .pen, "t": .text, "x": .pixelate]
}

/// One annotation, kept as an editable object (never baked into the image until export).
struct Annotation: Equatable {
    var id = UUID()
    var tool: Tool
    var start: NSPoint
    var end: NSPoint
    var points: [NSPoint] = []
    var text: String = ""
    var color: NSColor

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
        points = points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
    }
}

/// Drawing surface in image coordinates. Click an annotation to select it, drag to move it, drag a handle
/// to resize it, double-click text to edit it; ⌫ deletes, arrows nudge, ⌘Z / ⇧⌘Z undo and redo.
final class CanvasView: NSView {
    let base: NSImage
    private(set) var items: [Annotation] = []
    var tool: Tool = .arrow
    var color: NSColor = .systemRed
    /// Called when a single-key shortcut switches the tool.
    var onToolShortcut: ((Tool) -> Void)?
    /// Called with the newly selected annotation (or nil) so the toolbar can mirror its color.
    var onSelectionChange: ((Annotation?) -> Void)?

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
        didSet { if selectedID != oldValue { onSelectionChange?(selectedIndex.map { items[$0] }) } }
    }
    private var selectedIndex: Int? { selectedID.flatMap { id in items.firstIndex { $0.id == id } } }

    private let lineWidth: CGFloat = 3

    init(image: NSImage) {
        base = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    /// Screen-space sizes (handles, hit slop) divided by the zoom so they feel the same at any magnification.
    private var zoom: CGFloat { max(enclosingScrollView?.magnification ?? 1, 0.01) }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        beforeDrag = items

        if let i = selectedIndex, let d = handleDrag(for: items[i], at: p) { drag = d; return }
        if let i = items.indices.reversed().first(where: { hits(items[$0], p) }) {
            selectedID = items[i].id
            if event.clickCount == 2, items[i].tool == .text { editText(at: i); return }
            drag = .move(last: p); needsDisplay = true
            return
        }
        selectedID = nil
        needsDisplay = true
        switch tool {
        case .select: return
        case .text: addText(at: p)
        default:
            draft = Annotation(tool: tool, start: p, end: p, points: [p], color: color)
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
        guard let d = drag else { return }   // text add/edit already recorded its own undo step
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
        guard window?.isKeyWindow == true, event.charactersIgnoringModifiers?.lowercased() == "z" else {
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
        guard let previous = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(items)
        items = previous
        if selectedIndex == nil { selectedID = nil }
        needsDisplay = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(items)
        items = next
        if selectedIndex == nil { selectedID = nil }
        needsDisplay = true
    }

    /// Sets the drawing color and recolors the selected annotation, if any.
    func applyColor(_ c: NSColor) {
        color = c
        guard let i = selectedIndex, items[i].color != c else { return }
        mutate { items[i].color = c }
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

    private func promptText(_ initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = "Text"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); tf.stringValue = initial
        alert.accessoryView = tf
        alert.addButton(withTitle: initial.isEmpty ? "Add" : "Update"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn, !tf.stringValue.isEmpty else { return nil }
        return tf.stringValue
    }

    private func addText(at p: NSPoint) {
        guard let s = promptText("") else { return }
        let a = Annotation(tool: .text, start: p, end: p, text: s, color: color)
        mutate { items.append(a) }
        selectedID = a.id
    }

    private func editText(at i: Int) {
        guard let s = promptText(items[i].text), s != items[i].text else { return }
        mutate { items[i].text = s }
    }

    // MARK: Geometry & hit testing

    private func rect(_ a: Annotation) -> NSRect {
        NSRect(x: min(a.start.x, a.end.x), y: min(a.start.y, a.end.y),
               width: abs(a.start.x - a.end.x), height: abs(a.start.y - a.end.y))
    }

    private func textAttributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: color]
    }

    private func bounds(of a: Annotation) -> NSRect {
        switch a.tool {
        case .text: return NSRect(origin: a.start, size: (a.text as NSString).size(withAttributes: textAttributes(a.color)))
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
        return path.cgPath.copy(strokingWithWidth: lineWidth + slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
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
        for a in items + (draft.map { [$0] } ?? []) { render(a) }
        if !exporting, let i = selectedIndex { drawSelection(items[i]) }
    }

    private func render(_ a: Annotation) {
        a.color.setStroke(); a.color.setFill()
        let lw = lineWidth
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
            (a.text as NSString).draw(at: a.start, withAttributes: textAttributes(a.color))
        case .pixelate:
            drawPixelated(rect(a))
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
    private func drawPixelated(_ r: NSRect) {
        guard r.width > 2, r.height > 2 else { return }
        let block: CGFloat = 10
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
        let img = NSImage(size: base.size)
        exporting = true
        img.lockFocus(); draw(bounds); img.unlockFocus()
        exporting = false
        return img
    }
}
