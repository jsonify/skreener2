import AppKit
import AVFoundation

/// Floating preview shown in the bottom-left corner after a capture, like CleanShot's. It stays until something is
/// done with it: hovering shows round buttons in the corners (close, edit, pin, share) and Copy / Save pills in the
/// middle, and any of them dismisses it. Previews of later captures stack upwards, newest at the bottom. While a new
/// capture is being taken they fade away, and come back once it is done (after its editor has opened). A finished
/// recording gets the same preview, showing its first frame, with Open and Show in Finder for Edit and Pin, and Trim.
/// Previews are semi-transparent unless the pointer is over them (#98).
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
    /// The file the screenshot was saved to (Settings → After Capture), which dragging the preview out hands over.
    private let saved: URL?
    /// The video or GIF file when this previews a recording; `image` is then its first frame.
    private let recording: URL?
    /// For a GIF recording, the temporary MP4 it was made from, kept for Trim; deleted when the preview goes away
    /// (unless the trim editor took it over).
    private var video: URL?
    /// The editor that opened with this capture, shown again by Edit while it is still open.
    private weak var editor: EditorWindowController?
    private let panel: NSPanel
    private var card: QuickAccessCard? { panel.contentView as? QuickAccessCard }

    // The app's capture flows (not main-actor isolated themselves) call these on the main thread.

    /// Adds a preview of `image` to the bottom of the stack. `editor` is the editor the capture opened in, if any.
    nonisolated static func show(_ image: NSImage, editor: EditorWindowController?, saved: URL? = nil) {
        MainActor.assumeIsolated {
            let qa = QuickAccessController(image: image, editor: editor, saved: saved)
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            live.append(qa)
            layout(animated: true)
            if !suspended {
                qa.panel.orderFrontRegardless()
                qa.card?.syncHover()
            }
        }
    }

    /// Adds a preview of a finished recording once its first frame is ready (a GIF shows animated). `video` is the
    /// temporary MP4 a GIF was made from, which the preview then looks after.
    nonisolated static func show(recording url: URL, video: URL? = nil) {
        Task { @MainActor in
            let qa = QuickAccessController(image: await Self.thumbnail(of: url), recording: url)
            qa.video = video == url ? nil : video
            Self.screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            Self.live.append(qa)
            Self.layout(animated: true)
            if !Self.suspended {
                qa.panel.orderFrontRegardless()
                qa.card?.syncHover()
            }
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

    private init(image: NSImage, editor: EditorWindowController? = nil, recording: URL? = nil, saved: URL? = nil) {
        self.image = image
        self.saved = saved
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
        let shareButton = card.addCorner(symbol: "square.and.arrow.up", label: "Share", at: .bottomRight) { [weak self, weak card] in
            if let card { self?.share(from: card) }
        }
        // Send To (custom actions, notes apps) sits beside Share.
        weak var sendButton: PillButton?
        sendButton = card.addCorner(symbol: "paperplane", label: "Send To", at: .bottomRight, beside: shareButton) { [weak self] in
            if let sendButton { self?.sendTo(from: sendButton) }
        }
        if recording != nil {
            card.addCenter([("Copy", { [weak self] in self?.copy() }), ("Trim", { [weak self] in self?.trim() })])
        } else {
            card.addCenter([("Copy", { [weak self] in self?.copy() }), ("Save", { [weak self] in self?.save() })])
        }
        // Double-clicking the preview does what Edit does (Open for a recording) (#127).
        card.onDoubleClick = { [weak self] in
            guard let self else { return }
            if recording != nil { open() } else { edit() }
        }
        // Dragging the preview out hands over the file: the recording, the saved screenshot, or a named temporary copy.
        card.fileToDrag = {
            recording ?? saved.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? Output.temporaryFile(image)
        }
        // Swiping it toward the screen edge dismisses it (#32).
        card.onSwipeDismiss = { [weak self] in self?.close() }
        panel.contentView = card
    }

    /// Left edge of a preview `width` wide in the bottom corner Settings → After Capture picks (#32).
    static func x(width: CGFloat, in frame: NSRect, onRight: Bool) -> CGFloat {
        onRight ? frame.maxX - margin - width : frame.minX + margin
    }

    /// Moves the previews on screen to the corner Settings now picks.
    static func refreshPosition() { layout(animated: true) }

    /// Places the previews from the bottom-left (or bottom-right) corner upwards, newest first. Ones that no longer
    /// fit are dropped.
    private static func layout(animated: Bool) {
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var y = frame.minY + margin
        var overflow: [QuickAccessController] = []
        for qa in live.reversed() {
            let size = qa.panel.frame.size
            if y + size.height > frame.maxY - margin, qa !== live.last { overflow.append(qa); continue }
            let left = x(width: size.width, in: frame, onRight: Preferences.quickAccessOnRight)
            let target = NSRect(origin: NSPoint(x: left, y: y), size: size)
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
        for qa in overflow { qa.panel.orderOut(nil); qa.discardVideo() }
        live.removeAll { qa in overflow.contains { $0 === qa } }
    }

    private func fade(in show: Bool) {
        if show {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            card?.syncHover()
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
        Sound.play("Pop")
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

    /// Opens the trim editor, which takes over the GIF's video.
    private func trim() {
        if let recording { RecordingTrimWindow.open(recording, video: video ?? recording) }
        video = nil
        close()
    }

    private func discardVideo() {
        if let video { try? FileManager.default.removeItem(at: video) }
        video = nil
    }

    private func showInFinder() {
        if let recording { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
        close()
    }

    private func share(from view: NSView) {
        card?.held = true   // stays opaque with its buttons while the share sheet is open
        if let recording { Output.share(recording, from: view, delegate: self) } else { Output.share(image, from: view, delegate: self) }
    }

    /// The Send To menu under its button. The preview stays opaque while the menu is open, and goes once a destination
    /// is picked.
    private func sendTo(from button: NSView) {
        card?.held = true
        let image = image, saved = saved, recording = recording
        let source = SendTo.Source(isImage: recording == nil, app: (recording ?? saved).flatMap(SendTo.appName(for:))) {
            if let recording { return (file: recording, image: nil) }
            if let saved, FileManager.default.fileExists(atPath: saved.path) { return (file: saved, image: image) }
            return Output.temporaryFile(image).map { (file: $0, image: image) }
        }
        SendTo.present(source, from: button) { [weak self] in self?.close() }
        card?.syncHover()
        card?.held = false
    }

    /// Once a share service is picked the preview has done its job; a cancelled share sheet leaves it.
    nonisolated func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            guard service != nil else {
                card?.syncHover()
                card?.held = false
                return
            }
            close()
        }
    }

    func close() {
        guard Self.live.contains(where: { $0 === self }) else { return }
        Self.live.removeAll { $0 === self }
        panel.orderOut(nil)
        discardVideo()
        Self.layout(animated: true)
    }
}

/// What a drag on a Quick Access preview means (#32): toward the edge of the screen the previews sit on swipes it
/// away; any other direction drags the file out.
enum QuickAccessGesture {
    enum Kind: Equatable { case swipe, fileDrag }

    /// Movement below this many points is still a click.
    static let slop: CGFloat = 4

    /// `dx`/`dy` are the pointer's movement since the mouse went down; `onRight` is the corner the previews are in.
    static func classify(dx: CGFloat, dy: CGFloat, onRight: Bool) -> Kind? {
        guard hypot(dx, dy) > slop else { return nil }
        let toward = onRight ? dx : -dx
        return toward > 0 && abs(dx) > abs(dy) ? .swipe : .fileDrag
    }

    /// Whether letting go after a swipe of `dx` dismisses: far enough (40% of the width), or flicked (`velocity` in
    /// points per second, positive to the right) after a short swipe.
    static func shouldDismiss(dx: CGFloat, width: CGFloat, velocity: CGFloat, onRight: Bool) -> Bool {
        let toward = onRight ? dx : -dx
        let speed = onRight ? velocity : -velocity
        return toward > width * 0.4 || (toward > 20 && speed > 600)
    }
}

/// Quick Access previews (of screenshots and recordings) rest semi-transparent, so they don't hide what is under them,
/// and turn opaque while the pointer is over them (#98).
enum PreviewHover {
    static let restingAlpha: CGFloat = 0.65

    /// Whether the pointer is over `view` now. A preview that appears under a still pointer gets no mouseEntered.
    @MainActor static func isPointer(inside view: NSView) -> Bool {
        guard let window = view.window else { return false }
        return view.bounds.contains(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}

/// The preview's content: the thumbnail, and on hover a dark veil with the corner buttons and the middle pills.
private final class QuickAccessCard: NSView, NSDraggingSource {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private let controls = NSView()
    private let thumb = NSImageView()
    /// A double-click anywhere but on a button.
    var onDoubleClick: (() -> Void)?
    /// The file a drag out of the preview carries.
    var fileToDrag: (() -> URL?)?
    /// A swipe toward the screen edge that was let go far (or fast) enough.
    var onSwipeDismiss: (() -> Void)?
    private var gesture: QuickAccessGesture.Kind?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var lastSample: (x: CGFloat, time: TimeInterval)?
    private var velocity: CGFloat = 0
    private var pointerInside = false { didSet { hovering = pointerInside || held } }
    /// Keeps the card opaque with its buttons showing whatever the pointer does, e.g. while its share sheet is open.
    var held = false { didSet { hovering = pointerInside || held } }
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                controls.animator().alphaValue = hovering ? 1 : 0
                animator().alphaValue = hovering ? 1 : PreviewHover.restingAlpha
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

        thumb.frame = bounds
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
        alphaValue = PreviewHover.restingAlpha
        // White pills with dark content on the dark veil, whatever the system appearance.
        controls.appearance = NSAppearance(named: .aqua)
        addSubview(controls)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `beside` puts the button next to another one in the same corner, on its inner side.
    @discardableResult
    func addCorner(symbol: String, label: String, at corner: Corner, beside other: PillButton? = nil,
                   run: @escaping () -> Void) -> PillButton {
        let button = PillButton(title: nil, symbol: symbol, style: .raised, height: 24, run: run)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        controls.addSubview(button)
        let inset: CGFloat = 7
        switch corner {
        case .topLeft, .bottomLeft:
            if let other {
                button.leadingAnchor.constraint(equalTo: other.trailingAnchor, constant: 6).isActive = true
            } else {
                button.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: inset).isActive = true
            }
        case .topRight, .bottomRight:
            if let other {
                button.trailingAnchor.constraint(equalTo: other.leadingAnchor, constant: -6).isActive = true
            } else {
                button.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -inset).isActive = true
            }
        }
        switch corner {
        case .topLeft, .topRight: button.topAnchor.constraint(equalTo: controls.topAnchor, constant: inset).isActive = true
        case .bottomLeft, .bottomRight: button.bottomAnchor.constraint(equalTo: controls.bottomAnchor, constant: -inset).isActive = true
        }
        return button
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

    /// Matches the hover state to where the pointer is, for when the card shows up (or comes back) under it.
    func syncHover() { pointerInside = PreviewHover.isPointer(inside: self) }

    /// Clicks on the thumbnail or the veil land here (not on the image view), so a double-click can open the editor.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === thumb || hit === controls ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(); return }
        gesture = nil
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        lastSample = nil
        velocity = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
        let onRight = Preferences.quickAccessOnRight
        if gesture == nil { gesture = QuickAccessGesture.classify(dx: dx, dy: dy, onRight: onRight) }
        switch gesture {
        case .fileDrag:
            gesture = nil   // the drag session takes over the mouse; a later drag decides again
            beginFileDrag(with: event)
        case .swipe:
            // Follows the pointer toward the edge (not away from it), fading as it goes.
            let moved = onRight ? max(dx, 0) : min(dx, 0)
            window.setFrameOrigin(NSPoint(x: startOrigin.x + moved, y: startOrigin.y))
            window.alphaValue = max(1 - abs(moved) / window.frame.width, 0.2)
            if let last = lastSample, event.timestamp > last.time {
                velocity = (mouse.x - last.x) / (event.timestamp - last.time)
            }
            lastSample = (mouse.x, event.timestamp)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard gesture == .swipe, let window else { return }
        gesture = nil
        let onRight = Preferences.quickAccessOnRight
        let dx = window.frame.origin.x - startOrigin.x
        let dismiss = QuickAccessGesture.shouldDismiss(dx: dx, width: window.frame.width, velocity: velocity, onRight: onRight)
        let off = NSPoint(x: startOrigin.x + (onRight ? 1 : -1) * (window.frame.width + 40), y: startOrigin.y)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().setFrameOrigin(dismiss ? off : startOrigin)
            window.animator().alphaValue = dismiss ? 0 : 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard dismiss else { return }
                self?.onSwipeDismiss?()
                window.alphaValue = 1   // a panel kept alive (e.g. by a suspend/resume) shouldn't stay see-through
            }
        })
    }

    /// Starts dragging the capture out as a file, with the thumbnail under the pointer.
    private func beginFileDrag(with event: NSEvent) {
        guard let url = fileToDrag?(), let image = thumb.image else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let width: CGFloat = 120
        let size = NSSize(width: width, height: max((width * image.size.height / max(image.size.width, 1)).rounded(), 40))
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
                              contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func mouseEntered(with event: NSEvent) { pointerInside = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
