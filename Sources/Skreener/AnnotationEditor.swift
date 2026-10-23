import AppKit
import CoreImage

enum Tool: Int, CaseIterable {
    /// `.image` is not a toolbar tool: it marks pictures added with Add Image or pasted with ⌘V. Nor is `.ruler`: a
    /// measurement kept by clicking while the ruler keys are held (#107).
    case select, arrow, rect, filledRect, ellipse, line, pen, highlighter, text, counter, pixelate, blur, spotlight,
         erase, magnifier, image, ruler

    /// Single-key shortcuts in the editor (no modifiers).
    static let shortcuts: [Character: Tool] = ["v": .select, "a": .arrow, "r": .rect, "f": .filledRect, "o": .ellipse,
                                               "l": .line, "p": .pen, "h": .highlighter, "t": .text, "n": .counter,
                                               "x": .pixelate, "b": .blur, "s": .spotlight, "e": .erase, "m": .magnifier]

    var usesStroke: Bool { [.arrow, .rect, .ellipse, .line, .pen, .highlighter, .magnifier].contains(self) }
    /// Tools that hide part of the screenshot (all of the box, or with `Style.textOnly` just the text in it).
    var obscures: Bool { self == .pixelate || self == .blur || self == .erase }
    /// Obscuring tools whose strength comes from `Style.pixelSize` (erase just paints over).
    var hasStrength: Bool { self == .pixelate || self == .blur }
    /// Rectangle-like tools whose corners can be rounded.
    var hasCorners: Bool { self == .rect || self == .filledRect || self == .spotlight }
    /// Freehand tools keep every point of the drag.
    var isFreehand: Bool { self == .pen || self == .highlighter }
    /// Box tools that snap to the edges of what's in the screenshot (#123).
    var snapsToObjects: Bool {
        [.rect, .filledRect, .pixelate, .blur, .spotlight, .erase, .magnifier].contains(self)
    }

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
        case .blur: return "Blur"
        case .spotlight: return "Spotlight"
        case .erase: return "Erase"
        case .magnifier: return "Magnifier"
        case .image: return "Image"
        case .ruler: return "Ruler"
        }
    }
}

enum ArrowStyle: Int {
    /// `tapered`: a filled shaft that widens toward the head (#119).
    case filled, open, double, tapered
}

enum LensShape: Int {
    case circle, rectangle
}

/// How rectangles and ellipses are filled (#120).
enum ShapeFill: Int {
    case outline, translucent, solid
}

/// The box behind a text label (#120): no box, filled in the style's color (the text then black or white, whichever
/// reads better), or outlined in it.
enum TextBox: Int {
    case plain, solid, outline
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
    /// Mosaic cell size for pixelate, blur radius for blur.
    var pixelSize: CGFloat = 10
    /// Corner radius for rectangles, filled rectangles and spotlights.
    var cornerRadius: CGFloat = 2
    var arrowStyle = ArrowStyle.filled
    /// Pixelate, blur and erase hide only the lines of text found in the box, not all of it.
    var textOnly = false
    /// How much a magnifier enlarges, and the shape of its lens.
    var magnification: CGFloat = 2
    var lensShape = LensShape.circle
    /// Rectangles and ellipses: outline only, or filled translucent or solid.
    var fill = ShapeFill.outline
    /// Text: the box behind it, and a speech-bubble tail on the box.
    var textBox = TextBox.plain
    var tail = false
    /// Arrows, lines, rectangles and ellipses drawn with a slight hand-drawn wobble (#119).
    var handDrawn = false
    /// Pen: a stroke that is nearly a straight line, an ellipse or a rectangle becomes that shape when let go.
    var shapeCorrection = false

    /// Every size scaled by `k`, for an image resized by that factor (#122).
    mutating func scale(by k: CGFloat) {
        lineWidth *= k; fontSize *= k; pixelSize *= k; cornerRadius *= k
    }

    var font: NSFont {
        if fontName.isEmpty { return .systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular) }
        let f = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        return bold ? NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) : f
    }

    var textAttributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: textColor] }

    /// Text on a solid box is black or white, whichever reads better on the box's color; otherwise the style's color.
    var textColor: NSColor {
        guard textBox == .solid, let c = color.usingColorSpace(.sRGB) else { return color }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.6 ? .black : .white
    }

    /// Room between the text and the edge of its box.
    var textBoxPadding: CGFloat { textBox == .plain ? 0 : (fontSize * 0.4).rounded() }

    /// Highlighter strokes are much wider than the chosen stroke width.
    var highlighterWidth: CGFloat { max(12, lineWidth * 5) }
    /// Counter badges scale with the font size.
    var counterRadius: CGFloat { max(10, fontSize * 0.75) }
}

// Saving (the editor starts with the last style used)
extension Style {
    /// The style as property-list values, for user defaults (#139).
    var plist: [String: Any] {
        [
            "color": Background.components(color), "lineWidth": Double(lineWidth), "fontSize": Double(fontSize),
            "fontName": fontName, "bold": bold, "pixelSize": Double(pixelSize), "cornerRadius": Double(cornerRadius),
            "arrowStyle": arrowStyle.rawValue, "textOnly": textOnly, "magnification": Double(magnification),
            "lensShape": lensShape.rawValue, "fill": fill.rawValue, "textBox": textBox.rawValue, "tail": tail,
            "handDrawn": handDrawn, "shapeCorrection": shapeCorrection,
        ]
    }

    /// A style read back from `plist`; missing or unknown values keep their defaults.
    init(plist d: [String: Any]) {
        self.init()
        func number(_ key: String) -> CGFloat? { (d[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
        func positive(_ key: String) -> CGFloat? { number(key).flatMap { $0 > 0 ? $0 : nil } }
        if let c = (d["color"] as? [Double]).flatMap(Background.color(from:)) { color = c }
        lineWidth = positive("lineWidth") ?? lineWidth
        fontSize = positive("fontSize") ?? fontSize
        fontName = d["fontName"] as? String ?? fontName
        bold = d["bold"] as? Bool ?? bold
        pixelSize = positive("pixelSize") ?? pixelSize
        cornerRadius = number("cornerRadius").map { max($0, 0) } ?? cornerRadius
        arrowStyle = (d["arrowStyle"] as? Int).flatMap(ArrowStyle.init(rawValue:)) ?? arrowStyle
        textOnly = d["textOnly"] as? Bool ?? textOnly
        magnification = positive("magnification") ?? magnification
        lensShape = (d["lensShape"] as? Int).flatMap(LensShape.init(rawValue:)) ?? lensShape
        fill = (d["fill"] as? Int).flatMap(ShapeFill.init(rawValue:)) ?? fill
        textBox = (d["textBox"] as? Int).flatMap(TextBox.init(rawValue:)) ?? textBox
        tail = d["tail"] as? Bool ?? tail
        handDrawn = d["handDrawn"] as? Bool ?? handDrawn
        shapeCorrection = d["shapeCorrection"] as? Bool ?? shapeCorrection
    }
}

/// One annotation, kept as an editable object (never baked into the image until export).
/// For text, `start` is the top-left corner of the text.
struct Annotation: Equatable {
    var id = UUID()
    /// Creation order. Counters are numbered by it, so arranging them front/back keeps their numbers.
    var seq = Annotation.nextSeq()
    var tool: Tool
    var start: NSPoint
    var end: NSPoint
    var points: [NSPoint] = []
    var text: String = ""
    var image: NSImage? = nil
    /// A magnifier's lens center; `start`/`end` are the area it shows. Nil while it is being drawn (it then sits
    /// beside that area).
    var lens: NSPoint? = nil
    /// Text: where its speech-bubble tail points (with `Style.tail`); nil puts it below the box's left side.
    var tail: NSPoint? = nil
    /// Text: the width it wraps at; nil keeps each line on one line.
    var wrapWidth: CGFloat? = nil
    /// Arrows and lines: how far the middle of the curve sits from the straight line, to its left (#119).
    var bend: CGFloat = 0
    /// Keeps the hand-drawn wobble the same every time it is drawn.
    var seed = UInt64.random(in: 0...UInt64.max)
    var style: Style

    private static var lastSeq = 0
    private static func nextSeq() -> Int { lastSeq += 1; return lastSeq }

    /// The same annotation as a new object: its own id, and the next creation number (a copied counter gets the next
    /// number, #125).
    func duplicate() -> Annotation {
        var a = self
        a.id = UUID()
        a.seq = Annotation.nextSeq()
        return a
    }

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        mapPoints { NSPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// Moves every point the annotation is made of with `f`.
    mutating func mapPoints(_ f: (NSPoint) -> NSPoint) {
        start = f(start); end = f(end)
        points = points.map(f)
        lens = lens.map(f)
        tail = tail.map(f)
    }
}

/// Text view used to type text annotations in place. The usual ⌘C/⌘V/⌘X/⌘A/⌘Z shortcuts are handled
/// here so they act on the text box, not the canvas; Esc or ⌘Return finishes editing.
private final class InlineTextView: NSTextView {
    var onFinish: (() -> Void)?
    /// The color under the pointer, written in the chosen color format (nil when the pointer is off the screenshot).
    var colorAtPointer: (() -> String?)?

    /// Tab types the color under the pointer instead of a tab (#108).
    override func insertTab(_ sender: Any?) {
        guard let color = colorAtPointer?() else { NSSound.beep(); return }
        insertText(color, replacementRange: selectedRange())
    }

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
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    /// The screenshot. It changes only when the whole image is rotated or flipped.
    private(set) var base: NSImage {
        didSet {
            guard base !== oldValue else { return }
            cachedRep = nil; cachedBackdrop = nil; cachedCG = nil; cachedPixels = nil; blurCache = [:]
            textLineCache = [:]; textLinePending = []; eraseColors = [:]
            updateExtent()
        }
    }
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
    /// Room around the canvas while cropping, so every handle can be grabbed even at the window's edges.
    private var cropMargin: CGFloat = 0
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
    /// Fill for the grown area: white, or the color of the image's top-left pixel (a Settings option).
    private var backdrop: NSColor {
        guard Preferences.matchExtensionColor else { return .white }
        if let c = cachedBackdrop { return c }
        let c = bitmap()?.colorAt(x: 0, y: 0) ?? .white
        cachedBackdrop = c
        return c
    }
    private var cachedBackdrop: NSColor?
    /// Starts as the last tool used in any editor, and is remembered for the next one (#139).
    var tool: Tool = Preferences.editorTool {
        didSet {
            guard tool != oldValue else { return }
            finishTextEditing(); endAreaPick(); notifyContext()
            Preferences.editorTool = tool
        }
    }
    /// Style given to new annotations; like the tool, remembered for the next editor (#139).
    private(set) var style = Preferences.editorStyle
    /// Called when a single-key shortcut switches the tool.
    var onToolShortcut: ((Tool) -> Void)?
    /// Esc with nothing selected and no mode active (the editor may then copy or save and close, #115).
    var onEscape: (() -> Void)?
    /// Called whenever the attributes bar should change: the tool whose options apply and the style to show.
    var onContextChange: ((Tool, Style) -> Void)?

    private enum Drag {
        case draw
        case move(last: NSPoint)
        /// ⌥-drag on an annotation: a copy is made on the first move and follows the pointer, the original stays (#137).
        case duplicate(last: NSPoint, copied: Bool)
        /// A magnifier's lens, which moves on its own.
        case moveLens(last: NSPoint)
        case resizeCorner(anchor: NSPoint)
        case resizeEnd(isStart: Bool)
        /// A text label's wrap width (its right-hand handle) or its tail's tip (#120).
        case textWidth
        case textTail
        /// An arrow's or line's middle handle, which bends it (#119).
        case bend
        case cropCorner(anchor: NSPoint)
        case cropEdges(CropEdges)
        case cropMove(last: NSPoint)
    }
    /// Which sides of the crop a handle moves: one for a side handle, two for a corner.
    private struct CropEdges {
        var left = false, right = false, bottom = false, top = false
    }
    /// Everything one undo step restores.
    private struct Snapshot: Equatable {
        var base: NSImage
        var items: [Annotation]
        var crop: NSRect?
        var background: Background?
    }
    private var snapshot: Snapshot {
        get { Snapshot(base: base, items: items, crop: crop, background: background) }
        set { base = newValue.base; items = newValue.items; crop = newValue.crop; background = newValue.background }
    }
    private var draft: Annotation? {
        didSet { updateExtent() }
    }
    private var drag: Drag?
    private lazy var beforeDrag = snapshot
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var exporting = false
    private var selectedID: UUID? {
        didSet { if selectedID != oldValue { notifyContext() } }
    }
    private var selectedIndex: Int? { index(of: selectedID) }

    private var textEditor: InlineTextView?
    private var editingID: UUID?
    private lazy var beforeEditing = snapshot

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
        if let kind = areaPick {
            if kind == .contrast, event.modifierFlags.contains(.option) { toggleContrastMethod(); return }
            areaAnchor = p; areaDraft = nil; return
        }
        if let r = cropDraft { drag = cropDrag(in: r, at: p); return }
        if ruler != nil {
            // Clicking while measuring keeps the measurement on the screenshot.
            if let d = rulerDraft { mutate { items.append(d) } }
            return
        }
        beforeDrag = snapshot

        if let i = selectedIndex, let d = handleDrag(for: items[i], at: p) { drag = d; return }
        if let i = items.indices.reversed().first(where: { hits(items[$0], p) }) {
            selectedID = items[i].id
            if event.clickCount == 2, items[i].tool == .text { beginTextEditing(at: i); return }
            let onLens = items[i].tool == .magnifier && lensPath(items[i]).contains(p)
            if event.modifierFlags.contains(.option) {
                drag = .duplicate(last: p, copied: false)
            } else {
                drag = onLens ? .moveLens(last: p) : .move(last: p)
            }
            needsDisplay = true
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
            drawAnchor = p
            drag = .draw
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pointerMoved(to: p)
        if let a = areaAnchor {
            if areaPick == .cutOut {
                areaDraft = cutBand(from: a, to: p, vertical: event.modifierFlags.contains(.option))
            } else {
                areaDraft = NSRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(p.x - a.x), height: abs(p.y - a.y))
            }
            return
        }
        switch drag {
        case .draw?:
            draft?.end = p
            if let d = draft, d.tool.snapsToObjects {
                let c = snapped(from: drawAnchor, to: p, free: event.modifierFlags.contains(.command))
                draft?.start = c.0; draft?.end = c.1
            }
            // Shift keeps a pen or highlighter stroke straight.
            if draft?.tool.isFreehand == true, event.modifierFlags.contains(.shift), let first = draft?.points.first {
                draft?.points = [first, p]
            } else {
                draft?.points.append(p)
            }
        case .move(let last)?:
            guard let i = selectedIndex else { return }
            // Dragging a magnifier's area leaves its lens where it is.
            let lens = items[i].lens
            items[i].translate(dx: p.x - last.x, dy: p.y - last.y)
            if items[i].tool == .magnifier { items[i].lens = lens }
            drag = .move(last: p)
        case .duplicate(let last, let copied)?:
            guard let i = selectedIndex else { return }
            var at = i
            if !copied {
                // On top, like ⌘D; the drag started in mouseDown, so making and moving it are one undo step.
                items.append(items[i].duplicate())
                at = items.count - 1
                selectedID = items[at].id
            }
            items[at].translate(dx: p.x - last.x, dy: p.y - last.y)
            drag = .duplicate(last: p, copied: true)
        case .moveLens(let last)?:
            guard let i = selectedIndex else { return }
            let c = items[i].lens ?? defaultLensCenter(items[i])
            items[i].lens = NSPoint(x: c.x + p.x - last.x, y: c.y + p.y - last.y)
            drag = .moveLens(last: p)
        case .resizeCorner(let anchor)?:
            guard let i = selectedIndex else { return }
            items[i].start = anchor
            if items[i].tool.snapsToObjects {
                let c = snapped(from: anchor, to: p, free: event.modifierFlags.contains(.command))
                items[i].start = c.0; items[i].end = c.1
            } else {
                items[i].end = items[i].tool == .image ? aspectLocked(items[i], anchor: anchor, to: p) : p
            }
        case .resizeEnd(let isStart)?:
            guard let i = selectedIndex else { return }
            if isStart { items[i].start = p } else { items[i].end = p }
        case .textWidth?:
            guard let i = selectedIndex else { return }
            let a = items[i]
            items[i].wrapWidth = max(a.style.fontSize * 1.5, p.x - a.style.textBoxPadding - a.start.x).rounded()
        case .textTail?:
            guard let i = selectedIndex else { return }
            items[i].tail = p
        case .bend?:
            guard let i = selectedIndex, let f = chordFrame(items[i]) else { return }
            let b = (p.x - f.mid.x) * f.normal.x + (p.y - f.mid.y) * f.normal.y
            // Close to straight snaps to straight.
            items[i].bend = abs(b) < 3 / zoom ? 0 : b
        case .cropCorner(let anchor)?:
            let full = fullContentRect()
            let q = NSPoint(x: min(max(p.x, full.minX), full.maxX), y: min(max(p.y, full.minY), full.maxY))
            cropDraft = NSRect(x: min(anchor.x, q.x), y: min(anchor.y, q.y), width: abs(q.x - anchor.x), height: abs(q.y - anchor.y))
        case .cropEdges(let e)?:
            guard let r = cropDraft else { return }
            let full = fullContentRect(), minSize: CGFloat = 4
            let q = NSPoint(x: min(max(p.x, full.minX), full.maxX), y: min(max(p.y, full.minY), full.maxY))
            var x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
            if e.left { x0 = min(q.x, x1 - minSize) }
            if e.right { x1 = max(q.x, x0 + minSize) }
            if e.bottom { y0 = min(q.y, y1 - minSize) }
            if e.top { y1 = max(q.y, y0 + minSize) }
            cropDraft = NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
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
        if let kind = areaPick, areaAnchor != nil {
            let r = areaDraft
            areaAnchor = nil; areaDraft = nil
            // A click without a drag just leaves the mode; Check Contrast stays on for the next area.
            guard let r, r.width >= 1, r.height >= 1 else {
                if kind != .contrast { endAreaPick() }
                return
            }
            switch kind {
            case .text:
                endAreaPick()
                if r.width >= 4, r.height >= 4 { copyText(in: r) }
            case .averageColor:
                endAreaPick()
                copyAverageColor(in: r)
            case .contrast:
                contrastArea = r
                refreshContrast()
            case .cutOut:
                endAreaPick()
                cutOut(r, axis: cutAxis)
            }
            return
        }
        snapGuides = []
        guard let d = drag else { return }   // text add/edit records its own undo step
        if isCropping { drag = nil; return }  // the crop is recorded when it is applied
        if case .draw = d, var a = draft, isMeaningful(a) {
            if a.tool == .magnifier { a.lens = defaultLensCenter(a) }
            if a.tool.isFreehand { a = finishedStroke(a) }
            items.append(a)
            selectedID = a.id
        }
        recordUndo(from: beforeDrag)
        draft = nil; drag = nil
        needsDisplay = true
    }

    /// A pen or highlighter stroke when let go: simplified (it is drawn smoothly through what is left), or, with Shape
    /// Correction, the line, ellipse or rectangle it was meant as (#119).
    private func finishedStroke(_ a: Annotation) -> Annotation {
        if a.tool == .pen, a.style.shapeCorrection, let shape = StrokeShapes.fit(a.points) {
            switch shape {
            case .line(let p, let q):
                return Annotation(tool: .line, start: p, end: q, style: a.style)
            case .ellipse(let r):
                return Annotation(tool: .ellipse, start: r.origin, end: NSPoint(x: r.maxX, y: r.maxY), style: a.style)
            case .rect(let r):
                return Annotation(tool: .rect, start: r.origin, end: NSPoint(x: r.maxX, y: r.maxY), style: a.style)
            }
        }
        var a = a
        a.points = StrokeShapes.simplify(a.points, epsilon: 1.5 / zoom)
        return a
    }

    // MARK: Snap to objects (#123)

    /// Where the box being drawn started (the draft's own start moves when it snaps).
    private var drawAnchor = NSPoint.zero
    /// The sides of the box that are on an edge of the screenshot's content, drawn as guides while dragging.
    private var snapGuides: [(NSPoint, NSPoint)] = []

    /// The corners of the box from `a` to `b` with its sides moved onto the edges of what's in the screenshot within a
    /// few points (Settings → Annotate → Snap to objects; `free`, ⌘ held, draws without). `a` stays the first corner.
    private func snapped(from a: NSPoint, to b: NSPoint, free: Bool) -> (NSPoint, NSPoint) {
        snapGuides = []
        guard Preferences.snapToObjects, !free, let buf = pixels else { return (a, b) }
        let r = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        guard r.width >= 4 / zoom, r.height >= 4 / zoom, r.intersects(imageRect) else { return (a, b) }
        let s = pixelScale, h = base.size.height
        let found = ObjectSnap.snap(pixelRect(r), in: buf, reach: max(Int((8 / zoom * s.x).rounded()), 1))
        guard found.sides.any else { return (a, b) }
        let q = found.rect
        var x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        if found.sides.left { x0 = q.minX / s.x }
        if found.sides.right { x1 = q.maxX / s.x }
        if found.sides.top { y1 = h - q.minY / s.y }
        if found.sides.bottom { y0 = h - q.maxY / s.y }
        let ext = 10 / zoom
        if found.sides.left { snapGuides.append((NSPoint(x: x0, y: y0 - ext), NSPoint(x: x0, y: y1 + ext))) }
        if found.sides.right { snapGuides.append((NSPoint(x: x1, y: y0 - ext), NSPoint(x: x1, y: y1 + ext))) }
        if found.sides.top { snapGuides.append((NSPoint(x: x0 - ext, y: y1), NSPoint(x: x1 + ext, y: y1))) }
        if found.sides.bottom { snapGuides.append((NSPoint(x: x0 - ext, y: y0), NSPoint(x: x1 + ext, y: y0))) }
        let leftFirst = a.x <= b.x, bottomFirst = a.y <= b.y
        return (NSPoint(x: leftFirst ? x0 : x1, y: bottomFirst ? y0 : y1),
                NSPoint(x: leftFirst ? x1 : x0, y: bottomFirst ? y1 : y0))
    }

    private func drawSnapGuides() {
        guard !snapGuides.isEmpty else { return }
        let path = NSBezierPath()
        for (a, b) in snapGuides { path.move(to: a); path.line(to: b) }
        path.lineWidth = 1 / zoom
        path.setLineDash([4 / zoom, 3 / zoom], count: 2, phase: 0)
        NSColor.systemPink.setStroke()
        path.stroke()
    }

    /// Image → Repeat on Similar Objects: copies of the selected box over every other place in the screenshot that looks
    /// like what's inside it (blur every avatar, box every price). One undo step.
    @objc func repeatOnSimilarObjects(_ sender: Any?) {
        finishTextEditing()
        applyCrop()
        guard let i = selectedIndex, items[i].tool.snapsToObjects, let buf = pixels else {
            onMessage?("Select a box, blur, pixelate or spotlight first"); NSSound.beep(); return
        }
        let a = items[i], box = rect(a)
        guard imageRect.contains(box) else { onMessage?("The box has to be inside the screenshot"); NSSound.beep(); return }
        let image = base, s = pixelScale, h = base.size.height, template = pixelRect(box)
        onMessage?("Looking for similar objects…")
        Task { @MainActor [weak self] in
            let found = await ObjectSnap.similar(to: template, in: buf)
            guard let self, self.base === image else { return }
            guard !found.isEmpty else { self.onMessage?("Nothing similar found"); NSSound.beep(); return }
            let added = found.map { q -> Annotation in
                var c = a.duplicate()
                let dx = q.minX / s.x - box.minX, dy = (h - q.maxY / s.y) - box.minY
                c.translate(dx: dx, dy: dy)
                return c
            }
            self.mutate { self.items += added }
            self.onMessage?(added.count == 1 ? "Added 1 copy" : "Added \(added.count) copies")
        }
    }

    @objc func toggleSnapToObjects(_ sender: Any?) {
        Preferences.snapToObjects.toggle()
    }

    static let snapCommands: [(String, Selector)] = [
        ("Snap to Objects", #selector(CanvasView.toggleSnapToObjects(_:))),
        ("Repeat on Similar Objects", #selector(CanvasView.repeatOnSimilarObjects(_:))),
    ]

    /// Corner for an image resized from `anchor` toward `p`, keeping the picture's proportions.
    private func aspectLocked(_ a: Annotation, anchor: NSPoint, to p: NSPoint) -> NSPoint {
        guard let s = a.image?.size, s.width > 0, s.height > 0 else { return p }
        let dx = p.x - anchor.x, dy = p.y - anchor.y
        let scale = max(abs(dx) / s.width, abs(dy) / s.height, 4 / min(s.width, s.height))
        return NSPoint(x: anchor.x + (dx < 0 ? -1 : 1) * s.width * scale, y: anchor.y + (dy < 0 ? -1 : 1) * s.height * scale)
    }

    private func isMeaningful(_ a: Annotation) -> Bool {
        a.tool.isFreehand ? a.points.count > 1 : hypot(a.end.x - a.start.x, a.end.y - a.start.y) > 2
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if areaPick != nil {
            if event.keyCode == 53 { endAreaPick() }   // Esc
            return
        }
        if isCropping {
            switch event.keyCode {
            case 36, 76: applyCrop()     // Return / Enter
            case 53: cancelCrop()        // Esc
            default: break
            }
            return
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        let shift = event.modifierFlags.contains(.shift)
        if mods.isEmpty, let axis = Self.rulerAxis(for: event.keyCode, nothingSelected: selectedIndex == nil) {
            if ruler == nil || !event.isARepeat { beginRuler(axis, key: event.keyCode) }
            return
        }
        if mods.isEmpty, event.keyCode == 48 { copyColorAtPointer(darkest: shift); return }   // Tab, ⇧Tab
        if mods.isEmpty, shift {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c"?: startAreaPick(.averageColor); return
            case "k"?: startAreaPick(.contrast); return
            default: break
            }
        }
        let step: CGFloat = shift ? 10 : 1
        switch event.keyCode {
        case 51, 117: deleteSelection(); return                         // ⌫, ⌦
        case 53:                                                        // Esc
            if selectedID != nil {
                selectedID = nil; needsDisplay = true
            } else if ruler == nil {
                onEscape?()
            }
            return
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

    override func keyUp(with event: NSEvent) {
        if let r = ruler, r.key == event.keyCode { endRuler(); return }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        // Shift switches the ruler between the inside and the outer size as soon as it is pressed or let go.
        if ruler != nil { updateRuler() }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        endRuler()
        return super.resignFirstResponder()
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
        Preferences.editorStyle = style
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

    // Edit menu → Paste (⌘V): copied annotations (#125), else an image from the clipboard, onto the canvas.
    @objc func paste(_ sender: Any?) {
        if let copied = AnnotationClipboard.read() { add(copied); return }
        guard let img = ImageSource.fromClipboard() else { NSSound.beep(); return }
        insertImage(img)
    }

    // Edit menu → Copy (⌘C): the selected annotation, as an editable object for another tab or editor; with nothing
    // selected, the whole image, like the footer's Copy.
    @objc func copy(_ sender: Any?) {
        finishTextEditing()
        guard let i = selectedIndex else { Output.copy(flattened()); return }
        AnnotationClipboard.write([items[i]])
    }

    // Edit menu → Cut (⌘X).
    @objc func cut(_ sender: Any?) {
        finishTextEditing()
        guard let i = selectedIndex else { NSSound.beep(); return }
        AnnotationClipboard.write([items[i]])
        deleteSelection()
    }

    // Edit menu → Duplicate (⌘D): a copy of the selection, 10 pt down and right.
    @objc func duplicate(_ sender: Any?) {
        finishTextEditing()
        guard let i = selectedIndex else { NSSound.beep(); return }
        add([items[i]])
    }

    /// Adds copies of `copied` (one undo step) and selects the last one.
    private func add(_ copied: [Annotation]) {
        finishTextEditing()
        cancelCrop()
        let added = AnnotationClipboard.pasted(copied, into: items)
        mutate { items += added }
        selectedID = added.last?.id
        window?.makeFirstResponder(self)
    }

    // MARK: Arrange (the screenshot itself is not an annotation, so it always stays at the bottom)

    var hasSelection: Bool { selectedIndex != nil }
    /// Something was changed since the editor opened (for the library's Edited filter, #117).
    var isEdited: Bool { !undoStack.isEmpty }

    @objc func bringToFront(_ sender: Any?) { moveSelection { _, n in n - 1 } }
    @objc func bringForward(_ sender: Any?) { moveSelection { i, _ in i + 1 } }
    @objc func sendBackward(_ sender: Any?) { moveSelection { i, _ in i - 1 } }
    @objc func sendToBack(_ sender: Any?) { moveSelection { _, _ in 0 } }
    @objc private func deleteSelected(_ sender: Any?) { deleteSelection() }

    /// Moves the selected annotation to `target(index, count)` in the stacking order (later draws on top).
    private func moveSelection(to target: (Int, Int) -> Int) {
        guard let i = selectedIndex else { NSSound.beep(); return }
        finishTextEditing()
        let j = min(max(target(i, items.count), 0), items.count - 1)
        guard j != i else { return }
        mutate { let a = items.remove(at: i); items.insert(a, at: j) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(bringToFront(_:)), #selector(bringForward(_:)):
            return selectedIndex.map { $0 < items.count - 1 } ?? false
        case #selector(sendBackward(_:)), #selector(sendToBack(_:)):
            return selectedIndex.map { $0 > 0 } ?? false
        case #selector(deleteSelected(_:)), #selector(cut(_:)), #selector(duplicate(_:)):
            return selectedIndex != nil
        case #selector(repeatOnSimilarObjects(_:)):
            return selectedIndex.map { items[$0].tool.snapsToObjects } ?? false
        case #selector(toggleSnapToObjects(_:)):
            item.state = Preferences.snapToObjects ? .on : .off
            return true
        default:
            return true
        }
    }

    /// Right-click an annotation: select it and offer Arrange and Delete.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isCropping else { return nil }
        finishTextEditing()
        let p = convert(event.locationInWindow, from: nil)
        guard let i = items.indices.reversed().first(where: { hits(items[$0], p) }) else { return nil }
        selectedID = items[i].id
        needsDisplay = true
        let m = NSMenu()
        for (title, action, key) in [("Cut", #selector(cut(_:)), "x"), ("Copy", #selector(copy(_:)), "c"),
                                     ("Duplicate", #selector(duplicate(_:)), "d")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            m.addItem(item)
        }
        m.addItem(.separator())
        for (title, action, key, mods) in CanvasView.arrangeCommands {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            m.addItem(item)
        }
        m.addItem(.separator())
        let delete = NSMenuItem(title: "Delete", action: #selector(deleteSelected(_:)), keyEquivalent: "")
        delete.target = self
        m.addItem(delete)
        return m
    }

    /// Arrange commands for menus: title, action, key, modifiers.
    static let arrangeCommands: [(String, Selector, String, NSEvent.ModifierFlags)] = [
        ("Bring to Front", #selector(CanvasView.bringToFront(_:)), "]", [.command, .option]),
        ("Bring Forward", #selector(CanvasView.bringForward(_:)), "]", [.command]),
        ("Send Backward", #selector(CanvasView.sendBackward(_:)), "[", [.command]),
        ("Send to Back", #selector(CanvasView.sendToBack(_:)), "[", [.command, .option]),
    ]

    // MARK: Rotate / flip (the screenshot and every annotation together; undoable)

    enum Orientation { case rotateLeft, rotateRight, flipHorizontal, flipVertical }

    @objc func rotateLeft(_ sender: Any?) { reorient(.rotateLeft) }
    @objc func rotateRight(_ sender: Any?) { reorient(.rotateRight) }
    @objc func flipHorizontal(_ sender: Any?) { reorient(.flipHorizontal) }
    @objc func flipVertical(_ sender: Any?) { reorient(.flipVertical) }

    static let imageCommands: [(String, Selector)] = [
        ("Rotate Left", #selector(CanvasView.rotateLeft(_:))), ("Rotate Right", #selector(CanvasView.rotateRight(_:))),
        ("Flip Horizontal", #selector(CanvasView.flipHorizontal(_:))), ("Flip Vertical", #selector(CanvasView.flipVertical(_:))),
    ]

    /// Resize, Cut Out and Remove Background (#121, #122).
    static let sizeCommands: [(String, Selector)] = [
        ("Resize Image…", #selector(CanvasView.resizeImage(_:))), ("Cut Out…", #selector(CanvasView.cutOut(_:))),
        ("Remove Background", #selector(CanvasView.removeBackground(_:))),
    ]

    /// The same orientation change as an affine map, for a w×h area with a bottom-left origin.
    private static func transform(_ op: Orientation, width w: CGFloat, height h: CGFloat) -> CGAffineTransform {
        switch op {
        case .rotateRight: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .rotateLeft: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .flipHorizontal: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .flipVertical: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        }
    }

    /// A rotated or flipped copy at full pixel resolution.
    static func reoriented(_ img: NSImage, _ op: Orientation) -> NSImage? {
        var r = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let turns = op == .rotateLeft || op == .rotateRight
        let pw = cg.width, ph = cg.height
        guard let ctx = CGContext(data: nil, width: turns ? ph : pw, height: turns ? pw : ph, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.concatenate(transform(op, width: CGFloat(pw), height: CGFloat(ph)))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: turns ? NSSize(width: img.size.height, height: img.size.width) : img.size)
    }

    private func reorient(_ op: Orientation) {
        finishTextEditing()
        cancelCrop()
        guard let newBase = Self.reoriented(base, op) else { NSSound.beep(); return }
        let t = Self.transform(op, width: base.size.width, height: base.size.height)
        mutate {
            base = newBase
            items = items.map { a in
                var a = a
                switch a.tool {
                case .text, .counter:
                    // Text and counters stay upright: only their center moves.
                    let b = bounds(of: a), c = NSPoint(x: b.midX, y: b.midY).applying(t)
                    a.translate(dx: c.x - b.midX, dy: c.y - b.midY)
                case .image:
                    a.image = a.image.flatMap { Self.reoriented($0, op) } ?? a.image
                    a.start = a.start.applying(t); a.end = a.end.applying(t)
                default:
                    a.start = a.start.applying(t); a.end = a.end.applying(t)
                    a.points = a.points.map { $0.applying(t) }
                    a.lens = a.lens?.applying(t)
                    // A mirror image bends the other way.
                    if op == .flipHorizontal || op == .flipVertical { a.bend = -a.bend }
                }
                return a
            }
            crop = crop.map { $0.applying(t) }
        }
    }

    // MARK: Resize, Cut Out, Remove Background (#121, #122)

    /// Image → Resize Image…: the editor asks for the new size, then calls `resize(toWidth:height:)`.
    var onResizeRequest: (() -> Void)?
    /// A short message for the editor to show over the canvas.
    var onMessage: ((String) -> Void)?

    /// The screenshot's size in pixels.
    var pixelSize: (width: Int, height: Int) {
        guard let cg = baseCG else { return (Int(base.size.width.rounded()), Int(base.size.height.rounded())) }
        return (cg.width, cg.height)
    }
    /// Pixels per point (2 for a Retina screenshot).
    var pixelDensity: CGFloat { pixelScale.x }

    @objc func resizeImage(_ sender: Any?) {
        finishTextEditing()
        applyCrop()
        onResizeRequest?()
    }

    /// Resamples the screenshot to `width` × `height` pixels; annotations, their sizes and the crop scale with it.
    func resize(toWidth width: Int, height: Int) {
        finishTextEditing()
        cancelCrop()
        guard ImageOps.resizeProblem(width: width, height: height) == nil, base.size.width > 0, base.size.height > 0,
              let newBase = ImageOps.resized(base, width: width, height: height) else { NSSound.beep(); return }
        let sx = newBase.size.width / base.size.width, sy = newBase.size.height / base.size.height
        let scale = { (p: NSPoint) in NSPoint(x: p.x * sx, y: p.y * sy) }
        mutate {
            base = newBase
            items = items.map { a in
                var a = a
                a.mapPoints(scale)
                a.style.scale(by: (sx + sy) / 2)
                a.wrapWidth = a.wrapWidth.map { $0 * sx }
                a.bend *= (sx + sy) / 2
                return a
            }
            crop = crop.map { NSRect(x: $0.minX * sx, y: $0.minY * sy, width: $0.width * sx, height: $0.height * sy) }
        }
    }

    /// Drag across the part of the screenshot to remove (⌥-drag for a vertical strip); the parts either side join.
    @objc func cutOut(_ sender: Any?) { startAreaPick(.cutOut) }

    /// Which way the strip being dragged for Cut Out runs.
    private var cutAxis = ImageOps.Axis.horizontal

    /// The strip between `a` and `p` across the whole screenshot: rows, or with `vertical` columns.
    private func cutBand(from a: NSPoint, to p: NSPoint, vertical: Bool) -> NSRect {
        cutAxis = vertical ? .vertical : .horizontal
        let r = imageRect
        if vertical {
            let x0 = min(max(min(a.x, p.x), r.minX), r.maxX), x1 = min(max(max(a.x, p.x), r.minX), r.maxX)
            return NSRect(x: x0, y: r.minY, width: x1 - x0, height: r.height)
        }
        let y0 = min(max(min(a.y, p.y), r.minY), r.maxY), y1 = min(max(max(a.y, p.y), r.minY), r.maxY)
        return NSRect(x: r.minX, y: y0, width: r.width, height: y1 - y0)
    }

    /// Removes the strip `r` from the screenshot. Annotations past it move up (or left) with the image; those wholly
    /// inside it are deleted. One undo step.
    private func cutOut(_ r: NSRect, axis: ImageOps.Axis) {
        let s = pixelScale, h = base.size.height
        // In whole pixels, counted from the top (rows) or the left (columns).
        let lo: Int, hi: Int
        switch axis {
        case .horizontal: lo = Int(((h - r.maxY) * s.y).rounded()); hi = Int(((h - r.minY) * s.y).rounded())
        case .vertical: lo = Int((r.minX * s.x).rounded()); hi = Int((r.maxX * s.x).rounded())
        }
        guard hi > lo, let newBase = ImageOps.removing(lo..<hi, axis: axis, from: base) else { NSSound.beep(); return }
        // The strip as cut, in image points (bottom-left origin).
        let p0 = axis == .horizontal ? h - CGFloat(hi) / s.y : CGFloat(lo) / s.x
        let p1 = axis == .horizontal ? h - CGFloat(lo) / s.y : CGFloat(hi) / s.x
        let move: (NSPoint) -> NSPoint = axis == .horizontal
            ? { NSPoint(x: $0.x, y: ImageOps.afterCut($0.y, lo: p0, hi: p1)) }
            : { NSPoint(x: ImageOps.afterCut($0.x, lo: p0, hi: p1), y: $0.y) }
        let inside = { (b: NSRect) in
            axis == .horizontal ? b.minY >= p0 && b.maxY <= p1 : b.minX >= p0 && b.maxX <= p1
        }
        mutate {
            items = items.filter { !inside(bounds(of: $0)) }.map { a in
                var a = a
                a.mapPoints(move)
                return a
            }
            base = newBase
            crop = crop.map { c in
                let a = move(NSPoint(x: c.minX, y: c.minY)), b = move(NSPoint(x: c.maxX, y: c.maxY))
                return NSRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
            }
        }
        if selectedIndex == nil { selectedID = nil }
    }

    /// Keeps only the screenshot's subject (Vision's foreground mask); the rest becomes transparent. One undo step.
    @objc func removeBackground(_ sender: Any?) {
        finishTextEditing()
        cancelCrop()
        let image = base
        onMessage?("Looking for the subject…")
        Task { @MainActor [weak self] in
            let kept = await ImageOps.removingBackground(image)
            guard let self, self.base === image else { return }
            guard let kept else { self.onMessage?("No subject found to keep"); NSSound.beep(); return }
            self.mutate { self.base = kept }
            self.onMessage?("Background removed")
        }
    }

    // MARK: Redact (OCR finds the text; each match gets an editable pixelate box)

    @objc func redactAllText(_ sender: Any?) { redact(.allText) }
    @objc func redactEmails(_ sender: Any?) { redact(.emails) }
    @objc func redactPhoneNumbers(_ sender: Any?) { redact(.phoneNumbers) }
    @objc func redactLinks(_ sender: Any?) { redact(.links) }

    static let redactCommands: [(String, Selector)] = [
        ("Redact All Text", #selector(CanvasView.redactAllText(_:))), ("Redact Email Addresses", #selector(CanvasView.redactEmails(_:))),
        ("Redact Phone Numbers", #selector(CanvasView.redactPhoneNumbers(_:))), ("Redact Links", #selector(CanvasView.redactLinks(_:))),
    ]

    private func redact(_ kind: TextRecognizer.Sensitive) {
        finishTextEditing()
        cancelCrop()
        let image = base
        Task { @MainActor [weak self] in
            let boxes = await TextRecognizer.boxes(in: image, matching: kind)
            guard let self, self.base === image else { return }
            guard !boxes.isEmpty else { NSSound.beep(); return }
            var s = self.style
            s.pixelSize = max(s.pixelSize, 8)
            let added = boxes.map { b -> Annotation in
                let r = b.insetBy(dx: -3, dy: -2)
                return Annotation(tool: .pixelate, start: r.origin, end: NSPoint(x: r.maxX, y: r.maxY), style: s)
            }
            self.mutate { self.items += added }
            self.selectedID = nil
        }
    }

    // MARK: Copy text (OCR on the screenshot; the text goes to the clipboard)

    /// Called with the text Copy Text found (empty when there was none); it is already on the clipboard.
    var onTextCopied: ((String) -> Void)?
    /// What a drag over the screenshot picks an area for, instead of drawing: Copy Text from Area, Copy Average Color,
    /// Check Contrast (which stays on, measuring each new area, until Esc), or the strip Cut Out removes.
    enum AreaPick { case text, averageColor, contrast, cutOut }

    /// Called when picking an area starts, changes kind, or ends (nil).
    var onAreaPickChange: ((AreaPick?) -> Void)?
    private(set) var areaPick: AreaPick? {
        didSet {
            guard areaPick != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            if areaPick != .contrast { contrastArea = nil; contrastSummary = nil }
            onAreaPickChange?(areaPick)
        }
    }
    private var areaAnchor: NSPoint?
    /// The area dragged so far (image coordinates).
    private var areaDraft: NSRect? {
        didSet { needsDisplay = true }
    }

    @objc func copyAllText(_ sender: Any?) {
        endAreaPick()
        copyText(in: nil)
    }

    /// Drag over the screenshot to copy the text in that area; Esc cancels.
    @objc func copyTextFromArea(_ sender: Any?) { startAreaPick(.text) }

    private func startAreaPick(_ kind: AreaPick) {
        finishTextEditing()
        applyCrop()
        clearSelection()
        endRuler()
        areaPick = kind
        window?.makeFirstResponder(self)
    }

    func endAreaPick() {
        areaAnchor = nil
        areaDraft = nil
        areaPick = nil
    }

    static let textCommands: [(String, Selector)] = [
        ("Copy Text from Area…", #selector(CanvasView.copyTextFromArea(_:))), ("Copy All Text", #selector(CanvasView.copyAllText(_:))),
    ]

    /// Reads the text in `area` of the screenshot (all of it when nil), copies it and reports it.
    private func copyText(in area: NSRect?) {
        let image = base
        let size = base.size
        var region: CGRect?
        if let area {
            let r = area.intersection(imageRect)
            guard !r.isEmpty, size.width > 0, size.height > 0 else { onTextCopied?(""); return }
            region = CGRect(x: r.minX / size.width, y: r.minY / size.height, width: r.width / size.width, height: r.height / size.height)
        }
        Task { @MainActor [weak self] in
            let text = await TextRecognizer.recognize(image, region: region)
            if !text.isEmpty { TextRecognizer.copyText(text) }
            self?.onTextCopied?(text)
        }
    }

    override func resetCursorRects() {
        if areaPick != nil { addCursorRect(visibleRect, cursor: .crosshair) }
    }

    private func drawAreaOverlay(_ r: NSRect) {
        let path = NSBezierPath(rect: r)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        path.fill()
        path.lineWidth = 1.5 / zoom
        path.setLineDash([6 / zoom, 4 / zoom], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    // MARK: Colors and measuring (#107, #108, #109)

    /// Called with each color copied (already on the clipboard, in the chosen format).
    var onColorCopied: ((String) -> Void)?
    /// Called as the pointer moves over the screenshot, with the color under it.
    var onHoverColor: ((RGBColor) -> Void)?
    /// Called with Check Contrast's result for the toolbar strip (nil until an area is measured).
    var onContrastChange: ((String?) -> Void)?

    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        rulerDraft = nil
    }

    private func pointerMoved(to p: NSPoint) {
        if let c = color(at: p) { onHoverColor?(c) }
        if ruler != nil { updateRuler() }
    }

    /// The pointer in image coordinates, while it is over the visible canvas.
    private var pointerLocation: NSPoint? {
        guard let w = window else { return nil }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        return visibleRect.contains(p) ? p : nil
    }

    /// The screenshot's color at `p` (image coordinates); nil off the screenshot.
    private func color(at p: NSPoint) -> RGBColor? {
        guard imageRect.contains(p), let buf = pixels else { return nil }
        let q = pixelPoint(p)
        return buf.color(x: q.x, y: q.y)
    }

    /// Tab: the pixel under the pointer. ⇧Tab: the darkest pixel within 10 px of it, e.g. the color of thin text.
    private func copyColorAtPointer(darkest: Bool) {
        guard let p = pointerLocation, imageRect.contains(p), let buf = pixels else { NSSound.beep(); return }
        let q = pixelPoint(p)
        guard let c = darkest ? buf.darkest(x: q.x, y: q.y) : buf.color(x: q.x, y: q.y) else { NSSound.beep(); return }
        copyColor(c)
    }

    /// Drag over an area to copy its average color; Esc cancels.
    @objc func copyAverageColorFromArea(_ sender: Any?) { startAreaPick(.averageColor) }

    /// Drag over text and its background to see their contrast; each new drag measures again, Esc ends it.
    @objc func checkContrast(_ sender: Any?) { startAreaPick(.contrast) }

    static let colorCommands: [(String, Selector)] = [
        ("Copy Average Color of Area…", #selector(CanvasView.copyAverageColorFromArea(_:))),
        ("Check Contrast…", #selector(CanvasView.checkContrast(_:))),
    ]

    private func copyAverageColor(in r: NSRect) {
        guard let c = pixels?.average(in: pixelRect(r)) else { NSSound.beep(); return }
        copyColor(c)
    }

    private func copyColor(_ c: RGBColor) {
        let text = Preferences.colorFormat.string(for: c)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onColorCopied?(text)
    }

    /// Check Contrast's area (image coordinates) and its short result, drawn until the mode ends.
    private var contrastArea: NSRect? {
        didSet { needsDisplay = true }
    }
    private var contrastSummary: String?

    /// Switches Check Contrast between WCAG 2 and APCA (also ⌥-click while checking).
    func toggleContrastMethod() {
        Preferences.contrastMethod = Preferences.contrastMethod == .wcag ? .apca : .wcag
        refreshContrast()
    }

    /// Measures `contrastArea` again (after a new drag, or a change of method or color format) and reports it.
    func refreshContrast() {
        guard let r = contrastArea, let found = pixels?.dominantColors(in: pixelRect(r)) else {
            contrastSummary = nil
            onContrastChange?(nil)
            return
        }
        let f = Preferences.colorFormat
        let summary = Contrast.summary(text: found.foreground, background: found.background, method: Preferences.contrastMethod)
        contrastSummary = summary
        onContrastChange?("\(f.display(for: found.foreground)) on \(f.display(for: found.background)) · \(summary)")
        needsDisplay = true
    }

    /// A label under `r` that stays the same size on screen at any zoom.
    private func drawTag(_ text: String, under r: NSRect) {
        let px = 1 / zoom
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12 * px, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
        let s = text as NSString
        let size = s.size(withAttributes: attrs)
        let box = NSRect(x: r.minX, y: r.minY - size.height - 10 * px, width: size.width + 12 * px, height: size.height + 4 * px)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        s.draw(at: NSPoint(x: box.minX + 6 * px, y: box.minY + 2 * px), withAttributes: attrs)
    }

    /// While 1 or 2 (or, with nothing selected, an arrow key) is held: the direction measured, and that key.
    private var ruler: (axis: RulerScanner.Axis, key: UInt16)?
    /// The measurement under the pointer; a click keeps it as an annotation.
    private var rulerDraft: Annotation? {
        didSet { needsDisplay = true }
    }

    /// 1 and ← → measure across, 2 and ↑ ↓ up and down; the arrows only when nothing is selected (they nudge it).
    private static func rulerAxis(for keyCode: UInt16, nothingSelected: Bool) -> RulerScanner.Axis? {
        switch keyCode {
        case 18, 83: return .horizontal              // 1, keypad 1
        case 19, 84: return .vertical                // 2, keypad 2
        case 123, 124: return nothingSelected ? .horizontal : nil
        case 125, 126: return nothingSelected ? .vertical : nil
        default: return nil
        }
    }

    private func beginRuler(_ axis: RulerScanner.Axis, key: UInt16) {
        ruler = (axis, key)
        updateRuler()
    }

    private func endRuler() {
        guard ruler != nil else { return }
        ruler = nil
        rulerDraft = nil
    }

    /// Measures the run of color under the pointer (Shift: with its border) as a line between its outer pixel edges.
    private func updateRuler() {
        guard let axis = ruler?.axis, let p = pointerLocation, imageRect.contains(p), let buf = pixels else {
            rulerDraft = nil; return
        }
        let q = pixelPoint(p)
        guard let span = RulerScanner.span(in: buf, x: q.x, y: q.y, axis: axis,
                                           outer: NSEvent.modifierFlags.contains(.shift)) else { rulerDraft = nil; return }
        let s = pixelScale, h = base.size.height
        let a: NSPoint, b: NSPoint
        switch axis {
        case .horizontal:
            let y = h - (CGFloat(q.y) + 0.5) / s.y
            a = NSPoint(x: CGFloat(span.lowerBound) / s.x, y: y)
            b = NSPoint(x: CGFloat(span.upperBound + 1) / s.x, y: y)
        case .vertical:
            let x = (CGFloat(q.x) + 0.5) / s.x
            a = NSPoint(x: x, y: h - CGFloat(span.upperBound + 1) / s.y)
            b = NSPoint(x: x, y: h - CGFloat(span.lowerBound) / s.y)
        }
        rulerDraft = Annotation(tool: .ruler, start: a, end: b, style: style)
    }

    /// A ruler's length: pixels, and points too when the screenshot is Retina.
    private func rulerLabel(_ length: CGFloat) -> String {
        let scale = pixelScale.x
        let px = Int((length * scale).rounded())
        guard abs(scale - 1) > 0.01 else { return "\(px) px" }
        let pt = (length * 10).rounded() / 10
        let points = pt == pt.rounded() ? "\(Int(pt))" : String(format: "%.1f", pt)
        return "\(points) pt · \(px) px"
    }

    /// A thin line with a tick at each end, and its length on a dark label beside it (inside the screenshot when it
    /// fits there). Stroke color is already set to the style's color.
    private func drawRuler(_ a: Annotation) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y, len = hypot(dx, dy)
        guard len > 0 else { return }
        // The unit normal: ticks run along it, and the label sits off the line along it.
        let nx = -dy / len, ny = dx / len, tick: CGFloat = 5
        let path = NSBezierPath()
        path.move(to: a.start); path.line(to: a.end)
        for p in [a.start, a.end] {
            path.move(to: NSPoint(x: p.x - nx * tick, y: p.y - ny * tick))
            path.line(to: NSPoint(x: p.x + nx * tick, y: p.y + ny * tick))
        }
        path.lineWidth = 1.5
        path.stroke()

        let label = rulerLabel(len) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        let w = size.width + 10, h = size.height + 4
        let mid = NSPoint(x: (a.start.x + a.end.x) / 2, y: (a.start.y + a.end.y) / 2)
        let off = tick + 3 + (abs(nx) * w + abs(ny) * h) / 2
        func box(_ side: CGFloat) -> NSRect {
            NSRect(x: mid.x + nx * off * side - w / 2, y: mid.y + ny * off * side - h / 2, width: w, height: h)
        }
        let pill = imageRect.contains(box(1)) || !imageRect.contains(box(-1)) ? box(1) : box(-1)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2).fill()
        label.draw(at: NSPoint(x: pill.minX + 5, y: pill.minY + 2), withAttributes: attrs)
    }

    // MARK: Crop

    /// Enters crop mode with the current crop (or everything) chosen.
    func beginCrop() {
        guard !isCropping else { return }
        finishTextEditing()
        clearSelection()
        cropMargin = 28 / zoom
        cropDraft = crop ?? fullContentRect()
        onCropModeChange?(true)
    }

    /// Keeps the chosen area. Choosing everything removes the crop; a tiny area is ignored.
    func applyCrop() {
        guard let r = cropDraft?.integral else { return }
        let before = snapshot
        let full = fullContentRect()
        cropMargin = 0
        cropDraft = nil
        if r.contains(full) { crop = nil } else if r.width >= 4, r.height >= 4 { crop = r }
        recordUndo(from: before)
        onCropModeChange?(false)
    }

    func cancelCrop() {
        guard isCropping else { return }
        cropMargin = 0
        cropDraft = nil
        onCropModeChange?(false)
    }

    /// While cropping, chooses everything again.
    func resetCrop() {
        if isCropping { cropDraft = fullContentRect() }
    }

    /// The crop's eight handles: four corners, then the middle of each side.
    private func cropHandles(_ r: NSRect) -> [(point: NSPoint, edges: CropEdges)] {
        [(NSPoint(x: r.minX, y: r.minY), CropEdges(left: true, bottom: true)),
         (NSPoint(x: r.maxX, y: r.minY), CropEdges(right: true, bottom: true)),
         (NSPoint(x: r.minX, y: r.maxY), CropEdges(left: true, top: true)),
         (NSPoint(x: r.maxX, y: r.maxY), CropEdges(right: true, top: true)),
         (NSPoint(x: r.minX, y: r.midY), CropEdges(left: true)),
         (NSPoint(x: r.maxX, y: r.midY), CropEdges(right: true)),
         (NSPoint(x: r.midX, y: r.minY), CropEdges(bottom: true)),
         (NSPoint(x: r.midX, y: r.maxY), CropEdges(top: true))]
    }

    /// A handle (or, failing that, a side of the frame) resizes; inside moves; outside draws a new area.
    private func cropDrag(in r: NSRect, at p: NSPoint) -> Drag {
        let hs = cropHandles(r)
        if let h = hs.min(by: { hypot($0.point.x - p.x, $0.point.y - p.y) < hypot($1.point.x - p.x, $1.point.y - p.y) }),
           hypot(h.point.x - p.x, h.point.y - p.y) <= 12 / zoom {
            return .cropEdges(h.edges)
        }
        let slop = 6 / zoom
        let inX = p.x >= r.minX - slop && p.x <= r.maxX + slop, inY = p.y >= r.minY - slop && p.y <= r.maxY + slop
        var e = CropEdges()
        e.left = inY && abs(p.x - r.minX) <= slop
        e.right = inY && abs(p.x - r.maxX) <= slop
        e.bottom = inX && abs(p.y - r.minY) <= slop
        e.top = inX && abs(p.y - r.maxY) <= slop
        if e.left || e.right || e.bottom || e.top { return .cropEdges(e) }
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
        tv.colorAtPointer = { [weak self] in
            guard let self, let p = self.pointerLocation, let c = self.color(at: p) else { return nil }
            return Preferences.colorFormat.string(for: c)
        }
        tv.string = a.text
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        // A wrapped label wraps at the same width while it is typed (#120).
        tv.textContainer?.containerSize = NSSize(width: a.wrapWidth ?? CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = a.wrapWidth == nil
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
        tv.textColor = s.textColor
        tv.insertionPointColor = s.textColor
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
        let size = NSSize(width: items[i].wrapWidth ?? max(used.width, font.pointSize * 0.6) + 2,
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
        let r: NSRect
        if isCropping {
            r = content.insetBy(dx: -cropMargin, dy: -cropMargin)
        } else if let bg = activeBackground {
            r = Background.canvas(around: content, margin: bg.padding + bg.inset, aspect: bg.aspect)
        } else {
            r = content
        }
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
        // A ruler's ticks and label stay out of it: a ruler across the whole screenshot shouldn't grow the canvas.
        case .text, .pixelate, .blur, .erase, .spotlight, .select, .filledRect, .counter, .image, .ruler: return 0
        case .highlighter: return a.style.highlighterWidth / 2
        case .arrow: return max(a.style.lineWidth / 2, max(12, a.style.lineWidth * 5) * 0.45)
        default: return a.style.lineWidth / 2 + (a.style.handDrawn ? handDrawnAmplitude(a) : 0)
        }
    }

    // MARK: Geometry & hit testing

    private func rect(_ a: Annotation) -> NSRect {
        NSRect(x: min(a.start.x, a.end.x), y: min(a.start.y, a.end.y),
               width: abs(a.start.x - a.end.x), height: abs(a.start.y - a.end.y))
    }

    private func textSize(_ a: Annotation) -> NSSize {
        let attrs = a.style.textAttributes
        guard let w = a.wrapWidth else { return (a.text as NSString).size(withAttributes: attrs) }
        let r = (a.text as NSString).boundingRect(with: NSSize(width: w, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin], attributes: attrs)
        return NSSize(width: w, height: ceil(r.height))
    }

    /// Where a text label's glyphs go (`start` is its top-left corner); at least one line high, so an empty label
    /// being typed still has a box.
    private func textRect(_ a: Annotation) -> NSRect {
        let s = textSize(a), f = a.style.font
        let h = max(s.height, ceil(f.ascender - f.descender + f.leading))
        let w = a.text.isEmpty ? max(s.width, f.pointSize * 0.6) : s.width
        return NSRect(x: a.start.x, y: a.start.y - h, width: w, height: h)
    }

    /// A text label's box (#120): its glyphs plus the padding.
    private func textBoxRect(_ a: Annotation) -> NSRect {
        let pad = a.style.textBoxPadding
        return textRect(a).insetBy(dx: -pad, dy: -pad)
    }

    /// Where a text label's tail points, when it has one.
    private func tailTip(_ a: Annotation) -> NSPoint? {
        guard a.tool == .text, a.style.tail, a.style.textBox != .plain else { return nil }
        if let t = a.tail { return t }
        let box = textBoxRect(a)
        return NSPoint(x: box.minX + min(box.width * 0.25, a.style.fontSize * 1.5), y: box.minY - a.style.fontSize * 1.2)
    }

    private func bounds(of a: Annotation) -> NSRect {
        // A bent line or arrow bulges past its ends.
        if a.tool == .line || a.tool == .arrow, a.bend != 0, let o = outline(a) { return o.bounds.union(rect(a)) }
        switch a.tool {
        case .text:
            let box = textBoxRect(a)
            guard let tip = tailTip(a) else { return box }
            return box.union(NSRect(origin: tip, size: .zero))
        case .counter:
            let r = a.style.counterRadius
            return NSRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
        case .pen, .highlighter:
            let xs = a.points.map(\.x), ys = a.points.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
            return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        case .magnifier: return rect(a).union(lensRect(a))
        default: return rect(a)
        }
    }

    /// The stroked outline used both for hit testing and (for most tools) drawing.
    private func outline(_ a: Annotation) -> NSBezierPath? {
        switch a.tool {
        case .rect, .filledRect, .spotlight:
            let r = rect(a), radius = min(a.style.cornerRadius, r.width / 2, r.height / 2)
            return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        case .ellipse: return NSBezierPath(ovalIn: rect(a))
        case .line, .arrow, .ruler:
            let p = NSBezierPath(); p.move(to: a.start)
            if a.tool != .ruler, a.bend != 0 {
                Self.quadCurve(p, to: a.end, control: bendControl(a))
            } else {
                p.line(to: a.end)
            }
            return p
        case .pen, .highlighter:
            guard !a.points.isEmpty else { return nil }
            return StrokeShapes.smoothPath(a.points)
        case .text, .pixelate, .blur, .erase, .magnifier, .select, .counter, .image: return nil
        }
    }

    /// The outline as drawn: with the hand-drawn wobble when that is on (#119).
    private func drawnOutline(_ a: Annotation) -> NSBezierPath? {
        guard let p = outline(a) else { return nil }
        guard a.style.handDrawn, [.rect, .ellipse, .line].contains(a.tool) else { return p }
        return StrokeShapes.handDrawn(p, seed: a.seed, amplitude: handDrawnAmplitude(a))
    }

    private func handDrawnAmplitude(_ a: Annotation) -> CGFloat { min(1 + a.style.lineWidth * 0.35, 4) }

    /// A line's or arrow's middle and its unit normal (to the left of start → end); nil when it has no length.
    private func chordFrame(_ a: Annotation) -> (mid: NSPoint, normal: NSPoint)? {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y, len = hypot(dx, dy)
        guard len > 0 else { return nil }
        return (NSPoint(x: (a.start.x + a.end.x) / 2, y: (a.start.y + a.end.y) / 2), NSPoint(x: -dy / len, y: dx / len))
    }

    /// The handle in the middle of a line or arrow: on the curve, `bend` from the straight line.
    private func bendHandle(_ a: Annotation) -> NSPoint {
        guard let f = chordFrame(a) else { return a.start }
        return NSPoint(x: f.mid.x + f.normal.x * a.bend, y: f.mid.y + f.normal.y * a.bend)
    }

    /// The control point of the quadratic curve through the ends and `bendHandle` (the middle of a straight one).
    private func bendControl(_ a: Annotation) -> NSPoint {
        guard let f = chordFrame(a) else { return a.start }
        return NSPoint(x: f.mid.x + f.normal.x * a.bend * 2, y: f.mid.y + f.normal.y * a.bend * 2)
    }

    /// Adds a quadratic curve to `p` (from its current point), as the cubic NSBezierPath draws.
    private static func quadCurve(_ p: NSBezierPath, to end: NSPoint, control c: NSPoint) {
        let s = p.currentPoint
        p.curve(to: end, controlPoint1: NSPoint(x: s.x + (c.x - s.x) * 2 / 3, y: s.y + (c.y - s.y) * 2 / 3),
                controlPoint2: NSPoint(x: end.x + (c.x - end.x) * 2 / 3, y: end.y + (c.y - end.y) * 2 / 3))
    }

    private func hits(_ a: Annotation, _ p: NSPoint) -> Bool {
        let slop = 5 / zoom
        // A spotlight is hit on its outline (like a rectangle), so annotations inside it stay clickable.
        if [.text, .pixelate, .blur, .erase, .filledRect, .counter, .image].contains(a.tool) {
            return bounds(of: a).insetBy(dx: -slop, dy: -slop).contains(p)
        }
        if a.tool == .magnifier {
            return rect(a).insetBy(dx: -slop, dy: -slop).contains(p) || lensPath(a).contains(p)
        }
        // A filled shape is hit anywhere inside, an outline only on its line.
        if a.tool == .rect || a.tool == .ellipse, a.style.fill != .outline, outline(a)?.contains(p) == true { return true }
        guard let path = outline(a) else { return false }
        let width = a.tool == .highlighter ? a.style.highlighterWidth : a.style.lineWidth
        return path.cgPath.copy(strokingWithWidth: width + slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(p)
    }

    /// Resize handles: rect corners as (BL, BR, TL, TR), or the two endpoints of a line/arrow.
    private func handles(_ a: Annotation) -> [NSPoint] {
        switch a.tool {
        case .rect, .filledRect, .ellipse, .pixelate, .blur, .erase, .spotlight, .magnifier, .image:
            let r = rect(a)
            return [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY),
                    NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)]
        case .line, .arrow: return [a.start, a.end, bendHandle(a)]
        case .ruler: return [a.start, a.end]
        case .text:
            // The wrap width on the right-hand side, then the tail's tip.
            let box = textBoxRect(a)
            return [NSPoint(x: box.maxX, y: box.midY)] + (tailTip(a).map { [$0] } ?? [])
        case .pen, .highlighter, .counter, .select: return []
        }
    }

    private func handleDrag(for a: Annotation, at p: NSPoint) -> Drag? {
        let hs = handles(a), radius = 8 / zoom
        guard let h = hs.indices.first(where: { hypot(hs[$0].x - p.x, hs[$0].y - p.y) <= radius }) else { return nil }
        if a.tool == .line || a.tool == .arrow || a.tool == .ruler { return h == 2 ? .bend : .resizeEnd(isStart: h == 0) }
        if a.tool == .text { return h == 0 ? .textWidth : .textTail }
        return .resizeCorner(anchor: hs[3 - h])   // the diagonally opposite corner stays put
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        if let bg = activeBackground {
            if bg.outerRadius > 0 {
                NSBezierPath(roundedRect: bounds, xRadius: bg.outerRadius, yRadius: bg.outerRadius).addClip()
            }
            bg.drawFill(in: bounds)
            let cardRect = contentRect.insetBy(dx: -bg.inset, dy: -bg.inset)
            let card = NSBezierPath(roundedRect: cardRect, xRadius: bg.cornerRadius, yRadius: bg.cornerRadius)
            if bg.shadow > 0 {
                ctx?.saveGState()
                ctx?.setShadow(offset: CGSize(width: 0, height: -8), blur: 28,
                               color: NSColor.black.withAlphaComponent(0.8 * bg.shadow).cgColor)
                backdrop.setFill(); card.fill()
                ctx?.restoreGState()
            }
            if bg.inset > 0 {
                // The inset is a frame in the screenshot's edge color; the screenshot's corners follow the card's.
                backdrop.setFill(); card.fill()
                let inner = max(bg.cornerRadius - bg.inset, 0)
                NSBezierPath(roundedRect: contentRect, xRadius: inner, yRadius: inner).addClip()
            } else {
                card.addClip()
            }
        } else {
            NSBezierPath(rect: contentRect).addClip()
        }
        if contentRect != imageRect { backdrop.setFill(); contentRect.fill() }
        base.draw(in: imageRect)
        let all = items + (draft.map { [$0] } ?? [])
        for a in all {
            // While a label is typed its text is in the text view; its box is still drawn under it.
            if a.id == editingID { drawTextBox(a) } else { render(a) }
        }
        drawSpotlights(all.filter { $0.tool == .spotlight })
        ctx?.restoreGState()
        if let r = cropDraft { drawCropOverlay(r) }
        if !exporting, let r = areaDraft ?? contrastArea { drawAreaOverlay(r) }
        if !exporting, areaDraft == nil, let r = contrastArea, let s = contrastSummary { drawTag(s, under: r) }
        if !exporting, textEditor == nil, let i = selectedIndex { drawSelection(items[i]) }
        if !exporting, let d = rulerDraft { renderShape(d) }
        if !exporting { drawSnapGuides() }
    }

    /// Dims the screenshot everywhere except inside the spotlights (all of them together, so they never double-darken).
    private func drawSpotlights(_ spots: [Annotation]) {
        guard !spots.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSColor.black.withAlphaComponent(0.55).setFill()
        contentRect.fill()
        ctx.setBlendMode(.clear)
        for s in spots { outline(s)?.fill() }
        ctx.endTransparencyLayer()
    }

    /// Dims everything outside the crop and draws its frame, thirds and eight handles.
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
        for c in cropHandles(r).map(\.point) {
            let s = 5 * px
            let dot = NSBezierPath(rect: NSRect(x: c.x - s, y: c.y - s, width: s * 2, height: s * 2))
            NSColor.white.setFill(); dot.fill()
            dot.lineWidth = px; NSColor.black.withAlphaComponent(0.4).setStroke(); dot.stroke()
        }
    }

    private func render(_ a: Annotation) {
        // The shadow goes on a transparency layer so overlapping parts (an arrow's shaft and head) cast one shadow.
        guard Preferences.annotationShadow, !a.tool.obscures, a.tool != .highlighter, a.tool != .spotlight, let ctx = NSGraphicsContext.current?.cgContext else {
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
        case .rect, .ellipse:
            guard let p = drawnOutline(a) else { return }
            switch a.style.fill {
            case .outline: break
            case .translucent:
                a.style.color.withAlphaComponent(0.3).setFill(); p.fill()
                a.style.color.setFill()
            case .solid: p.fill()
            }
            p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .line, .pen:
            guard let p = drawnOutline(a) else { return }
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
            drawArrow(a)
        case .text:
            drawTextBox(a)
            let r = textRect(a)
            if a.wrapWidth != nil {
                (a.text as NSString).draw(with: r, options: [.usesLineFragmentOrigin], attributes: a.style.textAttributes)
            } else {
                (a.text as NSString).draw(at: r.origin, withAttributes: a.style.textAttributes)
            }
        case .pixelate:
            for r in concealRects(a) { drawPixelated(r, block: a.style.pixelSize) }
        case .blur:
            let parts = concealRects(a).map { $0.intersection(imageRect) }.filter { !$0.isEmpty }
            guard !parts.isEmpty, let img = blurred(radius: a.style.pixelSize),
                  let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.clip(to: parts)
            ctx.draw(img, in: imageRect)
            ctx.restoreGState()
        case .erase:
            for r in concealRects(a) {
                guard let c = eraseColor(around: r) else { continue }
                c.setFill(); r.fill()
            }
        case .magnifier:
            drawMagnifier(a)
        case .ruler:
            drawRuler(a)
        case .spotlight, .select:
            break   // spotlights are drawn together by drawSpotlights
        }
    }

    /// A text label's box, with its tail, when it has one (#120).
    private func drawTextBox(_ a: Annotation) {
        guard a.tool == .text, a.style.textBox != .plain else { return }
        let box = textBoxRect(a), radius = min(a.style.fontSize * 0.3, box.width / 2, box.height / 2)
        let path = Self.bubblePath(box, radius: radius, tail: tailTip(a), tailWidth: a.style.fontSize * 0.8)
        a.style.color.set()
        if a.style.textBox == .solid {
            path.fill()
        } else {
            path.lineWidth = max(1.5, a.style.fontSize / 12)
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    /// A rounded rectangle, with a triangular tail out to `tail` (when it lies outside) as part of the same outline,
    /// so an outlined bubble has no line across the tail's base.
    static func bubblePath(_ r: NSRect, radius: CGFloat, tail: NSPoint?, tailWidth: CGFloat) -> NSBezierPath {
        enum Side { case bottom, right, top, left }
        var side: Side?
        var base: CGFloat = 0
        if let t = tail, !r.contains(t), r.width > 0, r.height > 0 {
            let dx = (t.x - r.midX) / (r.width / 2), dy = (t.y - r.midY) / (r.height / 2)
            if abs(dx) > abs(dy) { side = dx > 0 ? .right : .left } else { side = dy > 0 ? .top : .bottom }
            let along = side == .bottom || side == .top
            let lo = (along ? r.minX : r.minY) + radius + tailWidth / 2, hi = (along ? r.maxX : r.maxY) - radius - tailWidth / 2
            let v = along ? t.x : t.y
            base = lo <= hi ? min(max(v, lo), hi) : (along ? r.midX : r.midY)
        }
        let w = tailWidth / 2, p = NSBezierPath()
        func tailOut(_ a: NSPoint, _ b: NSPoint) {
            guard let t = tail else { return }
            p.line(to: a); p.line(to: t); p.line(to: b)
        }
        // Counterclockwise from the bottom-left corner.
        p.move(to: NSPoint(x: r.minX + radius, y: r.minY))
        if side == .bottom { tailOut(NSPoint(x: base - w, y: r.minY), NSPoint(x: base + w, y: r.minY)) }
        p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        p.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: 270, endAngle: 360)
        if side == .right { tailOut(NSPoint(x: r.maxX, y: base - w), NSPoint(x: r.maxX, y: base + w)) }
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        p.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        if side == .top { tailOut(NSPoint(x: base + w, y: r.maxY), NSPoint(x: base - w, y: r.maxY)) }
        p.line(to: NSPoint(x: r.minX + radius, y: r.maxY))
        p.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
        if side == .left { tailOut(NSPoint(x: r.minX, y: base + w), NSPoint(x: r.minX, y: base - w)) }
        p.line(to: NSPoint(x: r.minX, y: r.minY + radius))
        p.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: 180, endAngle: 270)
        p.close()
        return p
    }

    /// An arrow, straight or bent; its heads point along the curve at its ends. Colors are already set.
    private func drawArrow(_ a: Annotation) {
        let lw = a.style.lineWidth
        guard hypot(a.end.x - a.start.x, a.end.y - a.start.y) > 2 else { return }
        let c = bendControl(a), head: CGFloat = max(12, lw * 5), style = a.style.arrowStyle
        // The directions the curve runs in at each end (for a straight arrow, both along it).
        let endAngle = atan2(a.end.y - c.y, a.end.x - c.x), startAngle = atan2(a.start.y - c.y, a.start.x - c.x)
        if style == .tapered { drawTaperedArrow(a, control: c, head: head, endAngle: endAngle); return }
        // A filled head covers the end of the shaft, so stop the shaft short of the tip.
        let inset = style == .open ? 0 : head * 0.6
        let shaftEnd = NSPoint(x: a.end.x - cos(endAngle) * inset, y: a.end.y - sin(endAngle) * inset)
        let shaftStart = style == .double ? NSPoint(x: a.start.x - cos(startAngle) * inset, y: a.start.y - sin(startAngle) * inset)
                                          : a.start
        var line = NSBezierPath()
        line.move(to: shaftStart)
        if a.bend != 0 { Self.quadCurve(line, to: shaftEnd, control: c) } else { line.line(to: shaftEnd) }
        if a.style.handDrawn { line = StrokeShapes.handDrawn(line, seed: a.seed, amplitude: handDrawnAmplitude(a)) }
        line.lineWidth = lw; line.lineCapStyle = .round; line.lineJoinStyle = .round
        line.stroke()
        drawArrowHead(tip: a.end, angle: endAngle, size: head, open: style == .open, lineWidth: lw)
        if style == .double { drawArrowHead(tip: a.start, angle: startAngle, size: head, open: false, lineWidth: lw) }
    }

    /// A filled shaft that widens from 30% to its full width toward a filled head (#119).
    private func drawTaperedArrow(_ a: Annotation, control c: NSPoint, head: CGFloat, endAngle: CGFloat) {
        let w = max(a.style.lineWidth * 1.6, 4)
        let base = NSPoint(x: a.end.x - cos(endAngle) * head * 0.7, y: a.end.y - sin(endAngle) * head * 0.7)
        let n = 24
        var left: [NSPoint] = [], right: [NSPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n), u = 1 - t
            // A point on the quadratic curve from the start to the head's base, and the curve's direction there.
            let p = NSPoint(x: u * u * a.start.x + 2 * u * t * c.x + t * t * base.x,
                            y: u * u * a.start.y + 2 * u * t * c.y + t * t * base.y)
            let dx = 2 * u * (c.x - a.start.x) + 2 * t * (base.x - c.x), dy = 2 * u * (c.y - a.start.y) + 2 * t * (base.y - c.y)
            let len = max(hypot(dx, dy), 0.001), half = w * (0.3 + 0.7 * t) / 2
            left.append(NSPoint(x: p.x - dy / len * half, y: p.y + dx / len * half))
            right.append(NSPoint(x: p.x + dy / len * half, y: p.y - dx / len * half))
        }
        let shaft = NSBezierPath()
        shaft.move(to: left[0])
        left.dropFirst().forEach { shaft.line(to: $0) }
        right.reversed().forEach { shaft.line(to: $0) }
        shaft.close()
        shaft.fill()
        drawArrowHead(tip: a.end, angle: endAngle, size: max(head, w * 2.2), open: false, lineWidth: a.style.lineWidth)
    }

    private func drawArrowHead(tip: NSPoint, angle: CGFloat, size: CGFloat, open: Bool, lineWidth: CGFloat) {
        let left = NSPoint(x: tip.x - size * cos(angle - .pi / 7), y: tip.y - size * sin(angle - .pi / 7))
        let right = NSPoint(x: tip.x - size * cos(angle + .pi / 7), y: tip.y - size * sin(angle + .pi / 7))
        let p = NSBezierPath()
        if open {
            p.move(to: left); p.line(to: tip); p.line(to: right)
            p.lineWidth = lineWidth; p.lineCapStyle = .round; p.lineJoinStyle = .round
            p.stroke()
        } else {
            p.move(to: tip); p.line(to: left); p.line(to: right); p.close()
            p.fill()
        }
    }

    /// Filled badge with the counter's number: its place among the counters in creation order, so deleting one
    /// renumbers the rest.
    private func drawCounter(_ a: Annotation) {
        let box = bounds(of: a)
        NSBezierPath(ovalIn: box).fill()
        let n = items.filter { $0.tool == .counter && $0.seq < a.seq }.count + 1
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

    // MARK: Text Only (pixelate, blur and erase just the lines of text OCR finds in the box)

    /// Lines of text found per box (key: the box, rounded to whole points), padded a little; cleared with `base`.
    private var textLineCache: [String: [NSRect]] = [:]
    private var textLinePending: Set<String> = []

    /// What a pixelate, blur or erase box hides: all of it, or with Text Only the lines of text in it. Until those
    /// have been found (and while dragging), all of it, so nothing shows that should be hidden.
    private func concealRects(_ a: Annotation) -> [NSRect] {
        let r = rect(a)
        guard a.style.textOnly else { return [r] }
        return textLines(in: r) ?? [r]
    }

    /// The lines of text in `r`, or nil while OCR is still looking (it starts here, once per box, when not dragging,
    /// and redraws when done). Moving or resizing a box makes it a new box, so it is looked at again.
    private func textLines(in r: NSRect) -> [NSRect]? {
        let area = r.integral
        let key = NSStringFromRect(area)
        if let found = textLineCache[key] { return found }
        guard drag == nil, !textLinePending.contains(key) else { return nil }
        textLinePending.insert(key)
        let image = base
        Task { @MainActor [weak self] in
            let found = await TextRecognizer.lineBoxes(in: image, area: area)
            guard let self, self.base === image else { return }
            self.textLinePending.remove(key)
            self.textLineCache[key] = found.map { $0.insetBy(dx: -2, dy: -2) }
            self.needsDisplay = true
        }
        return nil
    }

    // MARK: Erase

    /// Fill per erased box (key: the box), from the screenshot around it; cleared with `base`.
    private var eraseColors: [String: NSColor] = [:]

    /// The background color around `r` (image points): the most common color just outside it.
    private func eraseColor(around r: NSRect) -> NSColor? {
        let key = NSStringFromRect(r)
        if let c = eraseColors[key] { return c }
        guard let cg = baseCG, base.size.width > 0, base.size.height > 0 else { return nil }
        let sx = CGFloat(cg.width) / base.size.width, sy = CGFloat(cg.height) / base.size.height
        // Pixels, top-left origin.
        let px = CGRect(x: r.minX * sx, y: (base.size.height - r.maxY) * sy, width: r.width * sx, height: r.height * sy)
        guard let c = SmartErase.fillColor(around: px, in: cg).flatMap(NSColor.init(cgColor:)) else { return nil }
        if eraseColors.count > 500 { eraseColors = [:] }   // resizing makes a new box every frame
        eraseColors[key] = c
        return c
    }

    // MARK: Magnifier

    private static let lensGap: CGFloat = 24

    /// The lens's size: the area times the magnification (for a circle, its longer side).
    private func lensSize(_ a: Annotation) -> NSSize {
        let src = rect(a), f = a.style.magnification
        if a.style.lensShape == .circle {
            let d = max(src.width, src.height) * f
            return NSSize(width: d, height: d)
        }
        return NSSize(width: src.width * f, height: src.height * f)
    }

    /// Where a new lens goes: beside the area, on the right when it fits inside the screenshot there, else on the left
    /// (if it fits neither way, on the right, and the canvas grows).
    private func defaultLensCenter(_ a: Annotation) -> NSPoint {
        let src = rect(a), w = lensSize(a).width, gap = Self.lensGap
        let fitsRight = src.maxX + gap + w <= imageRect.maxX, fitsLeft = src.minX - gap - w >= imageRect.minX
        let x = fitsRight || !fitsLeft ? src.maxX + gap + w / 2 : src.minX - gap - w / 2
        return NSPoint(x: x, y: src.midY)
    }

    private func lensRect(_ a: Annotation) -> NSRect {
        let c = a.lens ?? defaultLensCenter(a), s = lensSize(a)
        return NSRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
    }

    private func lensPath(_ a: Annotation) -> NSBezierPath {
        let r = lensRect(a)
        if a.style.lensShape == .circle { return NSBezierPath(ovalIn: r) }
        let radius = min(8, r.width / 2, r.height / 2)
        return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    }

    /// Where the line from the middle of `r` toward `p` leaves `r` (or the oval in it).
    private func edgePoint(of r: NSRect, toward p: NSPoint, oval: Bool) -> NSPoint {
        let dx = p.x - r.midX, dy = p.y - r.midY
        let hw = max(r.width / 2, 0.5), hh = max(r.height / 2, 0.5)
        guard dx != 0 || dy != 0 else { return NSPoint(x: r.midX, y: r.midY) }
        let t: CGFloat
        if oval {
            t = 1 / hypot(dx / hw, dy / hh)
        } else {
            let tx: CGFloat = dx == 0 ? .infinity : hw / abs(dx)
            let ty: CGFloat = dy == 0 ? .infinity : hh / abs(dy)
            t = min(tx, ty)
        }
        return NSPoint(x: r.midX + dx * t, y: r.midY + dy * t)
    }

    /// A frame around the area, a lens showing it enlarged (the screenshot only, not other annotations), and a line
    /// between the two. Stroke and fill colors are already set to the style's color.
    private func drawMagnifier(_ a: Annotation) {
        let src = rect(a), lens = lensRect(a), lw = a.style.lineWidth, f = a.style.magnification
        guard src.width >= 1, src.height >= 1, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let thin = max(1, lw / 2)
        if !lens.intersects(src) {
            let line = NSBezierPath()
            line.move(to: edgePoint(of: src, toward: NSPoint(x: lens.midX, y: lens.midY), oval: false))
            line.line(to: edgePoint(of: lens, toward: NSPoint(x: src.midX, y: src.midY), oval: a.style.lensShape == .circle))
            line.lineWidth = thin; line.lineCapStyle = .round
            line.stroke()
        }
        let frame = NSBezierPath(rect: src)
        frame.lineWidth = thin
        frame.stroke()

        let path = lensPath(a)
        ctx.saveGState()
        path.addClip()
        backdrop.setFill(); lens.fill()   // what lies past the screenshot's edge
        if let cg = baseCG {
            // The area's center lands on the lens's center, scaled by the magnification.
            ctx.translateBy(x: lens.midX - src.midX * f, y: lens.midY - src.midY * f)
            ctx.scaleBy(x: f, y: f)
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: imageRect)
        }
        ctx.restoreGState()
        path.lineWidth = lw
        path.stroke()
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
    private var cachedRep: NSBitmapImageRep?
    private func bitmap() -> NSBitmapImageRep? {
        if cachedRep == nil { cachedRep = base.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) }
        return cachedRep
    }

    private var cachedCG: CGImage?
    private var baseCG: CGImage? {
        if cachedCG == nil {
            var r = CGRect(origin: .zero, size: base.size)
            cachedCG = base.cgImage(forProposedRect: &r, context: nil, hints: nil)
        }
        return cachedCG
    }
    private var cachedPixels: PixelBuffer?
    /// The screenshot's pixels for the color picker, the ruler and the contrast checker; read on first use.
    private var pixels: PixelBuffer? {
        if cachedPixels == nil, let cg = baseCG { cachedPixels = PixelBuffer(cg) }
        return cachedPixels
    }

    /// Pixels per point of the screenshot (2 for Retina).
    private var pixelScale: (x: CGFloat, y: CGFloat) {
        guard let cg = baseCG, base.size.width > 0, base.size.height > 0 else { return (1, 1) }
        return (CGFloat(cg.width) / base.size.width, CGFloat(cg.height) / base.size.height)
    }

    /// The pixel (top-left origin) under a point in image coordinates.
    private func pixelPoint(_ p: NSPoint) -> (x: Int, y: Int) {
        let s = pixelScale
        return (Int(floor(p.x * s.x)), Int(floor((base.size.height - p.y) * s.y)))
    }

    /// An area in image coordinates as pixels (top-left origin).
    private func pixelRect(_ r: NSRect) -> CGRect {
        let s = pixelScale
        return CGRect(x: r.minX * s.x, y: (base.size.height - r.maxY) * s.y, width: r.width * s.x, height: r.height * s.y)
    }

    private static let ciContext = CIContext()
    private var blurCache: [Int: CGImage] = [:]

    /// The whole screenshot gaussian-blurred (cached per radius); blur annotations show a piece of it.
    private func blurred(radius: CGFloat) -> CGImage? {
        let key = Int(radius)
        if let c = blurCache[key] { return c }
        guard let cg = baseCG, base.size.width > 0 else { return nil }
        let ci = CIImage(cgImage: cg)
        let sigma = Double(radius * CGFloat(cg.width) / base.size.width)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: ci.extent)
        let img = Self.ciContext.createCGImage(out, from: ci.extent)
        blurCache[key] = img
        return img
    }

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
