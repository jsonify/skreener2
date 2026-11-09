import SK1Tokens
import SK1UI
import SkreenerCore
import SwiftUI

/// The Draw preview: the screenshot with its redactions and drawings, aspect-fitted or zoomed. Drag to draw an arrow,
/// line, rectangle, ellipse or highlight (the shape follows the finger); with Pen, draw freely (the stroke follows the
/// finger; a tap is a dot); with the Text tool, tap where the label goes. Pinch, two-finger drag and double-tap zoom
/// and pan (`CanvasTouches`); a pinch drops the shape or stroke being drawn.
struct DrawCanvas: View {
    @ObservedObject var model: ShareModel
    let preview: UIImage
    @Binding var zoom: PreviewZoom

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    /// The pen stroke being drawn, in full-image pixels.
    @State private var penPoints: [CGPoint] = []

    var body: some View {
        GeometryReader { geo in
            let view = geo.size
            let shown = PreviewMapping.displayed(preview.size, in: view, zoom: zoom)
            let toView = PreviewMapping.imageToView(image: shown, full: model.fullSize)
            let draft = self.draft(shown)
            let width = Int(model.fullSize.width)
            ZStack(alignment: .topLeading) {
                PreviewImage(preview: preview, rect: shown,
                             label: "Preview. Drag to draw; with the Text tool, tap where the text goes. Pinch to zoom.")
                // The shape being drawn, or the label being typed, drawn as the export will draw it.
                Canvas { context, _ in
                    guard let draft else { return }
                    context.withCGContext { cg in
                        cg.concatenate(toView)
                        Markup.draw([draft], imageWidth: width, in: cg)
                    }
                }
                .allowsHitTesting(false)
                if let spot = model.textSpot {
                    Circle()
                        .stroke(Color(sk1Hex: SK1.orange), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .position(spot.applying(toView))
                        .allowsHitTesting(false)
                }
                touches(view: view)
                    .frame(width: view.width, height: view.height)
            }
            .frame(width: view.width, height: view.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// The shape or pen stroke under the finger, once the drag is long enough to count; otherwise the label being
    /// typed.
    private func draft(_ shown: CGRect) -> Markup? {
        if model.tool == .pen { return model.penStroke(penPoints) }
        if let a = dragStart, let b = dragEnd, model.tool != .text, PreviewMapping.isDrag(from: a, to: b) {
            return model.shape(from: imagePoint(a, shown), to: imagePoint(b, shown))
        }
        return model.draftMarkup
    }

    private func imagePoint(_ p: CGPoint, _ shown: CGRect) -> CGPoint {
        PreviewMapping.imagePoint(p, image: shown, full: model.fullSize)
    }

    private func touches(view: CGSize) -> CanvasTouches {
        // The rect is worked out at each touch, so it follows the zoom.
        func point(_ p: CGPoint) -> CGPoint {
            imagePoint(p, PreviewMapping.displayed(preview.size, in: view, zoom: zoom))
        }
        return CanvasTouches(
            zoom: $zoom, preview: preview.size, view: view,
            onDraft: { start, current in
                dragStart = start
                dragEnd = current
            },
            onDraftEnd: { start, end in
                dragStart = nil
                dragEnd = nil
                if model.tool == .pen {
                    let stroke = penPoints
                    penPoints = []
                    model.drawPen(stroke)
                } else if model.tool == .text {
                    model.placeText(at: point(end))
                } else if PreviewMapping.isDrag(from: start, to: end) {
                    model.draw(from: point(start), to: point(end))
                }
            },
            onDraftCancel: {
                dragStart = nil
                dragEnd = nil
                penPoints = []
            },
            onTap: { p in
                switch model.tool {
                case .text: model.placeText(at: point(p))
                case .pen: model.drawDot(at: point(p))
                default: break
                }
            },
            onDraftPoints: { path in
                guard model.tool == .pen else { return }
                var stroke = penPoints
                for p in path { model.addPenPoint(point(p), to: &stroke) }
                penPoints = stroke
            })
    }
}
