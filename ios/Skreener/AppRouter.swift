import Photos
import SwiftUI

/// What the Shortcuts actions ask the app's screens to show (#439): the home screen opens the requested screenshot in
/// the editor, as a tap in its inbox does. One instance, shared by `SkreenerApp`, `HomeView` and the intents.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// A screenshot to open in the editor. Each request is new, even for the same screenshot.
    struct Request {
        let id = UUID()
        let asset: PHAsset
    }

    /// Waits here until the home screen takes it, so a request made before the screen exists (the app was launched
    /// for the intent) still opens.
    @Published private(set) var request: Request?

    /// Asks the home screen to open `asset` in the editor, replacing any editor on screen.
    func open(_ asset: PHAsset) {
        request = Request(asset: asset)
    }

    /// The screenshot to open, if any; the request is done once taken.
    func take() -> PHAsset? {
        defer { request = nil }
        return request?.asset
    }
}
