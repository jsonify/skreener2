import CoreGraphics
import Foundation

/// An sRGB color with components from 0 to 1, as the editor's color picker, ruler and contrast checker read them.
struct RGBColor: Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1

    /// 8-bit channel values (0–255).
    init(r8: Int, g8: Int, b8: Int, a8: Int = 255) {
        self.init(r: Double(r8) / 255, g: Double(g8) / 255, b: Double(b8) / 255, a: Double(a8) / 255)
    }

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// A channel as 0–255.
    static func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }

    /// WCAG 2 relative luminance (linear-light, 0 for black, 1 for white).
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

/// A screenshot's pixels as 8-bit sRGB RGBA, row 0 at the top, read once so the editor can look at single pixels as
/// the pointer moves (the color picker, the ruler) or at an area (average color, contrast).
struct PixelBuffer: Sendable {
    let width: Int
    let height: Int
    /// Premultiplied RGBA, four bytes per pixel.
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w; height = h; data = buf
    }

    func contains(x: Int, y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    /// The raw (premultiplied) bytes of a pixel, for quick comparisons.
    func rgba(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    /// The color of one pixel (top-left origin), or nil outside the image.
    func color(x: Int, y: Int) -> RGBColor? {
        guard contains(x: x, y: y) else { return nil }
        let p = rgba(x: x, y: y)
        return Self.unpremultiplied(r: Double(p.r), g: Double(p.g), b: Double(p.b), a: Double(p.a))
    }

    /// The darkest pixel (lowest luminance) within `radius` pixels of (x, y) each way, e.g. the text color under the
    /// pointer even when it sits between two strokes.
    func darkest(x: Int, y: Int, radius: Int = 10) -> RGBColor? {
        guard contains(x: x, y: y), radius >= 0 else { return nil }
        var best: RGBColor?, bestLum = Double.infinity
        for yy in max(y - radius, 0)...min(y + radius, height - 1) {
            for xx in max(x - radius, 0)...min(x + radius, width - 1) {
                guard let c = color(x: xx, y: yy), c.a > 0 else { continue }
                let lum = c.luminance
                if lum < bestLum { bestLum = lum; best = c }
            }
        }
        return best
    }

    /// The pixel rect (top-left origin) clipped to the image; nil when nothing is left.
    private func clipped(_ rect: CGRect) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return (Int(r.minX), Int(r.minY), Int(r.maxX), Int(r.maxY))
    }

    /// The mean of the sRGB values in `rect` (pixels, top-left origin): half black, half white gives #808080.
    func average(in rect: CGRect) -> RGBColor? {
        guard let c = clipped(rect) else { return nil }
        var r = 0, g = 0, b = 0, a = 0
        for y in c.y0..<c.y1 {
            for x in c.x0..<c.x1 {
                let p = rgba(x: x, y: y)
                r += p.r; g += p.g; b += p.b; a += p.a
            }
        }
        return Self.unpremultiplied(r: Double(r), g: Double(g), b: Double(b), a: Double(a), count: (c.x1 - c.x0) * (c.y1 - c.y0))
    }

    /// The two colors that make up `rect` (pixels, top-left origin): the most common one, taken as the background, and
    /// the one that stands out most against it among the others that cover a fair share of the area (text, an icon).
    /// Colors are grouped at 4 bits per channel, so anti-aliasing counts as its color; each is the mean of its group.
    /// With a single color, both are that color.
    func dominantColors(in rect: CGRect) -> (background: RGBColor, foreground: RGBColor)? {
        guard let c = clipped(rect) else { return nil }
        var groups: [Int: (count: Int, r: Int, g: Int, b: Int, a: Int)] = [:]
        for y in c.y0..<c.y1 {
            for x in c.x0..<c.x1 {
                let p = rgba(x: x, y: y)
                let key = (p.r >> 4) << 8 | (p.g >> 4) << 4 | (p.b >> 4)
                var s = groups[key] ?? (count: 0, r: 0, g: 0, b: 0, a: 0)
                s.count += 1; s.r += p.r; s.g += p.g; s.b += p.b; s.a += p.a
                groups[key] = s
            }
        }
        let total = (c.x1 - c.x0) * (c.y1 - c.y0)
        let colors = groups.values.sorted { $0.count > $1.count }.map { s in
            (count: s.count, color: Self.unpremultiplied(r: Double(s.r), g: Double(s.g), b: Double(s.b), a: Double(s.a), count: s.count))
        }
        guard let bg = colors.first else { return nil }
        // Thin text covers only a few percent of a box around it.
        let minShare = max(1, total / 200)
        let fg = colors.dropFirst().filter { $0.count >= minShare }
            .max { Contrast.wcag($0.color, bg.color) < Contrast.wcag($1.color, bg.color) }
        return (bg.color, fg?.color ?? bg.color)
    }

    /// Sums of the premultiplied channels of `count` pixels, as their mean straight-alpha color.
    private static func unpremultiplied(r: Double, g: Double, b: Double, a: Double, count: Int = 1) -> RGBColor {
        guard a > 0, count > 0 else { return RGBColor(r: 0, g: 0, b: 0, a: 0) }
        // Dividing by the alpha sum undoes the premultiplication and the averaging at once.
        return RGBColor(r: min(r / a, 1), g: min(g / a, 1), b: min(b / a, 1), a: a / 255 / Double(count))
    }
}
