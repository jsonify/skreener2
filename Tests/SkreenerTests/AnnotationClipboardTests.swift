import AppKit
import XCTest
@testable import Skreener

final class AnnotationClipboardTests: XCTestCase {
    private var board: NSPasteboard!

    override func setUp() {
        super.setUp()
        board = NSPasteboard(name: NSPasteboard.Name("SkreenerTests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        board.releaseGlobally()
        super.tearDown()
    }

    private func arrow(at x: CGFloat) -> Annotation {
        var s = Style()
        s.color = .systemBlue
        s.lineWidth = 5
        return Annotation(tool: .arrow, start: NSPoint(x: x, y: 50), end: NSPoint(x: x + 80, y: 90), bend: 12, style: s)
    }

    func testCopiedAnnotationsComeBackWhileTheyAreOnThePasteboard() {
        let a = arrow(at: 10)
        AnnotationClipboard.write([a], to: board)
        XCTAssertEqual(AnnotationClipboard.read(from: board), [a])

        // Anything copied afterwards wins.
        board.clearContents()
        board.setString("hello", forType: .string)
        XCTAssertNil(AnnotationClipboard.read(from: board))
    }

    func testPastingIntoAnotherScreenshotKeepsThePlaceAndTheLook() {
        let a = arrow(at: 10)
        let pasted = AnnotationClipboard.pasted([a], into: [])
        XCTAssertEqual(pasted.count, 1)
        let b = pasted[0]
        XCTAssertNotEqual(b.id, a.id)
        XCTAssertGreaterThan(b.seq, a.seq)
        XCTAssertEqual(b.start, a.start)
        XCTAssertEqual(b.end, a.end)
        XCTAssertEqual(b.bend, a.bend)
        XCTAssertEqual(b.style, a.style)
        XCTAssertEqual(b.tool, .arrow)
    }

    func testPastingOverTheOriginalMovesTheCopyAside() {
        let a = arrow(at: 10)
        let first = AnnotationClipboard.pasted([a], into: [a])[0]
        XCTAssertEqual(first.start, NSPoint(x: 20, y: 40))
        let second = AnnotationClipboard.pasted([a], into: [a, first])[0]
        XCTAssertEqual(second.start, NSPoint(x: 30, y: 30))
        XCTAssertEqual(second.end, NSPoint(x: 110, y: 70))
    }
}
