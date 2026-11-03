import AppKit
import XCTest
@testable import Skreener
@testable import SkreenerCore

/// SkreenerCore draws frames, backgrounds and the canvas underlay with CoreGraphics; the app drew them with AppKit
/// before (#396). Each case draws both (the AppKit copies are in LegacyDrawing.swift) into identical sRGB bitmaps and
/// compares them: every channel within 1, except the browser's address text, where up to 2% of the pixels in the
/// address field may differ (CoreText lays the text out directly, AppKit through its text system).
final class CoreDrawingIdentityTests: XCTestCase {
    struct Bitmap {
        let width: Int, height: Int
        let data: [UInt8]
    }

    /// Draws into a cleared sRGB bitmap of `area` (whole points, y-up), in `area`'s coordinates.
    static func render(_ area: CGRect, _ draw: (CGContext) -> Void) -> Bitmap {
        let w = Int(area.width), h = Int(area.height)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.translateBy(x: -area.minX, y: -area.minY)
            draw(ctx)
        }
        return Bitmap(width: w, height: h, data: data)
    }

    /// The same with AppKit's current context set to it, as the canvas has.
    static func renderLegacy(_ area: CGRect, _ draw: () -> Void) -> Bitmap {
        render(area) { ctx in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            draw()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    struct Diff {
        /// The largest channel difference outside `region`.
        var maxOutside = 0
        /// Inside `region`: the largest difference, how many pixels differ by more than 1, out of how many.
        var maxInside = 0
        var differingInside = 0
        var pixelsInside = 0

        var shareInside: Double { pixelsInside == 0 ? 0 : Double(differingInside) / Double(pixelsInside) }
    }

    static func diff(_ a: Bitmap, _ b: Bitmap, area: CGRect, region: CGRect? = nil) -> Diff {
        precondition(a.width == b.width && a.height == b.height)
        var d = Diff()
        // The region in pixel columns and rows (row 0 at the top).
        var c0 = 0, c1 = 0, r0 = 0, r1 = 0
        if let region {
            c0 = Int((region.minX - area.minX).rounded(.down)); c1 = Int((region.maxX - area.minX).rounded(.up))
            r0 = a.height - Int((region.maxY - area.minY).rounded(.up)); r1 = a.height - Int((region.minY - area.minY).rounded(.down))
        }
        a.data.withUnsafeBufferPointer { pa in
            b.data.withUnsafeBufferPointer { pb in
                for row in 0..<a.height {
                    let rowInside = row >= r0 && row < r1
                    for col in 0..<a.width {
                        let i = (row * a.width + col) * 4
                        var m = 0
                        for k in 0..<4 { m = max(m, abs(Int(pa[i + k]) - Int(pb[i + k]))) }
                        if rowInside && col >= c0 && col < c1 {
                            d.pixelsInside += 1
                            d.maxInside = max(d.maxInside, m)
                            if m > 1 { d.differingInside += 1 }
                        } else {
                            d.maxOutside = max(d.maxOutside, m)
                        }
                    }
                }
            }
        }
        return d
    }

    private func check(_ d: Diff, _ label: String, text: Bool, file: StaticString = #filePath, line: UInt = #line) {
        print(String(format: "IDENTITY %@: max %d outside the address; address max %d, %.2f%% of %d pixels differ",
                     label, d.maxOutside, d.maxInside, d.shareInside * 100, d.pixelsInside))
        XCTAssertLessThanOrEqual(d.maxOutside, 1, label, file: file, line: line)
        if text {
            XCTAssertLessThanOrEqual(d.shareInside, 0.02, label, file: file, line: line)
        } else {
            XCTAssertLessThanOrEqual(d.maxInside, 1, label, file: file, line: line)
        }
    }

    private static func srgbComponents(_ c: CGColor) -> [CGFloat] {
        c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
    }

    // MARK: Frames

    func testEveryFrameMatchesTheAppKitDrawing() {
        // Landscape, portrait, and very wide (bigger chrome: unit 2.5).
        let contents = [CGRect(x: 10, y: 20, width: 800, height: 500), CGRect(x: 0, y: 0, width: 400, height: 900),
                        CGRect(x: 5, y: 7, width: 3000, height: 400)]
        for kind in DeviceFrame.Kind.allCases where kind != .none {
            for dark in [false, true] {
                for content in contents {
                    var f = DeviceFrame()
                    f.kind = kind; f.dark = dark
                    checkFrame(f, around: content)
                }
            }
        }
        // An address too long for the field is cut off.
        var f = DeviceFrame()
        f.kind = .browser
        f.url = "a-rather-long-address.example.com/with/a/path/that/cannot/fit/in/the/field"
        checkFrame(f, around: CGRect(x: 0, y: 0, width: 640, height: 300))
        f.dark = true
        checkFrame(f, around: CGRect(x: 0, y: 0, width: 2600, height: 300))
    }

    private func checkFrame(_ f: DeviceFrame, around content: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let legacy = LegacyDeviceFrameDrawing(f)
        let label = "\(f.kind.name)\(f.dark ? " dark" : "") \(Int(content.width))×\(Int(content.height))"
        XCTAssertEqual(Self.srgbComponents(legacy.bodyColor.cgColor), Self.srgbComponents(f.bodyColor), label,
                       file: file, line: line)
        let l = f.layout(around: content)
        let area = l.outer.insetBy(dx: -4, dy: -4).integral
        let old = Self.renderLegacy(area) { legacy.drawChrome(l) }
        let new = Self.render(area) { f.drawChrome(l, in: $0) }
        check(Self.diff(old, new, area: area, region: l.urlField), label, text: l.urlField != nil, file: file, line: line)

        // The clip paths.
        let oldClip = Self.renderLegacy(area) {
            legacy.outerPath(l).addClip(); legacy.screenPath(l).addClip()
            NSColor.systemRed.setFill(); area.fill()
        }
        let newClip = Self.render(area) { ctx in
            Draw.clip(to: f.outerPath(l), in: ctx); Draw.clip(to: f.screenPath(l), in: ctx)
            ctx.setFillColor(NSColor.systemRed.cgColor); ctx.fill(area)
        }
        check(Self.diff(oldClip, newClip, area: area), label + " clip", text: false, file: file, line: line)
    }

    // MARK: Backgrounds

    func testEveryFillMatchesTheAppKitDrawing() {
        let rects = [CGRect(x: 0, y: 0, width: 320, height: 200), CGRect(x: 3, y: 5, width: 150, height: 400)]
        for fill in Array(Background.presets.indices) + [Background.customFill] {
            for direction in Background.GradientDirection.allCases {
                for rect in rects {
                    var b = Background()
                    b.fill = fill; b.direction = direction
                    checkFill(b, in: rect, label: "fill \(fill) \(direction.name) \(Int(rect.width))×\(Int(rect.height))")
                }
            }
        }
        // A custom gradient with see-through colors.
        var b = Background()
        b.fill = Background.customFill
        b.colors = [RGBColor(r: 0.9, g: 0.1, b: 0.3, a: 0.4), RGBColor(r: 0.1, g: 0.8, b: 0.2, a: 1)]
        checkFill(b, in: CGRect(x: 0, y: 0, width: 300, height: 300), label: "custom see-through")
        // The wallpaper or a picture that can't be read.
        b.fill = Background.wallpaperFill
        checkFill(b, in: CGRect(x: 0, y: 0, width: 100, height: 60), label: "no wallpaper")
    }

    func testPictureFillsMatchTheAppKitDrawing() {
        let picture = Self.render(CGRect(x: 0, y: 0, width: 240, height: 160)) { ctx in
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1),
                                        CGColor(srgbRed: 0, green: 0.3, blue: 0.9, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 240, y: 160), options: [])
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 60, y: 40, width: 50, height: 70))
        }
        let cg = Self.image(picture)
        let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        for blur in [0, 20] as [CGFloat] {
            for rect in [CGRect(x: 0, y: 0, width: 300, height: 120), CGRect(x: 0, y: 0, width: 90, height: 200)] {
                var b = Background()
                b.fill = Background.imageFill; b.imageBlur = blur
                let old = Self.renderLegacy(rect) { LegacyBackgroundFill(b, picture: (ns, "test")).drawFill(in: rect) }
                let new = Self.render(rect) { b.drawFill(in: rect, ctx: $0, picture: cg, fallback: NSColor.windowBackgroundColor.cgColor) }
                check(Self.diff(old, new, area: rect), "picture blur \(Int(blur)) \(Int(rect.width))×\(Int(rect.height))", text: false)
            }
        }
    }

    static func image(_ b: Bitmap) -> CGImage {
        let provider = CGDataProvider(data: Data(b.data) as CFData)!
        return CGImage(width: b.width, height: b.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: b.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    private func checkFill(_ b: Background, in rect: CGRect, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let old = Self.renderLegacy(rect) { LegacyBackgroundFill(b).drawFill(in: rect) }
        let new = Self.render(rect) { b.drawFill(in: rect, ctx: $0, picture: nil, fallback: NSColor.windowBackgroundColor.cgColor) }
        check(Self.diff(old, new, area: rect), label, text: false, file: file, line: line)
    }

    // MARK: The canvas underlay

    func testTheUnderlayMatchesTheCanvasDrawing() {
        let content = CGRect(x: 0, y: 0, width: 600, height: 400)
        var framedBG = Background()
        framedBG.fill = 1; framedBG.shadow = 0.6; framedBG.inset = 8
        var radialBG = Background()
        radialBG.fill = Background.customFill; radialBG.direction = .radial
        radialBG.shadow = 0.5; radialBG.inset = 6; radialBG.outerRadius = 20
        var plain = Background()
        plain.fill = 6; plain.shadow = 0.5; plain.inset = 0; plain.outerRadius = 16; plain.cornerRadius = 10
        var inset = Background()
        inset.fill = 9; inset.direction = .vertical; inset.shadow = 0.8; inset.inset = 12; inset.outerRadius = 24
        inset.cornerRadius = 18; inset.aspect = Background.Aspect(width: 16, height: 9)
        var bigInset = inset
        bigInset.inset = 30; bigInset.cornerRadius = 10
        func frame(_ kind: DeviceFrame.Kind, dark: Bool = false) -> DeviceFrame {
            var f = DeviceFrame()
            f.kind = kind; f.dark = dark
            return f
        }
        let cases: [(String, DeviceFrame?, Background?)] = [
            ("browser + background", frame(.browser), framedBG),
            ("dark iPhone + radial background", frame(.iPhone, dark: true), radialBG),
            ("MacBook + background", frame(.macBook), inset),
            ("background, no inset", nil, plain),
            ("background with inset", nil, inset),
            ("background with an inset past the corners", nil, bigInset),
            ("window frame only", frame(.macWindow), nil),
            ("iPad frame only", frame(.iPad), nil),
            ("nothing", nil, nil),
        ]
        let backdrop = NSColor(srgbRed: 0.95, green: 0.4, blue: 0.2, alpha: 1)
        let screenshot = CGColor(srgbRed: 0.1, green: 0.3, blue: 1, alpha: 0.6)
        for (label, f, b) in cases {
            let framed = f.map { $0.layout(around: content).outer } ?? content
            let bounds = b.map { Background.canvas(around: framed, margin: $0.padding + $0.inset, aspect: $0.aspect) } ?? framed
            let area = bounds.integral
            var oldLayout: DeviceFrame.Layout?, newLayout: DeviceFrame.Layout?
            let old = Self.renderLegacy(area) {
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.saveGState()
                oldLayout = LegacyUnderlay.draw(bounds: bounds, contentRect: content, activeFrame: f, activeBackground: b,
                                                backdrop: backdrop)
                // Shows the clip left for the screenshot.
                ctx.setFillColor(screenshot); ctx.fill(bounds)
                ctx.restoreGState()
            }
            let new = Self.render(area) { ctx in
                ctx.saveGState()
                newLayout = Framing.drawUnderlay(in: ctx, bounds: bounds, content: content, frame: f, background: b, picture: nil,
                                                 fallback: NSColor.windowBackgroundColor.cgColor, backdrop: backdrop.cgColor)
                ctx.setFillColor(screenshot); ctx.fill(bounds)
                ctx.restoreGState()
            }
            XCTAssertEqual(oldLayout, newLayout, label)
            let field = newLayout?.urlField
            check(Self.diff(old, new, area: area, region: field), "underlay: " + label, text: field != nil)
        }
    }
}
