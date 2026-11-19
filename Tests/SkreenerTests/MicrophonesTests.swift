import XCTest
@testable import Skreener

/// Picking the microphone a recording uses.
final class MicrophonesTests: XCTestCase {
    private let devices = [Microphones.Device(id: "builtin", name: "MacBook Pro Microphone"),
                           Microphones.Device(id: "usb-1", name: "USB Headset")]

    func testAPickedConnectedMicrophoneIsUsed() {
        XCTAssertEqual(Microphones.chosen("usb-1", among: devices), "usb-1")
    }

    func testNoneOrADisconnectedOneFallsBackToTheDefault() {
        XCTAssertNil(Microphones.chosen(nil, among: devices))
        XCTAssertNil(Microphones.chosen("unplugged", among: devices))
    }
}
