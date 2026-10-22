import CoreGraphics
import XCTest
@testable import Skreener

/// The editor's measuring tools: pixel colors and their formats (#108), contrast (#109) and the ruler (#107).
final class ColorToolsTests: XCTestCase {
    /// A `width` × `height` sRGB image whose pixel (x, y), top-left origin, is `color(x, y)` as 0–255 RGB.
    private func image(_ width: Int, _ height: Int, _ color: (Int, Int) -> (Int, Int, Int)) -> PixelBuffer {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = color(x, y), i = (y * width + x) * 4
                bytes[i] = UInt8(r); bytes[i + 1] = UInt8(g); bytes[i + 2] = UInt8(b)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return PixelBuffer(cg)!
    }

    // MARK: Pixel colors

    func testPixelColorIsReadTopLeft() {
        let buf = image(4, 4) { x, y in x == 1 && y == 0 ? (255, 0, 0) : (255, 255, 255) }
        XCTAssertEqual(ColorFormat.hex.string(for: buf.color(x: 1, y: 0)!), "#FF0000")
        XCTAssertEqual(ColorFormat.hex.string(for: buf.color(x: 1, y: 3)!), "#FFFFFF")
        XCTAssertNil(buf.color(x: 4, y: 0))
        XCTAssertNil(buf.color(x: -1, y: 0))
    }

    func testDarkestNearbyFindsTheTextColor() {
        // White, with a 1-px dark gray stroke 5 px to the right of the pointer.
        let buf = image(40, 40) { x, _ in x == 25 ? (30, 30, 30) : (255, 255, 255) }
        XCTAssertEqual(ColorFormat.hex.string(for: buf.darkest(x: 20, y: 20)!), "#1E1E1E")
        // Out of reach: just white.
        XCTAssertEqual(ColorFormat.hex.string(for: buf.darkest(x: 5, y: 20, radius: 10)!), "#FFFFFF")
        XCTAssertNil(buf.darkest(x: 50, y: 20))
    }

    func testAverageOfHalfBlackHalfWhiteIsMidGray() {
        let buf = image(10, 10) { x, _ in x < 5 ? (0, 0, 0) : (255, 255, 255) }
        XCTAssertEqual(ColorFormat.hex.string(for: buf.average(in: CGRect(x: 0, y: 0, width: 10, height: 10))!), "#808080")
        // Clipped to the image.
        XCTAssertEqual(ColorFormat.hex.string(for: buf.average(in: CGRect(x: 5, y: -5, width: 20, height: 20))!), "#FFFFFF")
        XCTAssertNil(buf.average(in: CGRect(x: 20, y: 20, width: 5, height: 5)))
    }

    // MARK: Formats

    func testEveryFormat() {
        let c = RGBColor(r8: 255, g8: 194, b8: 0)
        let expected: [ColorFormat: String] = [
            .hex: "#FFC200",
            .hexNoHash: "FFC200",
            .css: "rgba(255, 194, 0, 1)",
            .rgbUnit: "(1.00, 0.76, 0.00)",
            .android: "0xFFFFC200",
            .uiColor: "UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)",
            .csharp: "Color.FromArgb(255, 194, 0)",
            .oklch: "oklch(84.60% 0.173 85.6)",
        ]
        for f in ColorFormat.allCases { XCTAssertEqual(f.string(for: c), expected[f], f.title) }
        XCTAssertEqual(ColorFormat.oklch.display(for: c), "84.60% 0.173 85.6")
        XCTAssertEqual(ColorFormat.hex.display(for: c), "#FFC200")
    }

    func testTranslucentFormats() {
        let c = RGBColor(r: 1, g: 0, b: 0, a: 0.5)
        XCTAssertEqual(ColorFormat.css.string(for: c), "rgba(255, 0, 0, 0.5)")
        XCTAssertEqual(ColorFormat.android.string(for: c), "0x80FF0000")
        XCTAssertEqual(ColorFormat.csharp.string(for: c), "Color.FromArgb(128, 255, 0, 0)")
    }

    func testOKLCHOfGraysHasNoHue() {
        XCTAssertEqual(ColorFormat.oklch.string(for: RGBColor(r: 1, g: 1, b: 1)), "oklch(100.00% 0.000 0.0)")
        XCTAssertEqual(ColorFormat.oklch.string(for: RGBColor(r: 0, g: 0, b: 0)), "oklch(0.00% 0.000 0.0)")
        let red = ColorFormat.oklchComponents(RGBColor(r: 1, g: 0, b: 0))
        XCTAssertEqual(red.l, 0.628, accuracy: 0.001)
        XCTAssertEqual(red.c, 0.258, accuracy: 0.001)
        XCTAssertEqual(red.h, 29.23, accuracy: 0.01)
    }

    // MARK: Contrast

    func testWCAG() {
        let black = RGBColor(r: 0, g: 0, b: 0), white = RGBColor(r: 1, g: 1, b: 1), gray = RGBColor(r8: 0x77, g8: 0x77, b8: 0x77)
        XCTAssertEqual(Contrast.wcag(black, white), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.wcag(white, black), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.wcag(gray, white), 4.48, accuracy: 0.005)
        XCTAssertEqual(Contrast.wcagRating(Contrast.wcag(gray, white)), "AA Large")   // just short of AA
        XCTAssertEqual(Contrast.wcagRating(21), "AAA")
        XCTAssertEqual(Contrast.wcagRating(4.5), "AA")
        XCTAssertEqual(Contrast.wcagRating(1.2), "Fail")
        XCTAssertEqual(Contrast.summary(text: gray, background: white, method: .wcag), "4.47:1 · AA Large")
    }

    func testAPCA() {
        let black = RGBColor(r: 0, g: 0, b: 0), white = RGBColor(r: 1, g: 1, b: 1), gray = RGBColor(r8: 0x77, g8: 0x77, b8: 0x77)
        XCTAssertEqual(Contrast.apca(text: black, background: white), 106.04, accuracy: 0.05)
        XCTAssertEqual(Contrast.apca(text: white, background: black), -107.88, accuracy: 0.05)
        XCTAssertEqual(Contrast.apca(text: gray, background: white), 71.11, accuracy: 0.05)
        XCTAssertEqual(Contrast.apca(text: white, background: white), 0)
        XCTAssertEqual(Contrast.summary(text: gray, background: white, method: .apca), "Lc 71 · Content text")
    }

    func testDominantColorsOfTextOnABackground() {
        // White with 10 % of the pixels a dark blue "text" and a few stray red pixels.
        let buf = image(100, 20) { x, y in
            if x % 10 == 0 { return (20, 30, 120) }
            if x == 55, y == 5 { return (255, 0, 0) }
            return (255, 255, 255)
        }
        let found = buf.dominantColors(in: CGRect(x: 0, y: 0, width: 100, height: 20))!
        XCTAssertEqual(ColorFormat.hex.string(for: found.background), "#FFFFFF")
        XCTAssertEqual(ColorFormat.hex.string(for: found.foreground), "#141E78")
    }

    func testDominantColorsOfOneColor() {
        let buf = image(10, 10) { _, _ in (10, 200, 10) }
        let found = buf.dominantColors(in: CGRect(x: 0, y: 0, width: 10, height: 10))!
        XCTAssertEqual(found.background, found.foreground)
        XCTAssertNil(buf.dominantColors(in: CGRect(x: 50, y: 50, width: 10, height: 10)))
    }

    // MARK: Ruler

    /// 200 × 100 white, with a blue box from x 40 to 139 and y 20 to 69 (100 × 50 px) that has a 2-px black border,
    /// and a second blue box 40 px to its right.
    private func boxes() -> PixelBuffer {
        image(220, 100) { x, y in
            if (180..<200).contains(x), (20..<70).contains(y) { return (0, 0, 255) }
            guard (40..<140).contains(x), (20..<70).contains(y) else { return (255, 255, 255) }
            if x < 42 || x >= 138 || y < 22 || y >= 68 { return (0, 0, 0) }
            return (0, 0, 255)
        }
    }

    func testRulerMeasuresTheInsideOfABox() {
        let buf = boxes()
        XCTAssertEqual(RulerScanner.span(in: buf, x: 90, y: 45, axis: .horizontal), 42...137)   // 96 px inside the border
        XCTAssertEqual(RulerScanner.span(in: buf, x: 90, y: 45, axis: .vertical), 22...67)      // 46 px
    }

    func testRulerWithShiftIncludesTheBorder() {
        let buf = boxes()
        XCTAssertEqual(RulerScanner.span(in: buf, x: 90, y: 45, axis: .horizontal, outer: true), 40...139)   // 100 px
        XCTAssertEqual(RulerScanner.span(in: buf, x: 90, y: 45, axis: .vertical, outer: true), 20...69)      // 50 px
    }

    func testRulerOuterIgnoresTheBackgroundAroundABorderlessBox() {
        // The right box has no border: past its edge is the white background, far wider than a border.
        XCTAssertEqual(RulerScanner.span(in: boxes(), x: 190, y: 45, axis: .horizontal, outer: true), 180...199)
    }

    func testRulerMeasuresTheGapBetweenBoxes() {
        XCTAssertEqual(RulerScanner.span(in: boxes(), x: 160, y: 45, axis: .horizontal), 140...179)   // 40 px
    }

    func testRulerRunsToTheImageEdge() {
        let buf = boxes()
        XCTAssertEqual(RulerScanner.span(in: buf, x: 5, y: 5, axis: .horizontal), 0...219)
        XCTAssertNil(RulerScanner.span(in: buf, x: 220, y: 5, axis: .horizontal))
    }

    func testRulerToleratesSlightNoise() {
        // Alternating 250/255 is one color within the default tolerance, not within 2.
        let buf = image(30, 1) { x, _ in x % 2 == 0 ? (255, 255, 255) : (250, 250, 250) }
        XCTAssertEqual(RulerScanner.span(in: buf, x: 10, y: 0, axis: .horizontal), 0...29)
        XCTAssertEqual(RulerScanner.span(in: buf, x: 10, y: 0, axis: .horizontal, tolerance: 2), 10...10)
    }
}
