import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SkreenerCore

/// Clean status bar (#408): the size table, where the items go, and the repainted bar.
final class StatusBarTests: XCTestCase {
    // MARK: Layout lookup

    func testIslandPhone() throws {
        let l = try XCTUnwrap(StatusBar.layout(forPixelWidth: 1179, height: 2556))
        XCTAssertEqual(l.style, .island)
        XCTAssertEqual(l.scale, 3)
        XCTAssertEqual(l.bar, CGRect(x: 0, y: 0, width: 1179, height: 162))
        let cutout = try XCTUnwrap(l.cutout)
        XCTAssertEqual(cutout.midX, 1179 / 2, accuracy: 0.01)
        XCTAssertGreaterThan(cutout.minY, 0)
    }

    func testNotchPhones() throws {
        for (w, h, scale) in [(1125, 2436, 3), (828, 1792, 2), (1080, 2340, 3), (1170, 2532, 3), (1284, 2778, 3)] {
            let l = try XCTUnwrap(StatusBar.layout(forPixelWidth: w, height: h), "\(w)×\(h)")
            XCTAssertEqual(l.style, .notch, "\(w)×\(h)")
            XCTAssertEqual(l.scale, CGFloat(scale), "\(w)×\(h)")
            XCTAssertEqual(try XCTUnwrap(l.cutout).minY, 0, "\(w)×\(h)")
        }
    }

    func testClassicPhones() throws {
        let se = try XCTUnwrap(StatusBar.layout(forPixelWidth: 750, height: 1334))
        XCTAssertEqual(se.style, .classic)
        XCTAssertEqual(se.scale, 2)
        XCTAssertEqual(se.bar.height, 40)
        XCTAssertNil(se.cutout)
        XCTAssertEqual(StatusBar.layout(forPixelWidth: 1242, height: 2208)?.style, .classic)
    }

    func testEveryListedSizeHasALayout() {
        let sizes = [(750, 1334), (1242, 2208), (1125, 2436), (828, 1792), (1242, 2688), (1080, 2340), (1170, 2532),
                     (1284, 2778), (1179, 2556), (1290, 2796), (1206, 2622), (1320, 2868), (1260, 2736)]
        for (w, h) in sizes { XCTAssertNotNil(StatusBar.layout(forPixelWidth: w, height: h), "\(w)×\(h)") }
        XCTAssertEqual(StatusBar.table.count, sizes.count)
    }

    func testOtherSizesHaveNone() {
        XCTAssertNil(StatusBar.layout(forPixelWidth: 2556, height: 1179), "landscape")
        XCTAssertNil(StatusBar.layout(forPixelWidth: 2048, height: 2732), "iPad")
        XCTAssertNil(StatusBar.layout(forPixelWidth: 4032, height: 3024), "photo")
        XCTAssertNil(StatusBar.layout(forPixelWidth: 1179, height: 2000), "cropped")
        XCTAssertNil(StatusBar.layout(forPixelWidth: 0, height: 0))
    }

    // MARK: Glyph geometry

    private func assertInside(_ inner: CGRect, _ outer: CGRect, _ message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(outer.insetBy(dx: -0.5, dy: -0.5).contains(inner), "\(message): \(inner) not in \(outer)",
                      file: file, line: line)
    }

    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        return !i.isNull && i.width > 0.5 && i.height > 0.5
    }

    func testGlyphsSitInTheBarAndTheirEars() {
        for m in StatusBar.table {
            let name = "\(m.width)×\(m.height)"
            guard let l = StatusBar.layout(forPixelWidth: m.width, height: m.height) else { XCTFail(name); continue }
            let g = StatusBar.glyphs(for: l)
            let all = [g.time, g.signal, g.wifi, g.battery]
            for r in all {
                assertInside(r, l.bar, name)
                XCTAssertGreaterThan(r.width, 0, name)
                XCTAssertGreaterThan(r.height, 0, name)
            }
            for i in all.indices {
                for j in all.indices where i < j { XCTAssertFalse(overlaps(all[i], all[j]), "\(name): \(i) and \(j)") }
            }
            if let cutout = l.cutout {
                // Time left of the cutout; icons right of it, signal before Wi-Fi before battery.
                XCTAssertLessThanOrEqual(g.time.maxX, cutout.minX + 0.5, name)
                XCTAssertGreaterThanOrEqual(g.signal.minX, cutout.maxX - 0.5, name)
                for r in all { XCTAssertFalse(overlaps(r, cutout), name) }
            } else {
                XCTAssertEqual(g.time.midX, l.bar.midX, accuracy: 0.5, name)
                XCTAssertLessThan(g.wifi.maxX, g.time.minX, name)
                XCTAssertGreaterThan(g.battery.minX, g.time.maxX, name)
                XCTAssertEqual(g.battery.maxX, l.bar.maxX - StatusBar.sideInset(.classic) * l.scale, accuracy: 0.5, name)
            }
            XCTAssertLessThan(g.signal.maxX, g.wifi.minX, name)
            XCTAssertLessThan(g.wifi.maxX, g.battery.minX, name)
            for r in all { XCTAssertEqual(r.midY, l.midY, accuracy: 0.5, name) }
        }
    }

    // MARK: Clean

    /// 393 × 852 px at 1x, like a 14 Pro in points: a `barColor` bar 54 px tall with "icon" blobs, a body below.
    private let smallLayout = StatusBar.Layout(bar: CGRect(x: 0, y: 0, width: 393, height: 54), scale: 1, style: .island,
                                               cutout: CGRect(x: 133.5, y: 11.33, width: 126, height: 37.33), midY: 30)

    private func screenshot(width: Int = 393, height: Int = 852, barHeight: Int = 54, bar: CGColor, body: CGColor) -> CGImage {
        var rng = SeededRandom(seed: 408)
        return TestImages.image(width: width, height: height) { ctx, r in
            ctx.setFillColor(body); ctx.fill(r)
            // Stripes in the body, so "unchanged" means more than one flat color.
            ctx.setFillColor(TestImages.srgb(0.9, 0.4, 0.1))
            for y in stride(from: 0, to: height - barHeight, by: 40) { ctx.fill(CGRect(x: 0, y: y, width: width, height: 7)) }
            let top = CGRect(x: 0, y: height - barHeight, width: width, height: barHeight)
            ctx.setFillColor(bar); ctx.fill(top)
            // Blobs where a carrier name, notification icons and a low battery would be.
            let colors = [TestImages.red, TestImages.srgb(0, 0.8, 0), TestImages.srgb(1, 1, 0)]
            for i in 0..<12 {
                let w = CGFloat(rng.next(in: 4...30)), h = CGFloat(rng.next(in: 4...Int(top.height) - 8))
                let x = CGFloat(rng.next(in: 0...(width - 30))), y = top.minY + CGFloat(rng.next(in: 2...Int(top.height - h) - 2))
                ctx.setFillColor(colors[i % colors.count])
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
        }
    }

    private func check(_ original: CGImage, cleaned: CGImage?, barHeight: Int, background: (Int, Int, Int),
                       ink: (Int, Int, Int), file: StaticString = #filePath, line: UInt = #line) throws {
        let out = try XCTUnwrap(cleaned, file: file, line: line)
        XCTAssertEqual(out.width, original.width, file: file, line: line)
        XCTAssertEqual(out.height, original.height, file: file, line: line)
        let a = try XCTUnwrap(PixelBuffer(original)), b = try XCTUnwrap(PixelBuffer(out))
        var changed = 0
        for y in barHeight..<a.height {
            for x in 0..<a.width where a.rgba(x: x, y: y) != b.rgba(x: x, y: y) { changed += 1 }
        }
        XCTAssertEqual(changed, 0, "pixels changed below the bar", file: file, line: line)

        // Each bar pixel is the background, the ink, or a blend of the two.
        var stray = 0, inked = 0
        let bg = (Double(background.0), Double(background.1), Double(background.2))
        let d = (Double(ink.0) - bg.0, Double(ink.1) - bg.1, Double(ink.2) - bg.2)
        let len2 = d.0 * d.0 + d.1 * d.1 + d.2 * d.2
        for y in 0..<barHeight {
            for x in 0..<b.width {
                let p = b.rgba(x: x, y: y)
                let v = (Double(p.r) - bg.0, Double(p.g) - bg.1, Double(p.b) - bg.2)
                let t = min(max((v.0 * d.0 + v.1 * d.1 + v.2 * d.2) / len2, 0), 1)
                let off = max(abs(v.0 - t * d.0), abs(v.1 - t * d.1), abs(v.2 - t * d.2))
                if off > 12 { stray += 1 }
                if t > 0.9 { inked += 1 }
            }
        }
        XCTAssertEqual(stray, 0, "bar pixels neither background nor ink", file: file, line: line)
        XCTAssertGreaterThan(inked, 200, "no ink drawn", file: file, line: line)
    }

    /// Writes `image` as a PNG in the temp folder and prints where, to look at by eye.
    private func save(_ image: CGImage?, _ name: String) {
        guard let image else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) { print("StatusBarTests: wrote \(url.path)") }
    }

    func testDarkBarGetsWhiteInk() throws {
        let image = screenshot(bar: TestImages.srgb(0.1, 0.15, 0.3), body: TestImages.white)
        let out = StatusBar.clean(image, layout: smallLayout)
        save(out, "statusbar-dark.png")
        try check(image, cleaned: out, barHeight: 54, background: (26, 38, 77), ink: (255, 255, 255))
    }

    func testLightBarGetsBlackInk() throws {
        let image = screenshot(bar: TestImages.srgb(0.95, 0.95, 0.9), body: TestImages.blue)
        let out = StatusBar.clean(image, layout: smallLayout)
        save(out, "statusbar-light.png")
        try check(image, cleaned: out, barHeight: 54, background: (242, 242, 230), ink: (0, 0, 0))
    }

    func testFullSizeScreenshotUsesTheTable() throws {
        let image = screenshot(width: 1179, height: 2556, barHeight: 162, bar: TestImages.white, body: TestImages.blue)
        let out = StatusBar.clean(image)
        save(out, "statusbar-1179x2556.png")
        try check(image, cleaned: out, barHeight: 162, background: (255, 255, 255), ink: (0, 0, 0))
    }

    func testClassicScreenshot() throws {
        let image = screenshot(width: 750, height: 1334, barHeight: 40, bar: TestImages.black, body: TestImages.white)
        let out = StatusBar.clean(image)
        save(out, "statusbar-750x1334.png")
        try check(image, cleaned: out, barHeight: 40, background: (0, 0, 0), ink: (255, 255, 255))
    }

    func testUnknownSizeIsNotCleaned() {
        XCTAssertNil(StatusBar.clean(screenshot(bar: TestImages.white, body: TestImages.blue)))
    }

    func testInkPicksTheStrongerContrast() {
        XCTAssertEqual(StatusBar.ink(on: RGBColor(r: 0.2, g: 0.2, b: 0.2)), RGBColor(r: 1, g: 1, b: 1))
        XCTAssertEqual(StatusBar.ink(on: RGBColor(r: 0.9, g: 0.9, b: 0.9)), RGBColor(r: 0, g: 0, b: 0))
    }
}

/// A small deterministic generator (SplitMix64), so the blobs are the same on every run.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next(in range: ClosedRange<Int>) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(z % span)
    }
}
