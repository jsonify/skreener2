import Foundation

/// A rule that files a capture into a folder of its own (#277), by the app it came from or by the text in it, e.g.
/// "Figma → ~/Design/Screens" or "contains Invoice → ~/Receipts". Settings → After Capture edits the list.
struct FilingRule: Codable, Equatable, Identifiable {
    enum Condition: String, Codable, CaseIterable {
        case appIs, textContains

        var title: String { self == .appIs ? "App name is" : "Text contains" }
    }

    var id = UUID()
    var enabled = true
    var condition: Condition = .appIs
    var value = ""
    /// The destination folder's path; empty until chosen.
    var folder = ""

    /// "App name is “Figma”", as the rules list shows it.
    var summary: String { "\(condition.title) “\(value)”" }
}

/// What happens to a capture once it is saved (#277): the filing rules, the Finder tag with the app's name and the
/// text in it for Spotlight. The matching and naming need no screen; the rest touches the file.
enum AutoFiling {
    static let defaultsKey = "filingRules"
    /// The Spotlight comment: Spotlight indexes it and finds the file by any word in it.
    static let commentAttribute = "com.apple.metadata:kMDItemFinderComment"

    enum Decision: Equatable {
        /// No rule matches: the file stays where it was saved.
        case stay
        case move(FilingRule)
        /// A text rule comes before any match, so it can only be told once OCR has read the file.
        case needsText
    }

    static func load(from defaults: UserDefaults = .standard) -> [FilingRule] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([FilingRule].self, from: data)) ?? []
    }

    static func save(_ rules: [FilingRule], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// The first enabled rule with a value and a folder that matches a capture from `app` holding `text` (nil while
    /// it hasn't been read) wins. Both conditions ignore case.
    static func decide(app: String?, text: String?, rules: [FilingRule]) -> Decision {
        let app = app?.trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in rules where rule.enabled && !rule.folder.isEmpty {
            let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            switch rule.condition {
            case .appIs:
                if let app, app.caseInsensitiveCompare(value) == .orderedSame { return .move(rule) }
            case .textContains:
                guard let text else { return .needsText }
                if text.range(of: value, options: .caseInsensitive) != nil { return .move(rule) }
            }
        }
        return .stay
    }

    /// Where `file` goes in `folder`: under its own name, or "name 2", "name 3"… when that is taken.
    static func destination(for file: URL, in folder: URL,
                            exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        Output.uniqueURL(in: folder, name: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension,
                         exists: exists)
    }

    // MARK: Files

    /// Files the rules moved, old place → new place, so a preview or editor still holding the old one finds it. Main thread.
    private static var moves: [String: URL] = [:]

    /// Where a file Skreener saved is now: `url` itself unless a rule moved it. Main thread.
    static func current(_ url: URL) -> URL {
        var url = url
        for _ in 0..<8 { guard let next = moves[url.standardizedFileURL.path] else { break }; url = next }
        return url
    }

    /// Runs once Skreener saved a capture from `app`: tags it, and files it now when the rules don't need its text,
    /// else once the library has read it (which is also when its text goes to Spotlight). Returns where it is now. Main thread.
    @discardableResult
    static func afterSave(_ file: URL, app: String?) -> URL {
        if Preferences.tagWithApp, let app, !app.isEmpty { addTag(app, to: file) }
        let isImage = SavedLibrary.Kind(fileExtension: file.pathExtension) == .image
        var now = file
        var waitForText = false
        switch decide(app: app, text: isImage ? nil : "", rules: Preferences.filingRules) {
        case .move(let rule): now = move(file, by: rule) ?? file
        case .needsText: waitForText = true
        case .stay: break
        }
        guard isImage, waitForText || Preferences.spotlightText else { return now }
        SavedLibrary.shared.whenRead(now) { text in
            let file = current(now)
            if Preferences.spotlightText { writeComment(text, to: file) }
            if waitForText, case .move(let rule) = decide(app: app, text: text, rules: Preferences.filingRules) {
                move(file, by: rule)
            }
        }
        return now
    }

    /// Moves `file` into the rule's folder; previews, editors and the library follow it. Returns the new place, or nil
    /// when it stayed (already there, or the move failed). Main thread.
    @discardableResult
    static func move(_ file: URL, by rule: FilingRule) -> URL? {
        do {
            guard let to = try relocate(file, to: rule.folder) else { return nil }
            remember(file, movedTo: to)
            SavedLibrary.shared.moved(from: file, to: to)
            return to
        } catch {
            NSLog("Filing \(file.lastPathComponent) failed: \(error)")
            return nil
        }
    }

    /// Moves `file` into the folder at `path`, made when missing, never over another file. Nil when it is already there.
    static func relocate(_ file: URL, to path: String) throws -> URL? {
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        guard folder.standardizedFileURL.path != file.deletingLastPathComponent().standardizedFileURL.path else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // moveItem refuses to replace a file, so one that appears in between isn't lost either.
        let to = destination(for: file, in: folder)
        try FileManager.default.moveItem(at: file, to: to)
        return to
    }

    static func remember(_ file: URL, movedTo new: URL) { moves[file.standardizedFileURL.path] = new }

    /// Adds a Finder tag (no color), keeping the file's other tags.
    static func addTag(_ tag: String, to file: URL) {
        var tags = (try? file.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        // URLResourceValues.tagNames can't be set; NSURL can.
        do { try (file as NSURL).setResourceValue(tags, forKey: .tagNamesKey) } catch { NSLog("Tagging failed: \(error)") }
    }

    /// The attribute's value: a binary property list holding the text as one string.
    static func commentData(_ text: String) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: text, format: .binary, options: 0)
    }

    /// Sets the file's Spotlight comment to `text`. Best effort: a volume without extended attributes is skipped.
    static func writeComment(_ text: String, to file: URL) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = commentData(text) else { return }
        data.withUnsafeBytes { buffer in
            _ = setxattr(file.path, commentAttribute, buffer.baseAddress, data.count, 0, 0)
        }
    }

    /// The tags and Spotlight comment of a file, which saving over it (an atomic write makes a new file) would lose.
    struct Kept {
        let tags: [String]
        let comment: Data?

        init(of file: URL) {
            tags = (try? file.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
            let size = getxattr(file.path, AutoFiling.commentAttribute, nil, 0, 0, 0)
            guard size > 0 else { comment = nil; return }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = getxattr(file.path, AutoFiling.commentAttribute, &buffer, size, 0, 0)
            comment = read > 0 ? Data(buffer.prefix(read)) : nil
        }

        func restore(to file: URL) {
            if !tags.isEmpty { try? (file as NSURL).setResourceValue(tags, forKey: .tagNamesKey) }
            if let comment {
                comment.withUnsafeBytes { buffer in
                    _ = setxattr(file.path, AutoFiling.commentAttribute, buffer.baseAddress, comment.count, 0, 0)
                }
            }
        }
    }
}
