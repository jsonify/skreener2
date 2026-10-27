import AppKit

/// The web page a browser capture came from (#269): asked of the browser over Apple Events right after the capture,
/// kept with the saved file and in Finder's "Where from" (`kMDItemWhereFroms`). Without the Automation permission the
/// browser just doesn't answer and the capture has no page.
enum SourcePage {
    struct Page: Equatable {
        let url: String
        let title: String?

        /// Only web pages count: a new-tab page, `chrome://` settings or an empty answer give nil.
        init?(url: String, title: String? = nil) {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parts = URLComponents(string: trimmed), let scheme = parts.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", parts.host?.isEmpty == false else { return nil }
            let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.url = trimmed
            self.title = name?.isEmpty == false ? name : nil
        }
    }

    /// How a browser is asked for its front tab.
    private enum Dialect { case safari, chromium }

    private static let dialects: [String: Dialect] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.beta": .chromium,
        "com.google.Chrome.canary": .chromium,
        "company.thebrowser.Browser": .chromium,   // Arc
        "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium,
    ]

    /// The AppleScript that answers "URL, line feed, title" for the front tab of the browser, or nil for any other app.
    /// The timeout keeps a busy or unresponsive browser from holding the lookup for the default two minutes.
    static func script(forBundleID bundleID: String?) -> String? {
        guard let bundleID, let dialect = dialects[bundleID] else { return nil }
        let tab: (url: String, title: String)
        switch dialect {
        case .safari: tab = ("URL of current tab of front window", "name of current tab of front window")
        case .chromium: tab = ("URL of active tab of front window", "title of active tab of front window")
        }
        return """
        with timeout of 3 seconds
            tell application id "\(bundleID)"
                return (\(tab.url)) & linefeed & (\(tab.title))
            end tell
        end timeout
        """
    }

    /// The page in the script's answer ("URL\ntitle"); nil when it isn't a web page.
    static func parse(reply: String?) -> Page? {
        guard let reply else { return nil }
        let lines = reply.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let url = lines.first else { return nil }
        return Page(url: String(url), title: lines.count > 1 ? String(lines[1]) : nil)
    }

    /// The site of a page address without a leading "www.", lowercased; nil when it has no host.
    static func host(of address: String?) -> String? {
        guard let address, let host = URLComponents(string: address)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }

    // MARK: Asking the browser

    private static let queue = DispatchQueue(label: "skreener.sourcepage", qos: .userInitiated)

    /// Asks the browser with `bundleID` for its front tab, off the main thread. Calls back on the main thread, with nil
    /// for any other app, when the setting is off, or when the browser doesn't answer (no Automation permission, no window).
    static func lookup(bundleID: String?, completion: @escaping (Page?) -> Void) {
        guard Preferences.rememberSourcePage, let source = script(forBundleID: bundleID) else {
            completion(nil)
            return
        }
        queue.async {
            var error: NSDictionary?
            let reply = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
            let page = error == nil ? parse(reply: reply) : nil
            DispatchQueue.main.async { completion(page) }
        }
    }

    // MARK: Finder's "Where from"

    static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"

    /// The attribute's value: a binary property list holding the addresses as an array of strings.
    static func whereFromsData(_ addresses: [String]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: addresses, format: .binary, options: 0)
    }

    /// The addresses in an attribute value; empty when it isn't a list of strings.
    static func addresses(inWhereFroms data: Data) -> [String] {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String] ?? []
    }

    /// Sets the file's "Where from" to the page's address. Best effort: a volume without extended attributes is skipped.
    static func writeWhereFroms(_ address: String, to file: URL) {
        guard let data = whereFromsData([address]) else { return }
        data.withUnsafeBytes { buffer in
            _ = setxattr(file.path, whereFromsAttribute, buffer.baseAddress, data.count, 0, 0)
        }
    }

    /// The first address in the file's "Where from", if any.
    static func readWhereFroms(of file: URL) -> String? {
        let size = getxattr(file.path, whereFromsAttribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(file.path, whereFromsAttribute, &buffer, size, 0, 0)
        guard read > 0 else { return nil }
        return addresses(inWhereFroms: Data(buffer.prefix(read))).first
    }
}
