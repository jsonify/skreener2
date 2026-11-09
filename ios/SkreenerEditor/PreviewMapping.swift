import CoreGraphics

/// How far the Redact and Draw previews are zoomed and panned (#441). Scale 1 is the aspect fit.
struct PreviewZoom: Equatable {
    static let maxScale: CGFloat = 6
    /// A double-tap at fit zooms to this.
    static let tapScale: CGFloat = 2.5

    var scale: CGFloat = 1
    /// From the view's centre to the picture's, in points.
    var offset: CGSize = .zero

    var isZoomed: Bool { scale > 1.001 }
}

/// Where the Redact and Draw previews sit in their view, and how a touch on them maps to the full image. The view is
/// in points with a top-left origin; `image` is the rect the preview is shown at in the view (`displayed`), `preview`
/// and `full` are the two images' sizes in pixels (the same shape), and full-image pixels have a bottom-left origin,
/// as Redaction and Vision's boxes do.
enum PreviewMapping {
    /// Smaller drags are taps.
    static let minDrag: CGFloat = 8

    static func isDrag(from a: CGPoint, to b: CGPoint) -> Bool {
        abs(a.x - b.x) >= minDrag || abs(a.y - b.y) >= minDrag
    }

    /// The preview's rect in the view when aspect-fitted and centred.
    static func fitted(_ preview: CGSize, in view: CGSize) -> CGRect {
        guard preview.width > 0, preview.height > 0 else { return .zero }
        let s = min(view.width / preview.width, view.height / preview.height)
        let size = CGSize(width: preview.width * s, height: preview.height * s)
        return CGRect(x: (view.width - size.width) / 2, y: (view.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The preview's rect in the view at `zoom`: the fitted rect scaled up and moved by the offset. Along each side the
    /// picture is wider than the view it leaves no gap at either end; along a side it fits, it stays centred.
    static func displayed(_ preview: CGSize, in view: CGSize, zoom: PreviewZoom) -> CGRect {
        let fit = fitted(preview, in: view)
        let w = fit.width * zoom.scale, h = fit.height * zoom.scale
        let x = origin(view.width / 2 + zoom.offset.width - w / 2, length: w, in: view.width)
        let y = origin(view.height / 2 + zoom.offset.height - h / 2, length: h, in: view.height)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// One side's origin, kept as `displayed` says.
    private static func origin(_ o: CGFloat, length: CGFloat, in span: CGFloat) -> CGFloat {
        length <= span ? (span - length) / 2 : min(max(o, span - length), 0)
    }

    /// `zoom` scaled by `factor` (kept between fit and the maximum) about the view point `anchor`, which stays over the
    /// same spot of the picture.
    static func zoom(_ zoom: PreviewZoom, by factor: CGFloat, at anchor: CGPoint, preview: CGSize,
                     view: CGSize) -> PreviewZoom {
        let rect = displayed(preview, in: view, zoom: zoom)
        let scale = min(max(zoom.scale * factor, 1), PreviewZoom.maxScale)
        let f = scale / zoom.scale
        let mid = CGPoint(x: anchor.x + (rect.midX - anchor.x) * f, y: anchor.y + (rect.midY - anchor.y) * f)
        return settled(scale: scale, mid: mid, preview: preview, view: view)
    }

    /// `zoom` moved by `delta` points.
    static func pan(_ zoom: PreviewZoom, by delta: CGSize, preview: CGSize, view: CGSize) -> PreviewZoom {
        let rect = displayed(preview, in: view, zoom: zoom)
        let mid = CGPoint(x: rect.midX + delta.width, y: rect.midY + delta.height)
        return settled(scale: zoom.scale, mid: mid, preview: preview, view: view)
    }

    /// The zoom with the picture's centre at `mid`, kept as `displayed` keeps it, so a pan past an edge doesn't build
    /// up an offset that has to be taken back first.
    private static func settled(scale: CGFloat, mid: CGPoint, preview: CGSize, view: CGSize) -> PreviewZoom {
        let wanted = PreviewZoom(scale: scale, offset: CGSize(width: mid.x - view.width / 2,
                                                              height: mid.y - view.height / 2))
        let rect = displayed(preview, in: view, zoom: wanted)
        return PreviewZoom(scale: scale, offset: CGSize(width: rect.midX - view.width / 2,
                                                        height: rect.midY - view.height / 2))
    }

    /// A view point as full-image pixels, flipped to a bottom-left origin. A point beside the picture maps outside
    /// the image.
    static func imagePoint(_ p: CGPoint, image: CGRect, full: CGSize) -> CGPoint {
        guard image.width > 0, image.height > 0 else { return .zero }
        return CGPoint(x: (p.x - image.minX) * full.width / image.width,
                       y: (image.maxY - p.y) * full.height / image.height)
    }

    /// The rect two view points span, as full-image pixels.
    static func imageRect(from a: CGPoint, to b: CGPoint, image: CGRect, full: CGSize) -> CGRect {
        let p = imagePoint(a, image: image, full: full)
        let q = imagePoint(b, image: image, full: full)
        return CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
    }

    /// A full-image rect back in view points, to outline it.
    static func viewRect(_ r: CGRect, image: CGRect, full: CGSize) -> CGRect {
        guard full.width > 0, full.height > 0 else { return .zero }
        let sx = image.width / full.width, sy = image.height / full.height
        return CGRect(x: image.minX + r.minX * sx, y: image.minY + (full.height - r.maxY) * sy,
                      width: r.width * sx, height: r.height * sy)
    }

    /// Full-image pixels (bottom-left origin) to view points, to draw full-size shapes over the preview.
    static func imageToView(image: CGRect, full: CGSize) -> CGAffineTransform {
        guard full.width > 0, full.height > 0 else { return .identity }
        return CGAffineTransform(a: image.width / full.width, b: 0, c: 0, d: -image.height / full.height,
                                 tx: image.minX, ty: image.maxY)
    }
}
