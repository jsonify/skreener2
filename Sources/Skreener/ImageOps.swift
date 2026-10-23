import AppKit
import Vision

/// Whole-image changes in the editor: resizing (#122), cutting out a strip and removing the background (#121).
enum ImageOps {
    /// Smallest and largest side, in pixels, the image can be resized to.
    static let minPixels = 8
    static let maxPixels = 16_384

    /// Why `width` × `height` pixels can't be used, or nil when it can.
    static func resizeProblem(width: Int, height: Int) -> String? {
        if width < minPixels || height < minPixels { return "New size is too small (at least \(minPixels) px each way)." }
        if width > maxPixels || height > maxPixels { return "New size is too large (at most \(maxPixels) px each way)." }
        return nil
    }

    /// The other side for `side` when the proportions of `original` are kept (`side` is a width when `isWidth`).
    static func proportional(_ side: Int, isWidth: Bool, original: (width: Int, height: Int)) -> Int {
        guard original.width > 0, original.height > 0 else { return side }
        let ratio = Double(isWidth ? original.height : original.width) / Double(isWidth ? original.width : original.height)
        return max(1, Int((Double(side) * ratio).rounded()))
    }

    /// The image resampled to `width` × `height` pixels, keeping its pixel density (a Retina screenshot stays 2×).
    static func resized(_ img: NSImage, width: Int, height: Int) -> NSImage? {
        guard let cg = cgImage(img), width > 0, height > 0, let ctx = context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else { return nil }
        let sx = img.size.width / CGFloat(cg.width), sy = img.size.height / CGFloat(cg.height)
        return NSImage(cgImage: out, size: NSSize(width: CGFloat(width) * sx, height: CGFloat(height) * sy))
    }

    enum Axis { case horizontal, vertical }

    /// The image with a strip taken out and the parts on either side joined: rows `band` (from the top) for a
    /// horizontal strip, columns `band` (from the left) for a vertical one.
    static func removing(_ band: Range<Int>, axis: Axis, from img: NSImage) -> NSImage? {
        guard let cg = cgImage(img) else { return nil }
        let w = cg.width, h = cg.height, length = axis == .horizontal ? h : w
        let cut = band.clamped(to: 0..<length)
        guard !cut.isEmpty, cut.count < length else { return nil }
        let nw = axis == .horizontal ? w : w - cut.count, nh = axis == .horizontal ? h - cut.count : h
        guard let ctx = context(width: nw, height: nh) else { return nil }
        // CGContext has a bottom-left origin; `band` counts from the top or the left.
        switch axis {
        case .horizontal:
            if let top = cg.cropping(to: CGRect(x: 0, y: 0, width: w, height: cut.lowerBound)) {
                ctx.draw(top, in: CGRect(x: 0, y: nh - cut.lowerBound, width: w, height: cut.lowerBound))
            }
            if let bottom = cg.cropping(to: CGRect(x: 0, y: cut.upperBound, width: w, height: h - cut.upperBound)) {
                ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: w, height: h - cut.upperBound))
            }
        case .vertical:
            if let left = cg.cropping(to: CGRect(x: 0, y: 0, width: cut.lowerBound, height: h)) {
                ctx.draw(left, in: CGRect(x: 0, y: 0, width: cut.lowerBound, height: h))
            }
            if let right = cg.cropping(to: CGRect(x: cut.upperBound, y: 0, width: w - cut.upperBound, height: h)) {
                ctx.draw(right, in: CGRect(x: cut.lowerBound, y: 0, width: w - cut.upperBound, height: h))
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        let sx = img.size.width / CGFloat(w), sy = img.size.height / CGFloat(h)
        return NSImage(cgImage: out, size: NSSize(width: CGFloat(nw) * sx, height: CGFloat(nh) * sy))
    }

    /// Where a coordinate ends up once `lo...hi` is cut out: past the strip it moves back by the strip's length, inside
    /// it lands on the join, before it stays.
    static func afterCut(_ v: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        if v >= hi { return v - (hi - lo) }
        return v > lo ? lo : v
    }

    /// The image with everything but its subject (people, objects, a window: what Vision picks out) made transparent;
    /// nil when Vision finds no subject.
    static func removingBackground(_ img: NSImage) async -> NSImage? {
        guard let cg = cgImage(img) else { return nil }
        let size = img.size
        let masked = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil, let result = request.results?.first,
                  !result.allInstances.isEmpty,
                  let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                               croppedToInstancesExtent: false) else { return nil }
            let ci = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(ci, from: ci.extent)
        }.value
        return masked.map { NSImage(cgImage: $0, size: size) }
    }

    private static func cgImage(_ img: NSImage) -> CGImage? {
        var r = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
