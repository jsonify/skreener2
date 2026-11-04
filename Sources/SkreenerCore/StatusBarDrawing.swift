import CoreGraphics
import CoreText
import Foundation

extension StatusBar {
    /// `image` with its status bar repainted: the bar's own background, then 9:41, full signal, Wi-Fi and battery in
    /// black or white, whichever stands out more. Everything below the bar is left as it was. `layout` defaults to the
    /// one for the image's size; nil when there is none, or the bar is outside the image.
    public static func clean(_ image: CGImage, layout: Layout? = nil) -> CGImage? {
        guard let layout = layout ?? Self.layout(forPixelWidth: image.width, height: image.height) else { return nil }
        let w = image.width, h = image.height
        let bar = layout.bar.integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !bar.isNull, bar.width >= 1, bar.height >= 1,
              let bg = background(of: image, in: bar),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let fg = ink(on: bg)
        let full = CGFloat(h)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        ctx.saveGState()
        // Top-left coordinates from here on, like the layout.
        ctx.translateBy(x: 0, y: full)
        ctx.scaleBy(x: 1, y: -1)
        ctx.clip(to: bar)
        ctx.setBlendMode(.copy)
        ctx.setFillColor(cgColor(bg))
        ctx.fill(bar)
        ctx.setBlendMode(.normal)
        let items = glyphs(for: layout)
        let inkColor = cgColor(fg)
        drawSignal(in: items.signal, color: inkColor, ctx: ctx)
        drawWifi(in: items.wifi, color: inkColor, ctx: ctx)
        drawBattery(in: items.battery, color: fg, ctx: ctx)
        ctx.restoreGState()

        // Text in the context's own y-up space, so the glyphs stay upright.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: bar.minX, y: full - bar.maxY, width: bar.width, height: bar.height))
        let time = items.time
        drawTime(in: CGRect(x: time.minX, y: full - time.maxY, width: time.width, height: time.height),
                 color: inkColor, ctx: ctx)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// The most common color in `rect` (pixels, top-left origin), averaged over the pixels of that color. Colors are
    /// grouped at 5 bits per channel, as Smart Erase does, so anti-aliasing and compression noise count as one color.
    static func background(of image: CGImage, in rect: CGRect) -> RGBColor? {
        guard let crop = image.cropping(to: rect), let pixels = PixelBuffer(crop) else { return nil }
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int, a: Int)] = [:]
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let p = pixels.rgba(x: x, y: y)
                let hi: Int = (p.r >> 3) << 15 | (p.g >> 3) << 10
                let key: Int = hi | (p.b >> 3) << 5 | (p.a >> 3)
                var s = buckets[key] ?? (count: 0, r: 0, g: 0, b: 0, a: 0)
                s.count += 1; s.r += p.r; s.g += p.g; s.b += p.b; s.a += p.a
                buckets[key] = s
            }
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }), best.a > 0 else {
            return RGBColor(r: 0, g: 0, b: 0, a: 0)
        }
        // The samples are premultiplied: dividing by the alpha sum undoes that and the averaging at once.
        let a = Double(best.a)
        return RGBColor(r: min(Double(best.r) / a, 1), g: min(Double(best.g) / a, 1), b: min(Double(best.b) / a, 1),
                        a: a / 255 / Double(best.count))
    }

    /// Black or white, whichever contrasts more with `background`.
    static func ink(on background: RGBColor) -> RGBColor {
        let white = RGBColor(r: 1, g: 1, b: 1), black = RGBColor(r: 0, g: 0, b: 0)
        return Contrast.wcag(white, background) > Contrast.wcag(black, background) ? white : black
    }

    private static func cgColor(_ c: RGBColor, alpha k: Double = 1) -> CGColor {
        CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a * k)
    }

    /// Four bars rising left to right, bottom-aligned.
    private static func drawSignal(in r: CGRect, color: CGColor, ctx: CGContext) {
        let gap = r.width * 1.7 / 17, barWidth = (r.width - 3 * gap) / 4
        let heights: [CGFloat] = [0.36, 0.57, 0.79, 1]
        let path = CGMutablePath()
        for (i, k) in heights.enumerated() {
            let bh = r.height * k
            let rect = CGRect(x: r.minX + CGFloat(i) * (barWidth + gap), y: r.maxY - bh, width: barWidth, height: bh)
            let radius = min(barWidth * 0.35, bh / 2)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// The Wi-Fi fan: a quarter-circle sector split into a dot and two arcs, pointing down to the bottom middle.
    private static func drawWifi(in r: CGRect, color: CGColor, ctx: CGContext) {
        let apex = CGPoint(x: r.midX, y: r.maxY)
        let radius = min(r.height, r.width / 2 / sin(CGFloat.pi / 4))
        // Up is -y here (top-left coordinates).
        let a0 = -CGFloat.pi * 3 / 4, a1 = -CGFloat.pi / 4
        let band = radius * 0.22
        let path = CGMutablePath()
        for i in 0..<3 {
            let outer = radius * CGFloat(i + 1) / 3
            let inner = i == 0 ? 0 : outer - band
            path.move(to: CGPoint(x: apex.x + inner * cos(a0), y: apex.y + inner * sin(a0)))
            path.addArc(center: apex, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
            if inner > 0 {
                path.addArc(center: apex, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
            } else {
                path.addLine(to: apex)
            }
            path.closeSubpath()
        }
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// A rounded outline (faint, as iOS draws it), filled to the end, with a small nub on the right.
    private static func drawBattery(in r: CGRect, color: RGBColor, ctx: CGContext) {
        let unit = r.height / batterySize.height
        let nubWidth = 1.33 * unit, nubGap = 1 * unit
        let body = CGRect(x: r.minX, y: r.minY, width: r.width - nubWidth - nubGap, height: r.height)
        let line = 1 * unit
        let outline = body.insetBy(dx: line / 2, dy: line / 2)
        let outer = min(4.3 * unit, outline.height / 2)
        ctx.setStrokeColor(cgColor(color, alpha: 0.4))
        ctx.setLineWidth(line)
        ctx.addPath(CGPath(roundedRect: outline, cornerWidth: outer, cornerHeight: outer, transform: nil))
        ctx.strokePath()

        let fill = body.insetBy(dx: 2 * unit, dy: 2 * unit)
        let inner = min(2.5 * unit, fill.height / 2, fill.width / 2)
        ctx.setFillColor(cgColor(color))
        ctx.addPath(CGPath(roundedRect: fill, cornerWidth: inner, cornerHeight: inner, transform: nil))
        ctx.fillPath()

        let nubHeight = 4.5 * unit
        let nub = CGRect(x: body.maxX + nubGap, y: r.midY - nubHeight / 2, width: nubWidth, height: nubHeight)
        let nubRadius = min(nubWidth / 2, nubHeight / 2)
        ctx.setFillColor(cgColor(color, alpha: 0.4))
        ctx.addPath(CGPath(roundedRect: nub, cornerWidth: nubRadius, cornerHeight: nubRadius, transform: nil))
        ctx.fillPath()
    }

    /// "9:41" in semibold system text, its outlines centred in `box` (y-up), sized so the digits are `box`'s height.
    private static func drawTime(in box: CGRect, color: CGColor, ctx: CGContext) {
        let size = box.height * timeFont / timeSize.height
        let line = timeLine(size: size, color: color)
        var bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        var drawn = line
        // Narrow the text if this font sets it wider than the box allows.
        if bounds.width > box.width * 1.15, bounds.width > 0 {
            drawn = timeLine(size: size * box.width * 1.15 / bounds.width, color: color)
            bounds = CTLineGetBoundsWithOptions(drawn, .useGlyphPathBounds)
        }
        ctx.textMatrix = .identity
        // iOS doesn't smooth (embolden) text; keeps the pixels a plain blend of ink and background.
        ctx.setShouldSmoothFonts(false)
        ctx.textPosition = CGPoint(x: box.midX - bounds.midX, y: box.midY - bounds.midY)
        CTLineDraw(drawn, ctx)
    }

    private static func timeLine(size: CGFloat, color: CGColor) -> CTLine {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        // Semibold: the system font's own family at the weight NSFont and UIFont call `.semibold`.
        let traits: [CFString: Any] = [kCTFontWeightTrait: 0.3]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base), [kCTFontTraitsAttribute: traits] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let string = CFAttributedStringCreate(nil, "9:41" as CFString, attrs as CFDictionary)
            ?? (NSAttributedString(string: "9:41") as CFAttributedString)
        return CTLineCreateWithAttributedString(string)
    }
}
