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

    /// The control-point distance of a quarter circle drawn as one cubic Bézier, as a share of its radius: AppKit's
    /// value, measured from NSBezierPath (a hair above the textbook 4/3 (√2 − 1)). [verify]
    private static let kappa: CGFloat = 0.5522895

    /// A rounded rect built as NSBezierPath built it (the same start, direction and control points), so edges and
    /// strokes come out identical. Each radius is clamped to half its side, as AppKit's were.
    static func roundedRect(_ r: CGRect, radius: CGFloat) -> CGPath {
        let rx = min(radius, r.width / 2), ry = min(radius, r.height / 2)
        guard rx > 0, ry > 0 else { return CGPath(rect: r, transform: nil) }
        let kx = kappa * rx, ky = kappa * ry
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + rx, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - ry), control1: CGPoint(x: r.minX + rx - kx, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - ry + ky))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + ry))
        p.addCurve(to: CGPoint(x: r.minX + rx, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + ry - ky),
                   control2: CGPoint(x: r.minX + rx - kx, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rx, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + ry), control1: CGPoint(x: r.maxX - rx + kx, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + ry - ky))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - ry))
        p.addCurve(to: CGPoint(x: r.maxX - rx, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - ry + ky),
                   control2: CGPoint(x: r.maxX - rx + kx, y: r.maxY))
        p.closeSubpath()
        return p
    }

    /// An oval as NSBezierPath built it: four quarter arcs counterclockwise from 45° below the right, left open.
    static func oval(in r: CGRect) -> CGPath {
        let c = CGPoint(x: r.midX, y: r.midY), rx = r.width / 2, ry = r.height / 2
        func point(_ a: CGFloat, _ along: CGFloat = 0) -> CGPoint {
            // On the unit circle at angle `a`, moved `along` its tangent, then scaled to the oval.
            CGPoint(x: c.x + (cos(a) - along * sin(a)) * rx, y: c.y + (sin(a) + along * cos(a)) * ry)
        }
        let p = CGMutablePath()
        var a = -CGFloat.pi / 4
        p.move(to: point(a))
        for _ in 0..<4 {
            let b = a + .pi / 2
            p.addCurve(to: point(b), control1: point(a, kappa), control2: point(b, -kappa))
            a = b
        }
        return p
    }

    /// AppKit's paths flattened curves to within 0.6 pixels (NSBezierPath's default flatness) rather than the
    /// context's own, finer setting; the same flatness keeps the edges identical.
    static let flatness: CGFloat = 0.6

    static func fill(_ path: CGPath, _ color: CGColor, in ctx: CGContext) {
        ctx.setFlatness(flatness)
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    static func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, in ctx: CGContext) {
        ctx.setFlatness(flatness)
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    static func clip(to path: CGPath, in ctx: CGContext) {
        ctx.setFlatness(flatness)
        ctx.addPath(path)
        ctx.clip()
    }
}
