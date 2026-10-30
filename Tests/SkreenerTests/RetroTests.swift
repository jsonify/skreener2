import XCTest
@testable import Skreener

final class RetroTests: XCTestCase {
    func testSevenSegmentDigits() {
        let expected: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg",
                                             "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": ""]
        for (c, segments) in expected {
            let lit = SevenSegment.lit(c).map(\.rawValue).sorted().joined()
            XCTAssertEqual(lit, segments, "\(c)")
        }
        XCTAssertTrue(SevenSegment.lit("x").isEmpty)
    }

    func testSegmentsFitTheirBox() {
        for s in SevenSegment.Segment.allCases {
            let points = SevenSegment.polygon(s)
            XCTAssertEqual(points.count, 6, "\(s)")
            for p in points {
                XCTAssertTrue((0...SevenSegment.width).contains(p.x) && (0...SevenSegment.height).contains(p.y), "\(s) \(p)")
            }
        }
        // The top and bottom bars are level and span the digit between the gaps.
        let a = SevenSegment.polygon(.a)
        XCTAssertEqual(a.map(\.y).min(), 0)
        XCTAssertEqual(SevenSegment.polygon(.d).map(\.y).max(), SevenSegment.height)
    }

    func testZoomCells() {
        XCTAssertEqual(SevenSegment.cells(100, count: 3), "100")
        XCTAssertEqual(SevenSegment.cells(25, count: 3), " 25")
        XCTAssertEqual(SevenSegment.cells(800, count: 3), "800")
        XCTAssertEqual(SevenSegment.cells(1200, count: 3), "---")
        XCTAssertEqual(SevenSegment.cells(-5, count: 3), "  0")
    }

    func testPaletteFollowsTheAppearance() {
        XCTAssertEqual(Retro.palette(dark: false), Retro.light)
        XCTAssertEqual(Retro.palette(dark: true), Retro.dark)
        XCTAssertEqual(Retro.light.chassis, 0xebe8e1)
        XCTAssertEqual(Retro.dark.chassis, 0x2b2a27)
        XCTAssertLessThan(Retro.dark.lcdBrightness, 1)
    }

    /// Text in both palettes is at least 4.5:1 against what it sits on.
    func testTextContrast() {
        func ratio(_ a: UInt32, _ b: UInt32) -> Double { Contrast.wcag(Retro.rgb(a), Retro.rgb(b)) }
        for p in [Retro.light, Retro.dark] {
            let mode = p.dark ? "dark" : "light"
            XCTAssertGreaterThanOrEqual(ratio(p.ink, p.chassis), 4.5, "caption on chassis, \(mode)")
            XCTAssertGreaterThanOrEqual(ratio(p.inkSoft, p.chassis), 4.5, "soft ink on chassis, \(mode)")
            XCTAssertGreaterThanOrEqual(ratio(p.keyInk, p.keyBottom), 4.5, "key ink, \(mode)")
            XCTAssertGreaterThanOrEqual(ratio(p.keyInk, p.keyDownBottom), 4.5, "pressed key ink, \(mode)")
            XCTAssertGreaterThanOrEqual(ratio(p.trackInk, p.track), 4.5, "segment ink, \(mode)")
            XCTAssertGreaterThanOrEqual(ratio(Retro.charcoalInk, p.charcoalTop), 4.5, "charcoal key ink, \(mode)")
        }
        XCTAssertGreaterThanOrEqual(ratio(Retro.charcoalInk, Retro.segmentTop), 4.5, "selected segment")
        XCTAssertGreaterThanOrEqual(ratio(Retro.lcdInk, Retro.glassBottom), 4.5, "LCD")
        XCTAssertGreaterThanOrEqual(ratio(Retro.lcdInk, Retro.chipBottom), 4.5, "LCD chip")
    }

    func testKeyLegends() {
        XCTAssertEqual(Tool.rect.shortcutLetter, "R")
        XCTAssertEqual(Tool.select.shortcutLetter, "V")
        XCTAssertNil(Tool.redactText.shortcutLetter)
    }
}
