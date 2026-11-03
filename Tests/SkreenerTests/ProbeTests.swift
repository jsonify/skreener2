import AppKit
import CoreText
import XCTest
@testable import Skreener
@testable import SkreenerCore

// TEMPORARY: measurements to settle the CoreGraphics details that match AppKit; removed before review.
final class ProbeTests: XCTestCase {
    typealias T = CoreDrawingIdentityTests

    func testProbeGradientSpaces() {
        let spaces: [(String, CGColorSpace?)] = [
            ("sRGB", CGColorSpace(name: CGColorSpace.sRGB)), ("genericRGB", NSColorSpace.genericRGB.cgColorSpace),
            ("deviceRGB", CGColorSpaceCreateDeviceRGB()), ("nil", nil),
            ("extSRGB", CGColorSpace(name: CGColorSpace.extendedSRGB)), ("displayP3", CGColorSpace(name: CGColorSpace.displayP3)),
        ]
        let rect = CGRect(x: 0, y: 0, width: 320, height: 200)
        for fill in [0, 6, 8] {
            for dir in Background.GradientDirection.allCases {
                var b = Background()
                b.fill = fill; b.direction = dir
                let old = T.renderLegacy(rect) { LegacyBackgroundFill(b).drawFill(in: rect) }
                var line = "PROBE gradient fill \(fill) \(dir.name):"
                for (name, space) in spaces {
                    let new = T.render(rect) { ctx in
                        Self.gradient(Background.presets[fill].colors, dir, rect, ctx, space)
                    }
                    line += " \(name)=\(T.diff(old, new, area: rect).maxOutside)"
                }
                print(line)
            }
        }
        // Generic RGB by name.
        if let g = NSColorSpace.genericRGB.cgColorSpace { print("PROBE genericRGB name \(String(describing: g.name))") }
        if let g = NSColorSpace.sRGB.cgColorSpace { print("PROBE sRGB name \(String(describing: g.name))") }
    }

    static func gradient(_ colors: [RGBColor], _ direction: Background.GradientDirection, _ r: CGRect, _ ctx: CGContext,
                         _ space: CGColorSpace?) {
        let locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        let g = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
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

    func testProbePaths() {
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        for (rect, radius) in [(CGRect(x: 3.3, y: 4.1, width: 90, height: 50), 10.0), (CGRect(x: 2, y: 2, width: 300, height: 200), 37.5),
                               (CGRect(x: 1.5, y: 2.5, width: 200, height: 120), 59.0), (CGRect(x: 0.5, y: 0.5, width: 30, height: 30), 6.0)]
            as [(CGRect, CGFloat)] {
            let area = rect.insetBy(dx: -3, dy: -3).integral
            let old = T.renderLegacy(area) { NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }
            let cg = T.render(area) { ctx in
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(black); ctx.fillPath()
            }
            let arcs = T.render(area) { ctx in
                let p = CGMutablePath()
                let r = radius
                p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
                p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
                p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: false)
                p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
                p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
                p.closeSubpath()
                ctx.addPath(p); ctx.setFillColor(black); ctx.fillPath()
            }
            let oldStroke = T.renderLegacy(area) {
                NSColor.black.setStroke(); let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius); p.lineWidth = 1; p.stroke()
            }
            let cgStroke = T.render(area) { ctx in
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setStrokeColor(black); ctx.setLineWidth(1); ctx.strokePath()
            }
            let oldOval = T.renderLegacy(area) { NSColor.black.setFill(); NSBezierPath(ovalIn: rect).fill() }
            let cgOval = T.render(area) { ctx in ctx.addEllipse(in: rect); ctx.setFillColor(black); ctx.fillPath() }
            print("PROBE path r=\(radius): cg=\(T.diff(old, cg, area: area).maxOutside) arcs=\(T.diff(old, arcs, area: area).maxOutside)"
                  + " stroke=\(T.diff(oldStroke, cgStroke, area: area).maxOutside) oval=\(T.diff(oldOval, cgOval, area: area).maxOutside)")
        }
    }

    /// The address text drawn with CoreText, moved by (dx, dy).
    static func ctText(_ url: String, field: CGRect, u: CGFloat, dark: Bool, dx: CGFloat, dy: CGFloat, ctx: CGContext) {
        let fill = dark ? RGBColor.hex(0x1B1B1D).cgColor : RGBColor.hex(0xE3E3E6).cgColor
        ctx.addPath(CGPath(roundedRect: field, cornerWidth: 6 * u, cornerHeight: 6 * u, transform: nil))
        ctx.setFillColor(fill); ctx.fillPath()
        let font = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)!
        let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                      kCTForegroundColorAttributeName: dark ? RGBColor.hex(0xB4B4B8).cgColor : RGBColor.hex(0x5C5C60).cgColor]
        func line(_ s: String) -> CTLine {
            CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
        }
        let width = max(field.width - 16 * u, 0)
        var text = line(url)
        if CTLineGetTypographicBounds(text, nil, nil, nil) > Double(width) {
            text = CTLineCreateTruncatedLine(text, Double(width), .end, line("\u{2026}")) ?? text
        }
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font), leading = CTFontGetLeading(font)
        let h = ascent + descent + leading
        let tw = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: field.minX + 8 * u + (width - tw) / 2 + dx, y: field.midY + h / 2 - ascent + dy)
        CTLineDraw(text, ctx)
        ctx.restoreGState()
    }

    func testProbeText() {
        for u in [1, 1.37, 2.5] as [CGFloat] {
            for url in ["example.com", "a-rather-long-address.example.com/with/a/path/that/cannot/fit/in/the/field"] {
                let field = CGRect(x: 100.25 * u, y: 7 * u, width: 320 * u, height: 26 * u)
                let area = field.insetBy(dx: -2, dy: -2).integral
                var f = DeviceFrame()
                f.kind = .browser; f.url = url
                let legacy = LegacyDeviceFrameDrawing(f)
                let old = T.renderLegacy(area) { legacy.drawURLField(field, unit: u) }
                let ns = NSAttributedString(string: url, attributes: [.font: NSFont.systemFont(ofSize: 12.5 * u)])
                let font = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)!
                var best = (dx: CGFloat(0), dy: CGFloat(0), n: Int.max)
                var atZero = 0
                for iy in -8...8 {
                    for ix in -8...8 {
                        let dx = CGFloat(ix) / 8, dy = CGFloat(iy) / 8
                        let new = T.render(area) { Self.ctText(url, field: field, u: u, dark: false, dx: dx, dy: dy, ctx: $0) }
                        let n = T.diff(old, new, area: area, region: area).differingInside
                        if ix == 0 && iy == 0 { atZero = n }
                        if n < best.n { best = (dx, dy, n) }
                    }
                }
                print("PROBE text u=\(u) \(url.prefix(12)): at 0 \(atZero), best dx \(best.dx) dy \(best.dy) -> \(best.n) of \(Int(area.width * area.height));"
                      + " NS height \(ns.size().height) CT a+d+l \(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))"
                      + " NSfont asc \(NSFont.systemFont(ofSize: 12.5 * u).ascender) desc \(NSFont.systemFont(ofSize: 12.5 * u).descender) leading \(NSFont.systemFont(ofSize: 12.5 * u).leading)"
                      + " CT asc \(CTFontGetAscent(font)) desc \(CTFontGetDescent(font)) lead \(CTFontGetLeading(font))")
            }
        }
    }
}
