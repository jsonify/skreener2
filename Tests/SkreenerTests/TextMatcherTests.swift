import XCTest
@testable import Skreener

/// Finding the terms to redact in OCR lines (#295).
final class TextMatcherTests: XCTestCase {
    private typealias Options = TextMatcher.Options

    private func find(_ terms: [String], _ lines: [String], _ options: Options = Options()) -> [TextMatcher.Match] {
        TextMatcher.matches(of: terms, in: lines, options: options)
    }

    /// The matched text of each span.
    private func texts(_ match: TextMatcher.Match, _ lines: [String]) -> [String] {
        match.spans.map { String(lines[$0.line][$0.range]) }
    }

    /// Each span as [line, start offset, end offset] in characters.
    private func offsets(_ match: TextMatcher.Match, _ lines: [String]) -> [[Int]] {
        match.spans.map {
            let s = lines[$0.line]
            return [$0.line, s.distance(from: s.startIndex, to: $0.range.lowerBound),
                    s.distance(from: s.startIndex, to: $0.range.upperBound)]
        }
    }

    func testPlainMatchAndExactRange() {
        let lines = ["Send it to Jane today"]
        let result = find(["Jane"], lines)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.term, 0)
        XCTAssertEqual(offsets(result[0], lines), [[0, 11, 15]])
    }

    func testCaseInsensitiveByDefault() {
        let lines = ["JANE and jane"]
        XCTAssertEqual(find(["Jane"], lines).count, 2)
        XCTAssertEqual(find(["Jane"], lines, Options(caseSensitive: true)).count, 0)
        XCTAssertEqual(find(["jane"], lines, Options(caseSensitive: true)).count, 1)
    }

    func testDiacriticsAreNotFolded() {
        XCTAssertEqual(find(["Cafe"], ["Café"], Options(wholeWord: false)).count, 0)
    }

    func testWholeWordOnAndOff() {
        let lines = ["concatenate a cat."]
        let on = find(["cat"], lines)
        XCTAssertEqual(on.count, 1)
        XCTAssertEqual(offsets(on[0], lines), [[0, 14, 17]])
        XCTAssertEqual(find(["cat"], lines, Options(wholeWord: false)).count, 2)
    }

    func testWholeWordChecksNeighboursNotThePunctuationInTheTerm() {
        let lines = ["jane@acme.com"]
        XCTAssertEqual(find(["@acme.com"], lines).count, 0)
        XCTAssertEqual(find(["@acme.com"], lines, Options(wholeWord: false)).count, 1)
        XCTAssertEqual(find(["@acme.com"], ["mail @acme.com now"]).count, 1)
    }

    func testMultipleTermsKeepTheirIndices() {
        let lines = ["alpha beta gamma"]
        let result = find(["gamma", "alpha"], lines)
        XCTAssertEqual(result.map(\.term), [1, 0])
        XCTAssertEqual(texts(result[0], lines), ["alpha"])
    }

    func testEmptyTermsAreIgnoredAndTermsTrimmed() {
        let result = find(["", "   ", " cat "], ["a cat"])
        XCTAssertEqual(result.map(\.term), [2])
    }

    func testPhraseAcrossTwoLines() {
        let lines = ["Hi Jane", "Doe ok"]
        let result = find(["Jane Doe"], lines)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(offsets(result[0], lines), [[0, 3, 7], [1, 0, 3]])
        XCTAssertEqual(texts(result[0], lines), ["Jane", "Doe"])
    }

    func testThreeLineWrap() {
        let lines = ["Jane", "Q", "Doe"]
        let result = find(["Jane Q Doe"], lines)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(texts(result[0], lines), ["Jane", "Q", "Doe"])
        XCTAssertEqual(result[0].spans.map(\.line), [0, 1, 2])
    }

    func testMatchesOfOneTermDoNotOverlap() {
        let lines = ["aaaaa"]
        let result = find(["aa"], lines, Options(wholeWord: false))
        XCTAssertEqual(result.map { offsets($0, lines) }, [[[0, 0, 2]], [[0, 2, 4]]])
    }

    func testDifferentTermsMayOverlap() {
        let result = find(["Jane Doe", "Doe"], ["Jane Doe"])
        XCTAssertEqual(result.count, 2)
    }

    func testIdenticalSpansKeepOnlyTheFirstTerm() {
        let result = find(["jane", "Jane"], ["Jane"])
        XCTAssertEqual(result.map(\.term), [0])
    }

    func testReadingOrder() {
        let lines = ["beta alpha", "alpha"]
        let result = find(["alpha", "beta"], lines)
        XCTAssertEqual(result.map(\.term), [1, 0, 0])
        XCTAssertEqual(result.map { $0.spans[0].line }, [0, 0, 1])
    }

    func testNonASCIIRanges() {
        let lines = ["Café Zoë here"]
        let result = find(["zoë", "café"], lines)
        XCTAssertEqual(result.map(\.term), [1, 0])
        XCTAssertEqual(texts(result[0], lines), ["Café"])
        XCTAssertEqual(offsets(result[1], lines), [[0, 5, 8]])
        XCTAssertEqual(find(["Caf"], lines).count, 0)
    }

    // MARK: Regex

    func testRegexWithGroups() {
        let lines = ["call 555-0132 or 555-0199"]
        let result = find([#"(\d{3})-(\d{4})"#], lines, Options(regex: true))
        XCTAssertEqual(result.map { texts($0, lines) }, [["555-0132"], ["555-0199"]])
        XCTAssertEqual(offsets(result[0], lines), [[0, 5, 13]])
    }

    func testRegexCase() {
        XCTAssertEqual(find(["jane"], ["JANE"], Options(regex: true)).count, 1)
        XCTAssertEqual(find(["jane"], ["JANE"], Options(caseSensitive: true, regex: true)).count, 0)
    }

    func testRegexWholeWord() {
        let lines = ["concatenate cat"]
        XCTAssertEqual(find(["cat"], lines, Options(regex: true)).count, 1)
        XCTAssertEqual(find(["cat"], lines, Options(wholeWord: false, regex: true)).count, 2)
    }

    func testRegexAcrossLines() {
        let lines = ["Jane", "Doe"]
        let result = find([#"Jane\s+Doe"#], lines, Options(regex: true))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(texts(result[0], lines), ["Jane", "Doe"])
    }

    func testInvalidRegexMatchesNothing() {
        XCTAssertEqual(find(["("], ["a (b)"], Options(regex: true)).count, 0)
        XCTAssertFalse(TextMatcher.isValidPattern("("))
        XCTAssertTrue(TextMatcher.isValidPattern("a+"))
    }

    func testZeroLengthRegexMatchesAreSkipped() {
        XCTAssertEqual(find(["x*"], ["abc"], Options(wholeWord: false, regex: true)).count, 0)
        let lines = ["axb"]
        let result = find(["x*"], lines, Options(wholeWord: false, regex: true))
        XCTAssertEqual(result.map { texts($0, lines) }, [["x"]])
    }

    // MARK: Fuzzy

    func testFuzzyZeroAndLetterO() {
        let lines = ["the ROOT user"]
        let result = find(["R00T"], lines, Options(fuzzy: true))
        XCTAssertEqual(result.map { texts($0, lines) }, [["ROOT"]])
        XCTAssertEqual(find(["R00T"], lines).count, 0)
    }

    func testFuzzyOneAndLetterL() {
        let lines = ["say He110 now"]
        XCTAssertEqual(find(["Hello"], lines, Options(fuzzy: true)).count, 1)
        XCTAssertEqual(find(["Hello"], lines).count, 0)
    }

    func testFuzzyRnAndM() {
        let lines = ["the modern one", "send to rnail"]
        let result = find(["modem", "mail"], lines, Options(fuzzy: true))
        XCTAssertEqual(result.map { texts($0, lines) }, [["modern"], ["rnail"]])
        XCTAssertEqual(find(["modem"], lines).count, 0)
        XCTAssertEqual(find(["vvhy"], ["why"], Options(fuzzy: true)).count, 1)
    }

    func testFuzzyIgnoresWhitespaceInTermAndText() {
        let lines = ["name J ane Doe", "call 555 0132 now"]
        let a = find(["Jane"], lines, Options(fuzzy: true))
        XCTAssertEqual(a.map { texts($0, lines) }, [["J ane"]])
        XCTAssertEqual(offsets(a[0], lines), [[0, 5, 10]])
        let b = find(["5550132"], lines, Options(fuzzy: true))
        XCTAssertEqual(b.map { texts($0, lines) }, [["555 0132"]])
        XCTAssertEqual(find(["J ane"], ["Jane"], Options(fuzzy: true)).count, 1)
        XCTAssertEqual(find(["555 0132"], ["5550132"], Options(fuzzy: true)).count, 1)
        XCTAssertEqual(find(["5550132"], lines).count, 0)
    }

    func testFuzzyWrapsAcrossLines() {
        let lines = ["Ja", "ne"]
        let result = find(["Jane"], lines, Options(fuzzy: true))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(texts(result[0], lines), ["Ja", "ne"])
    }

    func testFuzzyWholeWordUsesOriginalBoundaries() {
        XCTAssertEqual(find(["ROOT"], ["xR00T"], Options(fuzzy: true)).count, 0)
        XCTAssertEqual(find(["ROOT"], ["xR00T"], Options(wholeWord: false, fuzzy: true)).count, 1)
    }

    func testFuzzyCaseSensitive() {
        XCTAssertEqual(find(["Abc"], ["abc"], Options(caseSensitive: true, fuzzy: true)).count, 0)
        XCTAssertEqual(find(["Abc"], ["abc"], Options(fuzzy: true)).count, 1)
    }

    func testFuzzyIsIgnoredInRegexMode() {
        XCTAssertEqual(find(["R00T"], ["ROOT"], Options(regex: true, fuzzy: true)).count, 0)
    }
}
