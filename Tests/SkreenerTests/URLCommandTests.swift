import XCTest
@testable import Skreener

/// skreener:// links (Raycast, Alfred, Shortcuts, scripts).
final class URLCommandTests: XCTestCase {
    private func parse(_ s: String) -> Result<URLCommand, URLCommandError> {
        URLCommand.parse(URL(string: s)!)
    }

    func testAreaWithThen() {
        XCTAssertEqual(parse("skreener://grab/area?then=copy,save"),
                       .success(URLCommand(command: .run(.captureArea), then: [.copy, .save])))
    }

    func testCaptureIsAnAliasForGrab() {
        XCTAssertEqual(parse("skreener://capture/fullscreen"), .success(URLCommand(command: .run(.captureFullscreen))))
    }

    func testWithoutSlashesCaseAndTrailingSlash() {
        XCTAssertEqual(parse("skreener:grab/window"), .success(URLCommand(command: .run(.captureWindow))))
        XCTAssertEqual(parse("SKREENER://Grab/Window/"), .success(URLCommand(command: .run(.captureWindow))))
    }

    func testActiveWindow() {
        XCTAssertEqual(parse("skreener://grab/window/active?then=copy"),
                       .success(URLCommand(command: .run(.captureActiveWindow), then: .copy)))
        XCTAssertEqual(parse("skreener://capture/window/active"), .success(URLCommand(command: .run(.captureActiveWindow))))
    }

    func testEveryCommandParses() {
        for (path, command) in URLCommand.commands {
            XCTAssertEqual(parse("skreener://" + path), .success(URLCommand(command: command)), path)
        }
    }

    func testSettingsAndOtherCommands() {
        XCTAssertEqual(parse("skreener://settings"), .success(URLCommand(command: .settings)))
        XCTAssertEqual(parse("skreener://ocr"), .success(URLCommand(command: .run(.captureText))))
        XCTAssertEqual(parse("skreener://ocr/code"), .success(URLCommand(command: .run(.captureCode))))
        XCTAssertEqual(parse("skreener://load/clipboard"), .success(URLCommand(command: .run(.openClipboard))))
    }

    func testEveryThenOption() {
        XCTAssertEqual(parse("skreener://grab/previous?then=copy,save,edit,pin,quickaccess"),
                       .success(URLCommand(command: .run(.capturePreviousArea),
                                           then: [.copy, .save, .edit, .pin, .quickAccess])))
        XCTAssertEqual(parse("skreener://grab/area?then=PIN"), .success(URLCommand(command: .run(.captureArea), then: .pin)))
    }

    func testDelay() {
        XCTAssertEqual(parse("skreener://grab/delayed/window?delay=10&then=edit"),
                       .success(URLCommand(command: .run(.timedWindow), then: .edit, delay: 10)))
        XCTAssertEqual(parse("skreener://grab/delayed?delay=3"), .success(URLCommand(command: .run(.timedArea), delay: 3)))
    }

    func testErrors() {
        XCTAssertEqual(parse("https://grab/area"), .failure(.wrongScheme))
        XCTAssertEqual(parse("skreener://grab/everything"), .failure(.unknownCommand("grab/everything")))
        XCTAssertEqual(parse("skreener://"), .failure(.unknownCommand("")))
        XCTAssertEqual(parse("skreener://grab/area?then=copy,print"), .failure(.badThen("print")))
        XCTAssertEqual(parse("skreener://grab/area?then="), .failure(.badThen("")))
        XCTAssertEqual(parse("skreener://grab/area?then=copy,"), .failure(.badThen("")))
        XCTAssertEqual(parse("skreener://ocr?then=copy"), .failure(.thenNotAllowed("ocr")))
        XCTAssertEqual(parse("skreener://settings?then=copy"), .failure(.thenNotAllowed("settings")))
        XCTAssertEqual(parse("skreener://grab/area?delay=5"), .failure(.delayNotAllowed("grab/area")))
        XCTAssertEqual(parse("skreener://grab/delayed?delay=0"), .failure(.badDelay("0")))
        XCTAssertEqual(parse("skreener://grab/delayed?delay=soon"), .failure(.badDelay("soon")))
        XCTAssertEqual(parse("skreener://grab/area?size=big"), .failure(.unknownParameter("size")))
    }

    func testErrorMessagesListTheOptions() {
        XCTAssertTrue(URLCommandError.badThen("print").message.contains("\"quickaccess\""))
        XCTAssertTrue(URLCommandError.unknownCommand("x").message.contains("grab/area"))
    }
}
