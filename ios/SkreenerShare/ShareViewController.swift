import Combine
import SkreenerEditor
import SwiftUI
import UIKit

/// The extension's principal class (named in Info.plist). It loads the shared image and hosts the SwiftUI view.
final class ShareViewController: UIViewController {
    private let model = ShareModel()
    private var modeWatch: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(model: model,
                             onClose: { [weak self] in self?.close() },
                             onShare: { [weak self] url in self?.share(url) })
        let host = UIHostingController(rootView: root)
        addChild(host)
        // Edge to edge: the editor fills the sheet with its chassis and keeps its keys inside the sheet's safe area.
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        // In Redact and Draw a downward drag on the preview covers an area or draws; it must not pull the sheet down.
        // Close still works.
        modeWatch = model.$mode.sink { [weak self] mode in self?.isModalInPresentation = mode != .style }

        model.load(items: extensionContext?.inputItems as? [NSExtensionItem] ?? [])
    }

    /// Ends the request. After a save this is not a cancel, so it completes normally.
    private func close() {
        extensionContext?.completeRequest(returningItems: [])
    }

    /// Presents the system share sheet for the PNG file, and removes the file when it is dismissed.
    private func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY,
                                                                 width: 0, height: 0)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        present(sheet, animated: true)
    }
}
