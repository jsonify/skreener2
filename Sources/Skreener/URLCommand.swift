import Foundation

/// What happens to a capture afterwards. Settings → After Capture gives the usual set; a skreener:// link can pick
/// its own with `then=`.
struct CaptureActions: OptionSet, Hashable {
    let rawValue: Int
    static let copy = CaptureActions(rawValue: 1 << 0)
    static let save = CaptureActions(rawValue: 1 << 1)
    static let edit = CaptureActions(rawValue: 1 << 2)
    static let pin = CaptureActions(rawValue: 1 << 3)
    static let quickAccess = CaptureActions(rawValue: 1 << 4)

    /// Names for `then=`, in the order error messages list them.
    static let names: [(name: String, action: CaptureActions)] = [
        ("copy", .copy), ("save", .save), ("edit", .edit), ("pin", .pin), ("quickaccess", .quickAccess),
    ]

    /// Settings → After Capture.
    static var fromPreferences: CaptureActions {
        var a: CaptureActions = []
        if Preferences.copyToClipboard { a.insert(.copy) }
        if Preferences.autoSave { a.insert(.save) }
        if Preferences.openEditorAfterCapture { a.insert(.edit) }
        if Preferences.showQuickAccess { a.insert(.quickAccess) }
        return a
    }
}

/// A skreener:// link, for Raycast, Alfred, Shortcuts and scripts: `skreener://grab/area?then=copy,save`,
/// `skreener://grab/delayed/window?delay=10`, `skreener://settings`. `capture/…` works as well as `grab/…`.
struct URLCommand: Equatable {
    enum Command: Equatable {
        case run(HotKeyAction)
        case settings
    }

    var command: Command
    /// After-capture steps for this capture only (nil: Settings → After Capture).
    var then: CaptureActions?
    /// Self-timer seconds for this capture only (nil: the Self-Timer menu's delay).
    var delay: Int?

    static let scheme = "skreener"
    static let delayRange = 1...60

    /// Every command, as written after `skreener://`.
    static let commands: [(path: String, command: Command)] = [
        ("grab/area", .run(.captureArea)),
        ("grab/previous", .run(.capturePreviousArea)),
        ("grab/fullscreen", .run(.captureFullscreen)),
        ("grab/window", .run(.captureWindow)),
        ("grab/window/active", .run(.captureActiveWindow)),
        ("grab/scrolling", .run(.captureScrolling)),
        ("grab/delayed", .run(.timedArea)),
        ("grab/delayed/area", .run(.timedArea)),
        ("grab/delayed/window", .run(.timedWindow)),
        ("grab/delayed/fullscreen", .run(.timedFullscreen)),
        ("ocr", .run(.captureText)),
        ("ocr/code", .run(.captureCode)),
        ("record", .run(.recordScreen)),
        ("load/clipboard", .run(.openClipboard)),
        ("load/file", .run(.openFile)),
        ("pin/clipboard", .run(.pinClipboard)),
        ("pin/file", .run(.pinFile)),
        ("pin/live", .run(.captureAreaAndLivePin)),
        ("pin/live/window", .run(.livePinWindow)),
        ("history", .run(.showHistory)),
        ("settings", .settings),
    ]

    /// Commands whose screenshot goes through the after-capture steps, so `then=` applies.
    private static let takesThen: Set<HotKeyAction> = [.captureArea, .capturePreviousArea, .captureFullscreen,
                                                        .captureWindow, .captureActiveWindow, .captureScrolling,
                                                        .timedArea, .timedWindow, .timedFullscreen]
    private static let takesDelay: Set<HotKeyAction> = [.timedArea, .timedWindow, .timedFullscreen]

    /// What the command does, for alerts.
    var title: String {
        switch command {
        case .run(let action): return action.title
        case .settings: return "Settings"
        }
    }

    static func parse(_ url: URL) -> Result<URLCommand, URLCommandError> {
        guard url.scheme?.lowercased() == scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(.wrongScheme) }
        // skreener://grab/area has host "grab" and path "/area"; skreener:grab/area has only a path.
        let segments = ([parts.host ?? ""] + parts.path.split(separator: "/").map(String.init))
            .map { $0.lowercased() }.filter { !$0.isEmpty }
        var path = segments.joined(separator: "/")
        if path.hasPrefix("capture/") { path = "grab/" + path.dropFirst("capture/".count) }
        guard let command = commands.first(where: { $0.path == path })?.command else {
            return .failure(.unknownCommand(path))
        }
        var result = URLCommand(command: command)
        var action: HotKeyAction?
        if case .run(let a) = command { action = a }
        for item in parts.queryItems ?? [] {
            let value = item.value ?? ""
            switch item.name.lowercased() {
            case "then":
                guard let action, takesThen.contains(action) else { return .failure(.thenNotAllowed(path)) }
                var then: CaptureActions = []
                for name in value.lowercased().split(separator: ",", omittingEmptySubsequences: false) {
                    let name = name.trimmingCharacters(in: .whitespaces)
                    guard let a = CaptureActions.names.first(where: { $0.name == name })?.action else {
                        return .failure(.badThen(String(name)))
                    }
                    then.insert(a)
                }
                result.then = then
            case "delay":
                guard let action, takesDelay.contains(action) else { return .failure(.delayNotAllowed(path)) }
                guard let s = Int(value), delayRange.contains(s) else { return .failure(.badDelay(value)) }
                result.delay = s
            default:
                return .failure(.unknownParameter(item.name))
            }
        }
        return .success(result)
    }
}

enum URLCommandError: Error, Equatable {
    case wrongScheme
    case unknownCommand(String)
    case unknownParameter(String)
    case thenNotAllowed(String)
    case badThen(String)
    case delayNotAllowed(String)
    case badDelay(String)

    var message: String {
        switch self {
        case .wrongScheme:
            return "Links must start with \(URLCommand.scheme)://."
        case .unknownCommand(let path):
            let list = URLCommand.commands.map(\.path).joined(separator: ", ")
            return "\"\(path)\" is not a command. Available commands: \(list) (capture/… works as well as grab/…)."
        case .unknownParameter(let name):
            return "Unknown parameter \"\(name)\". Available parameters: then (capture commands), delay (grab/delayed)."
        case .thenNotAllowed(let path):
            return "\"\(path)\" does not take a \"then\" parameter; only grab/… commands do."
        case .badThen(let name):
            let list = CaptureActions.names.map { "\"\($0.name)\"" }.joined(separator: ", ")
            return "Unrecognized \"then\" option \"\(name)\". Available options: \(list), or a comma-separated combination."
        case .delayNotAllowed(let path):
            return "\"\(path)\" does not take a \"delay\" parameter; only grab/delayed commands do."
        case .badDelay(let value):
            return "\"\(value)\" is not a valid delay. Use whole seconds from \(URLCommand.delayRange.lowerBound) to \(URLCommand.delayRange.upperBound)."
        }
    }
}
