import AppKit

extension Notification.Name {
    /// Posted by the Settings window when an option that affects open windows changes.
    static let skreenerPreferencesChanged = Notification.Name("SkreenerPreferencesChanged")
}

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
    /// Subtle drop shadow under annotations (shapes, arrows, pen, text), in the editor and in exports.
    static var annotationShadow: Bool {
        get { d.object(forKey: "annotationShadow") as? Bool ?? true }
        set { d.set(newValue, forKey: "annotationShadow") }
    }
    /// Open each screenshot straight in the editor instead of the Quick Access thumbnail.
    static var openEditorAfterCapture: Bool {
        get { d.object(forKey: "openEditorAfterCapture") as? Bool ?? true }
        set { d.set(newValue, forKey: "openEditorAfterCapture") }
    }
    /// Open each new editor as a tab of the editor window that is already open, instead of its own window.
    static var editorTabs: Bool {
        get { d.object(forKey: "editorTabs") as? Bool ?? true }
        set { d.set(newValue, forKey: "editorTabs") }
    }
    /// Self-timer countdown in seconds (3, 5 or 10).
    static var selfTimerSeconds: Int {
        get { [3, 5, 10].contains(d.integer(forKey: "selfTimerSeconds")) ? d.integer(forKey: "selfTimerSeconds") : 5 }
        set { d.set(newValue, forKey: "selfTimerSeconds") }
    }
    /// Keep every capture in the Capture History panel.
    static var keepHistory: Bool {
        get { d.object(forKey: "keepHistory") as? Bool ?? true }
        set { d.set(newValue, forKey: "keepHistory") }
    }
    /// Screen recordings: include system audio (other apps' sound).
    static var recordSystemAudio: Bool {
        get { d.bool(forKey: "recordSystemAudio") }
        set { d.set(newValue, forKey: "recordSystemAudio") }
    }
    /// Screen recordings: include the microphone (macOS 15 or later).
    static var recordMicrophone: Bool {
        get { d.bool(forKey: "recordMicrophone") }
        set { d.set(newValue, forKey: "recordMicrophone") }
    }
    static var recordShowsCursor: Bool {
        get { d.object(forKey: "recordShowsCursor") as? Bool ?? true }
        set { d.set(newValue, forKey: "recordShowsCursor") }
    }
    /// Screen recordings: frames per second (30 or 60).
    static var recordFrameRate: Int {
        get { d.integer(forKey: "recordFrameRate") == 60 ? 60 : 30 }
        set { d.set(newValue, forKey: "recordFrameRate") }
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
