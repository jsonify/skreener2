import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The touch layer over the Redact and Draw previews (#441), in UIKit so one finger and two never fight. Pinch zooms
/// about the pinch and two fingers pan, through `zoom`; a double-tap zooms in at the tap, or back to fit. One finger
/// drags a draft (`onDraft` while it moves, `onDraftEnd` on release) or taps (`onTap`). A second finger cancels the
/// draft (`onDraftCancel`), so a pinch never leaves a stray box or arrow. A single tap waits for a double-tap to fail,
/// so a double-tap doesn't also tap. Points are in the canvas, which this layer covers.
struct CanvasTouches: UIViewRepresentable {
    @Binding var zoom: PreviewZoom
    let preview: CGSize
    let view: CGSize
    let onDraft: (_ start: CGPoint, _ current: CGPoint) -> Void
    let onDraftEnd: (_ start: CGPoint, _ end: CGPoint) -> Void
    let onDraftCancel: () -> Void
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let surface = UIView()
        surface.backgroundColor = .clear
        surface.isMultipleTouchEnabled = true
        let c = context.coordinator
        let draft = DraftRecognizer(target: c, action: #selector(Coordinator.draft(_:)))
        let doubleTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: doubleTap)
        tap.require(toFail: draft)
        doubleTap.require(toFail: draft)
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        for g in [draft, doubleTap, tap, pinch, pan] {
            g.delegate = c
            surface.addGestureRecognizer(g)
        }
        return surface
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasTouches

        init(_ parent: CanvasTouches) {
            self.parent = parent
        }

        @objc func draft(_ g: DraftRecognizer) {
            switch g.state {
            case .began, .changed: parent.onDraft(g.start, g.current)
            case .ended: parent.onDraftEnd(g.start, g.current)
            default: parent.onDraftCancel()
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap(g.location(in: g.view))
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            let p = parent
            if p.zoom.isZoomed {
                p.zoom = PreviewZoom()
            } else {
                p.zoom = PreviewMapping.zoom(p.zoom, by: PreviewZoom.tapScale / p.zoom.scale, at: g.location(in: g.view),
                                             preview: p.preview, view: p.view)
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .began || g.state == .changed, g.numberOfTouches >= 2 else { return }
            let p = parent
            p.zoom = PreviewMapping.zoom(p.zoom, by: g.scale, at: g.location(in: g.view), preview: p.preview,
                                         view: p.view)
            g.scale = 1
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard g.state == .began || g.state == .changed else { return }
            let t = g.translation(in: g.view)
            let p = parent
            p.zoom = PreviewMapping.pan(p.zoom, by: CGSize(width: t.x, height: t.y), preview: p.preview, view: p.view)
            g.setTranslation(.zero, in: g.view)
        }

        /// All at once: the pinch and the pan run together, and either can take over from a draft, which then
        /// cancels itself.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// One finger dragging: begins once it has moved `PreviewMapping.minDrag` points from where it landed (a shorter
/// touch fails, and is a tap), and cancels, or fails, as soon as a second finger lands.
final class DraftRecognizer: UIGestureRecognizer {
    /// Where the finger landed and where it is now, in the view.
    private(set) var start: CGPoint = .zero
    private(set) var current: CGPoint = .zero
    private var finger: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard finger == nil, touches.count == 1, let touch = touches.first else {
            stop()
            return
        }
        finger = touch
        start = touch.location(in: view)
        current = start
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let finger, touches.contains(finger) else { return }
        current = finger.location(in: view)
        if state == .possible {
            if PreviewMapping.isDrag(from: start, to: current) { state = .began }
        } else if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let finger, touches.contains(finger) else { return }
        current = finger.location(in: view)
        state = isDragging ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        stop()
    }

    override func reset() {
        super.reset()
        finger = nil
    }

    private var isDragging: Bool { state == .began || state == .changed }

    /// Drops the draft without making anything.
    private func stop() {
        if isDragging {
            state = .cancelled
        } else if state == .possible {
            state = .failed
        }
    }
}
