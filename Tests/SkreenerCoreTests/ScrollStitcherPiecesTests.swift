import CoreGraphics
import XCTest
@testable import SkreenerCore

/// Taking finished pieces out of the stitcher as it goes (the iPhone's broadcast extension, #456): joined top to
/// bottom with what is left at the end, they make the same image as `makeImage()` of a stitcher that kept everything.
final class ScrollStitcherPiecesTests: XCTestCase {
    private let width = 192, frameHeight = 240

    /// Gray rows, each its own pseudo-random pattern of mid-range values, like lines of text (the same for the same seed).
    private func rows(_ count: Int, seed: UInt32) -> [[UInt8]] {
        var state = seed
        return (0..<count).map { _ in
            (0..<width).map { _ in
                state = state &* 1_664_525 &+ 1_013_904_223
                return UInt8(64 + (state >> 24) / 2)
            }
        }
    }

    /// An opaque sRGB image of `rows` (the first row at the top).
    private func image(_ rows: [[UInt8]]) -> CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(rows.count * width * 4)
        for row in rows {
            for v in row { bytes += [v, v, v, 255] }
        }
        return CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// The frames of a page scrolled by `steps` pixels at a time, each with `header` rows above and `footer` below.
    private func frames(page: [[UInt8]], steps: [Int], header: [[UInt8]] = [], footer: [[UInt8]] = []) -> [CGImage] {
        let content = frameHeight - header.count - footer.count
        var top = 0
        var result = [image(header + page[top..<(top + content)] + footer)]
        for step in steps {
            top += step
            result.append(image(header + page[top..<(top + content)] + footer))
        }
        return result
    }

    /// The RGBA bytes of `parts` stacked top to bottom, drawn as the stitcher draws.
    private func pixels(_ parts: [CGImage]) -> (height: Int, bytes: [UInt8]) {
        let height = parts.reduce(0) { $0 + $1.height }
        guard height > 0 else { return (0, []) }
        var bytes = [UInt8](repeating: 0, count: height * width * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            var y = height
            for p in parts {
                y -= p.height
                ctx.draw(p, in: CGRect(x: 0, y: y, width: width, height: p.height))
            }
        }
        return (height, bytes)
    }

    /// Feeds `frames` to a stitcher that keeps everything and to one whose pieces are taken after every frame, and
    /// checks the joined pieces match `makeImage()`. Returns the untouched stitcher's height.
    @discardableResult
    private func checkTakingPieces(_ frames: [CGImage], keepingLast keep: Int,
                                   file: StaticString = #filePath, line: UInt = #line) -> Int {
        let whole = ScrollStitcher(first: frames[0], ignoreRight: 0)
        let taking = ScrollStitcher(first: frames[0], ignoreRight: 0)
        var taken: [CGImage] = []
        for frame in frames.dropFirst() {
            let a = whole.add(frame), b = taking.add(frame)
            XCTAssertEqual("\(a)", "\(b)", file: file, line: line)
            taken += taking.takeFinishedPieces(keepingLast: keep)
        }
        XCTAssertFalse(taken.isEmpty, "nothing was taken", file: file, line: line)
        XCTAssertEqual(whole.height, taking.height, file: file, line: line)
        let joined = taken + taking.takeRemaining()
        let expected = pixels([whole.makeImage()!])
        let actual = pixels(joined)
        XCTAssertEqual(actual.height, whole.height, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        XCTAssertTrue(actual.bytes == expected.bytes, "joined pieces differ from makeImage()", file: file, line: line)
        return whole.height
    }

    func testTakenPiecesJoinToTheWholeImage() {
        let page = rows(1600, seed: 1)
        let steps = [30, 45, 0, 60, 80, 25, 100, 70, 50, 90, 120, 40, 65, 85, 110]
        let height = checkTakingPieces(frames(page: page, steps: steps), keepingLast: frameHeight)
        XCTAssertEqual(height, frameHeight + steps.reduce(0, +))
    }

    func testTakenPiecesWithStickyHeaderAndFooter() {
        let page = rows(1600, seed: 3)
        let steps = [40, 55, 70, 35, 90, 60, 80, 45, 100]
        let header = rows(24, seed: 7), footer = rows(30, seed: 9)
        checkTakingPieces(frames(page: page, steps: steps, header: header, footer: footer), keepingLast: frameHeight / 2)
    }

    func testNothingMovedGivesTheFirstFrame() {
        let page = rows(400, seed: 5)
        let all = frames(page: page, steps: [0, 0])
        let stitcher = ScrollStitcher(first: all[0], ignoreRight: 0)
        for frame in all.dropFirst() { _ = stitcher.add(frame) }
        XCTAssertTrue(stitcher.takeFinishedPieces(keepingLast: 0).isEmpty)
        let rest = stitcher.takeRemaining()
        XCTAssertEqual(rest.count, 1)
        XCTAssertEqual(rest.first?.height, frameHeight)
    }

    func testFinishedStitcherIgnoresFrames() {
        let page = rows(600, seed: 6)
        let all = frames(page: page, steps: [50, 50])
        let stitcher = ScrollStitcher(first: all[0], ignoreRight: 0)
        _ = stitcher.add(all[1])
        _ = stitcher.takeRemaining()
        guard case .full = stitcher.add(all[2]) else { return XCTFail("expected .full after takeRemaining") }
        XCTAssertTrue(stitcher.takeRemaining().isEmpty)
    }
}
