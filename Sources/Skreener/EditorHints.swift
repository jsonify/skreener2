import AppKit

/// The editor's live hint line (#303): what the pointer is doing right now. Each one matches what the canvas really
/// does (`CanvasView.mouseDragged`).
enum EditorHint: Equatable {
    /// An arrow's or line's middle handle.
    case bend
    /// A text label's side handles.
    case wrapWidth
    /// A speech bubble's tail tip.
    case tail
    /// A pen or highlighter stroke being drawn.
    case straightStroke
    /// A box drawn or resized while Snap to Objects is on.
    case snapping

    var text: String {
        switch self {
        case .bend: return "Drag to bend"
        case .wrapWidth: return "Drag to set wrap width"
        case .tail: return "Drag to point the tail"
        case .straightStroke: return "⇧ keeps it straight"
        case .snapping: return "⌘ turns off snapping"
        }
    }
}

/// Boxes drawn by hand in one screenshot, for the Repeat on Similar Objects nudge (#303).
enum BoxSimilarity {
    /// Within 15% (and at least 4 pt) of each other in both width and height.
    static func isSimilar(_ a: CGSize, _ b: CGSize) -> Bool {
        func close(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) <= max(4, 0.15 * max(x, y)) }
        return close(a.width, b.width) && close(a.height, b.height)
    }

    /// How many of `sizes` (the last one included) are similar to the last one.
    static func similarToLast(_ sizes: [CGSize]) -> Int {
        guard let last = sizes.last else { return 0 }
        return sizes.filter { isSimilar($0, last) }.count
    }
}

/// A label that never takes the mouse: clicks go through to the canvas under it.
private final class HintLine: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A small accent-colored dot on a control for a feature not used yet (#303).
private final class NewDot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// One editor's tips, hint line and "New" dots (#301, #303). The window controller hands it the canvas and ways to
/// find its controls; it never builds or rearranges them.
@MainActor final class EditorHelp {
    private weak var canvas: CanvasView?
    private let hintLine = HintLine(labelWithString: "")
    private var hintText: String?
    private var hintTask: Task<Void, Never>?
    /// Sizes of the rectangles and filled rectangles drawn by hand in this screenshot.
    private var boxes: [CGSize] = []
    private var dots: [NSView] = []
    private var opened = false
    private let toolPill: (Tool) -> NSView?
    private let featurePills: () -> [PillPopUp]

    /// `toolPill` finds a tool's button; `featurePills` the toolbar pull-downs, whose menus may hold new features.
    init(canvas: CanvasView, over scroll: NSView, in content: NSView, toolPill: @escaping (Tool) -> NSView?,
         featurePills: @escaping () -> [PillPopUp]) {
        self.canvas = canvas
        self.toolPill = toolPill
        self.featurePills = featurePills
        Tips.startWatching()

        hintLine.font = .systemFont(ofSize: 11)
        hintLine.textColor = .secondaryLabelColor
        hintLine.alignment = .center
        hintLine.lineBreakMode = .byTruncatingTail
        hintLine.alphaValue = 0
        hintLine.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hintLine)
        NSLayoutConstraint.activate([
            hintLine.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            hintLine.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -3),
            hintLine.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 16),
        ])

        canvas.onHint = { [weak self] text, dragging in self?.showHint(text, now: dragging) }
        canvas.onDrawnByHand = { [weak self] tool, box, id in self?.drew(tool, box, id) }
        let nc = NotificationCenter.default
        for name in [Tips.didChange, .skreenerPreferencesChanged] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDots() }
            }
        }
    }

    // MARK: Hint line

    /// `text` under the canvas: at once during a drag, after 400 ms of hovering; nil fades it out.
    private func showHint(_ text: String?, now: Bool) {
        let text = Tips.enabled ? text : nil
        guard text != hintText else { return }
        hintText = text
        hintTask?.cancel()
        guard let text else {
            let line = hintLine
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                line.animator().alphaValue = 0
            }
            return
        }
        hintLine.alphaValue = 0
        hintTask = Task { @MainActor [weak self] in
            if !now { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled, let self else { return }
            let line = self.hintLine
            line.stringValue = text
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                line.animator().alphaValue = 1
            }
        }
    }

    // MARK: Tips

    /// The editor is on screen: the first time any editor opens, the Counter tool's tip.
    func editorShown() {
        refreshDots()
        guard !opened else { return }
        opened = true
        Tips.record(.editorOpened)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            self?.refreshDots()   // the toolbar's items exist once the window is on screen
            guard let self, let pill = self.toolPill(.counter), pill.window?.isKeyWindow == true,
                  Tips.canShow(.counterTool, busy: self.isBusy) else { return }
            TipPopover.show(.counterTool, relativeTo: pill.bounds, of: pill, edge: pill.isFlipped ? .maxY : .minY)
        }
    }

    /// Dragging, drawing or typing: no tip now.
    private var isBusy: Bool { NSEvent.pressedMouseButtons != 0 || canvas?.isBusy != false }

    private func drew(_ tool: Tool, _ box: NSRect, _ id: UUID) {
        guard tool == .rect || tool == .filledRect else { return }
        if tool == .rect { Tips.record(.rectangleDrawn) }
        boxes.append(box.size)
        // After the mouse-up that drew it has been handled.
        Task { @MainActor [weak self] in
            guard let self, let canvas = self.canvas, !self.isBusy else { return }
            if BoxSimilarity.similarToLast(self.boxes) >= 3, Tips.canShow(.repeatSimilar, busy: false) {
                let anchor = box.intersection(canvas.visibleRect)
                guard !anchor.isNull, !anchor.isEmpty else { return }
                TipPopover.show(.repeatSimilar, relativeTo: anchor, of: canvas, edge: .maxY,
                                actionTitle: "Repeat on Similar Objects") { [weak canvas] in
                    guard let canvas else { return }
                    Tips.markUsed(.repeatOnSimilarObjects)
                    canvas.selectAnnotation(id)
                    canvas.repeatOnSimilarObjects(nil)
                }
            } else if tool == .rect, Tips.canShow(.filledRect, busy: false), let pill = self.toolPill(.filledRect) {
                TipPopover.show(.filledRect, relativeTo: pill.bounds, of: pill, edge: pill.isFlipped ? .maxY : .minY)
            }
        }
    }

    // MARK: "New" dots

    /// A dot on each toolbar pull-down whose menu holds a feature not used yet, and "New" on those menu items.
    func refreshDots() {
        dots.forEach { $0.removeFromSuperview() }
        dots = []
        for pill in featurePills() {
            Tips.refreshBadges(in: pill.menu)
            let features = (pill.menu?.items ?? []).compactMap { $0.action.flatMap(NewFeature.running) }
            guard features.contains(where: { Tips.isNew($0) }) else { continue }
            let dot = NewDot()
            dot.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
                dot.topAnchor.constraint(equalTo: pill.topAnchor, constant: 1),
                dot.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -1),
            ])
            dot.setAccessibilityElement(false)
            dots.append(dot)
        }
    }
}
