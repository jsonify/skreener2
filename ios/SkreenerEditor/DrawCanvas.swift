import SK1Tokens
import SK1UI
import SkreenerCore
import SwiftUI

/// The Draw preview: the screenshot with its redactions and drawings, aspect-fitted or zoomed. Drag to draw an arrow,
/// line, rectangle, ellipse or highlight (the shape follows the finger); with Pen, draw freely (the stroke follows the
/// finger; a tap is a dot); with the Text tool, tap where the label goes. Pinch, two-finger drag and double-tap zoom
/// and pan (`CanvasTouches`); a pinch drops the shape or stroke being drawn.
///
/// Drawings stay editable, as in the system's Markup (#440): tap one to select it (handles, and a menu with Edit for a
/// label, Duplicate and Delete); tap a selected label to retype it; drag a drawing to move it (a highlight, or
/// anything with Pen, once selected); drag a handle to move an arrow's or line's end or a box's corner. The colour key
/// and size slider then change the selected drawing. A tap on nothing deselects.
struct DrawCanvas: View {
    @ObservedObject var model: ShareModel
    let preview: UIImage
    @Binding var zoom: PreviewZoom

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    /// The pen stroke being drawn, in full-image pixels.
    @State private var penPoints: [CGPoint] = []
    /// What the drag under way does, once its first move says: draw, or move or reshape a drawing.
    @State private var gesture: DragKind?
    /// The drawing being moved or reshaped.
    @State private var edit: MarkupDrag?

    private enum DragKind {
        case draw, edit
    }

    /// A drag of a drawing: as it was, the handle dragged (nil to move it whole), where the drag started and the
    /// drawing now (full-image pixels).
    private struct MarkupDrag {
        var original: Markup
        var handle: Markup.Handle?
        var start: CGPoint
        var live: Markup
    }

    var body: some View {
        GeometryReader { geo in
            let view = geo.size
            let shown = PreviewMapping.displayed(preview.size, in: view, zoom: zoom)
            let toView = PreviewMapping.imageToView(image: shown, full: model.fullSize)
            let draft = edit?.live ?? self.draft(shown)
            let width = Int(model.fullSize.width)
            let selected = model.textSpot == nil ? (edit?.live ?? model.selectedMarkup) : nil
            let box = selected.flatMap { selectionBox($0, shown) }
            ZStack(alignment: .topLeading) {
                PreviewImage(preview: preview, rect: shown,
                             label: "Preview. Drag to draw; tap a drawing to select it, then drag it, change it or "
                                + "delete it. With the Text tool, tap where the text goes. Pinch to zoom.")
                // The shape being drawn or dragged, or the label being typed, drawn as the export will draw it.
                Canvas { context, _ in
                    guard let draft else { return }
                    context.withCGContext { cg in
                        cg.concatenate(toView)
                        Markup.draw([draft], imageWidth: width, in: cg)
                    }
                }
                .allowsHitTesting(false)
                if let selected, let box {
                    SelectionOutline(box: hasEnds(selected) ? nil : box,
                                     handles: selected.handles.map { $0.point.applying(toView) })
                }
                if let spot = model.textSpot {
                    Circle()
                        .stroke(Color(sk1Hex: SK1.orange), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .position(spot.applying(toView))
                        .allowsHitTesting(false)
                }
                touches(view: view)
                    .frame(width: view.width, height: view.height)
                if edit == nil, model.selectedMarkup != nil, let box {
                    SelectionMenu(items: menuItems, target: box, view: view)
                }
            }
            .frame(width: view.width, height: view.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// Edit (for a label), Duplicate and Delete.
    private var menuItems: [SelectionMenu.Item] {
        var items: [SelectionMenu.Item] = []
        if model.canEditSelectedText {
            items.append(.init(title: "Edit") { model.editSelectedText() })
        }
        items.append(.init(title: "Duplicate") { model.duplicateSelection() })
        items.append(.init(title: "Delete", destructive: true) { model.deleteSelection() })
        return items
    }

    /// An arrow or a line: its handles are its ends, with no box around it.
    private func hasEnds(_ m: Markup) -> Bool {
        switch m.kind {
        case .arrow, .line: return true
        default: return false
        }
    }

    /// The selected drawing's box in view points.
    private func selectionBox(_ m: Markup, _ shown: CGRect) -> CGRect? {
        let r = m.selectionBounds(imageWidth: Int(model.fullSize.width))
        guard !r.isNull else { return nil }
        return PreviewMapping.viewRect(r, image: shown, full: model.fullSize)
    }

    /// The shape or pen stroke under the finger, once the drag is long enough to count; otherwise the label being
    /// typed.
    private func draft(_ shown: CGRect) -> Markup? {
        if model.tool == .pen, model.textSpot == nil { return model.penStroke(penPoints) }
        if let a = dragStart, let b = dragEnd, model.tool != .text, model.textSpot == nil,
           PreviewMapping.isDrag(from: a, to: b) {
            return model.shape(from: imagePoint(a, shown), to: imagePoint(b, shown))
        }
        return model.draftMarkup
    }

    private func imagePoint(_ p: CGPoint, _ shown: CGRect) -> CGPoint {
        PreviewMapping.imagePoint(p, image: shown, full: model.fullSize)
    }

    /// `p` kept inside the image.
    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), model.fullSize.width), y: min(max(p.y, 0), model.fullSize.height))
    }

    /// Starts moving or reshaping a drawing if the drag starts on one (`p` in full-image pixels; `perPoint` is full
    /// pixels per view point): the selected drawing's handle, the selected drawing, or (not with Pen) any drawing but a
    /// highlight, which is selected first so whatever is under it can still be highlighted.
    private func startEdit(at p: CGPoint, perPoint: CGFloat) -> Bool {
        let imageWidth = Int(model.fullSize.width)
        if let m = model.selectedMarkup {
            let reach = SelectionReach.handle * perPoint
            let near = m.handles
                .map { (handle: $0.handle, distance: hypot($0.point.x - p.x, $0.point.y - p.y)) }
                .filter { $0.distance <= reach }
                .min { $0.distance < $1.distance }
            if let near {
                beginEdit(m, handle: near.handle, at: p)
                return true
            }
            if m.hits(p, tolerance: SelectionReach.tap * perPoint, imageWidth: imageWidth) {
                beginEdit(m, handle: nil, at: p)
                return true
            }
        }
        guard model.tool != .pen,
              let i = model.markupIndex(at: p, tolerance: SelectionReach.grab * perPoint) else { return false }
        if case .highlight = model.markups[i].kind { return false }
        model.selectMarkup(i)
        beginEdit(model.markups[i], handle: nil, at: p)
        return true
    }

    private func beginEdit(_ m: Markup, handle: Markup.Handle?, at p: CGPoint) {
        model.liftSelectedMarkup()
        edit = MarkupDrag(original: m, handle: handle, start: p, live: m)
    }

    /// The dragged drawing with the finger at `p` (full-image pixels): the handle there, or the whole drawing moved
    /// by as much as the finger, keeping its middle on the picture.
    private func dragged(_ e: MarkupDrag, to p: CGPoint) -> Markup {
        if let handle = e.handle { return e.original.moving(handle, to: clamped(p)) }
        let bounds = e.original.selectionBounds(imageWidth: Int(model.fullSize.width))
        guard !bounds.isNull else { return e.original }
        let mid = clamped(CGPoint(x: bounds.midX + p.x - e.start.x, y: bounds.midY + p.y - e.start.y))
        return e.original.offsetBy(dx: mid.x - bounds.midX, dy: mid.y - bounds.midY)
    }

    /// A reshaped drawing too small to see (an arrow with both ends together, a flat box) is not kept.
    private func isVisible(_ m: Markup) -> Bool {
        switch m.kind {
        case .arrow(let a, let b), .line(let a, let b): return hypot(b.x - a.x, b.y - a.y) >= 1
        case .rectangle(let r), .ellipse(let r), .highlight(let r): return r.width >= 1 && r.height >= 1
        case .pen, .text: return true
        }
    }

    private func touches(view: CGSize) -> CanvasTouches {
        // The rect is worked out at each touch, so it follows the zoom.
        func shown() -> CGRect { PreviewMapping.displayed(preview.size, in: view, zoom: zoom) }
        func point(_ p: CGPoint) -> CGPoint { imagePoint(p, shown()) }
        func perPoint() -> CGFloat { model.fullSize.width / max(shown().width, 1) }
        /// Decides, on the drag's first report, whether it draws or edits.
        func decide(_ start: CGPoint) {
            guard gesture == nil else { return }
            let edits = model.textSpot == nil && startEdit(at: point(start), perPoint: perPoint())
            gesture = edits ? .edit : .draw
        }
        func reset() {
            gesture = nil
            edit = nil
            dragStart = nil
            dragEnd = nil
            penPoints = []
        }
        return CanvasTouches(
            zoom: $zoom, preview: preview.size, view: view,
            onDraft: { start, current in
                decide(start)
                if var e = edit {
                    e.live = dragged(e, to: point(current))
                    edit = e
                    return
                }
                dragStart = start
                dragEnd = current
            },
            onDraftEnd: { start, end in
                decide(start)
                if let e = edit {
                    let live = dragged(e, to: point(end))
                    model.dropMarkup(isVisible(live) ? live : nil)
                    reset()
                    return
                }
                let stroke = penPoints
                reset()
                if model.textSpot != nil || model.tool == .text {
                    model.placeText(at: point(end))
                } else if model.tool == .pen {
                    model.drawPen(stroke)
                } else if PreviewMapping.isDrag(from: start, to: end) {
                    model.draw(from: point(start), to: point(end))
                }
            },
            onDraftCancel: {
                if edit != nil { model.dropMarkup(nil) }
                reset()
            },
            onTap: { p in
                let q = point(p)
                // While a label is typed, a tap moves it.
                if model.textSpot != nil {
                    model.placeText(at: q)
                    return
                }
                if let i = model.markupIndex(at: q, tolerance: SelectionReach.tap * perPoint()) {
                    if model.selection == .markup(i), model.canEditSelectedText {
                        model.editSelectedText()
                    } else {
                        model.selectMarkup(i)
                    }
                    return
                }
                if model.selection != nil {
                    model.deselect()
                    return
                }
                switch model.tool {
                case .text: model.placeText(at: q)
                case .pen: model.drawDot(at: q)
                default: break
                }
            },
            onDraftPoints: { path in
                if let first = path.first { decide(first) }
                guard gesture == .draw, model.tool == .pen, model.textSpot == nil else { return }
                var stroke = penPoints
                for p in path { model.addPenPoint(point(p), to: &stroke) }
                penPoints = stroke
            })
    }
}
