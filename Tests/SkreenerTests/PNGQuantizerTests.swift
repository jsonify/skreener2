import AppKit
import ImageIO
import XCTest
@testable import Skreener

final class PNGQuantizerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Quantizing

    /// `colors` repeated over `count` pixels.
    private func pixels(_ colors: [[UInt8]], count: Int) -> [UInt8] {
        var out: [UInt8] = []
        for i in 0..<count { out += colors[i % colors.count] }
        return out
    }

    private func color(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> [UInt8] {
        [UInt8(r), UInt8(g), UInt8(b), UInt8(a)]
    }

    private func expand(_ indices: [UInt8], _ palette: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        for i in indices {
            let at = Int(i) * 4
            out += palette[at..<at + 4]
        }
        return out
    }

    private func reconstruct(_ q: PNGQuantizer.Quantized) -> [UInt8] {
        expand(q.indices, q.palette)
    }

    func testFewColorsAreExact() throws {
        let colors: [[UInt8]] = [[255, 255, 255, 255], [10, 20, 30, 255], [200, 0, 0, 128], [0, 0, 0, 0]]
        let rgba = pixels(colors, count: 400)
        let q = try XCTUnwrap(PNGQuantizer.quantize(rgba: rgba))
        XCTAssertEqual(q.palette.count / 4, 4)
        XCTAssertEqual(q.meanError, 0)
        XCTAssertEqual(reconstruct(q), rgba)
    }

    func testTransparentPixelsAreOneColorWhateverTheirRGB() throws {
        let rgba: [UInt8] = [1, 2, 3, 0, 200, 100, 50, 0, 9, 9, 9, 255]
        let q = try XCTUnwrap(PNGQuantizer.quantize(rgba: rgba))
        XCTAssertEqual(q.palette.count / 4, 2)
        XCTAssertEqual(q.indices[0], q.indices[1])
        XCTAssertEqual(q.meanError, 0)
    }

    func testExactlyTheMaximumNumberOfColorsIsExact() throws {
        let colors: [[UInt8]] = (0..<256).map { i in color(i, 255 - i, i / 2) }
        let rgba = pixels(colors, count: 256 * 3)
        let q = try XCTUnwrap(PNGQuantizer.quantize(rgba: rgba))
        XCTAssertEqual(q.palette.count / 4, 256)
        XCTAssertEqual(q.meanError, 0)
        XCTAssertEqual(reconstruct(q), rgba)
    }

    func testMoreColorsAreReducedWithABoundedError() throws {
        // 32 × 32 colors, 8 apart in red and green.
        let colors: [[UInt8]] = (0..<1024).map { i in color(i % 32 * 8, i / 32 * 8, 128) }
        let q = try XCTUnwrap(PNGQuantizer.quantize(rgba: pixels(colors, count: 1024)))
        XCTAssertLessThanOrEqual(q.palette.count / 4, 256)
        XCTAssertGreaterThan(q.meanError, 0)
        XCTAssertLessThan(q.meanError, 8)
        XCTAssertTrue(q.indices.allSatisfy { Int($0) < q.palette.count / 4 })
    }

    func testSameImageGivesSamePalette() throws {
        let colors: [[UInt8]] = (0..<1000).map { i in color(i % 40 * 6, i / 40 * 10, i % 7 * 30) }
        let rgba = pixels(colors, count: 1000)
        XCTAssertEqual(PNGQuantizer.quantize(rgba: rgba)?.palette, PNGQuantizer.quantize(rgba: rgba)?.palette)
    }

    // MARK: Encoder

    private func decode(_ data: Data) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (try XCTUnwrap(PNGQuantizer.rgba(of: image)), image.width, image.height)
    }

    /// Every bit depth the encoder picks (1, 2, 4 and 8), on a width that isn't a multiple of 8.
    func testEncodedPNGDecodesToTheSamePixels() throws {
        for colorCount in [2, 3, 12, 200] {
            let width = 13, height = 7
            var palette: [UInt8] = []
            for i in 0..<colorCount {
                let alpha: Int = i % 5 == 0 ? 255 : 255 - (i % 3) * 40
                palette += color(i * 7 % 256, i * 13 % 256, 255 - i, alpha)
            }
            let indices: [UInt8] = (0..<width * height).map { (i: Int) -> UInt8 in UInt8(i * 3 % colorCount) }
            let expected = expand(indices, palette)

            let png = try XCTUnwrap(IndexedPNG.encode(width: width, height: height, palette: palette, indices: indices,
                                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
            let decoded = try decode(png)
            XCTAssertEqual(decoded.width, width)
            XCTAssertEqual(decoded.height, height)
            XCTAssertEqual(decoded.pixels.count, expected.count)
            // Transparent-ish pixels go through premultiplication once, so allow a little rounding.
            for (a, b) in zip(decoded.pixels, expected) {
                XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), 6, "\(colorCount) colors")
            }
        }
    }

    func testOpaqueAndFullyTransparentPixelsRoundTripExactly() throws {
        let palette: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0]
        let indices: [UInt8] = [0, 1, 2, 0, 1, 2]
        let png = try XCTUnwrap(IndexedPNG.encode(width: 3, height: 2, palette: palette, indices: indices))
        let decoded = try decode(png)
        XCTAssertEqual(decoded.pixels, [255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0])
    }

    func testChecksums() {
        XCTAssertEqual(IndexedPNG.crc32(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(IndexedPNG.adler32(Array("Wikipedia".utf8)), 0x11E6_0398)
    }

    func testRejectsMismatchedInput() {
        XCTAssertNil(IndexedPNG.encode(width: 2, height: 2, palette: [0, 0, 0, 255], indices: [0, 0, 0]))
        XCTAssertNil(IndexedPNG.encode(width: 2, height: 2, palette: [], indices: [0, 0, 0, 0]))
    }

    // MARK: Whole PNGs

    private func png(of image: NSImage) throws -> Data {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    /// A few flat rectangles, like a UI.
    private func flatScreenshot() -> NSImage {
        TestImages.image(width: 400, height: 300) { r in
            NSColor.white.setFill(); r.fill()
            NSColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1).setFill()
            NSRect(x: 20, y: 20, width: 200, height: 100).fill()
            NSColor(srgbRed: 0.9, green: 0.3, blue: 0.2, alpha: 1).setFill()
            NSRect(x: 150, y: 80, width: 200, height: 150).fill()
        }
    }

    func testFlatScreenshotShrinksWithoutChangingPixels() throws {
        let original = try png(of: flatScreenshot())
        let smaller = try XCTUnwrap(PNGQuantizer.compressed(png: original))
        XCTAssertLessThan(smaller.count, original.count)
        let before = try decode(original), after = try decode(smaller)
        XCTAssertEqual(after.width, before.width)
        XCTAssertEqual(after.height, before.height)
        XCTAssertEqual(after.pixels, before.pixels)
        print("PNG compression fixture: \(original.count) -> \(smaller.count) bytes")
    }

    func testKeepsPixelDensity() throws {
        let retina = TestImages.image(width: 400, height: 300, points: NSSize(width: 200, height: 150)) { r in
            NSColor.white.setFill(); r.fill()
        }
        let smaller = try XCTUnwrap(PNGQuantizer.compressed(png: try png(of: retina)))
        let image = try XCTUnwrap(NSImage(data: smaller))
        XCTAssertEqual(image.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 150, accuracy: 0.5)
    }

    /// Noise has far too many colors for a palette: the original is the better picture.
    func testKeepsTheOriginalWhenTheErrorIsTooBig() throws {
        var seed: UInt32 = 12345
        func next() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 24) / 255
        }
        let noise = TestImages.image(width: 128, height: 128) { _ in
            for x in 0..<128 {
                for y in 0..<128 {
                    NSColor(srgbRed: next(), green: next(), blue: next(), alpha: 1).setFill()
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
        }
        let original = try png(of: noise)
        XCTAssertNil(PNGQuantizer.compressed(png: original))
        XCTAssertNotNil(PNGQuantizer.compressed(png: original, maxError: 100))
    }

    func testKeepsTheOriginalWhenItIsNotAPNG() {
        XCTAssertNil(PNGQuantizer.compressed(png: Data("not an image".utf8)))
    }

    // MARK: Files

    func testCompressImageReplacesTheFileOnlyWhenSmaller() throws {
        let url = dir.appendingPathComponent("shot.png")
        let original = try png(of: flatScreenshot())
        try original.write(to: url)
        let savings = try XCTUnwrap(Compressor.compressImage(at: url))
        XCTAssertEqual(savings.before, original.count)
        XCTAssertEqual(savings.after, try Data(contentsOf: url).count)
        XCTAssertLessThan(savings.after, savings.before)
        // Already compressed: nothing more to gain, and the file is left as it is.
        let compressed = try Data(contentsOf: url)
        XCTAssertNil(Compressor.compressImage(at: url))
        XCTAssertEqual(try Data(contentsOf: url), compressed)
    }

    func testSummaryShowsBothSizes() {
        let text = Compressor.summary(before: 1_200_000, after: 310_000)
        XCTAssertTrue(text.contains(" → "), text)
        XCTAssertTrue(text.contains("MB") && text.contains("KB"), text)
    }

    func testOnlyPNGAndMP4CanBeCompressed() {
        XCTAssertTrue(Compressor.canCompress(URL(fileURLWithPath: "/a/b.PNG")))
        XCTAssertTrue(Compressor.canCompress(URL(fileURLWithPath: "/a/b.mp4")))
        XCTAssertFalse(Compressor.canCompress(URL(fileURLWithPath: "/a/b.jpg")))
        XCTAssertFalse(Compressor.canCompress(URL(fileURLWithPath: "/a/b.gif")))
    }
}
