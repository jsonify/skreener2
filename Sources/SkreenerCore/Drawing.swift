import CoreGraphics
import Foundation

// Small CoreGraphics helpers shared by the frame, background and underlay drawing. Contexts are y-up, like the Mac
// canvas; an iOS caller (UIKit's contexts are y-down) must flip the context before drawing.

extension RGBColor {
    /// An opaque sRGB color from 0xRRGGBB.
    public static func hex(_ v: Int) -> RGBColor {
        RGBColor(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    public var cgColor: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }

    /// `[r, g, b, a]`, as saved in property lists.
    public var components: [Double] { [r, g, b, a] }

    /// A color read back from `components`; nil unless there are exactly four values.
    public init?(components v: [Double]) {
        guard v.count == 4 else { return nil }
        self.init(r: v[0], g: v[1], b: v[2], a: v[3])
    }
}

enum Draw {
    static func srgb(_ v: Int) -> CGColor { RGBColor.hex(v).cgColor }

    /// A rounded rect; the radius is clamped to half the shorter side, as AppKit's rounded rects are.
    static func roundedRect(_ r: CGRect, radius: CGFloat) -> CGPath {
        let radius = max(min(radius, r.width / 2, r.height / 2), 0)
        guard radius > 0 else { return CGPath(rect: r, transform: nil) }
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func fill(_ path: CGPath, _ color: CGColor, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    static func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    static func clip(to path: CGPath, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.clip()
    }
}
