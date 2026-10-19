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
    /// Show a still frame of the screen while picking an area, and capture from that frame.
    static var freezeScreen: Bool {
        get { d.bool(forKey: "freezeScreen") }
        set { d.set(newValue, forKey: "freezeScreen") }
    }
    /// Hide Finder desktop icons for the duration of each capture.
    static var hideIconsWhileCapturing: Bool {
        get { d.bool(forKey: "hideIconsWhileCapturing") }
        set { d.set(newValue, forKey: "hideIconsWhileCapturing") }
    }
    static var windowShadow: Bool {
        get { d.object(forKey: "windowShadow") as? Bool ?? true }
        set { d.set(newValue, forKey: "windowShadow") }
    }
    /// When false, window captures get a solid white background instead of transparency.
    static var windowTransparentBackground: Bool {
        get { d.object(forKey: "windowTransparentBackground") as? Bool ?? true }
        set { d.set(newValue, forKey: "windowTransparentBackground") }
    }
    /// Extra space (points) around window captures.
    static var windowPadding: Int {
        get { d.integer(forKey: "windowPadding") }
        set { d.set(newValue, forKey: "windowPadding") }
    }
}
