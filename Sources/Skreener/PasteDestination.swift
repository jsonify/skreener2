import Foundation

/// Where a Capture Text copy is being pasted (#327): the app in front, and for browsers the site, read from the end of
/// the front window's title ("… · GitHub", "… - Google Docs"). Each destination gets clean text or Markdown as the
/// copy's plain text: the user's remembered choice, else a built-in rule, else clean text.
struct PasteDestination: Equatable {
    /// What the plain text of a Capture Text copy is.
    enum Choice: String, CaseIterable {
        case clean, markdown

        var title: String { self == .clean ? "Clean text" : "Markdown" }
        /// For the banner: "Pasted clean text into …".
        var phrase: String { self == .clean ? "clean text" : "Markdown" }
        var other: Choice { self == .clean ? .markdown : .clean }
    }

    let bundleID: String
    let appName: String
    /// The site, for browsers whose window title ends in one; nil for every other app.
    let site: String?

    /// Browsers by bundle ID (the ones `SourcePage` asks, and Firefox), with the short name the banner shows.
    static let browsers: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari",
        "com.google.Chrome": "Chrome",
        "com.google.Chrome.beta": "Chrome",
        "com.google.Chrome.canary": "Chrome",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
    ]

    /// Apps that read Markdown: code editors, Markdown notes and terminals.
    static let markdownApps: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.apple.dt.Xcode",
        "md.obsidian",
        "com.apple.Terminal", "com.googlecode.iterm2",
        "dev.zed.Zed", "dev.zed.Zed-Preview",
        "com.sublimetext.4", "com.sublimetext.3",
    ]

    /// Sites (lowercased, as `site(fromTitle:)` gives them) that read Markdown in any browser.
    static let markdownSites: Set<String> = ["github"]

    init(bundleID: String, appName: String, windowTitle: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        site = Self.browsers[bundleID] != nil ? windowTitle.flatMap(Self.site(fromTitle:)) : nil
    }

    /// The remembered choices' key: the bundle ID, plus "|" and the lowercased site for a browser on a site.
    var key: String {
        guard let site else { return bundleID }
        return bundleID + "|" + site.lowercased()
    }

    /// "Chrome · GitHub", "Chrome", or the app's name.
    var displayName: String {
        guard let browser = Self.browsers[bundleID] else { return appName }
        return site.map { browser + " · " + $0 } ?? browser
    }

    /// The built-in rule: Markdown for GitHub and the apps in `markdownApps`; nil (clean text) for everything else.
    var builtInChoice: Choice? {
        if Self.markdownApps.contains(bundleID) { return .markdown }
        if let site, Self.markdownSites.contains(site.lowercased()) { return .markdown }
        return nil
    }

    /// The choice for this destination: `remembered` (key → "clean" / "markdown"), else the built-in rule, else clean.
    func choice(remembered: [String: String]) -> Choice {
        remembered[key].flatMap(Choice.init(rawValue:)) ?? builtInChoice ?? .clean
    }

    /// Whether the banner shows for this paste: only when no choice is remembered here and it hasn't been shown for
    /// this destination before.
    func showsBanner(remembered: [String: String], shown: Set<String>) -> Bool {
        remembered[key] == nil && !shown.contains(key)
    }

    /// The separators between a page's title and its site at the end of a window title.
    private static let separators = [" · ", " - ", " – ", " — "]

    /// The site at the end of a browser window's title: the last segment after " · ", " - ", " – " or " — ", with a
    /// trailing browser name ("… - Google Chrome") left out. Nil when there is no such segment, or it's too long or
    /// has no letters to be a site's name.
    static func site(fromTitle title: String) -> String? {
        var rest = title.replacingOccurrences(of: "\u{200B}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        var segment: String?
        repeat {
            guard let cut = separators.compactMap({ rest.range(of: $0, options: .backwards) })
                .max(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
            segment = rest[cut.upperBound...].trimmingCharacters(in: .whitespaces)
            rest = String(rest[..<cut.lowerBound])
        } while segment.map(isBrowserName) == true
        guard let segment, !segment.isEmpty, segment.count <= 40, segment.contains(where: \.isLetter) else { return nil }
        return segment
    }

    /// Names browsers add to the end of their window titles.
    private static let browserNames: Set<String> = [
        "safari", "google chrome", "chrome", "arc", "microsoft edge", "edge", "brave", "mozilla firefox", "firefox",
    ]

    private static func isBrowserName(_ segment: String) -> Bool { browserNames.contains(segment.lowercased()) }
}
