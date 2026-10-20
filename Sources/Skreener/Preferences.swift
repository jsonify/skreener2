import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted by the Settings window when an option that affects open windows changes.
    static let skreenerPreferencesChanged = Notification.Name("SkreenerPreferencesChanged")
}

/// File format for saved screenshots (the capture history always keeps PNG).
enum ImageFormat: String {
    case png, jpeg
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: UTType { self == .png ? .png : .jpeg }
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
    static var imageFormat: ImageFormat {
        get { d.string(forKey: "imageFormat").flatMap(ImageFormat.init(rawValue:)) ?? .png }
        set { d.set(newValue.rawValue, forKey: "imageFormat") }
    }
    /// Save Retina captures at 1× (half the pixels each way) instead of full resolution.
    static var downscaleRetina: Bool {
        get { d.bool(forKey: "downscaleRetina") }
        set { d.set(newValue, forKey: "downscaleRetina") }
    }
    static let defaultFilenameTemplate = "Skreener %Y-%m-%d at %H.%M.%S"
    /// Saved file names; see `Output.filename` for the tokens.
    static var filenameTemplate: String {
        get { d.string(forKey: "filenameTemplate").flatMap { $0.isEmpty ? nil : $0 } ?? defaultFilenameTemplate }
        set { d.set(newValue, forKey: "filenameTemplate") }
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
    /// Fill the area an annotation grows the canvas into with the image's top-left pixel colour instead of white.
    static var matchExtensionColor: Bool {
        get { d.bool(forKey: "matchExtensionColor") }
        set { d.set(newValue, forKey: "matchExtensionColor") }
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
    // Recording options (the sliders button on the record panel). Defaults follow CleanShot X.
    /// Show the HUD (time, pause, stop) while recording.
    static var recordShowControls: Bool {
        get { d.object(forKey: "recordShowControls") as? Bool ?? true }
        set { d.set(newValue, forKey: "recordShowControls") }
    }
    /// Start Record Area with the previous recording's area already selected.
    static var recordRememberSelection: Bool {
        get { d.bool(forKey: "recordRememberSelection") }
        set { d.set(newValue, forKey: "recordRememberSelection") }
    }
    static var recordTimeInMenuBar: Bool {
        get { d.bool(forKey: "recordTimeInMenuBar") }
        set { d.set(newValue, forKey: "recordTimeInMenuBar") }
    }
    /// Dim everything outside the recorded area (the dimming is not in the video).
    static var recordDimScreen: Bool {
        get { d.object(forKey: "recordDimScreen") as? Bool ?? true }
        set { d.set(newValue, forKey: "recordDimScreen") }
    }
    /// 3-second countdown before a recording starts.
    static var recordCountdown: Bool {
        get { d.object(forKey: "recordCountdown") as? Bool ?? true }
        set { d.set(newValue, forKey: "recordCountdown") }
    }
    /// Draw a ring at each mouse click, in the video.
    static var recordHighlightClicks: Bool {
        get { d.bool(forKey: "recordHighlightClicks") }
        set { d.set(newValue, forKey: "recordHighlightClicks") }
    }
    /// Index into `ClickStyle.colors`.
    static var clickHighlightColor: Int {
        get { d.integer(forKey: "clickHighlightColor") }
        set { d.set(newValue, forKey: "clickHighlightColor") }
    }
    /// Ring diameter in points (32, 48 or 64).
    static var clickHighlightSize: Int {
        get { [32, 48, 64].contains(d.integer(forKey: "clickHighlightSize")) ? d.integer(forKey: "clickHighlightSize") : 48 }
        set { d.set(newValue, forKey: "clickHighlightSize") }
    }
    /// Show pressed keys in the video (needs Accessibility access).
    static var recordShowKeystrokes: Bool {
        get { d.bool(forKey: "recordShowKeystrokes") }
        set { d.set(newValue, forKey: "recordShowKeystrokes") }
    }
    /// Only show keys pressed with ⌘, ⌃ or ⌥ (shortcuts), not plain typing.
    static var keystrokesOnlyShortcuts: Bool {
        get { d.bool(forKey: "keystrokesOnlyShortcuts") }
        set { d.set(newValue, forKey: "keystrokesOnlyShortcuts") }
    }
    /// Keystroke text size in points (18, 24 or 32).
    static var keystrokeSize: Int {
        get { [18, 24, 32].contains(d.integer(forKey: "keystrokeSize")) ? d.integer(forKey: "keystrokeSize") : 24 }
        set { d.set(newValue, forKey: "keystrokeSize") }
    }
    /// Keystrokes at the top of the recorded area instead of the bottom.
    static var keystrokesAtTop: Bool {
        get { d.bool(forKey: "keystrokesAtTop") }
        set { d.set(newValue, forKey: "keystrokesAtTop") }
    }
    /// The last recorded area (global coordinates), for `recordRememberSelection`.
    static var lastRecordRect: CGRect? {
        get { d.string(forKey: "lastRecordRect").map(NSRectFromString).flatMap { $0.isEmpty ? nil : $0 } }
        set { d.set(newValue.map(NSStringFromRect), forKey: "lastRecordRect") }
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
