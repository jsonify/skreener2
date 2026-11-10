import SK1Tokens
import SK1UI
import SkreenerCore
import SwiftUI

/// The Redact preview: the bare screenshot, aspect-fitted or zoomed. Drag to cover an area; tap a found match (orange
/// outline) to take it out or back in. Pinch, two-finger drag and double-tap zoom and pan (`CanvasTouches`).
///
/// Covered areas stay editable (#440): tap one to select it (corner handles, and a menu with Duplicate and Delete),
/// then drag it to move it or drag a corner to resize it; Pixelate, Blur and Solid then change its cover. A tap on
/// nothing deselects.
struct RedactCanvas: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    let preview: UIImage
    @Binding var zoom: PreviewZoom

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    /// The drag under way has decided whether it covers a new area or edits the selected one.
    @State private var decided = false
    /// The selected redaction being moved or resized.
    @State private var edit: RedactionDrag?

    /// A drag of a redaction: as it was, the corner dragged (nil to move it whole) and where the drag started
    /// (full-image pixels).
    private struct RedactionDrag {
        var original: Redaction
        var corner: Int?
        var start: CGPoint
    }

    var body: some View {
        GeometryReader { geo in
            let view = geo.size
            let shown = PreviewMapping.displayed(preview.size, in: view, zoom: zoom)
            ZStack(alignment: .topLeading) {
                PreviewImage(preview: preview, rect: shown,
                             label: "Preview. Drag to cover an area; tap a covered area to select it, then drag it, "
                                + "resize it or delete it. Pinch to zoom.")
                matches(shown, selected: true)
                    .stroke(orange, lineWidth: 2)
                matches(shown, selected: false)
                    .stroke(orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let band = band {
                    Path(band).fill(orange.opacity(0.15))
                    Path(band).stroke(orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                let selected = model.selectedRedaction.map {
                    PreviewMapping.viewRect($0.rect, image: shown, full: model.fullSize)
                }
                if let selected {
                    SelectionOutline(box: selected, handles: BoxHandles.corners(of: selected))
                }
                touches(view: view)
                    .frame(width: view.width, height: view.height)
                if edit == nil, let selected {
                    SelectionMenu(items: [
                        .init(title: "Duplicate") { model.duplicateSelection() },
                        .init(title: "Delete", destructive: true) { model.deleteSelection() },
                    ], target: selected, view: view)
                }
            }
            .frame(width: view.width, height: view.height, alignment: .topLeading)
            .clipped()
        }
    }

    private var orange: Color { Color(sk1Hex: SK1.orange) }

    /// The rubber band while dragging, once the drag is long enough to count.
    private var band: CGRect? {
        guard let a = dragStart, let b = dragEnd, PreviewMapping.isDrag(from: a, to: b) else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func matches(_ shown: CGRect, selected: Bool) -> Path {
        Path { path in
            for hit in finder.hits where hit.selected == selected {
                for box in hit.boxes {
                    path.addRect(PreviewMapping.viewRect(box, image: shown, full: model.fullSize))
                }
            }
        }
    }

    /// Starts moving or resizing the selected redaction if the drag starts on its corner or inside it (`p` in
    /// full-image pixels; `perPoint` is full pixels per view point).
    private func startEdit(at p: CGPoint, perPoint: CGFloat) -> Bool {
        guard let r = model.selectedRedaction else { return false }
        let reach = SelectionReach.handle * perPoint
        let corners = BoxHandles.corners(of: r.rect)
        let near = corners.indices
            .map { (corner: $0, distance: hypot(corners[$0].x - p.x, corners[$0].y - p.y)) }
            .filter { $0.distance <= reach }
            .min { $0.distance < $1.distance }
        let inside = r.rect.standardized.insetBy(dx: -SelectionReach.grab * perPoint,
                                                 dy: -SelectionReach.grab * perPoint).contains(p)
        guard near != nil || inside else { return false }
        model.beginRedactionEdit()
        edit = RedactionDrag(original: r, corner: near?.corner, start: p)
        return true
    }

    /// The dragged redaction with the finger at `p` (full-image pixels): the corner there, or the whole area moved by
    /// as much as the finger, kept on the picture.
    private func dragged(_ e: RedactionDrag, to p: CGPoint) -> Redaction {
        let full = model.fullSize
        if let corner = e.corner {
            let q = CGPoint(x: min(max(p.x, 0), full.width), y: min(max(p.y, 0), full.height))
            return e.original.moving(corner: corner, to: q)
        }
        let r = e.original.rect.standardized
        let dx = min(max(p.x - e.start.x, -r.minX), full.width - r.maxX)
        let dy = min(max(p.y - e.start.y, -r.minY), full.height - r.maxY)
        return e.original.offsetBy(dx: dx, dy: dy)
    }

    private func touches(view: CGSize) -> CanvasTouches {
        // The rect is worked out at each touch, so it follows the zoom.
        func shown() -> CGRect { PreviewMapping.displayed(preview.size, in: view, zoom: zoom) }
        func point(_ p: CGPoint) -> CGPoint { PreviewMapping.imagePoint(p, image: shown(), full: model.fullSize) }
        func decide(_ start: CGPoint) {
            guard !decided else { return }
            decided = true
            _ = startEdit(at: point(start), perPoint: model.fullSize.width / max(shown().width, 1))
        }
        func reset() {
            decided = false
            edit = nil
            dragStart = nil
            dragEnd = nil
        }
        return CanvasTouches(
            zoom: $zoom, preview: preview.size, view: view,
            onDraft: { start, current in
                decide(start)
                if let e = edit {
                    model.setSelectedRedaction(dragged(e, to: point(current)))
                    return
                }
                dragStart = start
                dragEnd = current
            },
            onDraftEnd: { start, end in
                decide(start)
                if let e = edit {
                    model.setSelectedRedaction(dragged(e, to: point(end)))
                    model.endRedactionEdit(original: e.original)
                    reset()
                    return
                }
                reset()
                guard PreviewMapping.isDrag(from: start, to: end) else { return }
                model.redact([PreviewMapping.imageRect(from: start, to: end, image: shown(), full: model.fullSize)])
            },
            onDraftCancel: {
                if let e = edit { model.cancelRedactionEdit(original: e.original) }
                reset()
            },
            onTap: { p in
                let q = point(p)
                if finder.toggle(at: q) { return }
                let perPoint = model.fullSize.width / max(shown().width, 1)
                if let i = model.redactionIndex(at: q, tolerance: SelectionReach.grab * perPoint) {
                    model.selectRedaction(i)
                } else {
                    model.deselect()
                }
            })
    }
}
