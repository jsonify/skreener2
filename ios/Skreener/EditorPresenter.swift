import SkreenerEditor
import SwiftUI
import UIKit

/// Shows the app's editor full screen through UIKit (#440), the way the Share Extension hosts it: `ShareView` in a
/// `UIHostingController` pinned edge to edge inside a plain view controller, presented `.fullScreen` from the top view
/// controller. SwiftUI's `fullScreenCover` let the editor's keys slide under the status bar, the Dynamic Island and the
/// home indicator on a real iPhone; UIKit's presentation keeps them inside the safe area, as in the extension.
///
/// `HomeView` stays the source of truth: it calls `show` when it has a new editor session and `dismiss` when the
/// session ends. One editor at a time: showing another replaces the one on screen.
@MainActor
enum EditorPresenter {
    /// The editor on screen, if any.
    private static weak var shown: EditorViewController?

    /// Presents a fresh editor on `model`, replacing any editor on screen (and anything over it, like a share sheet).
    /// `onClose` runs when the editor's Close key is tapped; it should end the session, which calls `dismiss`.
    static func show(_ model: ShareModel, onClose: @escaping () -> Void) {
        let editor = EditorViewController(rootView: ShareView(model: model,
                                                              onClose: onClose,
                                                              onShare: { url in Presenter.share(url) }))
        if let old = shown, let presenting = old.presentingViewController {
            shown = editor
            presenting.dismiss(animated: false) { present(editor) }
        } else {
            shown = editor
            present(editor)
        }
    }

    /// Dismisses the editor on screen, if any, with whatever is over it.
    static func dismiss() {
        guard let editor = shown else { return }
        shown = nil
        if let presenting = editor.presentingViewController {
            presenting.dismiss(animated: true)
        }
    }

    /// Presents `editor` from the top view controller once no presentation is coming or going: the window may not be
    /// up yet (a Shortcut launched the app), or a sheet such as the system photo picker may still be going away.
    /// Presenting during the photo picker's dismissal is what put the editor's keys outside the safe area on a real
    /// iPhone (#440). After about two seconds it presents anyway, from the last controller that is not being
    /// dismissed (`Presenter.top()`); it gives up if the editor was replaced or dismissed meanwhile.
    private static func present(_ editor: EditorViewController) {
        Task { @MainActor in
            await Presenter.waitUntilSettled(limit: 2)
            guard shown === editor, let top = Presenter.top() else { return }
            top.present(editor, animated: true)
        }
    }
}

/// The editor's full-screen controller: the SwiftUI editor pinned to its edges, as `ShareViewController` pins it in
/// the extension. The hosting controller keeps its default safe-area handling, so the chassis fills the screen while
/// the keys stay inside the safe area.
final class EditorViewController: UIViewController {
    private let host: UIHostingController<ShareView>

    init(rootView: ShareView) {
        host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}
