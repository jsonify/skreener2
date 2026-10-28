import AppKit
import XCTest
@testable import Skreener

final class TipsTests: XCTestCase {
    func testATipIsDueOnceItsEventReachesItsCount() {
        var book = TipBook()
        XCTAssertFalse(book.isDue(.filledRect))
        book.record(.rectangleDrawn)
        book.record(.rectangleDrawn)
        XCTAssertFalse(book.isDue(.filledRect))
        book.record(.rectangleDrawn)
        XCTAssertTrue(book.isDue(.filledRect))
        XCTAssertEqual(book.count(.rectangleDrawn), 3)
    }

    func testTheFirstEditorShowsTheCounterTip() {
        var book = TipBook()
        XCTAssertFalse(book.isDue(.counterTool))
        book.record(.editorOpened)
        XCTAssertTrue(book.isDue(.counterTool))
    }

    func testTheSpaceTipWaitsForTwoAreaCaptures() {
        var book = TipBook()
        book.record(.areaCaptured)
        XCTAssertFalse(book.isDue(.moveSelection))
        book.record(.areaCaptured)
        XCTAssertTrue(book.isDue(.moveSelection))
    }

    func testASeenTipNeverShowsAgain() {
        var book = TipBook()
        book.record(.editorOpened)
        book.markSeen(.counterTool)
        XCTAssertFalse(book.isDue(.counterTool))
        book.record(.editorOpened)
        XCTAssertFalse(book.isDue(.counterTool))
    }

    func testATipWithoutARuleIsDueUntilSeen() {
        var book = TipBook()
        XCTAssertTrue(book.isDue(.repeatSimilar))
        book.markSeen(.repeatSimilar)
        XCTAssertFalse(book.isDue(.repeatSimilar))
    }

    func testOneTipPerSessionNeverWhileBusyAndNothingWhenOff() {
        var book = TipBook()
        book.record(.editorOpened)
        XCTAssertTrue(book.shouldShow(.counterTool, enabled: true, shownThisSession: false, busy: false))
        XCTAssertFalse(book.shouldShow(.counterTool, enabled: true, shownThisSession: true, busy: false))
        XCTAssertFalse(book.shouldShow(.counterTool, enabled: true, shownThisSession: false, busy: true))
        XCTAssertFalse(book.shouldShow(.counterTool, enabled: false, shownThisSession: false, busy: false))
    }

    func testFeaturesAreNewUntilUsed() {
        var book = TipBook()
        XCTAssertTrue(NewFeature.allCases.allSatisfy { book.isNew($0) })
        book.markUsed(.cutOut)
        XCTAssertFalse(book.isNew(.cutOut))
        XCTAssertTrue(book.isNew(.removeBackground))
    }

    func testTheBookSurvivesAPropertyListRoundTrip() {
        var book = TipBook()
        book.record(.rectangleDrawn)
        book.record(.areaCaptured)
        book.record(.areaCaptured)
        book.markSeen(.counterTool)
        book.markUsed(.combineScreenshots)
        XCTAssertEqual(TipBook(plist: book.plist), book)
        XCTAssertEqual(TipBook(plist: [:]), TipBook())
    }

    func testMenuActionsMapToFeatures() {
        XCTAssertEqual(NewFeature.running(#selector(CanvasView.removeBackground(_:))), .removeBackground)
        XCTAssertEqual(NewFeature.running(#selector(CanvasView.cutOut(_:))), .cutOut)
        XCTAssertEqual(NewFeature.running(#selector(CanvasView.repeatOnSimilarObjects(_:))), .repeatOnSimilarObjects)
        XCTAssertEqual(NewFeature.running(#selector(EditorWindow.combineScreenshots(_:))), .combineScreenshots)
        XCTAssertEqual(NewFeature.running(#selector(EditorWindowController.combineScreenshots)), .combineScreenshots)
        XCTAssertNil(NewFeature.running(#selector(CanvasView.rotateLeft(_:))))
    }

    func testTipLinesSplitIntoTextAndKeys() {
        let parts = TipText.segments("Press {N} for numbered counters")
        XCTAssertEqual(parts.map(\.text), ["Press", "N", "for numbered counters"])
        XCTAssertEqual(parts.map(\.isKey), [false, true, false])
        XCTAssertEqual(TipText.plain(TipID.moveSelection.line), "Hold Space to move the selection")
        XCTAssertEqual(TipText.segments("No keys").map(\.text), ["No keys"])
    }

    func testSimilarBoxes() {
        XCTAssertTrue(BoxSimilarity.isSimilar(CGSize(width: 100, height: 40), CGSize(width: 110, height: 37)))
        XCTAssertFalse(BoxSimilarity.isSimilar(CGSize(width: 100, height: 40), CGSize(width: 140, height: 40)))
        // Small boxes get a few points of slack.
        XCTAssertTrue(BoxSimilarity.isSimilar(CGSize(width: 12, height: 12), CGSize(width: 15, height: 9)))
        let sizes = [CGSize(width: 100, height: 40), CGSize(width: 300, height: 200), CGSize(width: 104, height: 42),
                     CGSize(width: 98, height: 39)]
        XCTAssertEqual(BoxSimilarity.similarToLast(sizes), 3)
        XCTAssertEqual(BoxSimilarity.similarToLast(Array(sizes.prefix(2))), 1)
        XCTAssertEqual(BoxSimilarity.similarToLast([]), 0)
    }

    func testHintTexts() {
        XCTAssertEqual(EditorHint.bend.text, "Drag to bend")
        XCTAssertEqual(EditorHint.wrapWidth.text, "Drag to set wrap width")
        XCTAssertEqual(EditorHint.tail.text, "Drag to point the tail")
        XCTAssertEqual(EditorHint.straightStroke.text, "⇧ keeps it straight")
        XCTAssertEqual(EditorHint.snapping.text, "⌘ turns off snapping")
    }
}
