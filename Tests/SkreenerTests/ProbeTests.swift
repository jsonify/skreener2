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

    func testProbeKappa() {
        let r = CGRect(x: 0, y: 0, width: 4000, height: 3000)
        let a = Self.points(NSBezierPath(roundedRect: r, xRadius: 1000, yRadius: 1000).cgPath)
        // M(1000,3000) C(c1)(c2)(0,2000): c1.x = 1000 - k*1000.
        print(String(format: "PROBE kappa round %.12f %.12f", (1000 - a[1].x) / 1000, (a[2].y - 2000) / 1000))
        let o = Self.points(NSBezierPath(ovalIn: CGRect(x: -1000, y: -1000, width: 2000, height: 2000)).cgPath)
        let k = hypot(o[1].x - o[0].x, o[1].y - o[0].y) / 1000
        print(String(format: "PROBE kappa oval %.12f start (%.9f, %.9f) all %@", k, o[0].x, o[0].y, o.map { String(format: "(%.6f,%.6f)", $0.x, $0.y) }.joined()))
    }
}
