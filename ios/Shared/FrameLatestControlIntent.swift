import AppIntents

/// The action of the Frame Latest control in Control Center and on the Action button (#439). It must run in the app,
/// where `perform()` frames and copies the newest screenshot (ios/Skreener/ShortcutActions.swift); the extension only
/// shows the control. A control's plain `AppIntent` runs in the widget extension's process, even with its file in the
/// app too: on a phone, the control lit up and copied nothing. iOS runs a `LiveActivityIntent` in the app's process
/// when the app has it, so this is one, though it starts no Live Activity. This file is in both targets.
struct FrameLatestControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Frame Latest Screenshot and Copy"
    static let description = IntentDescription("Frames your newest screenshot with the look you used last in Skreener and copies it. If Safe Check finds something private on it, Skreener opens it in the editor instead.")
    static let openAppWhenRun = false
    /// Shortcuts already has Frame Latest Screenshot, which does the same with more choices.
    static let isDiscoverable = false

    init() {}
}
