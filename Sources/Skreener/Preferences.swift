import AppKit

enum Preferences {
    private static let d = UserDefaults.standard

    static var saveDirectory: URL {
        get {
            if let p = d.string(forKey: "saveDirectory") { return URL(fileURLWithPath: p) }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { d.set(newValue.path, forKey: "saveDirectory") }
    }
    static var copyToClipboard: Bool {
        get { d.object(forKey: "copyToClipboard") as? Bool ?? true }
        set { d.set(newValue, forKey: "copyToClipboard") }
    }
    static var autoSave: Bool {
        get { d.object(forKey: "autoSave") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoSave") }
    }
    static var showCursor: Bool {
        get { d.bool(forKey: "showCursor") }
        set { d.set(newValue, forKey: "showCursor") }
    }
}
