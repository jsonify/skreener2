import AppIntents
import Photos
import SkreenerEditor
import UniformTypeIdentifiers

// The Shortcuts actions (#439): Siri, Spotlight, the Shortcuts app and Back Tap run them. They read the newest
// screenshot only with the access Skreener already has: they never show the Photos permission prompt.

/// Opens the newest screenshot in the editor, as the home screen's Latest screenshot key does.
struct OpenLatestScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Latest Screenshot in Skreener"
    static let description = IntentDescription("Opens Skreener with your newest screenshot in the editor.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let asset = try LatestScreenshot.asset()
        AppRouter.shared.open(asset)
        return .result()
    }
}

/// Frames the newest screenshot in the last look without opening the app, checks it with Safe Check and returns the
/// PNG, so it chains in Shortcuts. If Safe Check finds anything, nothing is handed on: the editor opens on it instead.
struct FrameLatestScreenshotIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Frame Latest Screenshot"
    static let description = IntentDescription("Frames your newest screenshot with the look you used last in Skreener and returns it as a PNG. If Safe Check finds something private on it, Skreener opens it in the editor instead.")
    static let openAppWhenRun = false

    @Parameter(title: "Then", default: .copy)
    var then: FrameThen

    static var parameterSummary: some ParameterSummary {
        Summary("Frame latest screenshot, then \(\.$then)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let png = try await FrameLatest.run(then: then) { text in
            try await requestToContinueInForeground(FrameLatest.dialog(text))
        }
        return .result(value: IntentFile(data: png, filename: "Skreener.png", type: .png))
    }
}

/// What Frame Latest Screenshot does: frame the newest screenshot in the last look, gated by Safe Check.
@MainActor
enum FrameLatest {
    /// Frames the newest screenshot, does `then` with it and returns the PNG. `continueInForeground` asks to bring
    /// Skreener to the front with that question (the calling intent's `requestToContinueInForeground`).
    static func run(then: FrameThen, continueInForeground: (String) async throws -> Void) async throws -> Data {
        let (asset, source) = try await latest()

        // The Safe Check gate: anything found goes to the editor, where the findings show as they do on any open.
        let found = await QuickFrame.findings(in: source)
        if found > 0 {
            try await continueInForeground(ShortcutError.gateQuestion(found))
            AppRouter.shared.open(asset)
            throw ShortcutError.safeCheck(found)
        }

        guard let png = try? await QuickFrame.png(source) else { throw ShortcutError.couldNotRender }
        switch then {
        case .copy:
            QuickFrame.copy(png)
        case .save:
            do {
                try await QuickFrame.save(png)
            } catch {
                throw ShortcutError.couldNotSave
            }
        case .share:
            try await continueInForeground("Open Skreener to share the framed screenshot?")
            let url = try QuickFrame.shareFile(png)
            await Presenter.shareWhenActive(url)
        case .nothing:
            break
        }
        return png
    }

    /// The newest screenshot and its bytes.
    private static func latest() async throws -> (PHAsset, ImageSource) {
        let asset = try LatestScreenshot.asset()
        guard let data = try? await ScreenshotLibrary.imageData(for: asset) else {
            throw ShortcutError.couldNotRead
        }
        return (asset, .data(data))
    }

    static func dialog(_ text: String) -> IntentDialog {
        IntentDialog(LocalizedStringResource(stringLiteral: text))
    }
}

/// What Frame Latest Screenshot does with the framed PNG, besides returning it.
enum FrameThen: String, AppEnum {
    case copy, save, share, nothing

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Then"
    static let caseDisplayRepresentations: [FrameThen: DisplayRepresentation] = [
        .copy: "Copy",
        .save: "Save to Photos",
        .share: "Share",
        .nothing: "Nothing",
    ]
}

/// Siri phrases and Spotlight entries for both actions, with no setup.
struct SkreenerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FrameLatestScreenshotIntent(),
                    phrases: [
                        "Frame my latest screenshot with \(.applicationName)",
                        "Frame my last screenshot with \(.applicationName)",
                        "\(.applicationName) frame latest screenshot",
                    ],
                    shortTitle: "Frame Latest Screenshot",
                    systemImageName: "iphone.gen3")
        AppShortcut(intent: OpenLatestScreenshotIntent(),
                    phrases: [
                        "Open my latest screenshot in \(.applicationName)",
                        "Edit my latest screenshot in \(.applicationName)",
                    ],
                    shortTitle: "Open Latest Screenshot",
                    systemImageName: "photo.on.rectangle")
    }
}

/// The newest screenshot for an action, with the access Skreener already has.
@MainActor
enum LatestScreenshot {
    static func asset() throws -> PHAsset {
        switch ScreenshotLibrary.currentAccess {
        case .notAsked:
            throw ShortcutError.notAsked
        case .denied:
            throw ShortcutError.denied
        case .limited:
            guard let asset = ScreenshotLibrary.newestScreenshot() else { throw ShortcutError.noneSelected }
            return asset
        case .full:
            guard let asset = ScreenshotLibrary.newestScreenshot() else { throw ShortcutError.noScreenshots }
            return asset
        }
    }
}

/// Why an action stopped, in words Shortcuts and Siri show.
enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case notAsked, denied, noneSelected, noScreenshots
    case couldNotRead, couldNotRender, couldNotSave
    /// Safe Check found this many things: the editor opened instead.
    case safeCheck(Int)

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: message)
    }

    var message: String {
        switch self {
        case .notAsked:
            return "Open Skreener and tap Show my screenshots to let it see your screenshots."
        case .denied:
            return "Skreener can't see your screenshots. Allow it in Settings > Privacy & Security > Photos."
        case .noneSelected:
            return "Skreener sees none of your screenshots. Open Skreener and tap Select more to choose them."
        case .noScreenshots:
            return "There are no screenshots yet."
        case .couldNotRead:
            return "Skreener could not read the latest screenshot."
        case .couldNotRender:
            return "Skreener could not frame the latest screenshot."
        case .couldNotSave:
            return "Skreener could not save to Photos. In Settings > Privacy & Security > Photos, allow "
                + "\u{201C}Add Photos Only\u{201D} for Skreener."
        case .safeCheck(let n):
            return "Safe Check found \(Self.things(n)) to cover, so nothing was handed on. Cover \(n == 1 ? "it" : "them") "
                + "in Skreener's editor."
        }
    }

    /// The gate's question before the editor opens.
    static func gateQuestion(_ n: Int) -> String {
        "Safe Check found \(things(n)) to cover. Open in Skreener?"
    }

    private static func things(_ n: Int) -> String {
        n == 1 ? "1 thing" : "\(n) things"
    }
}
