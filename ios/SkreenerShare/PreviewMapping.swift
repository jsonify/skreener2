import CoreGraphics

/// Where the Redact preview sits in its view, and how a touch on it maps to the full image. The view is in points
/// with a top-left origin; `preview` and `full` are the two images' sizes in pixels (the same shape), and full-image
/// pixels have a bottom-left origin, as Redaction and Vision's boxes do.
enum PreviewMapping {
    /// The preview's rect in the view when aspect-fitted and centred.
    static func fitted(_ preview: CGSize, in view: CGSize) -> CGRect {
        guard preview.width > 0, preview.height > 0 else { return .zero }
        let s = min(view.width / preview.width, view.height / preview.height)
        let size = CGSize(width: preview.width * s, height: preview.height * s)
        return CGRect(x: (view.width - size.width) / 2, y: (view.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// A view point as full-image pixels: view points to preview pixels (top-left origin), then flipped and scaled
    /// up to the full image. A point beside the picture maps outside the image.
    static func imagePoint(_ p: CGPoint, view: CGSize, preview: CGSize, full: CGSize) -> CGPoint {
        let fit = fitted(preview, in: view)
        guard fit.width > 0, fit.height > 0 else { return .zero }
        let px = (p.x - fit.minX) * preview.width / fit.width
        let py = (p.y - fit.minY) * preview.height / fit.height
        return CGPoint(x: px * full.width / preview.width, y: (preview.height - py) * full.height / preview.height)
    }

    /// The rect two view points span, as full-image pixels.
    static func imageRect(from a: CGPoint, to b: CGPoint, view: CGSize, preview: CGSize, full: CGSize) -> CGRect {
        let p = imagePoint(a, view: view, preview: preview, full: full)
        let q = imagePoint(b, view: view, preview: preview, full: full)
        return CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
    }

    /// A full-image rect back in view points, to outline it.
    static func viewRect(_ r: CGRect, view: CGSize, preview: CGSize, full: CGSize) -> CGRect {
        let fit = fitted(preview, in: view)
        guard full.width > 0, full.height > 0 else { return .zero }
        let sx = fit.width / full.width, sy = fit.height / full.height
        return CGRect(x: fit.minX + r.minX * sx, y: fit.minY + (full.height - r.maxY) * sy,
                      width: r.width * sx, height: r.height * sy)
    }
}
