import Foundation

/// An event to add to Calendar (#243).
struct CalendarEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var location: String?
}

/// Something found in a capture: by the data detector in its text, or by Vision as a QR code or barcode (#243).
enum SmartDetection: Equatable {
    /// `line` is the line of text the date was in, which becomes the event's title.
    case date(start: Date, duration: TimeInterval, line: String)
    case address(String)
    case phone(String)
    case link(URL)
    case flight(String)
    case code(String)
}

/// What a smart action does (#243).
struct SmartAction: Equatable {
    /// The order the actions are offered in.
    enum Kind: Int, Comparable {
        case openCode, copyCode, calendar, maps, call, link, flight
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    var kind: Kind
    /// For menus, e.g. "Open in Maps: 1 Infinite Loop".
    var title: String
    /// For a Quick Access chip, e.g. "Maps".
    var chipTitle: String
    /// What opens (maps, call, link, flight search, QR link).
    var url: URL?
    /// What Copy puts on the clipboard.
    var text: String?
    var event: CalendarEvent?

    var symbol: String {
        switch kind {
        case .openCode: return "qrcode"
        case .copyCode: return "doc.on.doc"
        case .calendar: return "calendar.badge.plus"
        case .maps: return "map"
        case .call: return "phone"
        case .link: return "link"
        case .flight: return "airplane"
        }
    }
}

/// Turns what was found in a capture into actions: the mapping, URLs, ordering and de-duplication (#243).
enum SmartActions {
    /// An event with no length of its own lasts this long.
    static let defaultDuration: TimeInterval = 3600

    /// Finds dates, addresses, phone numbers, links and flights in `text`, in the order they appear.
    static func detections(in text: String) -> [SmartDetection] {
        let types: NSTextCheckingResult.CheckingType = [.date, .address, .phoneNumber, .link, .transitInformation]
        guard !text.isEmpty, let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let ns = text as NSString
        var out: [SmartDetection] = []
        for r in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let matched = ns.substring(with: r.range).trimmingCharacters(in: .whitespacesAndNewlines)
            switch r.resultType {
            case .date:
                guard let date = r.date else { continue }
                let line = ns.substring(with: ns.lineRange(for: r.range)).trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(.date(start: date, duration: r.duration, line: line))
            case .address:
                out.append(.address(matched))
            case .phoneNumber:
                out.append(.phone(r.phoneNumber ?? matched))
            case .link:
                if let url = r.url { out.append(.link(url)) }
            case .transitInformation:
                let parts = [r.components?[.airline], r.components?[.flight]].compactMap { $0 }
                out.append(.flight(parts.isEmpty ? matched : parts.joined(separator: " ")))
            default:
                break
            }
        }
        return out
    }

    /// The actions for `found`, in the order they are offered (QR codes first), without duplicates, at most `limit`.
    static func actions(for found: [SmartDetection], limit: Int = 8) -> [SmartAction] {
        var location: String?
        var codeLinks = Set<String>()
        for d in found {
            if case .address(let a) = d, location == nil { location = a }
            // A link that a QR code also holds is offered once.
            if case .code(let payload) = d, let url = openableURL(payload) { codeLinks.insert(linkKey(url)) }
        }
        var seen = Set<String>()
        var out: [SmartAction] = []
        func add(_ a: SmartAction, key: String) {
            if seen.insert("\(a.kind.rawValue)|\(key)").inserted { out.append(a) }
        }
        for d in found {
            switch d {
            case .code(let payload):
                let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if let url = openableURL(text) {
                    add(SmartAction(kind: .openCode, title: "Open \(short(text, 40)) from QR Code", chipTitle: "Open QR", url: url),
                        key: linkKey(url))
                }
                add(SmartAction(kind: .copyCode, title: "Copy QR Code Content: \(short(text, 40))", chipTitle: "Copy QR", text: text),
                    key: text)
            case .date(let start, let duration, let line):
                let end = start.addingTimeInterval(duration > 0 ? duration : defaultDuration)
                let event = CalendarEvent(title: line.isEmpty ? "Event" : short(line, 80), start: start, end: end, location: location)
                add(SmartAction(kind: .calendar, title: "Add to Calendar: \(short(line, 40))", chipTitle: "Calendar", event: event),
                    key: String(Int(start.timeIntervalSince1970)))
            case .address(let address):
                guard let url = mapsURL(for: address) else { continue }
                add(SmartAction(kind: .maps, title: "Open in Maps: \(short(address, 40))", chipTitle: "Maps", url: url),
                    key: address.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " "))
            case .phone(let number):
                guard let url = telURL(for: number) else { continue }
                add(SmartAction(kind: .call, title: "Call \(short(number, 30))", chipTitle: "Call", url: url),
                    key: url.absoluteString)
            case .link(let url):
                guard !codeLinks.contains(linkKey(url)), let scheme = url.scheme?.lowercased() else { continue }
                if scheme == "mailto" {
                    let address = String(url.absoluteString.dropFirst("mailto:".count))
                    add(SmartAction(kind: .link, title: "Email \(short(address, 40))", chipTitle: "Email", url: url),
                        key: linkKey(url))
                } else if scheme == "http" || scheme == "https" {
                    add(SmartAction(kind: .link, title: "Open \(short(url.host ?? url.absoluteString, 40))", chipTitle: "Open Link",
                                    url: url), key: linkKey(url))
                }
            case .flight(let flight):
                guard let url = flightURL(for: flight) else { continue }
                add(SmartAction(kind: .flight, title: "Look Up Flight \(short(flight, 20))", chipTitle: "Flight", url: url),
                    key: flight.lowercased())
            }
        }
        // Stable: actions of one kind keep the order they were found in.
        let ranked = out.enumerated().sorted { ($0.element.kind, $0.offset) < ($1.element.kind, $1.offset) }
        return ranked.prefix(limit).map(\.element)
    }

    // MARK: URLs

    /// Percent-encodes `s` for a query value (only letters, digits and `-._~` stay as they are).
    static func queryEscaped(_ s: String) -> String {
        let keep = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: keep) ?? s
    }

    /// Apple Maps, searching for `address` (its lines joined with commas).
    static func mapsURL(for address: String) -> URL? {
        let q = address.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return q.isEmpty ? nil : URL(string: "https://maps.apple.com/?q=" + queryEscaped(q))
    }

    /// `tel:` with just the digits (and a leading +), or nil when there are too few to be a number.
    static func telURL(for number: String) -> URL? {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        let digits = String(trimmed.filter { $0.isASCII && $0.isNumber })
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:" + (trimmed.hasPrefix("+") ? "+" : "") + digits)
    }

    /// A web search for a flight such as "UA 123".
    static func flightURL(for flight: String) -> URL? {
        let q = flight.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? nil : URL(string: "https://www.google.com/search?q=" + queryEscaped("flight " + q))
    }

    /// The URL a QR code's content is, when it is one worth opening: a web address, or a mail or phone link.
    static func openableURL(_ payload: String) -> URL? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text), let scheme = url.scheme?.lowercased()
        else { return nil }
        switch scheme {
        case "http", "https": return url.host?.isEmpty == false ? url : nil
        case "mailto", "tel": return text.count > scheme.count + 1 ? url : nil
        default: return nil
        }
    }

    private static func linkKey(_ url: URL) -> String {
        var s = url.absoluteString.lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// `s` on one line, cut to `max` characters with an ellipsis.
    static func short(_ s: String, _ max: Int) -> String {
        let one = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return one.count > max ? String(one.prefix(max - 1)) + "…" : one
    }
}

/// An .ics file for Calendar to open, so no Calendar permission is needed (#243).
enum ICalendar {
    /// The event as a calendar file (CRLF lines, times in UTC).
    static func file(for e: CalendarEvent, uid: String = UUID().uuidString, stamp: Date = Date()) -> String {
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Skreener//Smart Actions//EN", "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT", "UID:\(uid)", "DTSTAMP:\(utc(stamp))", "DTSTART:\(utc(e.start))", "DTEND:\(utc(e.end))",
            "SUMMARY:\(escape(e.title))",
        ]
        if let place = e.location, !place.isEmpty { lines.append("LOCATION:\(escape(place))") }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// `20261028T143000Z`.
    static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    /// Text values escape backslash, semicolon, comma and line breaks.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next line after a space, never in the middle of a character.
    static func fold(_ line: String) -> String {
        var out = "", used = 0
        for ch in line {
            let n = String(ch).utf8.count
            if used + n > 75 { out += "\r\n "; used = 1 }
            out.append(ch)
            used += n
        }
        return out
    }
}
