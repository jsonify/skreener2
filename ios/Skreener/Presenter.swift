import Photos
import UIKit

/// UIKit sheets the SwiftUI screens show: the system share sheet and the limited-library picker. They are presented
/// from the top view controller, so they also work over the full-screen editor.
@MainActor
enum Presenter {
    /// The view controller on top of the app's window.
    static func top() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    /// Presents the system share sheet for the PNG file, and removes the file when it is dismissed (as the Share
    /// Extension does).
    static func share(_ url: URL) {
        guard let top = top() else {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY,
                                                                 width: 0, height: 0)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        top.present(sheet, animated: true)
    }

    /// Like `share`, for a Shortcuts action that has just brought the app to the front (#439): waits up to two seconds
    /// for the window to be active first, so the sheet has somewhere to show.
    static func shareWhenActive(_ url: URL) async {
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        share(url)
    }

    /// Lets the user change which photos Skreener can see (limited access). A change reaches `ScreenshotLibrary`
    /// through its library observer.
    static func selectMorePhotos() {
        guard let top = top() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
