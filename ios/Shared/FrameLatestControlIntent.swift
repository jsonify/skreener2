import AppIntents

/// The action of the Frame Latest control in Control Center and on the Action button (#439). This file is in both
/// the app and the SkreenerControls widget extension, so the system runs the intent in the app, where `perform()`
/// frames and copies the newest screenshot (ios/Skreener/ShortcutActions.swift). The extension only shows the control.
struct FrameLatestControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Frame Latest Screenshot and Copy"
    static let description = IntentDescription("Frames your newest screenshot with the look you used last in Skreener and copies it. If Safe Check finds something private on it, Skreener opens it in the editor instead.")
    static let openAppWhenRun = false
    /// Shortcuts already has Frame Latest Screenshot, which does the same with more choices.
    static let isDiscoverable = false

    init() {}
}
