import SkreenerEditor
import SwiftUI
import UIKit

/// Shows the app's editor full screen through UIKit (#440), the way the Share Extension hosts it: `ShareView` in a
/// `UIHostingController` pinned edge to edge inside a plain view controller, presented `.fullScreen` from the top view
/// controller. SwiftUI's `fullScreenCover` let the editor's keys slide under the status bar, the Dynamic Island and the
/// home indicator on a real iPhone; UIKit's presentation keeps them inside the safe area, as in the extension.
///
/// `HomeView` stays the source of truth for which editor should be up: it calls `show` when it has a new editor session
/// and `dismiss` when the session ends. One editor at a time: showing another replaces the one on screen. Close does
/// not wait for `HomeView`, though: it dismisses its own editor straight away, then tells `HomeView` (#439). When Close
/// went only through `HomeView`'s state, an editor that a second open had already replaced in that state (two quick
/// opens, such as two taps on the Frame Latest control) stayed on screen with a Close that did nothing.
@MainActor
enum EditorPresenter {
    /// The editor that should be on screen, if any (it may still be waiting to be presented).
    private static weak var shown: EditorViewController?

    /// Presents a fresh editor on `model`, replacing any editor on screen (and anything over it, like a share sheet).
    /// The editor's Close key dismisses it, then runs `onClose`, which should end the session (`dismiss` then finds
    /// nothing left to do). `notice`, if any, shows over the editor for a few seconds.
    static func show(_ model: ShareModel, notice: String? = nil, onClose: @escaping () -> Void) {
        let ref = EditorRef()
        let editor = EditorViewController(rootView: ShareView(model: model,
                                                              onClose: {
                                                                  if let editor = ref.editor { close(editor) }
                                                                  onClose()
                                                              },
                                                              onShare: { url in Presenter.share(url) }),
                                          notice: notice)
        ref.editor = editor
        shown = editor
        present(editor)
    }

    /// Dismisses the editor `HomeView` showed last, if it is still up or on its way, with whatever is over it.
    static func dismiss() {
        guard let editor = shown else { return }
        close(editor)
    }

    /// Dismisses `editor` (and anything over it, like a share sheet), whether or not it is still the one `HomeView`
    /// wants: its Close must always work.
    private static func close(_ editor: EditorViewController) {
        if shown === editor { shown = nil }
        guard let presenting = editor.presentingViewController, !editor.isBeingDismissed else { return }
        presenting.dismiss(animated: true)
    }

    /// The first editor in the window's chain of presented controllers, if any.
    private static func onScreen() -> EditorViewController? {
        var controller = Presenter.root()
        while let current = controller {
            if let editor = current as? EditorViewController { return editor }
            controller = current.presentedViewController
        }
        return nil
    }

    /// Presents `editor` from the top view controller once no presentation is coming or going: the window may not be
    /// up yet (a Shortcut launched the app), a sheet such as the system photo picker may still be going away, or the
    /// editor it replaces may still be coming up. Presenting during the photo picker's dismissal is what put the
    /// editor's keys outside the safe area on a real iPhone (#440); dismissing an editor that is still being presented
    /// fails, which left the old editor up. Any editor already up is dismissed first, once settled. After about two
    /// seconds it goes ahead anyway, from the last controller that is not being dismissed (`Presenter.top()`); an old
    /// editor that would not go stays under the new one, its Close still working. It gives up if the editor was
    /// replaced or dismissed meanwhile.
    private static func present(_ editor: EditorViewController) {
        Task { @MainActor in
            await Presenter.waitUntilSettled(limit: 2)
            guard shown === editor else { return }
            if let old = onScreen(), old !== editor, let presenting = old.presentingViewController {
                presenting.dismiss(animated: false)
                await Presenter.waitUntilSettled(limit: 1)
                guard shown === editor else { return }
            }
            guard let top = Presenter.top() else { return }
            top.present(editor, animated: true)
        }
    }
}

/// Lets the editor's Close reach its own controller, which is made after the view that holds the Close.
@MainActor
private final class EditorRef {
    weak var editor: EditorViewController?
}

/// The editor's full-screen controller: the SwiftUI editor pinned to its edges, as `ShareViewController` pins it in
/// the extension. The hosting controller keeps its default safe-area handling, so the chassis fills the screen while
/// the keys stay inside the safe area. The editor is portrait only: it opens upright and stays upright when the phone
/// turns (a full-screen presentation decides the orientation while it is up); Home still rotates.
final class EditorViewController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    private let host: UIHostingController<ShareView>
    /// A line about the picture (a long screenshot that only partly stitched, #456), shown over the editor for a
    /// few seconds once it is up; a tap hides it sooner. It never blocks the editor.
    private let notice: String?
    private var noticeView: UIView?
    private var noticeShown = false

    init(rootView: ShareView, notice: String? = nil) {
        host = UIHostingController(rootView: rootView)
        self.notice = notice
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let notice, !noticeShown else { return }
        noticeShown = true
        showNotice(notice)
    }

    /// A rounded banner with the notice, over the top of the picture (clear of the top keys), gone after eight
    /// seconds or a tap. VoiceOver reads it out.
    private func showNotice(_ text: String) {
        let banner = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        banner.layer.cornerRadius = 14
        banner.layer.cornerCurve = .continuous
        banner.clipsToBounds = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.contentView.addSubview(label)
        view.addSubview(banner)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: banner.contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: banner.contentView.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: banner.contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: banner.contentView.trailingAnchor, constant: -14),
            banner.topAnchor.constraint(equalTo: guide.topAnchor, constant: 120),
            banner.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
        ])
        banner.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideNotice)))
        banner.alpha = 0
        UIView.animate(withDuration: 0.25) { banner.alpha = 1 }
        noticeView = banner
        UIAccessibility.post(notification: .announcement, argument: text)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.hideNotice()
        }
    }

    @objc private func hideNotice() {
        guard let banner = noticeView else { return }
        noticeView = nil
        UIView.animate(withDuration: 0.25, animations: { banner.alpha = 0 },
                       completion: { _ in banner.removeFromSuperview() })
    }
}
