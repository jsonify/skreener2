import AppKit
import CoreImage

/// Backdrop drawn around the whole screenshot (CleanShot's "Background" tool): a gradient, a solid color, the desktop
/// wallpaper or an image of your own (optionally blurred), with padding, an inset frame, rounded corners inside and
/// outside, an adjustable shadow under the screenshot, and an aspect ratio for the whole image (#124).
struct Background: Equatable {
    /// A preset's index, or `wallpaperFill`, `customFill` or `imageFill`.
    var fill = 0
    /// The two colors of the custom gradient (`customFill`).
    var colors: [NSColor] = [Background.hex(0x4FACFE), Background.hex(0xF5576C)]
    /// Which way gradients run (presets and the custom one).
    var direction = GradientDirection.diagonal
    /// The picture for `imageFill`.
    var imageURL: URL?
    /// Blur for the wallpaper or picture: a gaussian radius per 1000 pixels of its width, so it looks the same for
    /// any size of picture.
    var imageBlur: CGFloat = 0
    /// The shape of the whole image; nil keeps the padding the same on every side.
    var aspect: Aspect?
    var padding: CGFloat = 48
    /// A frame inside the card, in the screenshot's own edge color, between it and the background.
    var inset: CGFloat = 0
    /// The card's corners (the screenshot's are rounded less by the inset, so the frame keeps an even width).
    var cornerRadius: CGFloat = 10
    /// The corners of the whole image; past them it is transparent.
    var outerRadius: CGFloat = 0
    /// How dark the shadow under the card is, from 0 (none) to 1.
    var shadow: CGFloat = 0.5

    enum GradientDirection: Int, CaseIterable {
        case diagonal, vertical, horizontal, radial

        var name: String {
            switch self {
            case .diagonal: return "Diagonal"
            case .vertical: return "Vertical"
            case .horizontal: return "Horizontal"
            case .radial: return "Radial"
            }
        }
    }

    /// A width-to-height ratio.
    struct Aspect: Equatable {
        var width: Int
        var height: Int
    }

    /// Aspect ratios offered in the editor: plain ratios, then the usual sizes of social media images.
    static let aspects: [(name: String, aspect: Aspect)] = [
        ("1:1", Aspect(width: 1, height: 1)), ("4:3", Aspect(width: 4, height: 3)), ("3:2", Aspect(width: 3, height: 2)),
        ("16:9", Aspect(width: 16, height: 9)), ("9:16", Aspect(width: 9, height: 16)), ("4:5", Aspect(width: 4, height: 5)),
        ("Twitter / X (16:9)", Aspect(width: 1600, height: 900)), ("Facebook (1200×630)", Aspect(width: 1200, height: 630)),
        ("LinkedIn (1200×627)", Aspect(width: 1200, height: 627)), ("YouTube (16:9)", Aspect(width: 1280, height: 720)),
        ("Instagram (4:5)", Aspect(width: 1080, height: 1350)), ("Pinterest (2:3)", Aspect(width: 1000, height: 1500)),
    ]

    static let presets: [(name: String, colors: [NSColor])] = [
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
        ("White", [.white]),
        ("Black", [.black]),
    ]

    /// `fill` values after the presets: the main screen's desktop wallpaper, the custom gradient, a picture.
    static var wallpaperFill: Int { presets.count }
    static var customFill: Int { presets.count + 1 }
    static var imageFill: Int { presets.count + 2 }

    static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    // MARK: Layout

    /// The whole image around `content`: `margin` (padding plus inset) on every side, then, with `aspect`, grown to
    /// that ratio with the content centered. Ratios of small numbers (16:9, 4:3) come out exact in whole points; for the
    /// others (1200×627) the size is within a point of it.
    static func canvas(around content: NSRect, margin: CGFloat, aspect: Aspect?) -> NSRect {
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
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Drawing

    /// Fills `r` with the background.
    func drawFill(in r: NSRect) {
        switch fill {
        case Self.wallpaperFill, Self.imageFill:
            let picture = fill == Self.wallpaperFill ? Self.wallpaperURL.flatMap(Self.image(at:))
                                                     : imageURL.flatMap(Self.image(at:))
            guard let picture else { NSColor.windowBackgroundColor.setFill(); r.fill(); return }
            Self.drawAspectFill(Self.blurred(picture.image, key: picture.key, amount: imageBlur), in: r)
        case Self.customFill:
            drawGradient(colors, in: r)
        default:
            drawGradient(Self.presets[min(max(fill, 0), Self.presets.count - 1)].colors, in: r)
        }
    }

    private func drawGradient(_ colors: [NSColor], in r: NSRect) {
        guard colors.count > 1, let g = NSGradient(colors: colors) else {
            (colors.first ?? .white).setFill(); r.fill(); return
        }
        switch direction {
        case .diagonal: g.draw(in: r, angle: -45)
        case .vertical: g.draw(in: r, angle: -90)
        case .horizontal: g.draw(in: r, angle: 0)
        case .radial: g.draw(in: r, relativeCenterPosition: .zero)
        }
    }

    /// Scaled to cover `r`, centered.
    private static func drawAspectFill(_ img: NSImage, in r: NSRect) {
        guard img.size.width > 0, img.size.height > 0 else { return }
        let scale = max(r.width / img.size.width, r.height / img.size.height)
        let w = img.size.width * scale, h = img.size.height * scale
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        img.draw(in: NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A small swatch of this background, for menus.
    func swatch(size: NSSize = NSSize(width: 26, height: 14)) -> NSImage {
        let bg = self
        return NSImage(size: size, flipped: false) { r in
            let clip = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            clip.addClip()
            bg.drawFill(in: r)
            NSColor.separatorColor.setStroke(); clip.stroke()
            return true
        }
    }

    // MARK: Pictures

    private static var wallpaperURL: URL? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    /// The main screen's current wallpaper, or nil when it is not a plain image file (a folder or a dynamic aerial).
    static var wallpaper: NSImage? { wallpaperURL.flatMap(image(at:))?.image }

    private static var imageCache: [URL: NSImage] = [:]
    /// The picture at `url` (read once), with a key naming it for the blur cache; nil if it can't be read.
    private static func image(at url: URL) -> (image: NSImage, key: String)? {
        if let img = imageCache[url] { return (img, url.path) }
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
        imageCache[url] = img
        return (img, url.path)
    }

    private static let ciContext = CIContext()
    private static var blurCache: (key: String, amount: CGFloat, image: NSImage)?

    /// `img` blurred by `amount` (radius per 1000 pixels of width); the last result is kept, so redrawing is cheap.
    private static func blurred(_ img: NSImage, key: String, amount: CGFloat) -> NSImage {
        guard amount > 0 else { return img }
        if let c = blurCache, c.key == key, c.amount == amount { return c.image }
        var rect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return img }
        let ci = CIImage(cgImage: cg)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(amount * CGFloat(cg.width) / 1000)).cropped(to: ci.extent)
        guard let blurredCG = ciContext.createCGImage(out, from: ci.extent) else { return img }
        let result = NSImage(cgImage: blurredCG, size: img.size)
        blurCache = (key, amount, result)
        return result
    }

    // MARK: Saving (the last background used is offered next time)

    /// The background as property-list values, for user defaults.
    var plist: [String: Any] {
        var d: [String: Any] = [
            "fill": fill, "direction": direction.rawValue, "imageBlur": Double(imageBlur), "padding": Double(padding),
            "inset": Double(inset), "cornerRadius": Double(cornerRadius), "outerRadius": Double(outerRadius),
            "shadow": Double(shadow), "colors": colors.map(Self.components),
        ]
        if let imageURL { d["imagePath"] = imageURL.path }
        if let aspect { d["aspect"] = [aspect.width, aspect.height] }
        return d
    }

    init() {}

    /// A background read back from `plist`; missing values keep their defaults.
    init(plist d: [String: Any]) {
        func number(_ key: String) -> CGFloat? { (d[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
        if let f = d["fill"] as? Int, f >= 0, f <= Self.imageFill { fill = f }
        if let c = d["colors"] as? [[Double]] {
            let parsed = c.compactMap(Self.color(from:))
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

    static func components(_ c: NSColor) -> [Double] {
        let s = c.usingColorSpace(.sRGB) ?? .black
        return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent].map(Double.init)
    }

    static func color(from v: [Double]) -> NSColor? {
        guard v.count == 4 else { return nil }
        return NSColor(srgbRed: CGFloat(v[0]), green: CGFloat(v[1]), blue: CGFloat(v[2]), alpha: CGFloat(v[3]))
    }
}
