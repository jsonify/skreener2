import CoreGraphics

/// Smart Erase: fills a box with the background around it, so the content looks as if it was never there.
enum SmartErase {
    /// The most common color in the one-pixel ring just outside `rect` (pixels, top-left origin, like
    /// `CGImage.cropping`), averaged over the pixels of that color. Colors are grouped at 5 bits per channel, so
    /// anti-aliasing and compression noise still count as the same color. Parts of the ring outside the image are
    /// skipped; nil when none of it is inside.
    static func fillColor(around rect: CGRect, in image: CGImage) -> CGColor? {
        let ring = rect.integral.insetBy(dx: -1, dy: -1)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // Top and bottom rows, then the left and right columns between them.
        let strips = [CGRect(x: ring.minX, y: ring.minY, width: ring.width, height: 1),
                      CGRect(x: ring.minX, y: ring.maxY - 1, width: ring.width, height: 1),
                      CGRect(x: ring.minX, y: ring.minY + 1, width: 1, height: ring.height - 2),
                      CGRect(x: ring.maxX - 1, y: ring.minY + 1, width: 1, height: ring.height - 2)]
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int, a: Int)] = [:]
        for strip in strips {
            for px in pixels(of: image, in: strip.intersection(bounds)) {
                let key = (px.r >> 3) << 15 | (px.g >> 3) << 10 | (px.b >> 3) << 5 | (px.a >> 3)
                var s = buckets[key] ?? (count: 0, r: 0, g: 0, b: 0, a: 0)
                s.count += 1; s.r += px.r; s.g += px.g; s.b += px.b; s.a += px.a
                buckets[key] = s
            }
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let n = CGFloat(best.count)
        let alpha = CGFloat(best.a) / n / 255
        // The samples are premultiplied.
        func channel(_ sum: Int) -> CGFloat { alpha > 0 ? min(CGFloat(sum) / n / 255 / alpha, 1) : 0 }
        return CGColor(srgbRed: channel(best.r), green: channel(best.g), blue: channel(best.b), alpha: alpha)
    }

    /// The sRGB, premultiplied RGBA pixels of `area` (pixels, top-left origin; empty when it is).
    private static func pixels(of image: CGImage, in area: CGRect) -> [(r: Int, g: Int, b: Int, a: Int)] {
        guard !area.isEmpty, let crop = image.cropping(to: area),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let w = crop.width, h = crop.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: buf.count, by: 4).map { i in
            (r: Int(buf[i]), g: Int(buf[i + 1]), b: Int(buf[i + 2]), a: Int(buf[i + 3]))
        }
    }
}
