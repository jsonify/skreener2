import AppKit
import SkreenerCore

/// The Mac-only side of `Background` (SkreenerCore): the desktop wallpaper, pictures read from disk, menu swatches and
/// NSColor conversions.
extension Background {
    /// Fills `r` in the current AppKit graphics context, with this Mac's wallpaper or the picture.
    func drawFill(in r: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawFill(in: r, ctx: ctx, picture: picture, fallback: NSColor.windowBackgroundColor.cgColor)
    }

    /// The wallpaper or picture this background shows, nil for gradients and colors (or when it can't be read).
    var picture: CGImage? {
        switch fill {
        case Self.wallpaperFill: return Self.wallpaperURL.flatMap(Self.loadPicture(at:))?.cgImage
        case Self.imageFill: return imageURL.flatMap(Self.loadPicture(at:))?.cgImage
        default: return nil
        }
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
    static var wallpaper: NSImage? { wallpaperURL.flatMap(loadPicture(at:))?.image }

    /// Pictures read once per file. Swatches can be drawn off the main thread, so it is behind a lock.
    private final class PictureCache: @unchecked Sendable {
        let lock = NSLock()
        var pictures: [URL: (image: NSImage, cgImage: CGImage)] = [:]
    }

    private static let pictureCache = PictureCache()

    /// The picture at `url` (read once); nil if it can't be read. The CGImage is the one the blur's size rule and
    /// cache go by, so it is made once per file.
    private static func loadPicture(at url: URL) -> (image: NSImage, cgImage: CGImage)? {
        let cache = pictureCache
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let p = cache.pictures[url] { return p }
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
        // [verify] Drawn as this CGImage, where the NSImage was drawn before: the same for single-image files.
        var rect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        cache.pictures[url] = (img, cg)
        return (img, cg)
    }

    // MARK: Colors

    /// sRGB components with alpha, as saved for gradients and annotation colors.
    static func components(_ c: NSColor) -> [Double] {
        let s = c.usingColorSpace(.sRGB) ?? .black
        return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent].map(Double.init)
    }

    static func color(from v: [Double]) -> NSColor? {
        guard v.count == 4 else { return nil }
        return NSColor(srgbRed: CGFloat(v[0]), green: CGFloat(v[1]), blue: CGFloat(v[2]), alpha: CGFloat(v[3]))
    }
}

extension RGBColor {
    /// The color's sRGB components, as the color wells give them.
    init(_ c: NSColor) {
        let v = Background.components(c)
        self.init(r: v[0], g: v[1], b: v[2], a: v[3])
    }

    var nsColor: NSColor { NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}
