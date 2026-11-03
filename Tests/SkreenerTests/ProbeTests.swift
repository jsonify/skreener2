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

    static func dump(_ p: CGPath) -> String {
        var out = ""
        p.applyWithBlock { e in
            let pts = e.pointee.points
            func f(_ i: Int) -> String { String(format: "(%.4f,%.4f)", pts[i].x, pts[i].y) }
            switch e.pointee.type {
            case .moveToPoint: out += " M" + f(0)
            case .addLineToPoint: out += " L" + f(0)
            case .addQuadCurveToPoint: out += " Q" + f(0) + f(1)
            case .addCurveToPoint: out += " C" + f(0) + f(1) + f(2)
            case .closeSubpath: out += " Z"
            @unknown default: out += " ?"
            }
        }
        return out
    }

    func testProbeDumpPaths() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 60)
        print("PROBE nsoval" + Self.dump(NSBezierPath(ovalIn: r).cgPath))
        print("PROBE cgoval" + Self.dump(CGPath(ellipseIn: r, transform: nil)))
        print("PROBE nsround" + Self.dump(NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).cgPath))
        print("PROBE cground" + Self.dump(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)))
        print("PROBE nsround40" + Self.dump(NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40).cgPath))
        print("PROBE nsround0" + Self.dump(NSBezierPath(roundedRect: r, xRadius: 0, yRadius: 0).cgPath))
        print("PROBE nsrect" + Self.dump(NSBezierPath(rect: r).cgPath))
    }

    /// Ink extents (columns, rows) of a bitmap.
    static func ink(_ b: T.Bitmap) -> String {
        var x0 = Int.max, x1 = -1, y0 = Int.max, y1 = -1
        for row in 0..<b.height { for col in 0..<b.width where b.data[(row * b.width + col) * 4 + 3] > 40 {
            x0 = min(x0, col); x1 = max(x1, col); y0 = min(y0, row); y1 = max(y1, row)
        } }
        return "x\(x0)-\(x1) y\(y0)-\(y1)"
    }

    func testProbeTruncationInk() {
        for u in [1, 2.5] as [CGFloat] {
            let url = "a-rather-long-address.example.com/with/a/path/that/cannot/fit/in/the/field"
            let field = CGRect(x: 100.25 * u, y: 7 * u, width: 320 * u, height: 26 * u)
            let area = field.insetBy(dx: -2, dy: -2).integral
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let text = NSAttributedString(string: url, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5 * u), .foregroundColor: NSColor.black, .paragraphStyle: style,
            ])
            let h = text.size().height
            let rect = NSRect(x: field.minX + 8 * u, y: field.midY - h / 2, width: max(field.width - 16 * u, 0), height: h)
            let old = T.renderLegacy(area) { text.draw(in: rect) }
            let plain = NSAttributedString(string: url, attributes: [.font: NSFont.systemFont(ofSize: 12.5 * u), .foregroundColor: NSColor.black])
            let left = T.renderLegacy(area) { NSGraphicsContext.saveGraphicsState(); rect.clip(); plain.draw(at: rect.origin); NSGraphicsContext.restoreGraphicsState() }
            let font = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)!
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
            func line(_ s: String) -> CTLine { CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)) }
            let t = CTLineCreateTruncatedLine(line(url), Double(rect.width), .end, line("\u{2026}"))!
            let tw = CGFloat(CTLineGetTypographicBounds(t, nil, nil, nil))
            let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
            let ct = T.render(area) { ctx in
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: rect.minX + (rect.width - tw) / 2, y: field.midY + (ascent + descent) / 2 - ascent)
                CTLineDraw(t, ctx)
            }
            print("PROBE ink u=\(u) rect \(rect) NS: \(Self.ink(old)) leftclip: \(Self.ink(left)) diffLeft=\(T.diff(old, left, area: area, region: area).differingInside) CT: \(Self.ink(ct)) tw=\(tw) glyphs=\(CTLineGetGlyphCount(t)) full=\(CTLineGetTypographicBounds(line(url), nil, nil, nil))")
            let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            print("PROBE ink u=\(u) NS boundingRect \(bounds)")
        }
    }
}
