import Foundation

/// Safe Check (#408): finds things in a screenshot that shouldn't be shared. The matchers here work on one line of
/// text and need no screen; `LeakScan+Vision.swift` runs them over OCR and adds faces.
public enum LeakScan {
    /// What a finding is. Faces come from Vision, not from text.
    public enum Kind: CaseIterable, Sendable {
        case email, phone, link, oneTimeCode, cardNumber, secret, face

        /// A short name for the Safe Check chips.
        public var title: String {
            switch self {
            case .email: return "Emails"
            case .phone: return "Phones"
            case .link: return "Links"
            case .oneTimeCode: return "Codes"
            case .cardNumber: return "Cards"
            case .secret: return "Keys"
            case .face: return "Faces"
            }
        }

        /// Wins an overlap: lower is more specific.
        fileprivate var rank: Int {
            switch self {
            case .secret: return 0
            case .cardNumber: return 1
            case .oneTimeCode: return 2
            case .email: return 3
            case .link: return 4
            case .phone: return 5
            case .face: return 6
            }
        }
    }

    /// Everything in `line` that looks like an email, phone, link, one-time code, card number or secret, in order
    /// and without overlaps (the more specific kind wins). Never returns `.face`.
    public static func matches(in line: String) -> [(kind: Kind, range: Range<String.Index>)] {
        let links = TextRecognizer.matches(.links, in: line)
        var found: [(kind: Kind, range: Range<String.Index>)] = []
        found += secrets(in: line, links: links).map { (kind: Kind.secret, range: $0) }
        found += cards(in: line).map { (kind: Kind.cardNumber, range: $0) }
        found += codes(in: line).map { (kind: Kind.oneTimeCode, range: $0) }
        found += TextRecognizer.matches(.emails, in: line).map { (kind: Kind.email, range: $0) }
        found += links.map { (kind: Kind.link, range: $0) }
        found += TextRecognizer.matches(.phoneNumbers, in: line).map { (kind: Kind.phone, range: $0) }

        var kept: [(kind: Kind, range: Range<String.Index>)] = []
        for item in found.sorted(by: { $0.kind.rank < $1.kind.rank }) where !kept.contains(where: { $0.range.overlaps(item.range) }) {
            kept.append(item)
        }
        return kept.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The Luhn check of a card number. Spaces and dashes are ignored; any other character fails it.
    public static func luhn(_ digits: String) -> Bool {
        var sum = 0, count = 0
        var doubled = false
        for ch in digits.reversed() {
            if ch == " " || ch == "-" { continue }
            guard ch.isASCII, let d = ch.wholeNumberValue else { return false }
            var v = d
            if doubled { v *= 2; if v > 9 { v -= 9 } }
            sum += v
            doubled.toggle()
            count += 1
        }
        return count > 0 && sum % 10 == 0
    }

    // MARK: Matchers

    private static let cardRegex = regex("(?<!\\d)\\d(?:[ -]?\\d){12,18}(?!\\d)")
    private static let codeRegex = regex("(?<![\\w.,:/$€£+-])(?:\\d{3,4}[ -]\\d{3,4}|\\d{4,8})(?![\\w%]|[.,:/]\\d)")
    private static let codeKeywords = regex(
        "\\b(?:codes?|otp|passcode|verification|verify|pin|2fa|one-time|security code|is your)\\b", options: .caseInsensitive)
    private static let sixDigits = regex("^\\d{6}$")
    private static let secretShapes = [
        regex("\\b(?:sk-|sk_live_|sk_test_|rk_live_|pk_live_)[A-Za-z0-9_\\-]{16,}"),
        regex("\\b(?:ghp_|gho_|ghu_|ghs_)[A-Za-z0-9]{20,}"),
        regex("\\bgithub_pat_[A-Za-z0-9_]{20,}"),
        regex("\\bxox[abprs]-[A-Za-z0-9-]{10,}"),
        regex("\\bAKIA[0-9A-Z]{16}\\b"),
        regex("\\bAIza[0-9A-Za-z_\\-]{35}"),
        regex("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"),
    ]
    private static let longRun = regex("[A-Za-z0-9_\\-+/=]{32,}")

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants above, so they always compile.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func ranges(_ re: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    private static func secrets(in line: String, links: [Range<String.Index>]) -> [Range<String.Index>] {
        var out = secretShapes.flatMap { ranges($0, in: line) }
        for run in ranges(longRun, in: line) where !links.contains(where: { $0.overlaps(run) }) {
            let s = line[run]
            if s.contains(where: \.isUppercase), s.contains(where: \.isLowercase), s.contains(where: \.isNumber),
               entropy(s) >= 3.5 { out.append(run) }
        }
        return out
    }

    /// Shannon entropy in bits per character.
    private static func entropy(_ s: Substring) -> Double {
        var counts: [Character: Int] = [:]
        for ch in s { counts[ch, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { $0 - Double($1) / n * log2(Double($1) / n) }
    }

    private static func cards(in line: String) -> [Range<String.Index>] {
        ranges(cardRegex, in: line).filter { luhn(String(line[$0])) }
    }

    private static func codes(in line: String) -> [Range<String.Index>] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ranges(sixDigits, in: trimmed).isEmpty, let r = line.range(of: trimmed) { return [r] }
        guard !ranges(codeKeywords, in: line).isEmpty else { return [] }
        return ranges(codeRegex, in: line).filter { !isYear(line[$0]) }
    }

    private static func isYear(_ s: Substring) -> Bool {
        guard s.count == 4, let n = Int(s) else { return false }
        return (1900...2099).contains(n)
    }
}
