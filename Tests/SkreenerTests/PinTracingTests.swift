import XCTest
@testable import Skreener

/// The pin's tracing controls (#244) that run without a screen.
final class PinTracingTests: XCTestCase {
    func testArrowKeysNudgeOnePoint() {
        XCTAssertEqual(PinNudge.offset(keyCode: 123, shift: false), CGVector(dx: -1, dy: 0))
        XCTAssertEqual(PinNudge.offset(keyCode: 124, shift: false), CGVector(dx: 1, dy: 0))
        XCTAssertEqual(PinNudge.offset(keyCode: 125, shift: false), CGVector(dx: 0, dy: -1))
        XCTAssertEqual(PinNudge.offset(keyCode: 126, shift: false), CGVector(dx: 0, dy: 1))
    }

    func testShiftNudgesTenPoints() {
        XCTAssertEqual(PinNudge.offset(keyCode: 123, shift: true), CGVector(dx: -10, dy: 0))
        XCTAssertEqual(PinNudge.offset(keyCode: 126, shift: true), CGVector(dx: 0, dy: 10))
    }

    func testOtherKeysDoNotNudge() {
        XCTAssertNil(PinNudge.offset(keyCode: 53, shift: false))   // Esc
        XCTAssertNil(PinNudge.offset(keyCode: 0, shift: true))     // A
    }

    func testClickThroughNeedsAPin() {
        XCTAssertNil(PinClickThrough.plan(states: [], underPointer: nil))
    }

    func testClickThroughGoesOnForThePinUnderThePointer() {
        let plan = PinClickThrough.plan(states: [false, false, false], underPointer: 1)
        XCTAssertEqual(plan?.pins, [1])
        XCTAssertEqual(plan?.on, true)
    }

    func testClickThroughGoesOnForTheNewestPinWhenNoneIsUnderThePointer() {
        let plan = PinClickThrough.plan(states: [false, false], underPointer: nil)
        XCTAssertEqual(plan?.pins, [1])
        XCTAssertEqual(plan?.on, true)
    }

    func testClickThroughGoesOffOnEveryPinThatHasIt() {
        let plan = PinClickThrough.plan(states: [true, false, true], underPointer: 1)
        XCTAssertEqual(plan?.pins, [0, 2])
        XCTAssertEqual(plan?.on, false)
    }

    func testBlendModesInMenuOrder() {
        XCTAssertEqual(PinBlend.allCases.map(\.title), ["Normal", "Onion Skin", "Difference"])
    }
}
