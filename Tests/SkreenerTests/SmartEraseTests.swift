import XCTest
@testable import Skreener

/// Smart Erase's fill: the background color around a box.
final class SmartEraseTests: XCTestCase {
    /// 100 × 100 px: white, with a black square from (30, 30) to (70, 70) (top-left origin) and a red dot in it.
    private func image() -> CGImage {
        let img = TestImages.image(width: 100, height: 100) { r in
            NSColor.white.setFill(); r.fill()
            NSColor.black.setFill(); NSRect(x: 30, y: 30, width: 40, height: 40).fill()
            NSColor.red.setFill(); NSRect(x: 45, y: 45, width: 4, height: 4).fill()
        }
        var r = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
    }

    private func components(_ c: CGColor?) -> [CGFloat] {
        c?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
    }

    private func assertColor(_ c: CGColor?, _ expected: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        let got = components(c)
        XCTAssertEqual(got.count, expected.count, "\(got)", file: file, line: line)
        for (g, e) in zip(got, expected) { XCTAssertEqual(g, e, accuracy: 0.03, "\(got)", file: file, line: line) }
    }

    func testBoxOnTheBlackSquareTakesBlack() {
        // Around the red dot, inside the black square.
        assertColor(SmartErase.fillColor(around: CGRect(x: 40, y: 40, width: 15, height: 15), in: image()), [0, 0, 0, 1])
    }

    func testBoxCoveringTheSquareTakesWhite() {
        assertColor(SmartErase.fillColor(around: CGRect(x: 20, y: 20, width: 60, height: 60), in: image()), [1, 1, 1, 1])
    }

    func testMostCommonColorWins() {
        // The ring runs mostly over white, partly over the square's edge.
        assertColor(SmartErase.fillColor(around: CGRect(x: 10, y: 10, width: 30, height: 30), in: image()), [1, 1, 1, 1])
    }

    func testBoxPastTheEdgeUsesTheRingInsideTheImage() {
        assertColor(SmartErase.fillColor(around: CGRect(x: -20, y: -20, width: 40, height: 40), in: image()), [1, 1, 1, 1])
    }

    func testBoxCoveringEverythingHasNoColor() {
        XCTAssertNil(SmartErase.fillColor(around: CGRect(x: -5, y: -5, width: 110, height: 110), in: image()))
    }
}
