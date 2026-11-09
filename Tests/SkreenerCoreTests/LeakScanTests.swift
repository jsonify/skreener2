import CoreGraphics
import XCTest
@testable import SkreenerCore

/// Safe Check's matchers (#408) on plain strings, and one OCR pass on text drawn in code.
final class LeakScanTests: XCTestCase {
    private func kinds(_ line: String) -> [LeakScan.Kind] { LeakScan.matches(in: line).map(\.kind) }

    private func text(_ line: String, _ kind: LeakScan.Kind) -> [String] {
        LeakScan.matches(in: line).filter { $0.kind == kind }.map { String(line[$0.range]) }
    }

    // MARK: Basics

    func testTitles() {
        XCTAssertEqual(LeakScan.Kind.allCases.map(\.title),
                       ["Emails", "Phones", "Links", "Codes", "Cards", "Keys", "Faces"])
    }

    func testEmailPhoneAndLinkKeepTheRedactRules() {
        XCTAssertEqual(text("Mail jane@example.com today", .email), ["jane@example.com"])
        XCTAssertEqual(text("Call 415-555-0132 soon", .phone), ["415-555-0132"])
        XCTAssertEqual(text("Visit https://example.com/a now", .link), ["https://example.com/a"])
    }

    func testPlainTextHasNoMatches() {
        XCTAssertTrue(LeakScan.matches(in: "Hello there, nothing to see").isEmpty)
        XCTAssertTrue(LeakScan.matches(in: "").isEmpty)
    }

    // MARK: Luhn and cards

    func testLuhn() {
        XCTAssertTrue(LeakScan.luhn("4111111111111111"))
        XCTAssertTrue(LeakScan.luhn("4242 4242 4242 4242"))
        XCTAssertTrue(LeakScan.luhn("4242-4242-4242-4242"))
        XCTAssertFalse(LeakScan.luhn("4111111111111112"))
        XCTAssertFalse(LeakScan.luhn(""))
        XCTAssertFalse(LeakScan.luhn("4111x111111111111"))
    }

    func testCardNumbers() {
        XCTAssertEqual(text("Card 4111111111111111 exp", .cardNumber), ["4111111111111111"])
        XCTAssertEqual(text("4242 4242 4242 4242", .cardNumber), ["4242 4242 4242 4242"])
        XCTAssertEqual(text("pay 4242-4242-4242-4242.", .cardNumber), ["4242-4242-4242-4242"])
        XCTAssertEqual(text("Amex 378282246310005", .cardNumber), ["378282246310005"])   // 15 digits
    }

    func testNonCardNumbers() {
        XCTAssertFalse(kinds("Card 4111111111111112").contains(.cardNumber))   // fails Luhn
        XCTAssertFalse(kinds("Order 411111111111").contains(.cardNumber))      // 12 digits
        XCTAssertFalse(kinds("Phone 415-555-0132").contains(.cardNumber))
        XCTAssertFalse(kinds("41111111111111111111").contains(.cardNumber))    // 20 digits
    }

    // MARK: One-time codes

    func testCodeWithKeyword() {
        XCTAssertEqual(text("Your code is 482913", .oneTimeCode), ["482913"])
        XCTAssertEqual(text("Your code is 482913.", .oneTimeCode), ["482913"])
        XCTAssertEqual(text("Verification code: 123 456", .oneTimeCode), ["123 456"])
        XCTAssertEqual(text("OTP 123-456 expires soon", .oneTimeCode), ["123-456"])
        XCTAssertEqual(text("Use 4821 as your PIN", .oneTimeCode), ["4821"])
        XCTAssertEqual(text("2FA: 12345678", .oneTimeCode), ["12345678"])
    }

    func testCodeAloneOnALine() {
        XCTAssertEqual(text("482913", .oneTimeCode), ["482913"])
        XCTAssertEqual(text("  482913  ", .oneTimeCode), ["482913"])
        XCTAssertFalse(kinds("48291").contains(.oneTimeCode))      // 5 digits, no keyword
        XCTAssertFalse(kinds("4829133").contains(.oneTimeCode))    // 7 digits, no keyword
    }

    func testCodeLookingNumberWithoutKeywordIsNotFlagged() {
        XCTAssertFalse(kinds("Order 482913 shipped").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Room 123 456 east").contains(.oneTimeCode))
    }

    func testNumbersThatAreNotCodes() {
        XCTAssertFalse(kinds("Call me at 3pm, code red").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Verify the total $1,299.00").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Verify copyright 2026").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Verify at 12:45 or 12:4567").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Your code is 12345.67").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Your code is $4829").contains(.oneTimeCode))
        XCTAssertFalse(kinds("Your code is 48% off").contains(.oneTimeCode))
        XCTAssertFalse(kinds("2026").contains(.oneTimeCode))
    }

    func testKeywordNeedsAWholeWord() {
        XCTAssertFalse(kinds("Shopping spinning 4821").contains(.oneTimeCode))
    }

    // MARK: Secrets

    func testSecretShapes() {
        let google = "AIza" + String(repeating: "aB3_x-", count: 5) + "abcde"   // 4 + 35
        let samples = [
            "sk-proj-abcdefghijklmnop1234",
            "sk_live_abcdefghijklmnop",
            "sk_test_abcdefghijklmnop",
            "rk_live_abcdefghijklmnop",
            "pk_live_abcdefghijklmnop",
            "ghp_abcdefghijklmnopqrstuv",
            "gho_abcdefghijklmnopqrstuv",
            "ghu_abcdefghijklmnopqrstuv",
            "ghs_abcdefghijklmnopqrstuv",
            "github_pat_11ABCDEFG0abcdefghijkl_mnop",
            "xoxb-123456789012-abcdefghij",
            "xoxp-123456789012-abcdefghij",
            "AKIAIOSFODNN7EXAMPLE",
            google,
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        ]
        for sample in samples {
            XCTAssertEqual(text("key: \(sample) end", .secret), [sample], sample)
        }
    }

    func testGenericHighEntropySecret() {
        let token = "aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5bC7d"
        XCTAssertEqual(text("token \(token)", .secret), [token])
    }

    func testNotSecrets() {
        XCTAssertFalse(kinds("sk-short").contains(.secret))
        XCTAssertFalse(kinds("ghp_tooshort").contains(.secret))
        XCTAssertFalse(kinds("AKIAIOSFODNN7EXAMPL").contains(.secret))                              // one short
        XCTAssertFalse(kinds("task-abcdefghijklmnopqrstuvwxyz").contains(.secret))                  // not at a word start
        XCTAssertFalse(kinds(String(repeating: "abcdef", count: 8)).contains(.secret))              // long but no digits/upper
        XCTAssertFalse(kinds("Aa1" + String(repeating: "a", count: 40)).contains(.secret))          // low entropy
    }

    func testLongURLWithTokenLikePathIsALinkNotASecret() {
        let line = "https://example.com/files/aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5bC7d"
        XCTAssertEqual(kinds(line), [.link])
    }

    // MARK: Keys in groups (#440)

    private let hexKey = "3F9A1C7E-B2D4E6F8-0A1B2C3D-4E5F6071"

    func testLicenseKeyCountsOnItsOwn() {
        XCTAssertEqual(text("K7QM-4XPZ-9TRW-2HBN", .secret), ["K7QM-4XPZ-9TRW-2HBN"])
        XCTAssertEqual(text("License key: K7QM-4XPZ-9TRW-2HBN.", .secret), ["K7QM-4XPZ-9TRW-2HBN"])
        XCTAssertEqual(text("serial k7qm-4xpz-9trw-2hbn ok", .secret), ["k7qm-4xpz-9trw-2hbn"])
    }

    func testHexKeyNeedsASecretWord() {
        XCTAssertEqual(text("Account key \(hexKey)", .secret), [hexKey])
        XCTAssertFalse(kinds(hexKey).contains(.secret))
        let lines = ["Your Account Key", hexKey, "Copy"]
        XCTAssertEqual(LeakScan.matches(inLines: lines).filter { $0.kind == .secret }.map { lines[$0.line] }, [hexKey])
        XCTAssertTrue(LeakScan.matches(inLines: ["Your Account Key", "Copy", hexKey]).filter { $0.kind == .secret }.isEmpty)
    }

    func testUUIDNeedsASecretWord() {
        let uuid = "9b2e4f1a-7c3d-4e5f-8a6b-1c2d3e4f5a6b"
        XCTAssertFalse(kinds("Request \(uuid) failed").contains(.secret))
        XCTAssertFalse(LeakScan.matches(inLines: ["Request ID", uuid, "Retry"]).contains { $0.kind == .secret })
        XCTAssertEqual(text("API token \(uuid)", .secret), [uuid])
    }

    func testThreeGroupsAndSpacedGroupsNeedASecretWord() {
        XCTAssertFalse(kinds("K7QM-4XPZ-9TRW").contains(.secret))
        XCTAssertEqual(text("Recovery key K7QM-4XPZ-9TRW", .secret), ["K7QM-4XPZ-9TRW"])
        XCTAssertFalse(kinds("K7QM 4XPZ 9TRW 2HBN").contains(.secret))
        XCTAssertEqual(text("Secret key: JBSW Y3DP EHPK 3PXP", .secret), ["JBSW Y3DP EHPK 3PXP"])
        XCTAssertFalse(kinds("Key: ROOM 1234 EAST WING").contains(.secret))   // no group mixes letters and digits
    }

    func testGroupsThatAreNotKeys() {
        let negatives = [
            "Due 2026-11-09 at 10:30",
            "Call 415-555-0132 or 1-800-356-9377",
            "Order ABC-12345 shipped",
            "Version 1.19.0 (build 2026-11-09)",
            "Order 1234 shipped today",
            "state-of-the-art key handling",
            "Key: 1234-5678-9012",
            "Password: Model-X200-Pro-Max",
        ]
        for line in negatives { XCTAssertFalse(kinds(line).contains(.secret), line) }
    }

    func testCardWithDashesIsStillACard() {
        XCTAssertEqual(kinds("License 4242-4242-4242-4242"), [.cardNumber])
    }

    func testUUIDInALinkIsNotAKey() {
        let line = "API https://example.com/items/3F9A1C7E-B2D4-4E6F-80A1-B2C3D4E5F607 open"
        XCTAssertFalse(kinds(line).contains(.secret), "\(kinds(line))")
        XCTAssertFalse(kinds("API docs at example.com/K7QM-4XPZ-9TRW-2HBN").contains(.secret))
    }

    func testKeyWrappedOntoTwoLines() {
        let lines = [
            "Your Account Key",
            "This is your Flexibits Account key. Keep it somewhere safe.",
            "3F9A1C7E-B2D4E6F8-",
            "0A1B2C3D-4E5F6071",
            "Never share your account key, it encrypts and protects your data.",
        ]
        let secrets = LeakScan.matches(inLines: lines).filter { $0.kind == .secret }
        XCTAssertEqual(secrets.map(\.line), [2, 3])
        XCTAssertEqual(secrets.map { String(lines[$0.line][$0.range]) }, ["3F9A1C7E-B2D4E6F8-", "0A1B2C3D-4E5F6071"])
    }

    func testWrappedLicenseKeyWithTextAround() {
        let lines = ["Your key is K7QM-4XPZ-", "9TRW-2HBN and never expires"]
        let secrets = LeakScan.matches(inLines: lines).filter { $0.kind == .secret }
        XCTAssertEqual(secrets.map { String(lines[$0.line][$0.range]) }, ["K7QM-4XPZ-", "9TRW-2HBN"])
    }

    func testHyphenatedWordsAcrossLinesAreNotKeys() {
        XCTAssertTrue(LeakScan.matches(inLines: ["A long and well-", "known story about keys"]).isEmpty)
        XCTAssertFalse(LeakScan.matches(inLines: ["Call 415-555-", "0132 today"]).contains { $0.kind == .secret })
        XCTAssertFalse(LeakScan.matches(inLines: ["3F9A1C7E-B2D4E6F8-", "0A1B2C3D-4E5F6071"]).contains { $0.kind == .secret })
    }

    func testLinesMatchLikeSingleLines() {
        let lines = ["Mail jane@example.com today", "Card 4242 4242 4242 4242"]
        XCTAssertEqual(LeakScan.matches(inLines: lines).map(\.kind), [.email, .cardNumber])
        XCTAssertTrue(LeakScan.matches(inLines: []).isEmpty)
    }

    // MARK: Overlaps and order

    func testSecretInsideALinkWinsAndNothingOverlaps() {
        let line = "https://x.com/?k=ghp_abcdefghijklmnopqrstuv"
        let found = LeakScan.matches(in: line)
        XCTAssertTrue(found.contains { $0.kind == .secret })
        for (i, a) in found.enumerated() {
            for b in found[(i + 1)...] { XCTAssertFalse(a.range.overlaps(b.range), "\(a) \(b)") }
        }
    }

    func testCardBeatsPhoneAndCode() {
        XCTAssertEqual(kinds("Card 4242 4242 4242 4242 code"), [.cardNumber])
    }

    func testEmailBeatsLink() {
        // The link detector reads an address as a mailto link; the email is the more specific kind.
        XCTAssertEqual(kinds("jane@example.com"), [.email])
    }

    func testCodeBeatsPhone() {
        XCTAssertEqual(kinds("Your code is 123-456"), [.oneTimeCode])
    }

    func testSortedByPositionWithCorrectRanges() {
        let line = "a@b.com then ghp_abcdefghijklmnopqrstuv then 415-555-0132"
        let found = LeakScan.matches(in: line)
        XCTAssertEqual(found.map(\.kind), [.email, .secret, .phone])
        XCTAssertEqual(found.map { String(line[$0.range]) }, ["a@b.com", "ghp_abcdefghijklmnopqrstuv", "415-555-0132"])
    }

    func testCodeDoesNotSplitAPhoneNumber() {
        let line = "Your code is 482913, call 415-555-0132"
        XCTAssertEqual(text(line, .oneTimeCode), ["482913"])
        XCTAssertEqual(text(line, .phone), ["415-555-0132"])
        let spaced = "Verify code 482913 or call 415 555 0132"
        XCTAssertEqual(text(spaced, .oneTimeCode), ["482913"])
        XCTAssertEqual(text(spaced, .phone), ["415 555 0132"])
        XCTAssertEqual(text("Your code is 482913 valid 10 minutes", .oneTimeCode), ["482913"])
    }

    func testNeverReturnsFaces() {
        let line = "a@b.com https://x.com 415-555-0132 Your code is 482913 and card 4242 4242 4242 4242 ghp_abcdefghijklmnopqrstuv"
        XCTAssertFalse(kinds(line).contains(.face))
        XCTAssertTrue(Set(kinds(line)).isSuperset(of: [.email, .link, .phone, .oneTimeCode, .cardNumber, .secret]), "\(kinds(line))")
    }

    // MARK: Scan (needs Vision OCR)

    func testScanFindsACardNumberInAnImage() async {
        let image = TestImages.text(["Card 4242 4242 4242 4242"])
        let findings = await LeakScan.scan(image, size: TestImages.size(of: image), kinds: [.cardNumber])
        // OCR can misread a digit, so only the kind is checked, not the exact box.
        XCTAssertTrue(findings.contains { $0.kind == .cardNumber }, "\(findings)")
        for f in findings { XCTAssertTrue(CGRect(x: -2, y: -2, width: 1004, height: 124).contains(f.box), "\(f)") }
    }

    func testScanHonorsTheWantedKinds() async {
        let image = TestImages.text(["Mail jane@example.com today"])
        let size = TestImages.size(of: image)
        let emails = await LeakScan.scan(image, size: size, kinds: [.email])
        let cards = await LeakScan.scan(image, size: size, kinds: [.cardNumber])
        XCTAssertEqual(emails.map(\.kind), [.email])
        XCTAssertTrue(cards.isEmpty)
    }

    func testScanRunsFaceDetectionAndFindsNoneInText() async {
        let image = TestImages.text(["No people here"])
        let findings = await LeakScan.scan(image, size: TestImages.size(of: image), kinds: [.face])
        XCTAssertTrue(findings.isEmpty, "\(findings)")
    }
}
