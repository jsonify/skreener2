import XCTest
@testable import Skreener

/// Ask Claude (#252): the request it builds and how it reads replies. Nothing here talks to the network.
final class AskClaudeTests: XCTestCase {
    func testPresetsHavePromptsAndCustomUsesTheQuestion() {
        for p in AskClaude.Preset.allCases where p != .custom {
            XCTAssertEqual(AskClaude.question(p, custom: "ignored"), p.prompt)
            XCTAssertNotNil(p.prompt)
        }
        XCTAssertEqual(AskClaude.question(.custom, custom: "  What app is this?\n"), "What app is this?")
        XCTAssertNil(AskClaude.question(.custom, custom: " \n "))
    }

    func testRequestCarriesKeyImageAndQuestion() throws {
        let image = Data([1, 2, 3])
        let request = AskClaude.request(image: image, mediaType: "image/png", question: "Explain", apiKey: "sk-ant-test")
        XCTAssertEqual(request.url, AskClaude.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), AskClaude.apiVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), AskClaude.fallbackBeta)

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, AskClaude.model)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["temperature"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        // The image comes before the question.
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "text"])
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, image.base64EncodedString())
        XCTAssertEqual(content[1]["text"] as? String, "Explain")
    }

    func testAnswerJoinsTextBlocksAndSkipsThinking() {
        let reply = """
        {"stop_reason": "end_turn", "content": [
          {"type": "thinking", "thinking": "", "signature": "x"},
          {"type": "text", "text": "A login form "},
          {"type": "text", "text": "with an error.\\n"}
        ]}
        """
        XCTAssertEqual(AskClaude.answer(from: Data(reply.utf8), status: 200), .success("A login form with an error."))
    }

    func testRefusalAndEmptyRepliesAreFailures() {
        let refusal = #"{"stop_reason": "refusal", "content": []}"#
        XCTAssertEqual(AskClaude.answer(from: Data(refusal.utf8), status: 200),
                       .failure(AskClaude.Failure("Claude declined to answer this one.")))
        let empty = #"{"stop_reason": "end_turn", "content": []}"#
        if case .success = AskClaude.answer(from: Data(empty.utf8), status: 200) { XCTFail("empty reply read as an answer") }
        if case .success = AskClaude.answer(from: Data("not json".utf8), status: 200) { XCTFail("junk read as an answer") }
    }

    func testHTTPErrorsSayWhatToDo() {
        let error = #"{"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}"#
        guard case .failure(let auth) = AskClaude.answer(from: Data(error.utf8), status: 401) else { return XCTFail() }
        XCTAssertTrue(auth.message.contains("Settings"), auth.message)
        guard case .failure(let other) = AskClaude.answer(from: Data(error.utf8), status: 400) else { return XCTFail() }
        XCTAssertTrue(other.message.contains("400") && other.message.contains("invalid x-api-key"), other.message)
        guard case .failure(let busy) = AskClaude.answer(from: Data(), status: 529) else { return XCTFail() }
        XCTAssertTrue(busy.message.contains("529"), busy.message)
    }

    func testImageIsScaledToTheLongSideLimit() throws {
        let image = TestImages.image(width: 3000, height: 1000) { r in NSColor.systemBlue.setFill(); r.fill() }
        let prepared = try XCTUnwrap(AskClaude.imageData(image))
        XCTAssertEqual(prepared.mediaType, "image/png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: prepared.data))
        XCTAssertEqual(rep.pixelsWide, AskClaude.maxImageSide)
        XCTAssertEqual(rep.pixelsHigh, 523)
    }

    func testSmallImageKeepsItsSize() throws {
        let image = TestImages.image(width: 400, height: 300) { r in NSColor.white.setFill(); r.fill() }
        let rep = try XCTUnwrap(AskClaude.imageData(image).flatMap { NSBitmapImageRep(data: $0.data) })
        XCTAssertEqual(rep.pixelsWide, 400)
        XCTAssertEqual(rep.pixelsHigh, 300)
    }

    func testBase64SizeAndMaskedKey() {
        XCTAssertEqual(AskClaude.base64Size(3), 4)
        XCTAssertEqual(AskClaude.base64Size(4), 8)
        XCTAssertEqual(APIKeyStore.masked("sk-ant-api03-abcdefghijklmnop1234"), "sk-ant-…1234")
        XCTAssertEqual(APIKeyStore.masked("short"), "•••••")
    }
}
