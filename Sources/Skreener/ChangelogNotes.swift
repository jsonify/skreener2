import Foundation

/// One heading of a release's notes ("Features", "Bug Fixes") with its cleaned-up bullets.
struct ChangelogGroup: Equatable {
    let title: String
    let items: [String]
}

/// Reads one version's section out of CHANGELOG.md (release-please's format: `## [0.14.0](compare link) (date)`,
/// `### Features` headings, `* **scope:** text ([#12](link)) ([abc1234](commit link))` bullets) for What's New (#302).
enum ChangelogNotes {
    /// The groups of `version`'s section, or nil when the changelog has no such section (or no bullets in it).
    static func groups(for version: String, in changelog: String) -> [ChangelogGroup]? {
        var inSection = false
        var title: String?
        var items: [String] = []
        var result: [ChangelogGroup] = []

        func flush() {
            if let t = title, !items.isEmpty { result.append(ChangelogGroup(title: t, items: items)) }
            items = []
        }

        for raw in changelog.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = sectionVersion(line) == version
                title = nil
                continue
            }
            guard inSection else { continue }
            if line.hasPrefix("### ") {
                flush()
                title = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("* ") || line.hasPrefix("- ") {
                let text = clean(String(line.dropFirst(2)))
                if title == nil { title = "Changes" }
                if !text.isEmpty, !items.contains(text) { items.append(text) }
            }
        }
        flush()
        return result.isEmpty ? nil : result
    }

    /// "## [0.14.0](https://…) (2026-10-27)" or "## 0.14.0 (date)" gives "0.14.0".
    static func sectionVersion(_ heading: String) -> String? {
        var s = heading.drop(while: { $0 == "#" || $0 == " " })
        if s.hasPrefix("[") { s = s.dropFirst() }
        let v = s.prefix(while: { $0.isNumber || $0 == "." })
        return v.isEmpty ? nil : String(v)
    }

    /// Drops the trailing "([#296](link)) ([d2531c0](link))" references and "(#296)", turns the remaining links into
    /// their text and "**capture:**" into "Capture:".
    static func clean(_ bullet: String) -> String {
        var s = bullet
        s = s.replacingOccurrences(of: #"\s*\(\[[^\]]*\]\([^)]*\)\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\((#\d+|[0-9a-f]{7,40})\)"#, with: "", options: .regularExpression)
        if let r = s.range(of: #"^\*\*[^*]+:\*\*\s*"#, options: .regularExpression) {
            let scope = s[r].dropFirst(2).prefix(while: { $0 != ":" && $0 != "*" })
            let name = String(scope)
            let rest = String(s[r.upperBound...])
            s = name.prefix(1).uppercased() + String(name.dropFirst()) + ": " + rest
        }
        return s.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// The marketing version ("0.14.0") from the Info.plist, or nil for a dev build whose version isn't X.Y.Z.
    static func releaseVersion(_ info: [String: Any]?) -> String? {
        guard let short = info?["CFBundleShortVersionString"] as? String, isReleaseVersion(short) else { return nil }
        return short
    }

    static func isReleaseVersion(_ v: String) -> Bool {
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    static func releaseURL(for version: String) -> URL? {
        URL(string: "https://github.com/jsonify/skreener2/releases/tag/v\(version)")
    }
}

/// What to show after launch, decided from the version stored last time (#302).
enum LaunchHelp: Equatable {
    case nothing, welcome, whatsNew

    static let storageKey = "lastSeenVersion"

    /// - `stored`: `lastSeenVersion` from UserDefaults.
    /// - `current`: the running marketing version (CFBundleShortVersionString, "dev" without an Info.plist).
    /// - `hasEarlierUse`: see `hasEarlierUse(defaults:historyHasFiles:)`.
    static func decide(stored: String?, current: String, hasEarlierUse: Bool) -> LaunchHelp {
        if stored == current { return .nothing }
        // A fresh install gets the Welcome Guide, dev build or not.
        if stored == nil && !hasEarlierUse { return .welcome }
        // A dev build ("dev", "0.0.0-abc") never pops What's New.
        return ChangelogNotes.isReleaseVersion(current) ? .whatsNew : .nothing
    }

    /// Whether Skreener ran on this Mac before: an install from before this feature has no `lastSeenVersion`, but it
    /// has captures in the history folder or settings the user changed (a rebound "shortcut.*", a window frame AppKit
    /// saved). Other keys are ignored on purpose: Skreener and AppKit write some by themselves on a first launch, so
    /// counting them would mistake a brand-new install for an old one.
    static func hasEarlierUse(defaults: UserDefaults, historyHasFiles: Bool) -> Bool {
        if historyHasFiles { return true }
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        return domain.keys.contains { $0.hasPrefix("shortcut.") || $0.hasPrefix("NSWindow Frame") }
    }

    /// True when the history folder holds at least one capture. Doesn't create the folder.
    static func historyHasFiles() -> Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Skreener/History", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.contains { !$0.hasPrefix(".") }
    }
}
