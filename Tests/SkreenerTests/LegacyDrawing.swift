import AppKit
import CoreImage
import SkreenerCore

// Verbatim copies of the AppKit drawing that SkreenerCore replaced (#396), from origin/main before the move, renamed.
// The pixel-identity tests (CoreDrawingIdentityTests) draw these and the CoreGraphics versions side by side. Only the
// names, the inputs (a struct's fields instead of `self`) and the picture loading (passed in) differ from the original.

private func legacyHex(_ v: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// `DeviceFrame`'s drawing as it was.
struct LegacyDeviceFrameDrawing {
    var kind: DeviceFrame.Kind
    var dark: Bool
    var url: String

    init(_ f: DeviceFrame) { kind = f.kind; dark = f.dark; url = f.url }

    private func hex(_ v: Int) -> NSColor { legacyHex(v) }

    /// The color of the frame's body, which the canvas also uses under the Background's shadow and inset.
    var bodyColor: NSColor {
        switch kind {
        case .macWindow: return dark ? hex(0x323234) : hex(0xE9E9EB)
        case .browser: return dark ? hex(0x2B2B2D) : hex(0xF2F2F4)
        default: return dark ? hex(0x1D1D1F) : hex(0xD9DADD)
        }
    }

    /// The outline the canvas clips the screenshot to, along with `screenPath`.
    func outerPath(_ l: DeviceFrame.Layout) -> NSBezierPath {
        NSBezierPath(roundedRect: l.outer, xRadius: l.outerRadius, yRadius: l.outerRadius)
    }

    func screenPath(_ l: DeviceFrame.Layout) -> NSBezierPath {
        l.screenRadius > 0 ? NSBezierPath(roundedRect: l.screen, xRadius: l.screenRadius, yRadius: l.screenRadius)
                           : NSBezierPath(rect: l.screen)
    }

    /// Draws the frame's body, bar and details; the screenshot goes on top of its screen afterwards.
    func drawChrome(_ l: DeviceFrame.Layout) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let u = l.unit
        let edge = (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.16 : 0.2)
        switch kind {
        case .none:
            return
        case .macWindow, .browser:
            let shape = outerPath(l)
            bodyColor.setFill(); shape.fill()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            // A hairline between the bar and the screenshot.
            edge.setFill(); NSRect(x: l.bar.minX, y: l.bar.minY, width: l.bar.width, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
            for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                let d = 12 * u
                let cx = l.bar.minX + (20 + 20 * CGFloat(i)) * u
                let dot = NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: l.bar.midY - d / 2, width: d, height: d))
                hex(color).setFill(); dot.fill()
                NSColor.black.withAlphaComponent(0.12).setStroke(); dot.lineWidth = 0.5; dot.stroke()
            }
            if let field = l.urlField { drawURLField(field, unit: u) }
            let border = NSBezierPath(roundedRect: l.outer.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: l.outerRadius, yRadius: l.outerRadius)
            edge.setStroke(); border.lineWidth = 1; border.stroke()
        case .iPhone, .iPad, .macBook:
            // A MacBook's lid reaches down under its base, which covers the lid's bottom corners.
            let body = l.base == nil ? outerPath(l)
                : NSBezierPath(roundedRect: CGRect(x: l.body.minX, y: l.body.minY - l.outerRadius, width: l.body.width,
                                                   height: l.body.height + l.outerRadius),
                               xRadius: l.outerRadius, yRadius: l.outerRadius)
            bodyColor.setFill(); body.fill()
            // The black glass around the screen.
            let glass = l.screen.insetBy(dx: -l.bezel * 0.8, dy: -l.bezel * 0.8)
            NSColor.black.setFill()
            if let base = l.base {
                let r = 0.01 * l.screen.width
                NSBezierPath(roundedRect: glass, xRadius: r, yRadius: r).fill()
                // Camera.
                let c = 0.004 * l.screen.width
                hex(0x2A2A2E).setFill()
                NSBezierPath(ovalIn: NSRect(x: l.screen.midX - c, y: (l.body.maxY + l.screen.maxY) / 2 - c,
                                            width: 2 * c, height: 2 * c)).fill()
                // The base, a little darker than the lid, with the notch for lifting it.
                let baseShape = NSBezierPath(roundedRect: base, xRadius: base.height * 0.45, yRadius: base.height * 0.45)
                (dark ? hex(0x2A2A2D) : hex(0xC6C7CB)).setFill(); baseShape.fill()
                edge.setStroke(); baseShape.lineWidth = 1; baseShape.stroke()
                let nw = 0.14 * l.screen.width, nh = base.height * 0.4
                (dark ? hex(0x1D1D1F) : hex(0xAEAFB3)).setFill()
                NSBezierPath(roundedRect: NSRect(x: base.midX - nw / 2, y: base.maxY - nh, width: nw, height: nh),
                             xRadius: nh / 2, yRadius: nh / 2).fill()
            } else {
                let r = l.screenRadius + l.bezel * 0.8
                NSBezierPath(roundedRect: glass, xRadius: r, yRadius: r).fill()
                edge.setStroke(); body.lineWidth = 1; body.stroke()
            }
        }
    }

    func drawURLField(_ field: CGRect, unit u: CGFloat) {
        let pill = NSBezierPath(roundedRect: field, xRadius: 6 * u, yRadius: 6 * u)
        (dark ? hex(0x1B1B1D) : hex(0xE3E3E6)).setFill(); pill.fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: url, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5 * u),
            .foregroundColor: dark ? hex(0xB4B4B8) : hex(0x5C5C60),
            .paragraphStyle: style,
        ])
        let h = text.size().height
        text.draw(in: NSRect(x: field.minX + 8 * u, y: field.midY - h / 2, width: max(field.width - 16 * u, 0), height: h))
    }
}

/// `Background`'s fill as it was. The picture is passed in (it was loaded from `imageURL` or the wallpaper).
struct LegacyBackgroundFill {
    var fill = 0
    var colors: [NSColor] = [legacyHex(0x4FACFE), legacyHex(0xF5576C)]
    var direction = Background.GradientDirection.diagonal
    var imageBlur: CGFloat = 0
    var picture: (image: NSImage, key: String)?

    init(_ b: Background, picture: (image: NSImage, key: String)? = nil) {
        fill = b.fill
        colors = b.colors.map { NSColor(srgbRed: CGFloat($0.r), green: CGFloat($0.g), blue: CGFloat($0.b), alpha: CGFloat($0.a)) }
        direction = b.direction
        imageBlur = b.imageBlur
        self.picture = picture
    }

    private static func hex(_ v: Int) -> NSColor { legacyHex(v) }

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

    static var wallpaperFill: Int { presets.count }
    static var customFill: Int { presets.count + 1 }
    static var imageFill: Int { presets.count + 2 }

    /// Fills `r` with the background.
    func drawFill(in r: NSRect) {
        switch fill {
        case Self.wallpaperFill, Self.imageFill:
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

    private static let ciContext = CIContext()

    /// `img` blurred by `amount` (radius per 1000 pixels of width); the last result is kept, so redrawing is cheap.
    private static func blurred(_ img: NSImage, key: String, amount: CGFloat) -> NSImage {
        guard amount > 0 else { return img }
        // (Not cached here: the tests draw each picture once.)
        var rect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return img }
        let ci = CIImage(cgImage: cg)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(amount * CGFloat(cg.width) / 1000)).cropped(to: ci.extent)
        guard let blurredCG = ciContext.createCGImage(out, from: ci.extent) else { return img }
        return NSImage(cgImage: blurredCG, size: img.size)
    }
}

/// The start of `CanvasView.draw(_:)` as it was, down to the clip the screenshot is drawn in.
enum LegacyUnderlay {
    static func draw(bounds: NSRect, contentRect: NSRect, activeFrame: DeviceFrame?, activeBackground: Background?,
                     backdrop: NSColor) -> DeviceFrame.Layout? {
        let ctx = NSGraphicsContext.current?.cgContext
        let device = activeFrame.map(LegacyDeviceFrameDrawing.init)
        let layout = activeFrame.map { $0.layout(around: contentRect) }
        if let bg = activeBackground {
            if bg.outerRadius > 0 {
                NSBezierPath(roundedRect: bounds, xRadius: bg.outerRadius, yRadius: bg.outerRadius).addClip()
            }
            LegacyBackgroundFill(bg).drawFill(in: bounds)
        }
        if let device, let layout {
            if let bg = activeBackground {
                let card = NSBezierPath(roundedRect: layout.outer.insetBy(dx: -bg.inset, dy: -bg.inset),
                                        xRadius: layout.outerRadius + bg.inset, yRadius: layout.outerRadius + bg.inset)
                if bg.shadow > 0 {
                    ctx?.saveGState()
                    ctx?.setShadow(offset: CGSize(width: 0, height: -8), blur: 28,
                                   color: NSColor.black.withAlphaComponent(0.8 * bg.shadow).cgColor)
                    device.bodyColor.setFill(); card.fill()
                    ctx?.restoreGState()
                }
                if bg.inset > 0 { device.bodyColor.setFill(); card.fill() }
            }
            device.drawChrome(layout)
            device.outerPath(layout).addClip()
            device.screenPath(layout).addClip()
        } else if let bg = activeBackground {
            let cardRect = contentRect.insetBy(dx: -bg.inset, dy: -bg.inset)
            let card = NSBezierPath(roundedRect: cardRect, xRadius: bg.cornerRadius, yRadius: bg.cornerRadius)
            if bg.shadow > 0 {
                ctx?.saveGState()
                ctx?.setShadow(offset: CGSize(width: 0, height: -8), blur: 28,
                               color: NSColor.black.withAlphaComponent(0.8 * bg.shadow).cgColor)
                backdrop.setFill(); card.fill()
                ctx?.restoreGState()
            }
            if bg.inset > 0 {
                // The inset is a frame in the screenshot's edge color; the screenshot's corners follow the card's.
                backdrop.setFill(); card.fill()
                let inner = max(bg.cornerRadius - bg.inset, 0)
                NSBezierPath(roundedRect: contentRect, xRadius: inner, yRadius: inner).addClip()
            } else {
                card.addClip()
            }
        } else {
            NSBezierPath(rect: contentRect).addClip()
        }
        return layout
    }
}
