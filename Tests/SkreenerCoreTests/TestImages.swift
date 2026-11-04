import CoreGraphics
import CoreText

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

    /// A bitmap's size in points when shown at 1x, as the OCR calls take it.
    static func size(of image: CGImage) -> CGSize { CGSize(width: image.width, height: image.height) }

    /// Black 48 pt text on white, one line per 120 px band (the first line at the top).
    static func text(_ lines: [String]) -> CGImage {
        image(width: 1000, height: 120 * lines.count) { ctx, r in
            ctx.setFillColor(white)
            ctx.fill(r)
            let attrs: [CFString: Any] = [kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 48, nil),
                                          kCTForegroundColorAttributeName: black]
            for (i, line) in lines.enumerated() {
                let string = CFAttributedStringCreate(nil, line as CFString, attrs as CFDictionary)!
                let ctLine = CTLineCreateWithAttributedString(string)
                ctx.textPosition = CGPoint(x: 40, y: r.height - CGFloat(i + 1) * 120 + 30)
                CTLineDraw(ctLine, ctx)
            }
        }
    }
}
