import SwiftUI
import UIKit

/// The extension's principal class (named in Info.plist). It loads the shared image and hosts the SwiftUI view.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(model: model,
                             onCancel: { [weak self] in self?.cancel() },
                             onDone: { [weak self] in self?.done() })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { [weak self] in
            do {
                let image = try await ImageLoader.load(from: items)
                self?.model.show(image)
            } catch {
                self?.model.fail()
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: [])
    }
}
