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
        case arrow, rect, text, highlight
    }

    enum Phase {
        case loading, ready, failed
    }

    /// Copy is the share sheet's Copy Photo (#440).
    enum Output {
        case save, share
    }

    /// One undo step: a redaction step (how many areas it added) or one drawing. Undo takes back the newest, whichever
    /// kind it is (#440).
    private enum UndoStep {
        case redaction(Int)
        case markup

        var isRedaction: Bool {
            if case .redaction = self { return true }
            return false
        }
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
            redraw()
        }
    }
    /// How new redactions cover: pixelate, blur or solid.
    @Published var redactStyle = RedactText.Cover.pixelate
    /// In full-image pixels (bottom-left origin); drawn over the screenshot in the preview and every export.
    @Published private(set) var redactions: [Redaction] = [] { didSet { scheduleRedraw() } }
    /// Finds text to redact.
    let finder = TextFinder()
    /// The Draw tool. Leaving Text drops the label being typed.
    @Published var tool = Tool.arrow { didSet { if tool != .text { cancelText() } } }
    /// The color of new arrows, rectangles, text and highlights.
    @Published var markupColor = Markup.defaultColor
    /// In full-image pixels; drawn over the redactions in the preview and every export. Each is its own undo step.
    /// Redrawn at once, so a finished shape doesn't blink between the live one and the preview.
    @Published private(set) var markups: [Markup] = [] { didSet { redraw() } }
    /// Where a tap with the Text tool put the label being typed (full-image pixels); nil when none is.
    @Published private(set) var textSpot: CGPoint?
    /// The label being typed.
    @Published var draftText = ""

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
        let marks = markups.map { $0.scaled(by: scale) }
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
        undoSteps.append(.redaction(added.count))
        redactions += added
    }

    /// Takes back the last step: one dragged area, or all the matches one Redact N covered.
    func undoRedaction() {
        guard let i = undoSteps.lastIndex(where: \.isRedaction),
              case .redaction(let n) = undoSteps.remove(at: i) else { return }
        redactions.removeLast(min(n, redactions.count))
    }

    func clearRedactions() {
        undoSteps.removeAll { $0.isRedaction }
        redactions = []
    }

    // MARK: Undo

    /// There is a redaction or a drawing to take back.
    var canUndo: Bool { !undoSteps.isEmpty }

    /// Takes back the newest edit: a redaction step or a drawing, whichever came last.
    func undo() {
        guard let step = undoSteps.popLast() else { return }
        switch step {
        case .redaction(let n): redactions.removeLast(min(n, redactions.count))
        case .markup: _ = markups.popLast()
        }
    }

    // MARK: Draw

    /// The full image's rect, in its pixels.
    private var imageBounds: CGRect { CGRect(origin: .zero, size: fullSize) }

    /// What the current tool makes from a drag between two full-image points (kept inside the image), in the current
    /// color; nil for the Text tool or when too little is left. Also the live shape while dragging.
    func shape(from a: CGPoint, to b: CGPoint) -> Markup? {
        let bounds = imageBounds
        func clamped(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
        }
        let p = clamped(a), q = clamped(b)
        let rect = CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
        switch tool {
        case .arrow:
            guard hypot(q.x - p.x, q.y - p.y) >= 1 else { return nil }
            return Markup(.arrow(from: p, to: q), color: markupColor)
        case .rect, .highlight:
            guard rect.width >= 1, rect.height >= 1 else { return nil }
            return Markup(tool == .rect ? .rectangle(rect) : .highlight(rect), color: markupColor)
        case .text:
            return nil
        }
    }

    /// Adds what a finished drag made.
    func draw(from a: CGPoint, to b: CGPoint) {
        guard let markup = shape(from: a, to: b) else { return }
        undoSteps.append(.markup)
        markups.append(markup)
    }

    /// Puts the label being typed at `p` (full-image pixels); a tap beside the picture is ignored.
    func placeText(at p: CGPoint) {
        guard imageBounds.contains(p) else { return }
        textSpot = p
    }

    /// The label being typed, to show it on the preview as it will be drawn.
    var draftMarkup: Markup? {
        guard let spot = textSpot else { return nil }
        return Markup(.text(draftText, at: spot), color: markupColor)
    }

    /// Adds the typed label at its spot; empty text adds nothing.
    func commitText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spot = textSpot, !text.isEmpty {
            undoSteps.append(.markup)
            markups.append(Markup(.text(text, at: spot), color: markupColor))
        }
        cancelText()
    }

    func cancelText() {
        textSpot = nil
        draftText = ""
    }

    func clearMarkups() {
        undoSteps.removeAll { !$0.isRedaction }
        markups = []
    }

    /// The look the controls show now.
    private var look: Look {
        Look(frame: frameChoice.name, dark: dark, background: backgroundChoice, padding: padding,
             cornerRadius: cornerRadius, shadow: shadow, cleanBar: cleanBar)
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
