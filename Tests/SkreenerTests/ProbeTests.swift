import AppKit
import CoreText
import XCTest
@testable import Skreener
@testable import SkreenerCore

// TEMPORARY: measurements to settle the CoreGraphics details that match AppKit; removed before review.
final class ProbeTests: XCTestCase {
    typealias T = CoreDrawingIdentityTests

    static func points(_ p: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        p.applyWithBlock { e in
            let n: Int
            switch e.pointee.type {
            case .moveToPoint, .addLineToPoint: n = 1
            case .addQuadCurveToPoint: n = 2
            case .addCurveToPoint: n = 3
            default: n = 0
            }
            for i in 0..<n { out.append(e.pointee.points[i]) }
        }
        return out
    }

    func testProbeBigShapes() {
        var f = DeviceFrame()
        f.kind = .iPhone
        let l = f.layout(around: CGRect(x: 5, y: 7, width: 3000, height: 400))
        let glass = l.screen.insetBy(dx: -l.bezel * 0.8, dy: -l.bezel * 0.8)
        let shapes: [(String, CGRect, CGFloat)] = [("outer", l.outer, l.outerRadius), ("screen", l.screen, l.screenRadius),
                                                   ("glass", glass, l.screenRadius + l.bezel * 0.8)]
        for (name, rect, radius) in shapes {
            let ns = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            let a = Self.points(ns.cgPath), b = Self.points(Draw.roundedRect(rect, radius: radius))
            let maxd = zip(a, b).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.max() ?? -1
            let area = rect.insetBy(dx: -3, dy: -3).integral
            let old = T.renderLegacy(area) { NSColor.black.setFill(); ns.fill() }
            let new = T.render(area) { Draw.fill(Draw.roundedRect(rect, radius: radius), CGColor(gray: 0, alpha: 1), in: $0) }
            let viaNS = T.render(area) { Draw.fill(ns.cgPath, CGColor(gray: 0, alpha: 1), in: $0) }
            let oldS = T.renderLegacy(area) { NSColor.black.setStroke(); ns.lineWidth = 1; ns.stroke() }
            let newS = T.render(area) { Draw.stroke(Draw.roundedRect(rect, radius: radius), CGColor(gray: 0, alpha: 1), width: 1, in: $0) }
            print("PROBE big \(name) r=\(radius) counts \(a.count)/\(b.count) maxpt \(maxd) fill \(T.diff(old, new, area: area).maxOutside) viaNS \(T.diff(old, viaNS, area: area).maxOutside) stroke \(T.diff(oldS, newS, area: area).maxOutside)")
        }
    }

    func testProbeTruncationGlyphs() {
        for u in [1, 2.5] as [CGFloat] {
            let url = "a-rather-long-address.example.com/with/a/path/that/cannot/fit/in/the/field"
            let field = CGRect(x: 100.25 * u, y: 7 * u, width: 320 * u, height: 26 * u)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let font = NSFont.systemFont(ofSize: 12.5 * u)
            let text = NSAttributedString(string: url, attributes: [.font: font, .paragraphStyle: style])
            let w = max(field.width - 16 * u, 0)
            let storage = NSTextStorage(attributedString: text)
            let lm = NSLayoutManager()
            let tc = NSTextContainer(size: NSSize(width: w, height: 1000))
            tc.lineFragmentPadding = 0
            tc.maximumNumberOfLines = 1
            lm.addTextContainer(tc); storage.addLayoutManager(lm)
            lm.ensureLayout(for: tc)
            let trunc = lm.truncatedGlyphRange(inLineFragmentForGlyphAt: 0)
            let used = lm.usedRect(for: tc)
            var out = "PROBE tk1 u=\(u) w=\(w) truncated \(trunc) used \(used)"
            let ctFont = CTFontCreateUIFontForLanguage(.system, 12.5 * u, nil)!
            let attrs: [CFString: Any] = [kCTFontAttributeName: ctFont]
            func width(_ s: String) -> Double {
                CTLineGetTypographicBounds(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)), nil, nil, nil)
            }
            out += " | prefixes:"
            for n in 30...60 { out += String(format: " %d=%.2f/%.2f", n, width(String(url.prefix(n))), width(String(url.prefix(n)) + "\u{2026}")) }
            print(out)
        }
    }
}
