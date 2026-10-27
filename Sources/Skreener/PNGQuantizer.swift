import Compression
import CoreGraphics
import Foundation
import ImageIO

/// Shrinks a PNG by reducing it to at most 256 colors (median cut) and writing it as a palette PNG. Screenshots of
/// UI have few colors, so this is usually exact; photos and gradients would show banding, so they are left alone.
///
/// The palette PNG is written here rather than by ImageIO: Core Graphics indexed color spaces can't carry alpha
/// (window captures have it), whereas PNG's PLTE + tRNS chunks can, and the format is small enough to write by hand.
enum PNGQuantizer {
    /// The palette (RGBA, 4 bytes per color), one palette index per pixel, and how far the palette is from the pixels.
    struct Quantized {
        var palette: [UInt8]
        var indices: [UInt8]
        /// Mean error per pixel, 0...255: color channels (weighted by opacity) averaged, plus the alpha difference.
        var meanError: Double
    }

    /// Above this mean error (out of 255) the result is no longer "looks the same", and the original is kept.
    static let defaultMaxError = 1.5

    // MARK: Quantizing

    private struct Entry {
        var r: UInt8, g: UInt8, b: UInt8, a: UInt8
        var count: Int
        func channel(_ axis: Int) -> UInt8 { axis == 0 ? r : axis == 1 ? g : axis == 2 ? b : a }
    }

    /// Reduces straight (not premultiplied) RGBA pixels to at most `maxColors` colors. Exact when the image has no
    /// more colors than that. Fully transparent pixels all count as one color, whatever their RGB.
    static func quantize(rgba: [UInt8], maxColors: Int = 256) -> Quantized? {
        let pixelCount = rgba.count / 4
        guard pixelCount > 0, rgba.count % 4 == 0, (2...256).contains(maxColors) else { return nil }

        var histogram: [UInt32: Int] = [:]
        var keys = [UInt32](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let a = rgba[i * 4 + 3]
            let key: UInt32 = a == 0 ? 0 : UInt32(rgba[i * 4]) << 24 | UInt32(rgba[i * 4 + 1]) << 16
                | UInt32(rgba[i * 4 + 2]) << 8 | UInt32(a)
            keys[i] = key
            histogram[key, default: 0] += 1
        }
        // Sorted so the same image always gives the same palette (dictionary order changes from run to run).
        var entries = histogram.sorted { $0.key < $1.key }.map { key, count in
            Entry(r: UInt8(key >> 24), g: UInt8((key >> 16) & 0xFF), b: UInt8((key >> 8) & 0xFF), a: UInt8(key & 0xFF), count: count)
        }

        // Median cut: boxes are ranges of `entries`; the box with the widest spread is split at its median.
        var boxes: [Range<Int>] = [0..<entries.count]
        while boxes.count < maxColors {
            var best: (index: Int, axis: Int, score: Double)?
            for (i, box) in boxes.enumerated() where box.count > 1 {
                let (axis, range) = widestAxis(entries[box])
                guard range > 0 else { continue }
                let pixels = entries[box].reduce(0) { $0 + $1.count }
                let score = Double(range) * Double(pixels)
                if best == nil || score > best!.score { best = (i, axis, score) }
            }
            guard let pick = best else { break }   // every box is a single color
            let box = boxes[pick.index]
            entries[box].sort { $0.channel(pick.axis) < $1.channel(pick.axis) }
            let total = entries[box].reduce(0) { $0 + $1.count }
            var running = 0, split = box.lowerBound + 1
            for i in box.lowerBound..<box.upperBound - 1 {
                running += entries[i].count
                split = i + 1
                if running * 2 >= total { break }
            }
            boxes[pick.index] = box.lowerBound..<split
            boxes.append(split..<box.upperBound)
        }

        // Each box becomes a palette color (the pixel-weighted average); the colors in it map to that entry.
        var palette: [UInt8] = []
        var indexOf: [UInt32: UInt8] = [:]
        var weightedError = 0.0
        for (n, box) in boxes.enumerated() {
            var sum = [0, 0, 0, 0], total = 0
            for e in entries[box] {
                sum[0] += Int(e.r) * e.count; sum[1] += Int(e.g) * e.count
                sum[2] += Int(e.b) * e.count; sum[3] += Int(e.a) * e.count
                total += e.count
            }
            let mean = sum.map { UInt8((Double($0) / Double(total)).rounded()) }
            palette += mean
            for e in entries[box] {
                let key = UInt32(e.r) << 24 | UInt32(e.g) << 16 | UInt32(e.b) << 8 | UInt32(e.a)
                indexOf[e.a == 0 ? 0 : key] = UInt8(n)
                weightedError += error(of: e, against: mean) * Double(e.count)
            }
        }

        var indices = [UInt8](repeating: 0, count: pixelCount)
        var lastKey = keys[0], lastIndex = indexOf[keys[0]] ?? 0
        for i in 0..<pixelCount {
            if keys[i] != lastKey { lastKey = keys[i]; lastIndex = indexOf[lastKey] ?? 0 }
            indices[i] = lastIndex
        }
        return Quantized(palette: palette, indices: indices, meanError: weightedError / Double(pixelCount))
    }

    private static func widestAxis(_ box: ArraySlice<Entry>) -> (axis: Int, range: Int) {
        var best = (axis: 0, range: 0)
        for axis in 0..<4 {
            var lo = 255, hi = 0
            for e in box {
                let v = Int(e.channel(axis))
                lo = min(lo, v); hi = max(hi, v)
            }
            if hi - lo > best.range { best = (axis, hi - lo) }
        }
        return best
    }

    private static func error(of e: Entry, against p: [UInt8]) -> Double {
        let color = Double(abs(Int(e.r) - Int(p[0])) + abs(Int(e.g) - Int(p[1])) + abs(Int(e.b) - Int(p[2]))) / 3
        return color * Double(e.a) / 255 + Double(abs(Int(e.a) - Int(p[3])))
    }

    // MARK: Reading pixels

    /// The pixels of `image` as straight RGBA, drawn in the image's own RGB color space (so no color conversion).
    /// Nil for non-RGB images, or a color space that can't be drawn into 8 bits per channel.
    static func rgba(of image: CGImage) -> [UInt8]? {
        guard let space = image.colorSpace, space.model == .rgb else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = Int(bytes[i + 3])
            guard a != 0, a != 255 else { continue }
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, (Int(bytes[i + c]) * 255 + a / 2) / a)) }
        }
        return bytes
    }

    // MARK: Whole PNG files

    /// `png` re-encoded with a palette, or nil when that isn't worth it: not a PNG ImageIO can read as RGB, more error
    /// than `maxError` (the original is the better picture), or the result isn't smaller.
    static func compressed(png: Data, maxError: Double = defaultMaxError) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = image.colorSpace, let pixels = rgba(of: image),
              let q = quantize(rgba: pixels), q.meanError <= maxError else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var dpi: (Double, Double)?
        if let x = properties?[kCGImagePropertyDPIWidth] as? Double, let y = properties?[kCGImagePropertyDPIHeight] as? Double {
            dpi = (x, y)
        }
        guard let out = IndexedPNG.encode(width: image.width, height: image.height, palette: q.palette, indices: q.indices,
                                          colorSpace: space, dpi: dpi), out.count < png.count else { return nil }
        return out
    }
}

/// Writes a palette PNG: IHDR, color profile, pixel density, PLTE, tRNS, IDAT, IEND.
enum IndexedPNG {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// `palette` is RGBA (4 bytes per color, at most 256 colors), `indices` one entry per pixel, row by row. Colors
    /// are in `colorSpace`, which is recorded in the file (sRGB flag or the ICC profile). `dpi` keeps a Retina
    /// screenshot's size in points when it is opened again.
    static func encode(width: Int, height: Int, palette: [UInt8], indices: [UInt8], colorSpace: CGColorSpace? = nil,
                       dpi: (Double, Double)? = nil) -> Data? {
        let colors = palette.count / 4
        guard width > 0, height > 0, (1...256).contains(colors), indices.count == width * height else { return nil }
        let depth = colors <= 2 ? 1 : colors <= 4 ? 2 : colors <= 16 ? 4 : 8

        // Rows start with a filter byte (0: none; palette indices don't predict well from their neighbours' values).
        let rowBytes = (width * depth + 7) / 8
        var raw = [UInt8](repeating: 0, count: (rowBytes + 1) * height)
        for y in 0..<height {
            let base = y * (rowBytes + 1) + 1
            for x in 0..<width {
                let v = indices[y * width + x]
                if depth == 8 {
                    raw[base + x] = v
                } else {
                    raw[base + x * depth / 8] |= v << UInt8(8 - depth - (x * depth) % 8)
                }
            }
        }
        guard let idat = zlib(raw) else { return nil }

        var out = Data(signature)
        var header: [UInt8] = []
        header += bigEndian(UInt32(width)) + bigEndian(UInt32(height))
        header += [UInt8(depth), 3, 0, 0, 0]
        chunk("IHDR", header, into: &out)

        if let space = colorSpace {
            if (space.name as String?) == (CGColorSpace.sRGB as String) {
                chunk("sRGB", [0], into: &out)
            } else if let icc = space.copyICCData(), let packed = zlib([UInt8](icc as Data)) {
                chunk("iCCP", Array("ICC".utf8) + [0, 0] + packed, into: &out)
            }
        }
        if let (dx, dy) = dpi, dx > 0, dy > 0 {
            chunk("pHYs", bigEndian(UInt32((dx / 0.0254).rounded())) + bigEndian(UInt32((dy / 0.0254).rounded())) + [1], into: &out)
        }

        var plte: [UInt8] = [], alpha: [UInt8] = []
        for i in 0..<colors {
            plte += palette[i * 4..<i * 4 + 3]
            alpha.append(palette[i * 4 + 3])
        }
        chunk("PLTE", plte, into: &out)
        if let last = alpha.lastIndex(where: { $0 != 255 }) { chunk("tRNS", Array(alpha[0...last]), into: &out) }
        chunk("IDAT", idat, into: &out)
        chunk("IEND", [], into: &out)
        return out
    }

    private static func chunk(_ type: String, _ body: [UInt8], into out: inout Data) {
        let name = Array(type.utf8)
        out.append(contentsOf: bigEndian(UInt32(body.count)))
        out.append(contentsOf: name)
        out.append(contentsOf: body)
        out.append(contentsOf: bigEndian(crc32(name + body)))
    }

    private static func bigEndian(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    /// zlib stream: the Compression framework's ZLIB is bare deflate, so the 2-byte header and the Adler-32 trailer
    /// that PNG expects are added around it.
    static func zlib(_ raw: [UInt8]) -> [UInt8]? {
        guard !raw.isEmpty else { return nil }
        var buffer = [UInt8](repeating: 0, count: raw.count + raw.count / 8 + 1024)   // deflate's worst case is a bit bigger
        let size = buffer.withUnsafeMutableBufferPointer { dst in
            raw.withUnsafeBufferPointer { src in
                compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard size > 0 else { return nil }
        return [0x78, 0x9C] + buffer[0..<size] + bigEndian(adler32(raw))
    }
}
