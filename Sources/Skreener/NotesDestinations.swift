import AppKit

/// The notes and task apps a capture can be sent to (#275). Only the ones that are installed are listed.
enum NotesApp: String, CaseIterable {
    case obsidian, bear, drafts, things, appleNotes, reminders

    var title: String {
        switch self {
        case .obsidian: return "Obsidian"
        case .bear: return "Bear"
        case .drafts: return "Drafts"
        case .things: return "Things"
        case .appleNotes: return "Apple Notes"
        case .reminders: return "Reminders"
        }
    }

    var symbol: String {
        switch self {
        case .obsidian: return "diamond"
        case .bear: return "pawprint"
        case .drafts: return "square.and.pencil"
        case .things: return "checkmark.circle"
        case .appleNotes: return "note.text"
        case .reminders: return "list.bullet"
        }
    }

    var bundleID: String {
        switch self {
        case .obsidian: return "md.obsidian"
        case .bear: return "net.shinyfrog.bear"
        case .drafts: return "com.agiletortoise.Drafts-OSX"
        case .things: return "com.culturedcode.ThingsMac"
        case .appleNotes: return "com.apple.Notes"
        case .reminders: return "com.apple.reminders"
        }
    }

    /// What this app can hold: Obsidian, Bear and Apple Notes take the picture; the others only text, so the picture
    /// is put on the clipboard for pasting.
    var takesImage: Bool { self == .obsidian || self == .bear || self == .appleNotes }

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
}

/// The links and scripts that hand a capture to those apps. Pure text-building, so it is unit-tested.
enum NoteLinks {
    /// Characters that need no escaping in a query value. Apps decode `%20` but not `+`, and `&`, `=`, `#` and `/`
    /// would end or split the value, so everything else is percent-encoded.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// `base?name=value&…`, leaving out the parameters whose value is nil or empty.
    static func link(_ base: String, _ items: [(name: String, value: String?)]) -> URL? {
        let query = items.compactMap { item -> String? in
            guard let value = item.value, !value.isEmpty else { return nil }
            return "\(item.name)=\(encode(value))"
        }
        return URL(string: query.isEmpty ? base : base + "?" + query.joined(separator: "&"))
    }

    /// Appends `content` to the note `file` (a path in the vault, without ".md") with Obsidian's own link; the note is
    /// made when it isn't there yet.
    static func obsidianNew(vault: String, file: String, content: String) -> URL? {
        link("obsidian://new", [("vault", vault), ("file", file), ("content", content), ("append", "true")])
    }

    /// Appends `content` to today's daily note: needs the Advanced URI plugin.
    static func obsidianDaily(vault: String, content: String) -> URL? {
        link("obsidian://advanced-uri", [("vault", vault), ("daily", "true"), ("data", content), ("mode", "append")])
    }

    /// What goes into the Obsidian note: the picture (already in the vault, by name) and the text found in it.
    static func obsidianEntry(image: String, text: String?) -> String {
        var entry = "\n![[\(image)]]\n"
        if let text, !text.isEmpty { entry += "\n\(text)\n" }
        return entry
    }

    /// A vault is named after its folder.
    static func vaultName(path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    /// A new Bear note. `file` is the picture's bytes in base64 (Bear attaches it under `filename`).
    static func bear(title: String, text: String?, file: String?, filename: String?) -> URL? {
        link("bear://x-callback-url/create", [("title", title), ("text", text), ("file", file), ("filename", filename)])
    }

    static func drafts(text: String) -> URL? { link("drafts://x-callback-url/create", [("text", text)]) }

    /// Things refuses notes longer than this.
    static let thingsNotesLimit = 10_000

    static func things(title: String, notes: String?) -> URL? {
        link("things:///add", [("title", title), ("notes", notes.map { String($0.prefix(thingsNotesLimit)) })])
    }

    // MARK: AppleScript (Apple Notes, Reminders)

    /// `text` as an AppleScript string: quotes and backslashes escaped, line breaks as `linefeed`.
    static func literal(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return lines.joined(separator: " & linefeed & ")
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The body of an Apple Notes note: the title as its heading, the picture inline, then the text a line to a paragraph.
    static func noteHTML(title: String, text: String?, imageType: String?, imageBase64: String?) -> String {
        var html = "<div><h1>\(escapeHTML(title))</h1></div>"
        if let imageType, let imageBase64 { html += "<div><img src=\"data:\(imageType);base64,\(imageBase64)\"></div>" }
        if let text, !text.isEmpty {
            for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
                html += line.isEmpty ? "<div><br></div>" : "<div>\(escapeHTML(line))</div>"
            }
        }
        return html
    }

    static func appleNotesScript(html: String) -> String {
        "tell application \"Notes\"\n    make new note with properties {body:\(literal(html))}\nend tell"
    }

    static func remindersScript(title: String, notes: String?) -> String {
        let body = notes.flatMap { $0.isEmpty ? nil : ", body:" + literal($0) } ?? ""
        return "tell application \"Reminders\"\n    make new reminder with properties {name:\(literal(title))\(body)}\nend tell"
    }

    /// The MIME type of a picture file, by its extension.
    static func imageType(of file: URL) -> String { ImageFormat(fileExtension: file.pathExtension) == .jpeg ? "image/jpeg" : "image/png" }
}

/// A notes app as a Send To destination. Each one is a small adapter: a link the app opens, or an AppleScript.
struct NotesDestination: SendDestination {
    let app: NotesApp

    /// The biggest picture handed over inside a link or a script; a larger one goes on the clipboard instead.
    static let maxInlineImageBytes = 1_500_000

    var id: String { "notes.\(app.rawValue)" }
    var title: String { app.title }
    var symbol: String { app.symbol }
    var acceptsRecordings: Bool { false }
    var isAvailable: Bool { app.isInstalled && !Preferences.sendToHidden.contains(id) }
    /// Drafts, Things and Reminders hold only text, so the text is their whole point; the others follow Settings.
    var wantsText: Bool { !app.takesImage || Preferences.sendToIncludeText }

    func send(file: URL, text: String?, app sourceApp: String?) async throws -> SendResult {
        switch app {
        case .obsidian: return try sendToObsidian(file: file, text: text)
        case .bear: return try sendToBear(file: file, text: text)
        case .drafts: return try sendToDrafts(file: file, text: text)
        case .things: return try sendToThings(file: file, text: text)
        case .appleNotes: return try sendToAppleNotes(file: file, text: text)
        case .reminders: return try sendToReminders(file: file, text: text)
        }
    }

    private func name(_ file: URL) -> String { file.deletingPathExtension().lastPathComponent }

    private func open(_ url: URL?) throws {
        guard let url, NSWorkspace.shared.open(url) else { throw SendError("\(app.title) didn't open the link.") }
    }

    /// For apps that can't take a picture: it is on the clipboard, ready to paste.
    private func copyImage(_ file: URL) -> Bool {
        guard let image = NSImage(contentsOf: file) else { return false }
        Output.copy(image)
        return true
    }

    private func done(copied: Bool = false) -> SendResult {
        SendResult(title: "Sent to \(app.title)", detail: copied ? "The picture is on the clipboard: paste it into the note." : nil)
    }

    // MARK: Obsidian

    /// The picture is copied into the vault's Skreener folder (Obsidian can't be handed a file), then a link appends
    /// `![[picture]]` and the text to the note Skreener/Captures, or to today's daily note.
    private func sendToObsidian(file: URL, text: String?) throws -> SendResult {
        let path = Preferences.obsidianVaultPath
        guard !path.isEmpty else { throw SendError("Choose your vault folder in Settings → Send To.") }
        let vault = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: vault.path) else {
            throw SendError("The vault folder isn't there any more: choose it again in Settings → Send To.")
        }
        let folder = vault.appendingPathComponent("Skreener", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = Output.uniqueURL(in: folder, name: name(file), ext: file.pathExtension)
        try FileManager.default.copyItem(at: file, to: copy)

        let content = NoteLinks.obsidianEntry(image: copy.lastPathComponent, text: text)
        let vaultName = NoteLinks.vaultName(path: path)
        try open(Preferences.obsidianDailyNote
                 ? NoteLinks.obsidianDaily(vault: vaultName, content: content)
                 : NoteLinks.obsidianNew(vault: vaultName, file: "Skreener/Captures", content: content))
        return done()
    }

    // MARK: Bear

    private func sendToBear(file: URL, text: String?) throws -> SendResult {
        let data = try Data(contentsOf: file)
        let inline = data.count <= Self.maxInlineImageBytes
        try open(NoteLinks.bear(title: name(file), text: text,
                                file: inline ? data.base64EncodedString() : nil, filename: inline ? file.lastPathComponent : nil))
        return done(copied: !inline && copyImage(file))
    }

    // MARK: Drafts and Things (text only)

    private func sendToDrafts(file: URL, text: String?) throws -> SendResult {
        try open(NoteLinks.drafts(text: text ?? name(file)))
        return done(copied: copyImage(file))
    }

    private func sendToThings(file: URL, text: String?) throws -> SendResult {
        try open(NoteLinks.things(title: name(file), notes: text))
        return done(copied: copyImage(file))
    }

    // MARK: Apple Notes and Reminders (AppleScript)

    private func runScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else { throw SendError("Couldn't prepare the script for \(app.title).") }
        var failure: NSDictionary?
        script.executeAndReturnError(&failure)
        if let failure {
            throw SendError(failure["NSAppleScriptErrorMessage"] as? String
                            ?? "\(app.title) didn't take it. Allow Skreener to control it in System Settings → Privacy & Security → Automation.")
        }
    }

    private func sendToAppleNotes(file: URL, text: String?) throws -> SendResult {
        let data = try Data(contentsOf: file)
        let inline = data.count <= Self.maxInlineImageBytes
        let html = NoteLinks.noteHTML(title: name(file), text: text, imageType: inline ? NoteLinks.imageType(of: file) : nil,
                                      imageBase64: inline ? data.base64EncodedString() : nil)
        try runScript(NoteLinks.appleNotesScript(html: html))
        return done(copied: !inline && copyImage(file))
    }

    private func sendToReminders(file: URL, text: String?) throws -> SendResult {
        try runScript(NoteLinks.remindersScript(title: name(file), notes: text))
        return done(copied: copyImage(file))
    }
}

enum NotesDestinations {
    /// Every notes destination; `SendTo` lists the ones that are installed and turned on.
    @MainActor static func all() -> [SendDestination] { NotesApp.allCases.map { NotesDestination(app: $0) } }
}
