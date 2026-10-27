import NaturalLanguage
import XCTest
@testable import Skreener

/// What the scratch pad's Speak reads, and which voice language it asks for.
final class TextSpeakerTests: XCTestCase {
    func testReadsTheSelection() {
        XCTAssertEqual(TextSpeaker.textToSpeak("one two three", selection: NSRange(location: 4, length: 3)), "two")
    }

    func testReadsAllWithoutSelection() {
        XCTAssertEqual(TextSpeaker.textToSpeak(" one two\n", selection: NSRange(location: 2, length: 0)), "one two")
    }

    func testWhitespaceSelectionFallsBackToAll() {
        XCTAssertEqual(TextSpeaker.textToSpeak("one  two", selection: NSRange(location: 3, length: 2)), "one  two")
    }

    func testOutOfRangeSelectionFallsBackToAll() {
        XCTAssertEqual(TextSpeaker.textToSpeak("one", selection: NSRange(location: 2, length: 9)), "one")
    }

    func testEmptyOrWhitespaceTextIsIgnored() {
        XCTAssertNil(TextSpeaker.textToSpeak("", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(TextSpeaker.textToSpeak(" \n\t ", selection: NSRange(location: 0, length: 4)))
    }

    func testLanguageCodeMapping() {
        XCTAssertEqual(TextSpeaker.voiceLanguage(for: NLLanguage.french), "fr")
        XCTAssertEqual(TextSpeaker.voiceLanguage(for: NLLanguage.simplifiedChinese), "zh-CN")
        XCTAssertEqual(TextSpeaker.voiceLanguage(for: NLLanguage.traditionalChinese), "zh-TW")
        XCTAssertNil(TextSpeaker.voiceLanguage(for: NLLanguage.undetermined))
        XCTAssertNil(TextSpeaker.voiceLanguage(for: nil as NLLanguage?))
    }

    func testGuessesTheTextsLanguage() {
        XCTAssertEqual(TextSpeaker.voiceLanguage(for: "This is a sentence written in plain English."), "en")
        XCTAssertEqual(TextSpeaker.voiceLanguage(for: "Dies ist ein Satz, der auf Deutsch geschrieben wurde."), "de")
        XCTAssertNil(TextSpeaker.voiceLanguage(for: ""))
    }
}
