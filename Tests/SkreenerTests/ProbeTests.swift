import AppKit
import CoreText
import XCTest
@testable import Skreener
@testable import SkreenerCore

// TEMPORARY: measurements to settle the CoreGraphics details that match AppKit; removed before review.
final class ProbeTests: XCTestCase {
    typealias T = CoreDrawingIdentityTests

    func testProbeTruncationPrefixes() {
        for u in [1, 1.37, 2.5] as [CGFloat] {
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
            let nsWidth = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]).width
            let font = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)!
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
            func line(_ s: String) -> CTLine { CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)) }
            let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
            let t = CTLineCreateTruncatedLine(line(url), Double(rect.width), .end, line("\u{2026}"))!
            var out = "PROBE prefix u=\(u) NSwidth \(nsWidth) CTtrunc \(CTLineGetTypographicBounds(t, nil, nil, nil)) glyphs \(CTLineGetGlyphCount(t)) ellipsis \(CTLineGetTypographicBounds(line("\u{2026}"), nil, nil, nil)):"
            for n in 38...56 {
                for joined in [true, false] {
                    let prefix = String(url.prefix(n))
                    let lw: CGFloat
                    let new: T.Bitmap
                    if joined {
                        let l = line(prefix + "\u{2026}")
                        lw = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
                        new = T.render(area) { ctx in
                            ctx.textMatrix = .identity
                            ctx.textPosition = CGPoint(x: rect.minX + (rect.width - lw) / 2, y: field.midY + (ascent + descent) / 2 - ascent)
                            CTLineDraw(l, ctx)
                        }
                    } else {
                        let a = line(prefix), e = line("\u{2026}")
                        let aw = CGFloat(CTLineGetTypographicBounds(a, nil, nil, nil))
                        lw = aw + CGFloat(CTLineGetTypographicBounds(e, nil, nil, nil))
                        new = T.render(area) { ctx in
                            ctx.textMatrix = .identity
                            let x = rect.minX + (rect.width - lw) / 2, y = field.midY + (ascent + descent) / 2 - ascent
                            ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(a, ctx)
                            ctx.textPosition = CGPoint(x: x + aw, y: y); CTLineDraw(e, ctx)
                        }
                    }
                    let d = T.diff(old, new, area: area, region: area).differingInside
                    if d < 800 || abs(lw - nsWidth) < 0.05 {
                        out += " n\(n)\(joined ? "j" : "s") w\(String(format: "%.2f", lw)) d\(d);"
                    }
                }
            }
            print(out)
        }
    }
}
