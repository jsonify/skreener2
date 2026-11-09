import Foundation

/// Safe Check (#408): finds things in a screenshot that shouldn't be shared. The matchers here work on lines of
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
    /// and without overlaps (the more specific kind wins). Never returns `.face`. A key that needs a secret word
    /// nearby (see `groupedKeys`) only counts here when `line` itself has one.
    public static func matches(in line: String) -> [(kind: Kind, range: Range<String.Index>)] {
        matches(in: line, nearSecretWord: hasSecretWord(line))
    }

    /// `matches(in:)` for each of `lines` (OCR lines, top to bottom), with two things one line can't show (#440): a
    /// secret word on the line before or after counts as nearby, and a key wrapped onto the next line after a hyphen
    /// is matched as one. A wrapped key comes back as one `.secret` per line, each covering that line's part.
    public static func matches(inLines lines: [String]) -> [(line: Int, kind: Kind, range: Range<String.Index>)] {
        let worded = lines.map(hasSecretWord)
        func nearWord(_ from: Int, _ to: Int) -> Bool {
            worded[max(0, from - 1)...min(lines.count - 1, to + 1)].contains(true)
        }
        var found: [(line: Int, kind: Kind, range: Range<String.Index>)] = []
        for (i, line) in lines.enumerated() {
            found += matches(in: line, nearSecretWord: nearWord(i, i)).map { (line: i, kind: $0.kind, range: $0.range) }
        }
        for i in lines.indices.dropLast() {
            for part in wrappedSecrets(lines[i], lines[i + 1], nearSecretWord: nearWord(i, i + 1)) {
                let line = i + part.next
                found.removeAll { $0.line == line && $0.range.overlaps(part.range) }
                found.append((line: line, kind: .secret, range: part.range))
            }
        }
        return found.sorted { $0.line != $1.line ? $0.line < $1.line : $0.range.lowerBound < $1.range.lowerBound }
    }

    static func matches(in line: String, nearSecretWord: Bool) -> [(kind: Kind, range: Range<String.Index>)] {
        let links = TextRecognizer.matches(.links, in: line)
        var found: [(kind: Kind, range: Range<String.Index>)] = []
        found += secrets(in: line, links: links, nearSecretWord: nearSecretWord).map { (kind: Kind.secret, range: $0) }
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
    // A code never starts or ends inside a longer group of digits joined by a dash or space (a phone number).
    private static let codeRegex = regex("(?<![\\w.,:/$€£+-])(?<!\\d[ -])(?:\\d{3,4}[ -]\\d{3,4}|\\d{4,8})(?![\\w%]|[.,:/-]\\d| \\d{3,4}(?!\\d))")
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
    // Three or more groups of 4–12 letters and digits joined by hyphens, not part of a path, address or longer word.
    private static let hyphenGroups = regex(
        "(?<![A-Za-z0-9_./@:-])[A-Za-z0-9]{4,12}(?:-[A-Za-z0-9]{4,12}){2,}(?![A-Za-z0-9_/@-]|\\.[A-Za-z0-9])")
    // Three or more groups of 4–8 capitals and digits joined by single spaces.
    private static let spaceGroups = regex("(?<![A-Za-z0-9_./@:-])[A-Z0-9]{4,8}(?: [A-Z0-9]{4,8}){2,}(?![A-Za-z0-9_/@-])")
    private static let secretWords = regex(
        "\\b(?:keys?|tokens?|secrets?|passwords?|passphrase|recovery|licen[cs]e|api|seed)\\b", options: .caseInsensitive)
    // A line's last key-shaped fragment that ends in a hyphen, and the next line's first one.
    private static let wrapTail = regex("(?<![A-Za-z0-9_./@:-])[A-Za-z0-9]{4,12}(?:-[A-Za-z0-9]{4,12})*-\\s*$")
    private static let wrapHead = regex("^\\s*[A-Za-z0-9]{4,12}(?:-[A-Za-z0-9]{4,12})*(?![A-Za-z0-9_/@-]|\\.[A-Za-z0-9])")

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants above, so they always compile.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func ranges(_ re: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    private static func secrets(in line: String, links: [Range<String.Index>], nearSecretWord: Bool) -> [Range<String.Index>] {
        var out = secretShapes.flatMap { ranges($0, in: line) }
        for run in ranges(longRun, in: line) where !links.contains(where: { $0.overlaps(run) }) {
            let s = line[run]
            if s.contains(where: \.isUppercase), s.contains(where: \.isLowercase), s.contains(where: \.isNumber),
               entropy(s) >= 3.5 { out.append(run) }
        }
        out += groupedKeys(in: line, nearSecretWord: nearSecretWord).filter { key in !links.contains { $0.overlaps(key) } }
        return out
    }

    /// Whether `line` has a word that says a key is near: key, token, secret, password, passphrase, recovery,
    /// license (licence), API or seed, in any case.
    static func hasSecretWord(_ line: String) -> Bool { !ranges(secretWords, in: line).isEmpty }

    /// Keys written as groups (#440), such as license, recovery and account keys or UUIDs. A key is three or more
    /// groups of 4–12 letters and digits joined by hyphens, or of 4–8 capitals and digits all one length joined by
    /// single spaces; it's in one case, and at least one group mixes letters and digits. Four or more hyphenated
    /// groups, two of them mixed, with a letter past F (K7QM-4XPZ-9TRW-2HBN) count on their own. The rest count only
    /// `nearSecretWord`: three groups, spaced groups, and hex-only keys such as a UUID or an 8-8-8-8 key, because
    /// UUIDs and hex IDs also name things that aren't secret. Dates, phones and card numbers have no letters.
    private static func groupedKeys(in line: String, nearSecretWord: Bool) -> [Range<String.Index>] {
        func mixed(_ group: Substring) -> Bool { group.contains(where: \.isLetter) && group.contains(where: \.isNumber) }
        var out: [Range<String.Index>] = []
        for r in ranges(hyphenGroups, in: line) {
            let key = line[r], groups = key.split(separator: "-")
            let mixedGroups = groups.filter(mixed).count
            guard mixedGroups > 0, !(key.contains(where: \.isUppercase) && key.contains(where: \.isLowercase)) else { continue }
            let alone = groups.count >= 4 && mixedGroups >= 2 && key.contains { $0.isLetter && !$0.isHexDigit }
            if alone || nearSecretWord { out.append(r) }
        }
        guard nearSecretWord else { return out }
        for r in ranges(spaceGroups, in: line) {
            // Runs of groups of one length, so a capitalized word before or after the key is left out.
            var run: [Substring] = []
            for group in line[r].split(separator: " ") + [line[r.upperBound..<r.upperBound]] {
                if let last = run.last, last.count == group.count { run.append(group); continue }
                if run.count >= 3, run.contains(where: mixed), let first = run.first, let last = run.last {
                    out.append(first.startIndex..<last.endIndex)
                }
                run = [group]
            }
        }
        return out
    }

    /// A key wrapped from `line` onto `next` after a hyphen (60752CED-67C223AA- / EEA34445-256C3881): the last
    /// key-shaped fragment of `line` and the first of `next` are joined and matched as secrets, and each match that
    /// spans the join comes back as its two parts (`next` is 0 for the part on `line`, 1 for the part on `next`).
    static func wrappedSecrets(_ line: String, _ next: String, nearSecretWord: Bool) -> [(next: Int, range: Range<String.Index>)] {
        guard let tail = ranges(wrapTail, in: line).first, let head = ranges(wrapHead, in: next).first else { return [] }
        let tailText = line[tail].trimmingCharacters(in: .whitespaces), headText = next[head].trimmingCharacters(in: .whitespaces)
        guard let tailStart = line[tail].firstIndex(where: { !$0.isWhitespace }),
              let headStart = next[head].firstIndex(where: { !$0.isWhitespace }) else { return [] }
        let joined = tailText + headText, cut = tailText.count
        var out: [(next: Int, range: Range<String.Index>)] = []
        // The fragments are ASCII letters, digits and hyphens, so character offsets carry over.
        for r in secrets(in: joined, links: [], nearSecretWord: nearSecretWord) {
            let start = joined.distance(from: joined.startIndex, to: r.lowerBound)
            let end = joined.distance(from: joined.startIndex, to: r.upperBound)
            guard start < cut, end > cut else { continue }
            out.append((next: 0, range: line.index(tailStart, offsetBy: start)..<line.index(tailStart, offsetBy: cut)))
            out.append((next: 1, range: headStart..<next.index(headStart, offsetBy: end - cut)))
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
