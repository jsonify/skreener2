import CoreGraphics
import CoreImage
import Foundation

/// Backdrop drawn around the whole screenshot (CleanShot's "Background" tool): a gradient, a solid color, the desktop
/// wallpaper or an image of your own (optionally blurred), with padding, an inset frame, rounded corners inside and
/// outside, an adjustable shadow under the screenshot, and an aspect ratio for the whole image (#124).
public struct Background: Equatable, Sendable {
    /// A preset's index, or `wallpaperFill`, `customFill` or `imageFill`.
    public var fill = 0
    /// The two colors of the custom gradient (`customFill`).
    public var colors: [RGBColor] = [.hex(0x4FACFE), .hex(0xF5576C)]
    /// Which way gradients run (presets and the custom one).
    public var direction = GradientDirection.diagonal
    /// The picture for `imageFill`.
    public var imageURL: URL?
    /// Blur for the wallpaper or picture: a gaussian radius per 1000 pixels of its width, so it looks the same for
    /// any size of picture.
    public var imageBlur: CGFloat = 0
    /// The shape of the whole image; nil keeps the padding the same on every side.
    public var aspect: Aspect?
    public var padding: CGFloat = 48
    /// A frame inside the card, in the screenshot's own edge color, between it and the background.
    public var inset: CGFloat = 0
    /// The card's corners (the screenshot's are rounded less by the inset, so the frame keeps an even width).
    public var cornerRadius: CGFloat = 10
    /// The corners of the whole image; past them it is transparent.
    public var outerRadius: CGFloat = 0
    /// How dark the shadow under the card is, from 0 (none) to 1.
    public var shadow: CGFloat = 0.5

    public enum GradientDirection: Int, CaseIterable, Sendable {
        case diagonal, vertical, horizontal, radial

        public var name: String {
            switch self {
            case .diagonal: return "Diagonal"
            case .vertical: return "Vertical"
            case .horizontal: return "Horizontal"
            case .radial: return "Radial"
            }
        }
    }

    /// A width-to-height ratio.
    public struct Aspect: Equatable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width; self.height = height
        }
    }

    /// Aspect ratios offered in the editor: plain ratios, then the usual sizes of social media images.
    public static let aspects: [(name: String, aspect: Aspect)] = [
        ("1:1", Aspect(width: 1, height: 1)), ("4:3", Aspect(width: 4, height: 3)), ("3:2", Aspect(width: 3, height: 2)),
        ("16:9", Aspect(width: 16, height: 9)), ("9:16", Aspect(width: 9, height: 16)), ("4:5", Aspect(width: 4, height: 5)),
        ("Twitter / X (16:9)", Aspect(width: 1600, height: 900)), ("Facebook (1200×630)", Aspect(width: 1200, height: 630)),
        ("LinkedIn (1200×627)", Aspect(width: 1200, height: 627)), ("YouTube (16:9)", Aspect(width: 1280, height: 720)),
        ("Instagram (4:5)", Aspect(width: 1080, height: 1350)), ("Pinterest (2:3)", Aspect(width: 1000, height: 1500)),
    ]

    public static let presets: [(name: String, colors: [RGBColor])] = [
        ("Sky", [hex(0x4FACFE), hex(0x00F2FE)]),
        ("Sunset", [hex(0xF093FB), hex(0xF5576C)]),
        ("Peach", [hex(0xFFECD2), hex(0xFCB69F)]),
        ("Mint", [hex(0x43E97B), hex(0x38F9D7)]),
        ("Violet", [hex(0x667EEA), hex(0x764BA2)]),
        ("Graphite", [hex(0x434343), hex(0x111111)]),
        ("Aurora", [hex(0x00C9FF), hex(0x92FE9D), hex(0xF9F586)]),
        ("Candy", [hex(0xFF9A9E), hex(0xFAD0C4), hex(0xA18CD1)]),
        ("Ocean", [hex(0x2E3192), hex(0x1BFFFF), hex(0xD4FFEC)]),
        ("Ember", [hex(0xF83600), hex(0xF9D423), hex(0xFE8C00)]),
        ("Night", [hex(0x0F2027), hex(0x203A43), hex(0x2C5364)]),
        ("White", [RGBColor(r: 1, g: 1, b: 1)]),
        ("Black", [RGBColor(r: 0, g: 0, b: 0)]),
    ]

    /// `fill` values after the presets: the main screen's desktop wallpaper, the custom gradient, a picture.
    public static var wallpaperFill: Int { presets.count }
    public static var customFill: Int { presets.count + 1 }
    public static var imageFill: Int { presets.count + 2 }

    private static func hex(_ v: Int) -> RGBColor { .hex(v) }

    // MARK: Layout

    /// The whole image around `content`: `margin` (padding plus inset) on every side, then, with `aspect`, grown to
    /// that ratio with the content centered. Ratios of small numbers (16:9, 4:3) come out exact in whole points; for the
    /// others (1200×627) the size is within a point of it.
    public static func canvas(around content: CGRect, margin: CGFloat, aspect: Aspect?) -> CGRect {
        let r = content.insetBy(dx: -margin, dy: -margin)
        guard let aspect, aspect.width > 0, aspect.height > 0, r.width > 0, r.height > 0 else { return r }
        var g = aspect.width, h0 = aspect.height
        while h0 != 0 { (g, h0) = (h0, g % h0) }
        let a = CGFloat(aspect.width / g), b = CGFloat(aspect.height / g)
        let need = max(r.width / a, r.height / b)
        var w: CGFloat, h: CGFloat
        if max(a, b) <= 32 {
            let k = max(ceil(need - 1e-9), 1)
            w = a * k; h = b * k
        } else {
            w = ceil(need * a - 1e-9); h = ceil(w * b / a - 1e-9)
        }
        w = max(w, ceil(r.width)); h = max(h, ceil(r.height))
        let x = min(max((r.midX - w / 2).rounded(.down), r.maxX - w), r.minX)
        let y = min(max((r.midY - h / 2).rounded(.down), r.maxY - h), r.minY)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Drawing

    /// Fills `r` with the background in `ctx` (y-up; an iOS caller must flip its context first). `picture` is the
    /// wallpaper or picture for `wallpaperFill` and `imageFill`, already loaded by the caller; without one those fill
    /// with `fallback`.
    public func drawFill(in r: CGRect, ctx: CGContext, picture: CGImage?, fallback: CGColor) {
        switch fill {
        case Self.wallpaperFill, Self.imageFill:
            guard let picture else { ctx.setFillColor(fallback); ctx.fill(r); return }
            Self.drawAspectFill(Self.blurred(picture, amount: imageBlur), in: r, ctx: ctx)
        case Self.customFill:
            drawGradient(colors, in: r, ctx: ctx)
        default:
            drawGradient(Self.presets[min(max(fill, 0), Self.presets.count - 1)].colors, in: r, ctx: ctx)
        }
    }

    /// The same geometry as AppKit's NSGradient, which drew these before: a linear gradient at `angle` degrees covers
    /// `r` from corner to corner, and the radial one runs from `r`'s center out to its corners.
    private func drawGradient(_ colors: [RGBColor], in r: CGRect, ctx: CGContext) {
        guard colors.count > 1, let g = Self.gradient(colors) else {
            ctx.setFillColor((colors.first ?? RGBColor(r: 1, g: 1, b: 1)).cgColor); ctx.fill(r); return
        }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: r)
        let center = CGPoint(x: r.midX, y: r.midY)
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        let angle: CGFloat
        switch direction {
        case .diagonal: angle = -45
        case .vertical: angle = -90
        case .horizontal: angle = 0
        case .radial:
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: hypot(r.width, r.height) / 2, options: options)
            return
        }
        let rad = angle * .pi / 180
        let dx = cos(rad), dy = sin(rad)
        let half = (abs(r.width * dx) + abs(r.height * dy)) / 2
        ctx.drawLinearGradient(g, start: CGPoint(x: center.x - dx * half, y: center.y - dy * half),
                               end: CGPoint(x: center.x + dx * half, y: center.y + dy * half), options: options)
    }

    /// Evenly spaced colors blended in sRGB, as NSGradient did. NSGradient blends see-through colors premultiplied
    /// (CGGradient doesn't), so those get many stops in between that follow the premultiplied blend.
    static func gradient(_ colors: [RGBColor]) -> CGGradient? {
        var stops = colors
        if colors.contains(where: { $0.a < 1 }) {
            let steps = 64
            stops = [colors[0]]
            for (c0, c1) in zip(colors, colors.dropFirst()) {
                for i in 1...steps {
                    let t = Double(i) / Double(steps)
                    let a = c0.a + (c1.a - c0.a) * t
                    func mix(_ v0: Double, _ v1: Double) -> Double {
                        a > 0 ? (v0 * c0.a + (v1 * c1.a - v0 * c0.a) * t) / a : 0
                    }
                    stops.append(RGBColor(r: mix(c0.r, c1.r), g: mix(c0.g, c1.g), b: mix(c0.b, c1.b), a: a))
                }
            }
        }
        let locations = stops.indices.map { CGFloat($0) / CGFloat(stops.count - 1) }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.cgColor) as CFArray,
                          locations: locations)
    }

    /// Scaled to cover `r`, centered.
    private static func drawAspectFill(_ img: CGImage, in r: CGRect, ctx: CGContext) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        guard iw > 0, ih > 0 else { return }
        let scale = max(r.width / iw, r.height / ih)
        let w = iw * scale, h = ih * scale
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.draw(img, in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    /// The last blurred picture, so redrawing is cheap. Drawing can happen off the main thread (menu swatches, video
    /// frames), so it is behind a lock.
    private final class BlurCache: @unchecked Sendable {
        let lock = NSLock()
        let context = CIContext()
        /// Keyed by the picture itself: the caller keeps one image per file, and this keeps it alive, so the same
        /// object means the same picture.
        var last: (source: CGImage, amount: CGFloat, result: CGImage)?
    }

    private static let blurCache = BlurCache()

    /// `img` blurred by `amount` (radius per 1000 pixels of width); the last result is kept.
    static func blurred(_ img: CGImage, amount: CGFloat) -> CGImage {
        guard amount > 0 else { return img }
        let cache = blurCache
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let c = cache.last, c.source === img, c.amount == amount { return c.result }
        let ci = CIImage(cgImage: img)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(amount * CGFloat(img.width) / 1000)).cropped(to: ci.extent)
        guard let result = cache.context.createCGImage(out, from: ci.extent) else { return img }
        cache.last = (img, amount, result)
        return result
    }

    // MARK: Saving (the last background used is offered next time)

    /// The background as property-list values, for user defaults.
    public var plist: [String: Any] {
        var d: [String: Any] = [
            "fill": fill, "direction": direction.rawValue, "imageBlur": Double(imageBlur), "padding": Double(padding),
            "inset": Double(inset), "cornerRadius": Double(cornerRadius), "outerRadius": Double(outerRadius),
            "shadow": Double(shadow), "colors": colors.map(\.components),
        ]
        if let imageURL { d["imagePath"] = imageURL.path }
        if let aspect { d["aspect"] = [aspect.width, aspect.height] }
        return d
    }

    public init() {}

    /// A background read back from `plist`; missing values keep their defaults.
    public init(plist d: [String: Any]) {
        func number(_ key: String) -> CGFloat? { (d[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
        if let f = d["fill"] as? Int, f >= 0, f <= Self.imageFill { fill = f }
        if let c = d["colors"] as? [[Double]] {
            let parsed = c.compactMap(RGBColor.init(components:))
            if parsed.count == 2 { colors = parsed }
        }
        if let v = d["direction"] as? Int, let dir = GradientDirection(rawValue: v) { direction = dir }
        if let p = d["imagePath"] as? String { imageURL = URL(fileURLWithPath: p) }
        if let a = d["aspect"] as? [Int], a.count == 2, a[0] > 0, a[1] > 0 { aspect = Aspect(width: a[0], height: a[1]) }
        imageBlur = number("imageBlur") ?? imageBlur
        padding = number("padding") ?? padding
        inset = number("inset") ?? inset
        cornerRadius = number("cornerRadius") ?? cornerRadius
        outerRadius = number("outerRadius") ?? outerRadius
        shadow = min(max(number("shadow") ?? shadow, 0), 1)
        // A picture that has since gone away falls back to the first preset.
        if fill == Self.imageFill, imageURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true { fill = 0 }
    }
}
