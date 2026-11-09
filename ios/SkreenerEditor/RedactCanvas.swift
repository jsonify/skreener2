import SK1Tokens
import SK1UI
import SwiftUI

/// The Redact preview: the bare screenshot, aspect-fitted or zoomed. Drag to cover an area; tap a found match (orange
/// outline) to take it out or back in. Pinch, two-finger drag and double-tap zoom and pan (`CanvasTouches`).
struct RedactCanvas: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    let preview: UIImage
    @Binding var zoom: PreviewZoom

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let view = geo.size
            let shown = PreviewMapping.displayed(preview.size, in: view, zoom: zoom)
            ZStack(alignment: .topLeading) {
                PreviewImage(preview: preview, rect: shown, label: "Preview. Drag to cover an area. Pinch to zoom.")
                matches(shown, selected: true)
                    .stroke(orange, lineWidth: 2)
                matches(shown, selected: false)
                    .stroke(orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let band = band {
                    Path(band).fill(orange.opacity(0.15))
                    Path(band).stroke(orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                touches(view: view)
                    .frame(width: view.width, height: view.height)
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

    private func touches(view: CGSize) -> CanvasTouches {
        // The rect is worked out at each touch, so it follows the zoom.
        func shown() -> CGRect { PreviewMapping.displayed(preview.size, in: view, zoom: zoom) }
        return CanvasTouches(
            zoom: $zoom, preview: preview.size, view: view,
            onDraft: { start, current in
                dragStart = start
                dragEnd = current
            },
            onDraftEnd: { start, end in
                dragStart = nil
                dragEnd = nil
                guard PreviewMapping.isDrag(from: start, to: end) else { return }
                model.redact([PreviewMapping.imageRect(from: start, to: end, image: shown(), full: model.fullSize)])
            },
            onDraftCancel: {
                dragStart = nil
                dragEnd = nil
            },
            onTap: { p in
                finder.toggle(at: PreviewMapping.imagePoint(p, image: shown(), full: model.fullSize))
            })
    }
}
