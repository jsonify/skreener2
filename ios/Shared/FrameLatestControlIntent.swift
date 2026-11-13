import AppIntents

/// The action of the Frame Latest control in Control Center and on the Action button (#439). It must run in the app,
/// in the foreground, where `perform()` frames and copies the newest screenshot (ios/Skreener/ShortcutActions.swift):
/// iOS takes a pasteboard write only from the app on screen. The extension only shows the control.
///
/// What didn't work on a phone: a plain `AppIntent` ran in the widget extension and copied nothing; a
/// `LiveActivityIntent` ran in the app but in the background, so the copy was refused, and iOS ignored its
/// `openAppWhenRun`. An `OpenIntent` is how Apple has a control open its app: iOS brings the app up and runs `perform()`
/// there. Its `target` says what to do, with one choice. This file is in both targets, as an `OpenIntent` must be.
struct FrameLatestControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "Frame Latest Screenshot and Copy"
    static let description = IntentDescription("Opens Skreener, frames your newest screenshot with the look you used last and copies it. If Safe Check finds something private on it, Skreener opens it in the editor instead.")
    /// Shortcuts already has Frame Latest Screenshot, which does the same with more choices.
    static let isDiscoverable = false

    @Parameter(title: "Action", default: .frameLatest)
    var target: ControlAction

    init() {}
}

/// What the control asks the app to do: an `OpenIntent` needs a target.
enum ControlAction: String, AppEnum {
    case frameLatest

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Skreener action"
    static let caseDisplayRepresentations: [ControlAction: DisplayRepresentation] = [
        .frameLatest: "Frame Latest Screenshot and Copy",
    ]
}
