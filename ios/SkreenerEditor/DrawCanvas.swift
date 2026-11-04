import SK1Tokens
import SK1UI
import SkreenerCore
import SwiftUI

/// The Draw preview: the screenshot with its redactions and drawings, aspect-fitted. Drag to draw an arrow, rectangle
/// or highlight (the shape follows the finger); with the Text tool, tap where the label goes.
struct DrawCanvas: View {
    @ObservedObject var model: ShareModel
    let preview: UIImage

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let view = geo.size
            let fit = PreviewMapping.fitted(preview.size, in: view)
            let toView = PreviewMapping.imageToView(view: view, preview: preview.size, full: model.fullSize)
            let draft = self.draft(view: view)
            let width = Int(model.fullSize.width)
            ZStack(alignment: .topLeading) {
                PreviewImage(preview: preview, fit: fit,
                             label: "Preview. Drag to draw; with the Text tool, tap where the text goes.")
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
            }
            .frame(width: view.width, height: view.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(drag(view: view))
        }
    }

    /// The shape under the finger, once the drag is long enough to count; otherwise the label being typed.
    private func draft(view: CGSize) -> Markup? {
        if let a = dragStart, let b = dragEnd, model.tool != .text, PreviewMapping.isDrag(from: a, to: b) {
            return model.shape(from: imagePoint(a, view: view), to: imagePoint(b, view: view))
        }
        return model.draftMarkup
    }

    private func imagePoint(_ p: CGPoint, view: CGSize) -> CGPoint {
        PreviewMapping.imagePoint(p, view: view, preview: preview.size, full: model.fullSize)
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
                if model.tool == .text {
                    model.placeText(at: imagePoint(value.location, view: view))
                } else if PreviewMapping.isDrag(from: value.startLocation, to: value.location) {
                    model.draw(from: imagePoint(value.startLocation, view: view),
                               to: imagePoint(value.location, view: view))
                }
            }
    }
}
