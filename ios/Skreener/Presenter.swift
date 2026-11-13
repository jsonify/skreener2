import Photos
import PhotosUI
import UIKit

/// UIKit sheets the SwiftUI screens show: the system share sheet and the limited-library picker. They are presented
/// from the top view controller, so they also work over the full-screen editor.
@MainActor
enum Presenter {
    /// The view controller on top of the app's window: the last presented one that is not being dismissed, so
    /// something presented from it stays up (presenting on a controller that is going away fails or misplaces it).
    static func top() -> UIViewController? {
        var controller = root()
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    /// The root view controller of the app's window.
    static func root() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow?.rootViewController
    }

    /// No presentation in the window is still coming or going: nothing is being presented or dismissed, no
    /// transition is running, and the system photo picker is gone.
    static var isSettled: Bool {
        guard let root = root() else { return false }
        var controller: UIViewController? = root
        while let current = controller {
            if current.isBeingPresented || current.isBeingDismissed || current.transitionCoordinator != nil
                || current is PHPickerViewController {
                return false
            }
            controller = current.presentedViewController
        }
        return true
    }

    /// Waits, up to `limit` seconds, until `isSettled`. The system photo picker (`PhotosPicker`) runs out of process
    /// and goes away a moment after its pick arrives: a full-screen controller presented during that dismissal was
    /// laid out without the safe area on a real iPhone (#440), its keys under the Dynamic Island and on the home
    /// indicator.
    static func waitUntilSettled(limit: Double = 1.5) async {
        var waited = 0.0
        while !isSettled, waited < limit {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 0.05
        }
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
