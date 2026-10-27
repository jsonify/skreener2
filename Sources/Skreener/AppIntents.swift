import AppIntents
import AppKit
import UniformTypeIdentifiers

// Skreener's actions in the Shortcuts app (#274). Unlike skreener:// links they take an image and hand back the
// screenshot or the text, so a shortcut can chain them with other apps. They run the same commands the links run,
// without asking first: the user put them in a shortcut. Shortcuts finds them through Metadata.appintents, which
// Scripts/build_app.sh generates (SwiftPM doesn't).

struct CaptureAreaIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Area"
    static let description = IntentDescription("Drag over part of the screen (or press Space to pick a window) and get the screenshot as an image file.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try ShortcutImages.file(try await ShortcutCapture.run(.captureArea)))
    }
}

struct CaptureWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Window"
    static let description = IntentDescription("Click a window and get the screenshot as an image file.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try ShortcutImages.file(try await ShortcutCapture.run(.captureWindow)))
    }
}

struct CaptureFullscreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Fullscreen"
    static let description = IntentDescription("Capture the screen under the pointer and get the screenshot as an image file.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        .result(value: try ShortcutImages.file(try await ShortcutCapture.run(.captureFullscreen)))
    }
}

struct CaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Text"
    static let description = IntentDescription("Drag over text on the screen and get what it says.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = await TextRecognizer.recognize(try await ShortcutCapture.run(.captureArea))
        guard !text.isEmpty else { throw ShortcutError.noText }
        return .result(value: text)
    }
}

struct PinImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin Image"
    static let description = IntentDescription("Pin an image on top of other windows.")

    @Parameter(title: "Image", supportedTypeIdentifiers: ["public.image"],
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var file: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("Pin \(\.$file)") }

    @MainActor func perform() async throws -> some IntentResult {
        PinnedScreenshotController.pin(try ShortcutImages.image(file))
        return .result()
    }
}

struct OpenInEditorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Editor"
    static let description = IntentDescription("Open an image in Skreener's editor to annotate it.")

    @Parameter(title: "Image", supportedTypeIdentifiers: ["public.image"],
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var file: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$file) in the editor") }

    @MainActor func perform() async throws -> some IntentResult {
        let name = (file.filename as NSString).deletingPathExtension
        EditorWindowController(image: try ShortcutImages.image(file), title: name.isEmpty ? nil : name).present()
        return .result()
    }
}

struct RecordScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Screen"
    static let description = IntentDescription("Pick an area and record it. While recording, this stops the recording.")

    @MainActor func perform() async throws -> some IntentResult {
        try ShortcutCapture.delegate().runForShortcut(.recordScreen)
        return .result()
    }
}

/// Phrases for Siri and Spotlight that work without building a shortcut first.
struct SkreenerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureAreaIntent(), phrases: ["Capture an area with \(.applicationName)"],
                    shortTitle: "Capture Area", systemImageName: "rectangle.dashed")
        AppShortcut(intent: CaptureWindowIntent(), phrases: ["Capture a window with \(.applicationName)"],
                    shortTitle: "Capture Window", systemImageName: "macwindow")
        AppShortcut(intent: CaptureFullscreenIntent(), phrases: ["Capture the screen with \(.applicationName)"],
                    shortTitle: "Capture Fullscreen", systemImageName: "display")
        AppShortcut(intent: CaptureTextIntent(), phrases: ["Capture text with \(.applicationName)"],
                    shortTitle: "Capture Text", systemImageName: "text.viewfinder")
        AppShortcut(intent: RecordScreenIntent(), phrases: ["Record the screen with \(.applicationName)"],
                    shortTitle: "Record Screen", systemImageName: "record.circle")
    }
}

enum ShortcutError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notRunning, busy, cancelled, noText, notAnImage

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: return "Skreener isn't ready yet. Try again."
        case .busy: return "Skreener is already capturing. Finish or cancel that first."
        case .cancelled: return "No screenshot was taken."
        case .noText: return "Skreener couldn't find any text in the area."
        case .notAnImage: return "The input isn't an image Skreener can open."
        }
    }
}

/// The captures behind the actions, through the app delegate.
@MainActor enum ShortcutCapture {
    static func delegate() throws -> AppDelegate {
        guard let d = NSApp.delegate as? AppDelegate else { throw ShortcutError.notRunning }
        return d
    }

    static func run(_ action: HotKeyAction) async throws -> NSImage {
        try await delegate().captureForShortcut(action)
    }
}

/// Images in and out of Shortcuts: a capture goes out as a file in the format chosen in Settings (PNG or JPEG),
/// named like a saved screenshot.
enum ShortcutImages {
    static func file(_ image: NSImage, format: ImageFormat = Preferences.imageFormat) throws -> IntentFile {
        guard let data = Output.fileData(image, format: format) else { throw ShortcutError.cancelled }
        return IntentFile(data: data, filename: Output.filename() + "." + format.fileExtension, type: format.contentType)
    }

    static func image(_ file: IntentFile) throws -> NSImage {
        guard let image = NSImage(data: file.data), image.isValid, image.size.width > 0 else { throw ShortcutError.notAnImage }
        return image
    }
}
