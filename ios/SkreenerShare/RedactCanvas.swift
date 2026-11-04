import SK1Tokens
import SK1UI
import SwiftUI

/// The Redact preview: the bare screenshot, aspect-fitted. Drag to cover an area; tap a found match (orange outline)
/// to take it out or back in.
struct RedactCanvas: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    let preview: UIImage

    /// Smaller drags are taps.
    private static let minDrag: CGFloat = 8

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let view = geo.size
            let fit = PreviewMapping.fitted(preview.size, in: view)
            ZStack(alignment: .topLeading) {
                Image(uiImage: preview)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .offset(x: fit.minX, y: fit.minY)
                    .accessibilityLabel(Text("Preview. Drag to cover an area."))
                matches(view: view, selected: true)
                    .stroke(orange, lineWidth: 2)
                matches(view: view, selected: false)
                    .stroke(orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let band = band {
                    Path(band).fill(orange.opacity(0.15))
                    Path(band).stroke(orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
            .frame(width: view.width, height: view.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(drag(view: view))
        }
    }

    private var orange: Color { Color(sk1Hex: SK1.orange) }

    /// The rubber band while dragging, once the drag is long enough to count.
    private var band: CGRect? {
        guard let a = dragStart, let b = dragEnd, Self.isDrag(from: a, to: b) else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private static func isDrag(from a: CGPoint, to b: CGPoint) -> Bool {
        abs(a.x - b.x) >= minDrag || abs(a.y - b.y) >= minDrag
    }

    private func matches(view: CGSize, selected: Bool) -> Path {
        Path { path in
            for hit in finder.hits where hit.selected == selected {
                for box in hit.boxes {
                    path.addRect(PreviewMapping.viewRect(box, view: view, preview: preview.size, full: model.fullSize))
                }
            }
        }
    }

    private func drag(view: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragStart = value.startLocation
                dragEnd = value.location
            }
            .onEnded { value in
                dragStart = nil
                dragEnd = nil
                let size = preview.size, full = model.fullSize
                if Self.isDrag(from: value.startLocation, to: value.location) {
                    model.redact([PreviewMapping.imageRect(from: value.startLocation, to: value.location, view: view,
                                                           preview: size, full: full)])
                } else {
                    finder.toggle(at: PreviewMapping.imagePoint(value.location, view: view, preview: size, full: full))
                }
            }
    }
}
