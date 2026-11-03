import AppKit
import CoreText
import XCTest
@testable import Skreener
@testable import SkreenerCore

// TEMPORARY: measurements to settle the CoreGraphics details that match AppKit; removed before review.
final class ProbeTests: XCTestCase {
    typealias T = CoreDrawingIdentityTests

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

    func testProbePathsFlatness() {
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let cases: [(CGRect, CGFloat)] = [(CGRect(x: 3.3, y: 4.1, width: 90, height: 50), 10), (CGRect(x: 2, y: 2, width: 300, height: 200), 37.5),
                                          (CGRect(x: 1.5, y: 2.5, width: 200, height: 120), 59), (CGRect(x: 0, y: 0, width: 800, height: 528), 10)]
        for (rect, radius) in cases {
            let area = rect.insetBy(dx: -3, dy: -3).integral
            for shape in ["round", "oval", "stroke"] {
                func ns() -> NSBezierPath {
                    shape == "oval" ? NSBezierPath(ovalIn: rect) : NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                }
                let old = T.renderLegacy(area) {
                    if shape == "stroke" { NSColor.black.setStroke(); let p = ns(); p.lineWidth = 1; p.stroke() } else { NSColor.black.setFill(); ns().fill() }
                }
                var line = "PROBE flat \(shape) r=\(radius) \(rect.width):"
                for flat in [CGFloat(-1), 0.1, 0.5, 0.6, 1.0] {
                    for useNS in [false, true] {
                        let new = T.render(area) { ctx in
                            if flat > 0 { ctx.setFlatness(flat) }
                            let path: CGPath = useNS ? ns().cgPath
                                : (shape == "oval" ? CGPath(ellipseIn: rect, transform: nil)
                                   : CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                            ctx.addPath(path)
                            if shape == "stroke" { ctx.setStrokeColor(black); ctx.setLineWidth(1); ctx.strokePath() } else { ctx.setFillColor(black); ctx.fillPath() }
                        }
                        line += " f\(flat)\(useNS ? "ns" : "cg")=\(T.diff(old, new, area: area).maxOutside)"
                    }
                }
                print(line)
            }
        }
        // What AppKit leaves in the context.
        _ = T.renderLegacy(CGRect(x: 0, y: 0, width: 10, height: 10)) {
            let ctx = NSGraphicsContext.current!.cgContext
            print("PROBE ctx interp \(ctx.interpolationQuality.rawValue) NS flatness default \(NSBezierPath.defaultFlatness)")
        }
    }

    func testProbeAlphaGradient() {
        var b = Background()
        b.fill = Background.customFill; b.direction = .horizontal
        b.colors = [RGBColor(r: 0.9, g: 0.1, b: 0.3, a: 0.4), RGBColor(r: 0.1, g: 0.8, b: 0.2, a: 1)]
        let rect = CGRect(x: 0, y: 0, width: 101, height: 4)
        let old = T.renderLegacy(rect) { LegacyBackgroundFill(b).drawFill(in: rect) }
        let new = T.render(rect) { b.drawFill(in: rect, ctx: $0, picture: nil, fallback: CGColor(gray: 0, alpha: 1)) }
        for x in [0, 10, 25, 50, 75, 90, 100] {
            let i = (1 * 101 + x) * 4
            print("PROBE alpha x=\(x) old \(Array(old.data[i..<i + 4])) new \(Array(new.data[i..<i + 4]))")
        }
    }

    func testProbeTruncation() {
        for u in [1, 1.37, 2.5] as [CGFloat] {
            let url = "a-rather-long-address.example.com/with/a/path/that/cannot/fit/in/the/field"
            let field = CGRect(x: 100.25 * u, y: 7 * u, width: 320 * u, height: 26 * u)
            let area = field.insetBy(dx: -2, dy: -2).integral
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let color = RGBColor.hex(0x5C5C60)
            let text = NSAttributedString(string: url, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5 * u), .foregroundColor: color.nsColor, .paragraphStyle: style,
            ])
            let h = text.size().height
            let rect = NSRect(x: field.minX + 8 * u, y: field.midY - h / 2, width: max(field.width - 16 * u, 0), height: h)
            let old = T.renderLegacy(area) { text.draw(in: rect) }
            let font = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)!
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color.cgColor]
            func line(_ s: String) -> CTLine { CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)) }
            let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font), leading = CTFontGetLeading(font)
            let ch = ascent + descent + leading
            var out = "PROBE trunc u=\(u) NSh=\(h):"
            for k in [-4, -2, 0, 2, 4, 6, 8, 10, 12, 16] as [CGFloat] {
                for left in [false, true] {
                    let w = rect.width - k
                    let t = CTLineCreateTruncatedLine(line(url), Double(w), .end, line("\u{2026}"))!
                    let tw = CGFloat(CTLineGetTypographicBounds(t, nil, nil, nil))
                    let new = T.render(area) { ctx in
                        ctx.textMatrix = .identity
                        ctx.textPosition = CGPoint(x: rect.minX + (left ? 0 : (rect.width - tw) / 2), y: field.midY + ch / 2 - ascent)
                        CTLineDraw(t, ctx)
                    }
                    out += " k\(Int(k))\(left ? "L" : "C")=\(T.diff(old, new, area: area, region: area).differingInside)/tw\(Int(tw))"
                }
            }
            // CTFramesetter with the paragraph style.
            var settings = [CTParagraphStyleSetting]()
            var align = CTTextAlignment.center, mode = CTLineBreakMode.byTruncatingTail
            withUnsafeBytes(of: &align) { a in
                withUnsafeBytes(of: &mode) { m in
                    settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a.baseAddress!),
                                CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: m.baseAddress!)]
                    var fa = attrs
                    fa[kCTParagraphStyleAttributeName] = CTParagraphStyleCreate(settings, settings.count)
                    let fs = CTFramesetterCreateWithAttributedString(CFAttributedStringCreate(nil, url as CFString, fa as CFDictionary))
                    let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
                    let new = T.render(area) { ctx in ctx.textMatrix = .identity; CTFrameDraw(frame, ctx) }
                    out += " frame=\(T.diff(old, new, area: area, region: area).differingInside)"
                }
            }
            print(out)
        }
    }
}
