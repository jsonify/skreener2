import CoreGraphics

extension FormattedText {
    /// An RGBA copy of an image on white, for reading how its words are drawn.
    struct Bitmap: Sendable {
        let width: Int
        let height: Int
        /// RGBA, 8 bits each, row 0 at the top.
        let bytes: [UInt8]

        init(width: Int, height: Int, bytes: [UInt8]) {
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        init?(_ image: CGImage) {
            let w = image.width, h = image.height
            guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var data = [UInt8](repeating: 255, count: w * h * 4)
            let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            self.init(width: w, height: h, bytes: data)
        }

        /// The color at `x`, `y` (pixels, bottom-left origin).
        func color(_ x: Int, _ y: Int) -> RGB {
            let i = ((height - 1 - y) * width + x) * 4
            return RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
        }

        /// The pixel bounds of `rect` (pixels, bottom-left origin) inside the bitmap, as half-open ranges.
        private func pixels(_ rect: CGRect) -> (x: Range<Int>, y: Range<Int>)? {
            let box = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !box.isNull, box.width >= 1, box.height >= 1 else { return nil }
            return (Int(box.minX)..<Int(box.maxX), Int(box.minY)..<Int(box.maxY))
        }

        /// What the pixels say about the word in `rect` (pixels, bottom-left origin): the background (the most common
        /// color in the box, when it fills at least half of it), the ink's color (its strongest pixels) and its stroke
        /// width in pixels (ink per crossing of a letter stroke on the middle rows).
        func look(_ rect: CGRect) -> Look {
            guard let box = pixels(rect), box.x.count >= 2, box.y.count >= 6 else { return Look() }
            let xs = box.x, ys = box.y

            let inside = ys.flatMap { y in xs.map { x in color(x, y) } }
            guard let bg = FormattedText.mostCommon(inside) else { return Look() }
            let even = inside.filter { $0.distance(to: bg) <= 0.04 }.count * 2 >= inside.count

            let far = inside.map { $0.distance(to: bg) }.max() ?? 0
            guard far >= 0.2 else { return Look(background: even ? bg : nil) }

            var ink = 0.0, crossings = 0
            let quarter = ys.count / 4
            for y in (ys.lowerBound + quarter)..<(ys.upperBound - quarter) {
                var inStroke = false
                for x in xs {
                    let s = min(1, color(x, y).distance(to: bg) / far)
                    ink += s
                    if s >= 0.5, !inStroke { crossings += 1 }
                    inStroke = s >= 0.5
                }
            }
            var sum = (r: 0.0, g: 0.0, b: 0.0), n = 0.0
            for y in ys {
                for x in xs {
                    let c = color(x, y)
                    guard c.distance(to: bg) >= far * 0.8 else { continue }
                    sum = (sum.r + c.r, sum.g + c.g, sum.b + c.b)
                    n += 1
                }
            }
            return Look(stroke: crossings > 0 ? ink / Double(crossings) : nil,
                        ink: n > 0 ? RGB(r: sum.r / n, g: sum.g / n, b: sum.b / n) : nil,
                        background: even ? bg : nil)
        }

        /// Whether a bullet (a small blob about as wide as tall, and nothing else) sits just left of the line in `rect`
        /// (pixels, bottom-left origin), for bullets Vision leaves out of the text.
        func hasBullet(leftOf rect: CGRect) -> Bool {
            let h = rect.height
            guard h >= 6, let box = pixels(CGRect(x: rect.minX - h * 1.6, y: rect.minY, width: h * 1.6 - 1, height: h)),
                  box.x.count >= 3 else { return false }
            let xs = box.x, ys = box.y
            var all: [RGB] = []
            for y in ys { for x in xs { all.append(color(x, y)) } }
            let bg = FormattedText.median(all)
            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min, count = 0
            for y in ys {
                for x in xs where color(x, y).distance(to: bg) > 0.3 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    count += 1
                }
            }
            guard count > 0 else { return false }
            let w = CGFloat(maxX - minX + 1), bh = CGFloat(maxY - minY + 1)
            let mid = (CGFloat(minY + maxY + 1) / 2 - rect.minY) / h
            return w >= h * 0.12 && w <= h * 0.6 && bh >= h * 0.12 && bh <= h * 0.6
                && w / bh >= 0.6 && w / bh <= 1.6                     // round or square, not a dash
                && CGFloat(count) >= w * bh * 0.25                     // a blob, not a stray mark
                && mid >= 0.2 && mid <= 0.8                            // beside the letters, not above or below
                && CGFloat(maxX) < rect.minX - h * 0.1                 // apart from the first letter
        }
    }
}
