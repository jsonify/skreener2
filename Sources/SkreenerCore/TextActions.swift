import CoreGraphics
import Foundation

/// What can be taken out of the text in a screenshot (#441): links, dates, phone numbers and emails, each once, in
/// reading order, plus the text itself. Pure text and boxes: the editor reads the lines with OCR (`TextRecognizer`)
/// and shows the result.
public enum TextActions {
    public struct Link: Equatable, Sendable {
        /// As it was read, e.g. "example.com/a".
        public let text: String
        /// What opens: the text with a scheme added when it had none (only http and https are kept).
        public let url: URL

        public init(text: String, url: URL) {
            self.text = text
            self.url = url
        }
    }

    /// A date or time found in a line, for a calendar event.
    public struct Event: Equatable, Sendable {
        /// As it was read, e.g. "March 5 at 7:30 PM".
        public let text: String
        public let start: Date
        /// The text has no time of day, so the event is all day.
        public let allDay: Bool
        /// How long it lasts: the text's own length ("7 to 8 PM") when it gives one, otherwise an hour. Zero when
        /// all day.
        public let duration: TimeInterval
        /// A short name for the event: the line it was found on without the date, or "Event".
        public let title: String

        public init(text: String, start: Date, allDay: Bool, duration: TimeInterval, title: String) {
            self.text = text
            self.start = start
            self.allDay = allDay
            self.duration = duration
            self.title = title
        }

        public var end: Date { allDay ? start : start.addingTimeInterval(duration) }
    }

    public struct Found: Equatable, Sendable {
        public var links: [Link] = []
        public var dates: [Event] = []
        public var phones: [String] = []
        public var emails: [String] = []

        public init() {}

        /// Nothing to act on besides copying the text.
        public var isEmpty: Bool { links.isEmpty && dates.isEmpty && phones.isEmpty && emails.isEmpty }
    }

    /// The default length of an event whose text gives none.
    public static let defaultDuration: TimeInterval = 3600

    // MARK: Lines

    /// `lines` in reading order (top to bottom, then left to right on one row), without the lines whose box a
    /// redaction in `covered` overlaps: they are hidden in the picture, so they are not handed out. `boxes` are the
    /// lines' boxes in image points, bottom-left origin, as `TextRecognizer.TextIndex` has them, and `covered` the
    /// redactions' rects in the same space. Without a box for every line, the lines come back as they are.
    public static func visibleLines(_ lines: [String], boxes: [CGRect], covered: [CGRect]) -> [String] {
        guard lines.count == boxes.count else { return lines }
        return readingOrder(boxes)
            .filter { !isCovered(boxes[$0], by: covered) && !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
            .map { lines[$0] }
    }

    /// The indexes of `boxes` from the top row to the bottom one (bottom-left origin: larger y is higher), each row
    /// left to right. Boxes whose centres are less than half the shorter one's height apart share a row.
    public static func readingOrder(_ boxes: [CGRect]) -> [Int] {
        let byHeight = boxes.indices.sorted { boxes[$0].midY > boxes[$1].midY }
        var rows: [[Int]] = []
        var rowMid = CGFloat.zero, rowHeight = CGFloat.zero
        for i in byHeight {
            if !rows.isEmpty, abs(boxes[i].midY - rowMid) < min(rowHeight, boxes[i].height) / 2 {
                rows[rows.count - 1].append(i)
            } else {
                rows.append([i])
                rowMid = boxes[i].midY
                rowHeight = boxes[i].height
            }
        }
        return rows.flatMap { $0.sorted { boxes[$0].minX < boxes[$1].minX } }
    }

    /// A redaction covers the line when it overlaps at least a third of the line's height and any of its width.
    /// Generous on purpose: a word left readable beside a covered one would be handed out.
    static func isCovered(_ box: CGRect, by covered: [CGRect]) -> Bool {
        covered.contains { rect in
            let overlap = box.intersection(rect.standardized)
            return !overlap.isNull && overlap.width >= 1 && overlap.height >= box.height / 3
        }
    }

    // MARK: Finding

    /// The links, dates, phone numbers and emails in `lines` (one OCR line each, in reading order), each once.
    public static func find(in lines: [String]) -> Found {
        var found = Found()
        var seen = Set<String>()
        func first(_ key: String) -> Bool { seen.insert(key).inserted }
        for line in lines {
            for match in detect(.link, in: line) {
                guard let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      let range = Range(match.range, in: line) else { continue }
                let text = trimmed(String(line[range]))
                if first("link:" + url.absoluteString.lowercased()) { found.links.append(Link(text: text, url: url)) }
            }
            for range in emailRanges(in: line) {
                let email = trimmed(String(line[range]))
                if first("email:" + email.lowercased()) { found.emails.append(email) }
            }
            for match in detect(.phoneNumber, in: line) {
                guard let range = Range(match.range, in: line) else { continue }
                let phone = trimmed(String(line[range]))
                let digits = phone.filter(\.isNumber)
                if digits.count >= 5, first("phone:" + digits) { found.phones.append(phone) }
            }
            for match in detect(.date, in: line) {
                guard let start = match.date, let range = Range(match.range, in: line) else { continue }
                let text = trimmed(String(line[range]))
                let allDay = !hasTimeOfDay(text)
                guard first("date:\(start.timeIntervalSince1970):\(allDay)") else { continue }
                let duration = match.duration > 0 ? match.duration : defaultDuration
                found.dates.append(Event(text: text, start: start, allDay: allDay, duration: allDay ? 0 : duration,
                                         title: title(line: line, removing: range)))
            }
        }
        return found
    }

    // MARK: Pieces

    private static func detect(_ type: NSTextCheckingResult.CheckingType, in line: String) -> [NSTextCheckingResult] {
        guard let detector = try? NSDataDetector(types: type.rawValue) else { return [] }
        return detector.matches(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private static let emailPattern = try? NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
                                                               options: .caseInsensitive)

    private static func emailRanges(in line: String) -> [Range<String.Index>] {
        (emailPattern?.matches(in: line, range: NSRange(line.startIndex..., in: line)) ?? [])
            .compactMap { Range($0.range, in: line) }
    }

    private static let timePattern = try? NSRegularExpression(
        pattern: "\\d\\s?:\\s?\\d{2}|\\b\\d{1,2}\\s?[ap]\\.?m\\b|\\bnoon\\b|\\bmidnight\\b|\\bo'clock\\b",
        options: .caseInsensitive)

    /// The date's text names a time of day ("7:30", "7 pm", "noon"). Without one the detector's time (noon) is not
    /// the user's, and the event is all day.
    static func hasTimeOfDay(_ text: String) -> Bool {
        timePattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The line without the date, as the event's name; "Event" when little is left.
    static func title(line: String, removing range: Range<String.Index>) -> String {
        var rest = line
        rest.removeSubrange(range)
        let edge = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—@|·•()[]"))
        var words = rest.trimmingCharacters(in: edge)
        // A dangling "at", "on" or "from" where the date was.
        for lead in ["at", "on", "from", "by"] {
            if words.lowercased().hasSuffix(" " + lead) { words = String(words.dropLast(lead.count + 1)) }
            if words.lowercased().hasPrefix(lead + " ") { words = String(words.dropFirst(lead.count + 1)) }
        }
        words = words.trimmingCharacters(in: edge)
        guard words.filter(\.isLetter).count >= 3 else { return "Event" }
        return words.count > 80 ? String(words.prefix(80)).trimmingCharacters(in: .whitespaces) + "…" : words
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:)]>")))
    }
}
