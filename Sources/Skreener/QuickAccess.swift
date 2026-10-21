import AppKit
import AVFoundation

/// Floating preview shown in the bottom-left corner after a capture, like CleanShot's. It stays until something is
/// done with it: hovering shows round buttons in the corners (close, edit, pin, share) and Copy / Save pills in the
/// middle, and any of them dismisses it. Previews of later captures stack upwards, newest at the bottom. While a new
/// capture is being taken they fade away, and come back once it is done (after its editor has opened). A finished
/// recording gets the same preview, showing its first frame, with Open and Show in Finder for Edit and Pin.
@MainActor final class QuickAccessController: NSObject, NSSharingServicePickerDelegate {
    private static var live: [QuickAccessController] = []
    /// The screen the stack is on: the one the newest preview appeared on.
    private static weak var screen: NSScreen?
    private static var suspended = false
    /// Bumped by `suspend()`, so a `resume()` that is still waiting doesn't bring the previews back mid-capture.
    private static var generation = 0

    static let width: CGFloat = 220
    private static let margin: CGFloat = 16
    private static let gap: CGFloat = 12

    private let image: NSImage
    /// The video or GIF file when this previews a recording; `image` is then its first frame.
    private let recording: URL?
    /// The editor that opened with this capture, shown again by Edit while it is still open.
    private weak var editor: EditorWindowController?
    private let panel: NSPanel

    // The app's capture flows (not main-actor isolated themselves) call these on the main thread.

    /// Adds a preview of `image` to the bottom of the stack. `editor` is the editor the capture opened in, if any.
    nonisolated static func show(_ image: NSImage, editor: EditorWindowController?) {
        MainActor.assumeIsolated {
            let qa = QuickAccessController(image: image, editor: editor)
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            live.append(qa)
            layout(animated: true)
            if !suspended { qa.panel.orderFrontRegardless() }
        }
    }

    /// Adds a preview of a finished recording once its first frame is ready (a GIF shows animated).
    nonisolated static func show(recording url: URL) {
        Task { @MainActor in
            let qa = QuickAccessController(image: await Self.thumbnail(of: url), recording: url)
            Self.screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            Self.live.append(qa)
            Self.layout(animated: true)
            if !Self.suspended { qa.panel.orderFrontRegardless() }
        }
    }

    private static func thumbnail(of url: URL) async -> NSImage {
        if url.pathExtension.lowercased() == "gif", let gif = NSImage(contentsOf: url) { return gif }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: width * 2, height: 400)
        if let cg = try? await gen.image(at: .zero).image { return NSImage(cgImage: cg, size: .zero) }
        // No frame to show: a film symbol on a 16:9 card.
        return NSImage(size: NSSize(width: 320, height: 180), flipped: false) { r in
            let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
                .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.6)]))
            guard let film = NSImage(systemSymbolName: "film", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            else { return true }
            film.draw(in: NSRect(x: r.midX - film.size.width / 2, y: r.midY - film.size.height / 2,
                                 width: film.size.width, height: film.size.height))
            return true
        }
    }

    /// Fades every preview out, so it isn't in the way of (or in) the capture about to be taken.
    nonisolated static func suspend() {
        MainActor.assumeIsolated {
            generation += 1
            suspended = true
            for qa in live { qa.fade(in: false) }
        }
    }

    /// Brings the previews back after a capture; a little later, so a new editor gets to open first.
    nonisolated static func resume() {
        MainActor.assumeIsolated {
            guard suspended else { return }
            let g = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated {
                    guard g == Self.generation else { return }
                    Self.suspended = false
                    for qa in Self.live { qa.fade(in: true) }
                }
            }
        }
    }

    private init(image: NSImage, editor: EditorWindowController? = nil, recording: URL? = nil) {
        self.image = image
        self.editor = editor
        self.recording = recording
        let aspect = image.size.height / max(image.size.width, 1)
        let size = NSSize(width: Self.width, height: min(max((Self.width * aspect).rounded(), 90), 200))
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.canHide = false   // stays put while Skreener hides (e.g. during a Drag Me drag)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let card = QuickAccessCard(frame: NSRect(origin: .zero, size: size), image: image)
        card.addCorner(symbol: "xmark", label: "Close", at: .topLeft) { [weak self] in self?.close() }
        if recording != nil {
            // The recording is already saved, so there is no Save; nor an editor or a pin for a video.
            card.addCorner(symbol: "play.fill", label: "Open", at: .topRight) { [weak self] in self?.open() }
            card.addCorner(symbol: "folder", label: "Show in Finder", at: .bottomLeft) { [weak self] in self?.showInFinder() }
        } else {
            card.addCorner(symbol: "pencil", label: "Edit", at: .topRight) { [weak self] in self?.edit() }
            card.addCorner(symbol: "pin.fill", label: "Pin", at: .bottomLeft) { [weak self] in self?.pin() }
        }
        card.addCorner(symbol: "square.and.arrow.up", label: "Share", at: .bottomRight) { [weak self, weak card] in
            if let card { self?.share(from: card) }
        }
        if recording != nil {
            card.addCenter([("Copy", { [weak self] in self?.copy() })])
        } else {
            card.addCenter([("Copy", { [weak self] in self?.copy() }), ("Save", { [weak self] in self?.save() })])
        }
        panel.contentView = card
    }

    /// Places the previews from the bottom-left corner upwards, newest first. Ones that no longer fit are dropped.
    private static func layout(animated: Bool) {
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var y = frame.minY + margin
        var overflow: [QuickAccessController] = []
        for qa in live.reversed() {
            let size = qa.panel.frame.size
            if y + size.height > frame.maxY - margin, qa !== live.last { overflow.append(qa); continue }
            let target = NSRect(origin: NSPoint(x: frame.minX + margin, y: y), size: size)
            // A new preview starts in place; the ones above it slide up to make room.
            if animated, qa.panel.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    qa.panel.animator().setFrame(target, display: true)
                }
            } else {
                qa.panel.setFrame(target, display: false)
            }
            y += size.height + gap
        }
        for qa in overflow { qa.panel.orderOut(nil) }
        live.removeAll { qa in overflow.contains { $0 === qa } }
    }

    private func fade(in show: Bool) {
        if show {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = show ? 0.2 : 0.1
            panel.animator().alphaValue = show ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Still hidden (no resume in the meantime): take it off the screen.
                if !show, Self.suspended { self?.panel.orderOut(nil) }
            }
        })
    }

    /// A recording is copied as its file, ready to paste into Finder, Mail or a chat.
    private func copy() {
        if let recording {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([recording as NSURL])
        } else {
            Output.copy(image)
        }
        NSSound(named: "Pop")?.play()
        close()
    }

    /// Saves to the export location, like the auto-save after a capture.
    private func save() {
        guard Output.save(image) != nil else { NSSound.beep(); return }
        close()
    }

    private func edit() {
        if let editor, EditorWindowController.live.contains(where: { $0 === editor }) {
            editor.reveal()
        } else {
            EditorWindowController(image: image).present()
        }
        close()
    }

    private func pin() {
        PinnedScreenshotController.pin(image)
        close()
    }

    private func open() {
        if let recording { NSWorkspace.shared.open(recording) }
        close()
    }

    private func showInFinder() {
        if let recording { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
        close()
    }

    private func share(from view: NSView) {
        if let recording { Output.share(recording, from: view, delegate: self) } else { Output.share(image, from: view, delegate: self) }
    }

    /// Once a share service is picked the preview has done its job; a cancelled share sheet leaves it.
    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard service != nil else { return }
        MainActor.assumeIsolated { close() }
    }

    func close() {
        guard Self.live.contains(where: { $0 === self }) else { return }
        Self.live.removeAll { $0 === self }
        panel.orderOut(nil)
        Self.layout(animated: true)
    }
}

/// The preview's content: the thumbnail, and on hover a dark veil with the corner buttons and the middle pills.
private final class QuickAccessCard: NSView {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private let controls = NSView()
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                controls.animator().alphaValue = hovering ? 1 : 0
            }
        }
    }

    init(frame: NSRect, image: NSImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let thumb = NSImageView(frame: bounds)
        thumb.image = image
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.animates = true   // a GIF recording plays
        thumb.autoresizingMask = [.width, .height]
        addSubview(thumb)

        controls.frame = bounds
        controls.autoresizingMask = [.width, .height]
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        controls.alphaValue = 0
        // White pills with dark content on the dark veil, whatever the system appearance.
        controls.appearance = NSAppearance(named: .aqua)
        addSubview(controls)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func addCorner(symbol: String, label: String, at corner: Corner, run: @escaping () -> Void) {
        let button = PillButton(title: nil, symbol: symbol, style: .raised, height: 24, run: run)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        controls.addSubview(button)
        let inset: CGFloat = 7
        switch corner {
        case .topLeft, .bottomLeft: button.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: inset).isActive = true
        case .topRight, .bottomRight: button.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -inset).isActive = true
        }
        switch corner {
        case .topLeft, .topRight: button.topAnchor.constraint(equalTo: controls.topAnchor, constant: inset).isActive = true
        case .bottomLeft, .bottomRight: button.bottomAnchor.constraint(equalTo: controls.bottomAnchor, constant: -inset).isActive = true
        }
    }

    func addCenter(_ actions: [(String, () -> Void)]) {
        let stack = NSStackView(views: actions.map { PillButton(title: $0.0, symbol: nil, style: .raised, height: 26, run: $0.1) })
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(stack)
        stack.centerXAnchor.constraint(equalTo: controls.centerXAnchor).isActive = true
        stack.centerYAnchor.constraint(equalTo: controls.centerYAnchor).isActive = true
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
