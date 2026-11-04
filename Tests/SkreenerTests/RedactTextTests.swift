import XCTest
import SkreenerCore
@testable import Skreener

/// The Redact Text tool's covering annotations (#295); matching and the find bar's state are in SkreenerCoreTests.
final class RedactTextTests: XCTestCase {
    private let a = CGRect(x: 10, y: 10, width: 50, height: 20)
    private let b = CGRect(x: 10, y: 40, width: 30, height: 20)

    func testSolidIsAnOpaqueBlackSquareBox() {
        var style = Style()
        style.color = .systemRed
        style.cornerRadius = 8
        style.textOnly = true
        let added = RedactText.annotations([a, b], cover: .solid, style: style)
        XCTAssertEqual(added.count, 2)
        for x in added {
            XCTAssertEqual(x.tool, .filledRect)
            XCTAssertEqual(x.style.color, .black)
            XCTAssertEqual(x.style.cornerRadius, 0)
            XCTAssertFalse(x.style.textOnly)
        }
        XCTAssertEqual(added[0].start, a.origin)
        XCTAssertEqual(added[0].end, NSPoint(x: a.maxX, y: a.maxY))
        XCTAssertNotEqual(added[0].id, added[1].id)
    }

    func testOtherCovers() {
        var style = Style()
        style.pixelSize = 4
        XCTAssertEqual(RedactText.annotations([a], cover: .pixelate, style: style).first?.style.pixelSize, 8)
        XCTAssertEqual(RedactText.annotations([a], cover: .pixelate, style: style).first?.tool, .pixelate)
        XCTAssertEqual(RedactText.annotations([a], cover: .blur, style: style).first?.tool, .blur)
        XCTAssertEqual(RedactText.annotations([a], cover: .erase, style: style).first?.tool, .erase)
    }

    /// Added last, so stored tool numbers keep their meaning; no single-key shortcut.
    func testRedactTextIsLastAndHasNoShortcut() {
        XCTAssertEqual(Tool.allCases.last, .redactText)
        XCTAssertEqual(Tool.redactText.rawValue, Tool.ruler.rawValue + 1)
        XCTAssertFalse(Tool.shortcuts.values.contains(.redactText))
        XCTAssertEqual(Tool.redactText.name, "Redact Text")
    }
}
