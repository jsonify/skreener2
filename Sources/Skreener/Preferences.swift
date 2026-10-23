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

    /// The format a file with this extension is in; nil for anything but PNG and JPEG.
    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        default: return nil
        }
    }
}

/// What Esc does in the editor when nothing is selected (#115).
enum EditorEscAction: String, CaseIterable {
    case nothing, copyAndClose, saveAndClose

    var title: String {
        switch self {
        case .nothing: return "Nothing"
        case .copyAndClose: return "Copy and Close"
        case .saveAndClose: return "Save and Close"
        }
    }
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
    /// Keep the area selection on screen after the drag, adjustable, until Return or a double-click captures it (#102).
    static var adjustAreaBeforeCapture: Bool {
        get { d.object(forKey: "adjustAreaBeforeCapture") as? Bool ?? true }
        set { d.set(newValue, forKey: "adjustAreaBeforeCapture") }
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
    /// The editor's Background tool starts from the last background chosen (#124).
    static var lastBackground: Background {
        get { (d.dictionary(forKey: "lastBackground")).map(Background.init(plist:)) ?? Background() }
        set { d.set(newValue.plist, forKey: "lastBackground") }
    }
    /// The editor's last tool and the style for new annotations, so the next editor (also after a relaunch) starts
    /// with them (#139).
    static var editorTool: Tool {
        get {
            // Only toolbar tools (pictures and rulers aren't picked from the toolbar).
            guard let raw = d.object(forKey: "editorTool") as? Int, let t = Tool(rawValue: raw),
                  Tool.shortcuts.values.contains(t) else { return .arrow }
            return t
        }
        set { d.set(newValue.rawValue, forKey: "editorTool") }
    }
    static var editorStyle: Style {
        get { (d.dictionary(forKey: "editorStyle")).map(Style.init(plist:)) ?? Style() }
        set { d.set(newValue.plist, forKey: "editorStyle") }
    }
    /// Boxes being drawn or resized in the editor snap to the edges of what's in the screenshot (#123).
    static var snapToObjects: Bool {
        get { d.object(forKey: "snapToObjects") as? Bool ?? true }
        set { d.set(newValue, forKey: "snapToObjects") }
    }
    /// Fill the area an annotation grows the canvas into with the image's top-left pixel colour instead of white.
    static var matchExtensionColor: Bool {
        get { d.bool(forKey: "matchExtensionColor") }
        set { d.set(newValue, forKey: "matchExtensionColor") }
    }
    /// How the editor's color picker writes colors (#108).
    static var colorFormat: ColorFormat {
        get { d.string(forKey: "colorFormat").flatMap(ColorFormat.init(rawValue:)) ?? .hex }
        set { d.set(newValue.rawValue, forKey: "colorFormat") }
    }
    /// The editor's contrast checker: a WCAG 2 ratio or an APCA Lc (#109).
    static var contrastMethod: Contrast.Method {
        get { d.string(forKey: "contrastMethod").flatMap(Contrast.Method.init(rawValue:)) ?? .wcag }
        set { d.set(newValue.rawValue, forKey: "contrastMethod") }
    }
    /// Run skreener:// links (Raycast, Alfred, Shortcuts, scripts). Off until the user allows it, from Settings or
    /// from the prompt the first link shows.
    static var allowURLScheme: Bool {
        get { d.bool(forKey: "allowURLScheme") }
        set { d.set(newValue, forKey: "allowURLScheme") }
    }
    /// Open each screenshot in the editor.
    static var openEditorAfterCapture: Bool {
        get { d.object(forKey: "openEditorAfterCapture") as? Bool ?? true }
        set { d.set(newValue, forKey: "openEditorAfterCapture") }
    }
    /// How a capture that shows nothing else (no editor, Quick Access or pin) is confirmed (#113).
    static var confirmationStyle: ConfirmationStyle {
        get { d.string(forKey: "confirmationStyle").flatMap(ConfirmationStyle.init(rawValue:)) ?? .hud }
        set { d.set(newValue.rawValue, forKey: "confirmationStyle") }
    }
    /// Capture Text opens the recognized text in a scratch pad to edit before copying, instead of copying it straight
    /// away (#134).
    static var textScratchPad: Bool {
        get { d.object(forKey: "textScratchPad") as? Bool ?? true }
        set { d.set(newValue, forKey: "textScratchPad") }
    }
    /// The editor's dock of open screenshots (#140): hidden with its button or ⌃⌘S, and on the left or right.
    static var editorDockCollapsed: Bool {
        get { d.bool(forKey: "editorDockCollapsed") }
        set { d.set(newValue, forKey: "editorDockCollapsed") }
    }
    static var editorDockOnRight: Bool {
        get { d.bool(forKey: "editorDockOnRight") }
        set { d.set(newValue, forKey: "editorDockOnRight") }
    }
    /// Editor windows and the full-screen capture overlays zoom in when they appear (macOS's own window animation),
    /// also when switching screenshots in the dock. Off by default.
    static var editorWindowZoom: Bool {
        get { d.bool(forKey: "editorWindowZoom") }
        set { d.set(newValue, forKey: "editorWindowZoom") }
    }
    /// The animation those windows use when they come to the front.
    static var windowAnimation: NSWindow.AnimationBehavior { editorWindowZoom ? .default : .none }
    /// Skreener's own sounds (copied, recording saved, cancelled).
    static var playSounds: Bool {
        get { d.object(forKey: "playSounds") as? Bool ?? true }
        set { d.set(newValue, forKey: "playSounds") }
    }
    /// Esc in the editor with nothing selected (#115).
    static var editorEscAction: EditorEscAction {
        get { d.string(forKey: "editorEscAction").flatMap(EditorEscAction.init(rawValue:)) ?? .nothing }
        set { d.set(newValue.rawValue, forKey: "editorEscAction") }
    }
    /// Saving an edited screenshot that was already saved (or opened from a file) writes over that file instead of
    /// making a new one (#118).
    static var saveOverExisting: Bool {
        get { d.object(forKey: "saveOverExisting") as? Bool ?? true }
        set { d.set(newValue, forKey: "saveOverExisting") }
    }
    /// Show a Quick Access preview of each screenshot in the bottom-left corner (as well as the editor, if that opens).
    static var showQuickAccess: Bool {
        get { d.object(forKey: "showQuickAccess") as? Bool ?? true }
        set { d.set(newValue, forKey: "showQuickAccess") }
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
    /// How many captures the history keeps: 25, 100, 500, or 0 for all of them.
    static var historyLimit: Int {
        get { d.object(forKey: "historyLimit") as? Int ?? 100 }
        set { d.set(newValue, forKey: "historyLimit") }
    }
    /// Thumbnail size in the history panel: 0 small, 1 medium, 2 large.
    static var libraryTileSize: Int {
        get { d.object(forKey: "libraryTileSize") as? Int ?? 1 }
        set { d.set(newValue, forKey: "libraryTileSize") }
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
    /// When false, the area around a captured window (rounded corners, shadow, padding) is white instead of transparent.
    static var windowTransparentBackground: Bool {
        get { d.object(forKey: "windowTransparentBackground") as? Bool ?? true }
        set { d.set(newValue, forKey: "windowTransparentBackground") }
    }
    /// The tint over the window under the pointer while picking a window (#129); the system blue until changed.
    static var windowHighlightColor: NSColor {
        get {
            guard let hex = d.string(forKey: "windowHighlightColor"), let v = Int(hex, radix: 16) else { return .systemBlue }
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        set {
            guard let c = newValue.usingColorSpace(.sRGB) else { return }
            let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
            d.set(String(format: "%02lX%02lX%02lX", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent)),
                  forKey: "windowHighlightColor")
        }
    }
    /// Extra space (points) around window captures.
    static var windowPadding: Int {
        get { d.integer(forKey: "windowPadding") }
        set { d.set(newValue, forKey: "windowPadding") }
    }
}
