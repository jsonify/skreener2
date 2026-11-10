import SkreenerCore
import SwiftUI
import UIKit

/// What the share sheet shows and the choices made in it.
@MainActor
public final class ShareModel: ObservableObject {
    /// Starts with the last look (#408), shared with the app or the extension through the App Group.
    public init() {
        let look = Look.load(offered: Self.backgroundChoices)
        frameChoice = FrameChoice(name: look.frame)
        dark = look.dark
        backgroundChoice = look.background
        padding = look.padding
        cornerRadius = look.cornerRadius
        shadow = look.shadow
        cleanBar = look.cleanBar
        markupWidth = Self.nearestMarkupWidth(look.markupWidth)
    }

    enum FrameChoice: Hashable {
        case plain, iPhone, browser, macWindow

        /// The name `Look` stores.
        var name: String {
            switch self {
            case .plain: return "plain"
            case .iPhone: return "iPhone"
            case .browser: return "browser"
            case .macWindow: return "macWindow"
            }
        }

        init(name: String) {
            switch name {
            case "plain": self = .plain
            case "browser": self = .browser
            case "macWindow": self = .macWindow
            default: self = .iPhone
            }
        }

    }

    /// What the controls edit.
    public enum Mode: Hashable {
        case style, redact, draw
    }

    /// What a drag (or, for text, a tap) on the Draw preview makes.
    enum Tool: Hashable {
        case arrow, line, rect, ellipse, pen, text, highlight

        /// New markups take the size slider's width; a highlight has one size.
        var hasWidth: Bool { self != .highlight }
    }

    enum Phase {
        case loading, ready, failed
    }

    /// Copy is the share sheet's Copy Photo (#440).
    enum Output {
        case save, share
    }

    /// One undo step: the redactions or the drawings as they were before it, so a step can add, change, move or
    /// delete any of them. Undo takes back the newest, whichever kind it is (#440).
    private enum UndoStep {
        case redactions([Redaction])
        case markups([Markup])

        var isRedaction: Bool {
            if case .redactions = self { return true }
            return false
        }
    }

    /// The drawing or redaction picked to edit: tapped, it shows handles and a menu (Edit, Duplicate, Delete) and can
    /// be dragged; the colour, size or cover then change it.
    enum Selection: Equatable {
        case markup(Int)
        case redaction(Int)
    }

    /// A line for the readout, and, when the user has to do something, what.
    struct Status: Equatable {
        var text: String
        var detail: String?
    }

    /// Background presets on offer, as indexes into `Background.presets`; nil is no background. Nonisolated, so
    /// `QuickFrame` can read the last look off the main actor.
    nonisolated static let backgroundChoices: [Int?] = [nil, 0, 1, 4, 3, 5]

    /// Colors on offer in Draw: the Mac's default red first, then some of its other presets (system colors).
    static let markupColors: [(name: String, color: RGBColor)] = [
        ("Red", Markup.defaultColor),
        ("Yellow", .hex(0xFFCC00)),
        ("Green", .hex(0x28CD41)),
        ("Blue", .hex(0x007AFF)),
        ("Black", .hex(0x000000)),
    ]

    /// The size slider's stops, as `Markup.width` multipliers (1 is the default 3 pt line).
    static let markupWidths: [Double] = [0.5, 1, 2, 3, 4]

    /// The stop nearest `w`.
    static func nearestMarkupWidth(_ w: Double) -> Double {
        markupWidths.min { abs($0 - w) < abs($1 - w) } ?? 1
    }

    /// Pen points closer than this (full-image pixels) to the last kept one are dropped.
    static let penSpacing: CGFloat = 2

    @Published private(set) var phase = Phase.loading
    @Published private(set) var preview: UIImage?
    @Published private(set) var status: Status?
    @Published private(set) var busy = false
    @Published var frameChoice = FrameChoice.iPhone { didSet { scheduleRedraw(); saveLook() } }
    @Published var backgroundChoice: Int? = 0 { didSet { scheduleRedraw(); saveLook() } }
    @Published var browserURL = DeviceFrame.defaultURL { didSet { scheduleRedraw() } }
    @Published var dark = false { didSet { scheduleRedraw(); saveLook() } }
    @Published var padding = 48.0 { didSet { scheduleRedraw(); saveLook() } }
    @Published var cornerRadius = 10.0 { didSet { scheduleRedraw(); saveLook() } }
    @Published var shadow = 0.5 { didSet { scheduleRedraw(); saveLook() } }
    /// Repaint an iPhone screenshot's status bar clean: 9:41, full signal, Wi-Fi and battery (#408). Part of the look.
    @Published var cleanBar = false { didSet { scheduleRedraw(); saveLook() } }
    /// Redact and Draw show the bare screenshot, so a touch maps straight to it. Redrawn at once on a switch: their
    /// canvases map touches with the preview's size.
    @Published public var mode = Mode.style {
        didSet {
            guard mode != oldValue else { return }
            if mode != .draw { cancelText() }
            deselect()
            redraw()
        }
    }
    /// How new redactions cover: pixelate, blur or solid.
    @Published var redactStyle = RedactText.Cover.pixelate { didSet { applyCoverToSelection() } }
    /// In full-image pixels (bottom-left origin); drawn over the screenshot in the preview and every export.
    @Published private(set) var redactions: [Redaction] = [] { didSet { scheduleRedraw() } }
    /// Finds text to redact.
    let finder = TextFinder()
    /// The Draw tool. Leaving Text drops the label being typed.
    @Published var tool = Tool.arrow {
        didSet {
            if tool != .text { cancelText() }
            if tool != oldValue { deselect() }
        }
    }
    /// The color of new drawings and text, and of the selected one.
    @Published var markupColor = Markup.defaultColor { didSet { applyStyleToSelection() } }
    /// The width of new drawings and the size of new text, one of `markupWidths` (highlights ignore it). Each markup
    /// keeps its own. Part of the look.
    @Published var markupWidth = 1.0 { didSet { saveLook(); applyStyleToSelection() } }
    /// In full-image pixels; drawn over the redactions in the preview and every export. Each is its own undo step.
    /// Redrawn at once, so a finished shape doesn't blink between the live one and the preview.
    @Published private(set) var markups: [Markup] = [] { didSet { redraw() } }
    /// Where a tap with the Text tool put the label being typed (full-image pixels); nil when none is.
    @Published private(set) var textSpot: CGPoint?
    /// The label being typed.
    @Published var draftText = ""
    /// The drawing or redaction being edited, if any.
    @Published private(set) var selection: Selection?
    /// A drawing left out of the preview while it is dragged or its text retyped: the canvas draws it live instead.
    private var liftedMarkup: Int?
    /// The text drawing being retyped: Done replaces it.
    private var editingText: Int?
    /// The drawing or redaction whose colour, size or cover was last changed in one undo step, so a slider drag is
    /// one step; any other step ends it.
    private var styledSelection: Selection?
    /// The colour key and size slider are being set to the selected drawing's, which must not change it.
    private var syncingStyle = false

    /// True when the full image is an iPhone screenshot whose status bar size is known.
    var canCleanBar: Bool {
        StatusBar.layout(forPixelWidth: Int(fullSize.width), height: Int(fullSize.height)) != nil
    }

    /// The clean bar's layout for the preview, or nil when it is off or not available. The preview is a downscaled
    /// copy that the size table doesn't list, so the full size's layout is scaled down to it.
    private func previewStatusBar(scale: CGFloat) -> StatusBar.Layout? {
        guard cleanBar else { return nil }
        return StatusBar.layout(forPixelWidth: Int(fullSize.width), height: Int(fullSize.height))?.scaled(by: scale)
    }

    var canExport: Bool { phase == .ready && !busy }

    /// Where the image comes from. Kept so an export can reload the full image: the decoded one (up to 4096 px) is
    /// dropped after the preview is made, since holding both would cost memory the extension may not have.
    private var imageSource: ImageSource?
    /// The screenshot at preview size.
    private var source: CGImage?
    /// The full image's size in pixels, to scale padding, corners and redactions down for the preview.
    private(set) var fullSize = CGSize(width: 1, height: 1)
    /// Every redaction step and drawing, oldest first, so Undo takes back a whole Redact N at once, and the newest
    /// edit of either kind.
    private var undoSteps: [UndoStep] = []
    private var redrawPending = false

    /// Loads the image from the extension's `items` and shows it.
    public func load(items: [NSExtensionItem]) {
        load(source: .items(items))
    }

    /// Loads the image from `source` and shows it. Call it once, on a fresh model.
    public func load(source: ImageSource) {
        imageSource = source
        Task { [weak self] in
            do {
                let image = try await source.load()
                self?.show(image)
            } catch {
                self?.fail()
            }
        }
    }

    private func show(_ image: CGImage) {
        fullSize = CGSize(width: max(image.width, 1), height: max(image.height, 1))
        if let imageSource { finder.prepare(source: imageSource, size: fullSize) }
        source = ImageLoader.preview(of: image)
        phase = .ready
        redraw()
        // Safe Check runs on every screenshot as it opens (SafeCheck.swift).
        finder.scanForLeaks()
    }

    private func fail() {
        phase = .failed
    }

    // MARK: Preview

    /// Redraws once for a burst of changes, so dragging a slider stays smooth.
    private func scheduleRedraw() {
        guard source != nil, !redrawPending else { return }
        redrawPending = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            self?.redrawPending = false
            self?.redraw()
        }
    }

    private func redraw() {
        guard let source else { return }
        // Padding and corners are in full-image pixels; the preview is smaller by this much.
        let scale = CGFloat(source.width) / fullSize.width
        let shown = redactions.map { $0.scaled(by: scale) }
        let marks = markups.indices.filter { $0 != liftedMarkup }.map { markups[$0].scaled(by: scale) }
        let bar = previewStatusBar(scale: scale)
        switch mode {
        case .style:
            preview = Renderer.render(image: source, frame: makeFrame(), background: makeBackground(scale: scale),
                                      redactions: shown, markups: marks, statusBar: bar)
        case .redact, .draw:
            preview = Renderer.render(image: source, frame: nil, background: nil, redactions: shown, markups: marks,
                                      statusBar: bar)
        }
    }

    // MARK: Redact

    var canUndoRedaction: Bool { undoSteps.contains(where: \.isRedaction) }

    /// Covers `rects` (full-image pixels) with the current style, as one step. Parts outside the image are dropped.
    func redact(_ rects: [CGRect]) {
        let bounds = CGRect(origin: .zero, size: fullSize)
        let added = rects.map { $0.standardized.intersection(bounds) }
            .filter { !$0.isNull && $0.width >= 1 && $0.height >= 1 }
            .map { Redaction(rect: $0, style: redactStyle) }
        guard !added.isEmpty else { return }
        pushUndo(.redactions(redactions))
        deselect()
        redactions += added
    }

    /// Takes back the last redaction step: one dragged area, all the matches one Redact N covered, a move or a delete.
    func undoRedaction() {
        guard let i = undoSteps.lastIndex(where: \.isRedaction),
              case .redactions(let before) = undoSteps.remove(at: i) else { return }
        deselect()
        styledSelection = nil
        redactions = before
    }

    /// Removes every redaction, as one step Undo takes back.
    func clearRedactions() {
        guard !redactions.isEmpty else { return }
        pushUndo(.redactions(redactions))
        deselect()
        redactions = []
    }

    // MARK: Undo

    /// There is a redaction or a drawing to take back.
    var canUndo: Bool { !undoSteps.isEmpty }

    /// Takes back the newest edit: a redaction step or a drawing, whichever came last.
    func undo() {
        guard let step = undoSteps.popLast() else { return }
        cancelText()
        deselect()
        styledSelection = nil
        switch step {
        case .redactions(let before): redactions = before
        case .markups(let before): markups = before
        }
    }

    /// Records the state before a new step.
    private func pushUndo(_ step: UndoStep) {
        undoSteps.append(step)
        styledSelection = nil
    }

    // MARK: Draw

    /// The full image's rect, in its pixels.
    private var imageBounds: CGRect { CGRect(origin: .zero, size: fullSize) }

    /// `p` kept inside the image.
    private func clamped(_ p: CGPoint) -> CGPoint {
        let bounds = imageBounds
        return CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    /// A new markup of `kind` in the current colour and width (a highlight keeps width 1: it has one size).
    private func newMarkup(_ kind: Markup.Kind) -> Markup {
        if case .highlight = kind { return Markup(kind, color: markupColor) }
        return Markup(kind, color: markupColor, width: CGFloat(markupWidth))
    }

    /// What the current tool makes from a drag between two full-image points (kept inside the image), in the current
    /// color and width; nil for Text and Pen or when too little is left. Also the live shape while dragging.
    func shape(from a: CGPoint, to b: CGPoint) -> Markup? {
        let p = clamped(a), q = clamped(b)
        let rect = CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
        switch tool {
        case .arrow, .line:
            guard hypot(q.x - p.x, q.y - p.y) >= 1 else { return nil }
            return newMarkup(tool == .arrow ? .arrow(from: p, to: q) : .line(from: p, to: q))
        case .rect, .ellipse, .highlight:
            guard rect.width >= 1, rect.height >= 1 else { return nil }
            switch tool {
            case .rect: return newMarkup(.rectangle(rect))
            case .ellipse: return newMarkup(.ellipse(rect))
            default: return newMarkup(.highlight(rect))
            }
        case .pen, .text:
            return nil
        }
    }

    /// Adds `p` (full-image pixels, kept inside the image) to a pen stroke being drawn, unless it is within
    /// `penSpacing` of the last point kept.
    func addPenPoint(_ p: CGPoint, to points: inout [CGPoint]) {
        let q = clamped(p)
        if let last = points.last, hypot(q.x - last.x, q.y - last.y) < Self.penSpacing { return }
        points.append(q)
    }

    /// A pen stroke through `points` (full-image pixels) in the current colour and width; one point is a dot. Nil
    /// for none. Also the live stroke while drawing.
    func penStroke(_ points: [CGPoint]) -> Markup? {
        points.isEmpty ? nil : newMarkup(.pen(points))
    }

    /// Adds a finished pen stroke.
    func drawPen(_ points: [CGPoint]) {
        guard let markup = penStroke(points) else { return }
        add(markup)
    }

    /// A tap with Pen: a dot at `p` (full-image pixels); a tap beside the picture is ignored.
    func drawDot(at p: CGPoint) {
        guard imageBounds.contains(p) else { return }
        drawPen([p])
    }

    /// Adds what a finished drag made.
    func draw(from a: CGPoint, to b: CGPoint) {
        guard let markup = shape(from: a, to: b) else { return }
        add(markup)
    }

    /// Puts the label being typed at `p` (full-image pixels); a tap beside the picture is ignored.
    func placeText(at p: CGPoint) {
        guard imageBounds.contains(p) else { return }
        textSpot = p
    }

    /// The label being typed, to show it on the preview as it will be drawn.
    var draftMarkup: Markup? {
        guard let spot = textSpot else { return nil }
        return newMarkup(.text(draftText, at: spot))
    }

    /// Adds a new drawing as one step.
    private func add(_ markup: Markup) {
        pushUndo(.markups(markups))
        deselect()
        markups.append(markup)
    }

    /// Adds the typed label at its spot, or, when retyping one, puts it back changed; empty text adds nothing (and
    /// deletes a retyped label).
    func commitText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = editingText, markups.indices.contains(i), let spot = textSpot {
            var m = markups[i]
            m.kind = .text(text, at: spot)
            m.color = markupColor
            m.width = CGFloat(markupWidth)
            if text.isEmpty {
                pushUndo(.markups(markups))
                markups.remove(at: i)
                selection = nil
            } else if m != markups[i] {
                pushUndo(.markups(markups))
                markups[i] = m
            }
        } else if let spot = textSpot, !text.isEmpty {
            add(newMarkup(.text(text, at: spot)))
        }
        cancelText()
    }

    /// Drops the label being typed; a label being retyped stays as it was.
    func cancelText() {
        textSpot = nil
        draftText = ""
        if editingText != nil {
            editingText = nil
            liftedMarkup = nil
            redraw()
        }
    }

    /// Removes every drawing, as one step Undo takes back.
    func clearMarkups() {
        guard !markups.isEmpty else { return }
        cancelText()
        pushUndo(.markups(markups))
        deselect()
        markups = []
    }

    // MARK: Editing

    /// The selected drawing, if a drawing is selected.
    var selectedMarkup: Markup? {
        guard case .markup(let i)? = selection, markups.indices.contains(i) else { return nil }
        return markups[i]
    }

    /// The selected redaction, if a redaction is selected.
    var selectedRedaction: Redaction? {
        guard case .redaction(let i)? = selection, redactions.indices.contains(i) else { return nil }
        return redactions[i]
    }

    /// The newest drawing within `tolerance` (full-image pixels) of `p`.
    func markupIndex(at p: CGPoint, tolerance: CGFloat) -> Int? {
        Markup.index(at: p, in: markups, tolerance: tolerance, imageWidth: Int(fullSize.width))
    }

    /// The newest redaction within `tolerance` (full-image pixels) of `p`.
    func redactionIndex(at p: CGPoint, tolerance: CGFloat) -> Int? {
        Redaction.index(at: p, in: redactions, tolerance: tolerance)
    }

    /// Selects drawing `i`. The colour key and size slider show its colour and size, so changing them changes it.
    func selectMarkup(_ i: Int) {
        guard markups.indices.contains(i) else { return }
        selection = .markup(i)
        styledSelection = nil
        let m = markups[i]
        syncingStyle = true
        defer { syncingStyle = false }
        markupColor = m.color
        if case .highlight = m.kind {} else { markupWidth = Self.nearestMarkupWidth(Double(m.width)) }
    }

    /// Selects redaction `i`; the cover control shows its cover, so changing it changes it.
    func selectRedaction(_ i: Int) {
        guard redactions.indices.contains(i) else { return }
        selection = .redaction(i)
        styledSelection = nil
        redactStyle = redactions[i].style
    }

    func deselect() {
        guard selection != nil else { return }
        selection = nil
    }

    /// Leaves the selected drawing out of the preview while it is dragged; `dropMarkup` puts it back.
    func liftSelectedMarkup() {
        guard case .markup(let i)? = selection, markups.indices.contains(i) else { return }
        liftedMarkup = i
        redraw()
    }

    /// Puts the lifted drawing back as `changed` (one step), or as it was for nil or the same.
    func dropMarkup(_ changed: Markup?) {
        guard let i = liftedMarkup else { return }
        if let changed, markups.indices.contains(i), changed != markups[i] {
            pushUndo(.markups(markups))
            liftedMarkup = nil
            // Redraws with it back in.
            markups[i] = changed
        } else {
            liftedMarkup = nil
            redraw()
        }
    }

    /// Starts a drag of the selected redaction: one undo step for the whole drag.
    func beginRedactionEdit() {
        guard selectedRedaction != nil else { return }
        pushUndo(.redactions(redactions))
    }

    /// Moves or resizes the selected redaction while it is dragged (no undo step: `beginRedactionEdit` made one).
    /// Kept at least a pixel big and on the image.
    func setSelectedRedaction(_ r: Redaction) {
        guard case .redaction(let i)? = selection, redactions.indices.contains(i) else { return }
        let rect = r.rect.standardized.intersection(imageBounds)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        redactions[i] = Redaction(rect: rect, style: r.style)
    }

    /// Ends a redaction drag; a drag that changed nothing takes its undo step back.
    func endRedactionEdit(original: Redaction) {
        guard selectedRedaction == original, case .redactions? = undoSteps.last else { return }
        undoSteps.removeLast()
    }

    /// Drops a redaction drag (a second finger landed): the redaction goes back where it was.
    func cancelRedactionEdit(original: Redaction) {
        setSelectedRedaction(original)
        endRedactionEdit(original: original)
    }

    /// Deletes the selected drawing or redaction, as one step.
    func deleteSelection() {
        switch selection {
        case .markup(let i)? where markups.indices.contains(i):
            cancelText()
            pushUndo(.markups(markups))
            selection = nil
            markups.remove(at: i)
        case .redaction(let i)? where redactions.indices.contains(i):
            pushUndo(.redactions(redactions))
            selection = nil
            redactions.remove(at: i)
        default:
            selection = nil
        }
    }

    /// Adds a copy of the selected drawing or redaction a little down and right of it, and selects the copy.
    func duplicateSelection() {
        let step = max(8, fullSize.width / 40)
        switch selection {
        case .markup(let i)? where markups.indices.contains(i):
            pushUndo(.markups(markups))
            markups.append(markups[i].offsetBy(dx: step, dy: -step))
            selectMarkup(markups.count - 1)
        case .redaction(let i)? where redactions.indices.contains(i):
            pushUndo(.redactions(redactions))
            let copy = redactions[i].offsetBy(dx: step, dy: -step)
            let rect = copy.rect.intersection(imageBounds)
            redactions.append(Redaction(rect: rect.isNull ? redactions[i].rect : rect, style: copy.style))
            selectRedaction(redactions.count - 1)
        default:
            break
        }
    }

    /// The selected drawing is a text label, so it can be retyped.
    var canEditSelectedText: Bool {
        if case .text? = selectedMarkup?.kind { return true }
        return false
    }

    /// Retypes the selected label: the text field comes up with its text, and the label follows what is typed.
    func editSelectedText() {
        guard case .markup(let i)? = selection, markups.indices.contains(i),
              case .text(let text, let at) = markups[i].kind else { return }
        editingText = i
        liftedMarkup = i
        draftText = text
        textSpot = at
        redraw()
    }

    /// The colour or size slider changed: the selected drawing takes it (a highlight keeps its one size).
    private func applyStyleToSelection() {
        guard !syncingStyle, editingText == nil, let sel = selection, case .markup(let i) = sel,
              markups.indices.contains(i) else { return }
        var m = markups[i]
        m.color = markupColor
        if case .highlight = m.kind {} else { m.width = CGFloat(markupWidth) }
        guard m != markups[i] else { return }
        if styledSelection != sel {
            pushUndo(.markups(markups))
            styledSelection = sel
        }
        markups[i] = m
    }

    /// The cover control changed: the selected redaction takes it.
    private func applyCoverToSelection() {
        guard let sel = selection, case .redaction(let i) = sel, redactions.indices.contains(i),
              redactions[i].style != redactStyle else { return }
        if styledSelection != sel {
            pushUndo(.redactions(redactions))
            styledSelection = sel
        }
        redactions[i].style = redactStyle
    }

    /// The look the controls show now.
    private var look: Look {
        Look(frame: frameChoice.name, dark: dark, background: backgroundChoice, padding: padding,
             cornerRadius: cornerRadius, shadow: shadow, cleanBar: cleanBar, markupWidth: markupWidth)
    }

    /// Remembers the look for the next editor, here or in the app or extension. It is a few bytes, so no debounce.
    private func saveLook() {
        look.save()
    }

    private func makeFrame() -> DeviceFrame {
        look.makeFrame(url: browserURL)
    }

    private func makeBackground(scale: CGFloat) -> Background? {
        look.makeBackground(scale: scale)
    }

    // MARK: Output

    /// Renders at full size, then saves or hands the file to `share`. The output keys are off meanwhile.
    func export(_ output: Output, share: @escaping (URL) -> Void) {
        guard canExport, let imageSource else { return }
        busy = true
        status = Status(text: output == .save ? "Saving…" : "Rendering…")
        let job = Exporter.Job(source: imageSource, frame: makeFrame(), background: makeBackground(scale: 1),
                               redactions: redactions, markups: markups,
                               cleanBar: cleanBar && canCleanBar)
        Task { [weak self] in
            await self?.perform(output, job: job, share: share)
        }
    }

    private func perform(_ output: Output, job: Exporter.Job, share: (URL) -> Void) async {
        defer { busy = false }
        do {
            let png = try await Exporter.png(job)
            switch output {
            case .save:
                try await Exporter.save(png)
                status = Status(text: "Saved to Photos")
            case .share:
                let url = try Exporter.shareFile(png)
                status = nil
                share(url)
            }
        } catch Exporter.ExportError.photosDenied {
            status = Status(text: "No access to Photos",
                            detail: "In Settings > Privacy & Security > Photos, allow “Add Photos Only” for Skreener.")
        } catch {
            status = Status(text: "Could not export")
        }
    }
}
