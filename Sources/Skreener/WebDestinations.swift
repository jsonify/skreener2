import AppKit

/// Web apps a capture can be sent to: Gmail and Google Chat, opened in the default browser. A web page can't be handed
/// a file, so the picture goes on the clipboard and the page opens ready to paste it into.
enum WebApp: String, CaseIterable {
    case gmail, googleChat

    var title: String {
        switch self {
        case .gmail: return "Gmail"
        case .googleChat: return "Google Chat"
        }
    }

    var symbol: String {
        switch self {
        case .gmail: return "envelope"
        case .googleChat: return "bubble.left.and.bubble.right"
        }
    }

    /// The page that opens: a new Gmail message titled after the capture, or Google Chat.
    func url(subject: String) -> URL? {
        switch self {
        case .gmail: return WebLinks.gmailCompose(subject: subject)
        case .googleChat: return WebLinks.googleChat
        }
    }

    /// What the user does next, once the page is open.
    var pasteHint: String {
        switch self {
        case .gmail: return "The picture is on the clipboard: press ⌘V in the message."
        case .googleChat: return "The picture is on the clipboard: pick a chat and press ⌘V."
        }
    }
}

/// The links that open Gmail and Google Chat. Pure text-building, so it is unit-tested.
enum WebLinks {
    static let googleChat = URL(string: "https://mail.google.com/chat/")

    /// Gmail's full-window compose form, with whichever fields are given.
    static func gmailCompose(to: String? = nil, cc: String? = nil, bcc: String? = nil, subject: String? = nil,
                             body: String? = nil) -> URL? {
        NoteLinks.link("https://mail.google.com/mail/", [("view", "cm"), ("fs", "1"), ("to", to), ("cc", cc), ("bcc", bcc),
                                                         ("su", subject), ("body", body)])
    }

    /// The same message as a `mailto:` link (address, subject, body, cc, bcc), written in Gmail instead, or nil when
    /// `mailto` isn't one.
    static func gmailCompose(mailto: URL) -> URL? {
        guard mailto.scheme?.lowercased() == "mailto",
              let parts = URLComponents(url: mailto, resolvingAgainstBaseURL: false) else { return nil }
        var fields: [String: [String]] = [:]
        if !parts.path.isEmpty { fields["to", default: []].append(parts.path) }
        for item in parts.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            fields[item.name.lowercased(), default: []].append(value)
        }
        func field(_ name: String) -> String? { fields[name].map { $0.joined(separator: ",") } }
        guard field("to") != nil || field("subject") != nil || field("body") != nil else { return nil }
        return gmailCompose(to: field("to"), cc: field("cc"), bcc: field("bcc"), subject: field("subject"),
                            body: field("body"))
    }

    /// Where an email link from a smart action goes: Gmail when Settings → Send To says so, else as it is (the Mac's
    /// default email app).
    static func emailLink(_ url: URL, inGmail: Bool) -> URL {
        guard inGmail, url.scheme?.lowercased() == "mailto" else { return url }
        return gmailCompose(mailto: url) ?? url
    }
}

/// A web app as a Send To destination: the picture on the clipboard and the page opened in the default browser.
struct WebDestination: SendDestination {
    let app: WebApp

    var id: String { "web.\(app.rawValue)" }
    var title: String { app.title }
    var symbol: String { app.symbol }
    /// A browser can't take a pasted video file.
    var acceptsRecordings: Bool { false }
    var wantsText: Bool { false }
    var isAvailable: Bool { !Preferences.sendToHidden.contains(id) }

    func send(file: URL, text: String?, app sourceApp: String?) async throws -> SendResult {
        guard let image = NSImage(contentsOf: file) else { throw SendError("Couldn't read the capture.") }
        Output.copy(image)
        guard let url = app.url(subject: file.deletingPathExtension().lastPathComponent), NSWorkspace.shared.open(url) else {
            throw SendError("Your browser didn't open \(app.title). The picture is on the clipboard.")
        }
        return SendResult(title: "Opened \(app.title)", detail: app.pasteHint)
    }
}

enum WebDestinations {
    /// Every web destination; `SendTo` lists the ones that are turned on.
    @MainActor static func all() -> [SendDestination] { WebApp.allCases.map { WebDestination(app: $0) } }
}
