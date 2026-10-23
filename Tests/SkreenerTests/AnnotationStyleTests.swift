import AppKit
import XCTest
@testable import Skreener

final class AnnotationStyleTests: XCTestCase {
    // MARK: Remembered style (#139)

    func testStyleSurvivesAPropertyListRoundTrip() throws {
        var s = Style()
        s.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        s.lineWidth = 7; s.fontSize = 31; s.fontName = "Menlo"; s.bold = false; s.pixelSize = 18; s.cornerRadius = 0
        s.arrowStyle = .tapered; s.textOnly = true; s.magnification = 3; s.lensShape = .rectangle; s.fill = .solid
        s.textBox = .outline; s.tail = true; s.handDrawn = true; s.shapeCorrection = true
        // Through a property list, as user defaults store it.
        let data = try PropertyListSerialization.data(fromPropertyList: s.plist, format: .binary, options: 0)
        let back = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(Style(plist: back), s)
    }

    func testMissingOrBadStyleValuesKeepDefaults() {
        let s = Style(plist: ["lineWidth": -2, "arrowStyle": 99, "fontSize": "big", "bold": false])
        XCTAssertEqual(s.lineWidth, Style().lineWidth)
        XCTAssertEqual(s.arrowStyle, Style().arrowStyle)
        XCTAssertEqual(s.fontSize, Style().fontSize)
        XCTAssertFalse(s.bold)
    }

    // MARK: Text boxes (#120)

    func testTextOnASolidBoxContrasts() {
        var s = Style()
        s.textBox = .solid
        s.color = .systemYellow
        XCTAssertEqual(s.textColor, .black)
        s.color = NSColor(srgbRed: 0, green: 0, blue: 0.6, alpha: 1)
        XCTAssertEqual(s.textColor, .white)
        s.textBox = .outline
        XCTAssertEqual(s.textColor, s.color)
    }

    func testBubbleTailIsPartOfTheOutline() {
        let box = NSRect(x: 0, y: 0, width: 100, height: 40)
        let tip = NSPoint(x: 30, y: -30)
        let path = CanvasView.bubblePath(box, radius: 6, tail: tip, tailWidth: 16)
        XCTAssertEqual(path.bounds.minY, -30, accuracy: 0.01)
        XCTAssertTrue(path.contains(NSPoint(x: 30, y: -10)), "the tail is filled")
        XCTAssertTrue(path.contains(NSPoint(x: 50, y: 20)), "the box is filled")
        // A tip inside the box gives no tail.
        let plain = CanvasView.bubblePath(box, radius: 6, tail: NSPoint(x: 50, y: 20), tailWidth: 16)
        XCTAssertEqual(plain.bounds.minY, 0, accuracy: 0.01)
        XCTAssertEqual(plain.bounds.height, 40, accuracy: 0.01)
    }
}
