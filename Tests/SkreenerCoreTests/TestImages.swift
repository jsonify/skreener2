import CoreGraphics

/// Images drawn in code for the tests, with CoreGraphics only (SkreenerCore has no AppKit).
enum TestImages {
    /// A `width` × `height` pixel sRGB bitmap drawn by `draw` in pixel coordinates (bottom-left origin).
    static func image(width: Int, height: Int, draw: (CGContext, CGRect) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    static let white = srgb(1, 1, 1), black = srgb(0, 0, 0), red = srgb(1, 0, 0), blue = srgb(0, 0, 1)
}
