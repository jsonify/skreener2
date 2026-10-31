import XCTest
@testable import Skreener

final class RetroKnobTests: XCTestCase {
    func testClickStopPositionsSpanTheSweep() {
        let s = KnobScale(kind: .stops(count: 4))
        XCTAssertEqual(s.count, 4)
        XCTAssertFalse(s.isSmooth)
        XCTAssertEqual(s.angle(0), 225)   // seven o'clock
        XCTAssertEqual(s.angle(3), -45)   // five o'clock
        XCTAssertEqual(s.angle(1), 135, accuracy: 0.001)
        XCTAssertEqual(s.ticks, [0, 1.0 / 3, 2.0 / 3, 1])
        XCTAssertEqual(s.clamp(-2), 0)
        XCTAssertEqual(s.clamp(9), 3)
        XCTAssertEqual(s.value(at: 2), 2)
    }

    func testSmoothRangeMapsValuesToPositions() {
        let s = KnobScale(kind: .smooth(min: 0, max: 100, step: 1))
        XCTAssertEqual(s.count, 101)
        XCTAssertTrue(s.isSmooth)
        XCTAssertEqual(s.position(for: 37), 37)
        XCTAssertEqual(s.value(at: 37), 37)
        XCTAssertEqual(s.position(for: 250), 100)
        XCTAssertEqual(s.position(for: -5), 0)
        XCTAssertEqual(s.fraction(50), 0.5)
        XCTAssertEqual(s.ticks.count, KnobScale.smoothTicks)

        let stepped = KnobScale(kind: .smooth(min: 10, max: 1010, step: 10))
        XCTAssertEqual(stepped.count, 101)
        XCTAssertEqual(stepped.position(for: 104), 9)   // nearest step: 100
        XCTAssertEqual(stepped.value(at: 9), 100)
    }

    func testClickStopDragCarriesTheRemainder() {
        let s = KnobScale(kind: .stops(count: 3))
        var carry: CGFloat = 0
        XCTAssertEqual(s.steps(forDrag: 10, carry: &carry), 0)
        XCTAssertEqual(s.steps(forDrag: 15, carry: &carry), 1)   // 25 pt: one click, 3 pt left
        XCTAssertEqual(carry, 3, accuracy: 0.001)
        XCTAssertEqual(s.steps(forDrag: -50, carry: &carry), -2)   // down turns it back
        XCTAssertEqual(carry, -3, accuracy: 0.001)
    }

    func testSmoothDragTurnsTheWholeSweepIn160Points() {
        let s = KnobScale(kind: .smooth(min: 0, max: 100, step: 1))
        var carry: CGFloat = 0
        XCTAssertEqual(s.steps(forDrag: KnobScale.dragForSweep + 1, carry: &carry), 100)
        XCTAssertEqual(carry, 1, accuracy: 0.01)
        XCTAssertEqual(s.steps(forDrag: -0.5, carry: &carry), 0)
    }

    func testSinglePositionKnobStaysPut() {
        let s = KnobScale(kind: .stops(count: 1))
        XCTAssertEqual(s.fraction(0), 0)
        XCTAssertEqual(s.ticks, [0])
        XCTAssertEqual(s.clamp(5), 0)
    }
}
