import AppKit
import ImageIO

extension Notification.Name {
    /// Posted when a capture is added to or removed from the history.
    static let skreenerHistoryChanged = Notification.Name("SkreenerHistoryChanged")
}

/// Every capture is kept as a PNG in Application Support, newest first, so the history panel can show,
/// copy, re-open or delete it. Only the newest `limit` captures are kept.
enum CaptureHistory {
    struct Entry {
        let url: URL
        let date: Date
    }

    static let limit = 100

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Skreener/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Encodes and writes in the background so a large capture never holds up the Quick Access thumbnail.
    static func add(_ image: NSImage) {
        guard Preferences.keepHistory, let tiff = image.tiffRepresentation else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let url = directory.appendingPathComponent("Skreener \(f.string(from: Date())).png")
        DispatchQueue.global(qos: .utility).async {
            guard let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            do { try data.write(to: url) } catch { NSLog("History save failed: \(error)"); return }
            for old in entries().dropFirst(limit) { try? FileManager.default.removeItem(at: old.url) }
            DispatchQueue.main.async { NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil) }
        }
    }

    /// Newest first.
    static func entries() -> [Entry] {
        let key = URLResourceKey.creationDateKey
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [key],
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "png" }
            .map { Entry(url: $0, date: (try? $0.resourceValues(forKeys: [key]).creationDate) ?? .distantPast) }
            .sorted { $0.date > $1.date }
    }

    static func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil)
    }

    static func clear() {
        entries().forEach { try? FileManager.default.removeItem(at: $0.url) }
        NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil)
    }

    /// A small, fast thumbnail (decodes only what it needs, unlike loading the full PNG).
    static func thumbnail(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// CleanShot-style capture history: a strip of recent captures that slides down from the top of the screen.
/// Hover a capture for Edit / Copy / Save / Share / Pin / Delete, double-click to edit, drag it out as a file.
/// Esc, a click elsewhere, or the menu item again slides it away.
final class CaptureHistoryPanel: NSObject {
    static let shared = CaptureHistoryPanel()

    private var panel: HistoryPanel?
    private let strip = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No captures yet. Screenshots you take show up here.")
    private var monitors: [Any] = []
    private var shownFrame = NSRect.zero
    /// Bumped on every show, so a slide-out that finishes after the panel was shown again leaves it on screen.
    private var generation = 0
    private static let height: CGFloat = 228

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let width = min(screen.visibleFrame.width - 40, 1600)
        shownFrame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.maxY - Self.height - 8,
                            width: width, height: Self.height)
        let p = panel ?? makePanel()
        panel = p
        generation += 1
        reload()
        // Start just above the top of the screen and slide down.
        var start = shownFrame
        start.origin.y = screen.frame.maxY
        p.setFrame(start, display: false)
        p.alphaValue = 1
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(shownFrame, display: true)
        }
        installMonitors()
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        removeMonitors()
        let gen = generation
        var end = p.frame
        end.origin.y = (p.screen ?? NSScreen.main)?.frame.maxY ?? end.maxY
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in if self?.generation == gen { p.orderOut(nil) } })
    }

    // MARK: Building

    private func makePanel() -> HistoryPanel {
        let p = HistoryPanel(contentRect: shownFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: "Capture History")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let more = NSPopUpButton(frame: .zero, pullsDown: true)
        more.bezelStyle = .texturedRounded
        more.isBordered = false
        let menu = NSMenu()
        menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.item(at: 0)?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
        for (t, sel) in [("Open History Folder", #selector(openFolder)), ("Clear History…", #selector(clearHistory))] {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; menu.addItem(i)
        }
        more.menu = menu

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") ?? NSImage(),
                             target: self, action: #selector(closeIt))
        close.isBordered = false
        close.toolTip = "Close (Esc)"

        strip.orientation = .horizontal
        strip.alignment = .top
        strip.spacing = 14
        strip.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(strip)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = doc

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        [title, more, close, scroll, emptyLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bg.addSubview($0) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: bg.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            more.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            more.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            strip.topAnchor.constraint(equalTo: doc.topAnchor),
            strip.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        p.contentView = bg

        NotificationCenter.default.addObserver(forName: .skreenerHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            if self?.isVisible == true { self?.reload() }
        }
        return p
    }

    private func reload() {
        strip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let entries = CaptureHistory.entries()
        emptyLabel.isHidden = !entries.isEmpty
        for e in entries {
            let cell = HistoryCell(entry: e)
            cell.onAction = { [weak self] action in self?.run(action, on: e) }
            strip.addArrangedSubview(cell)
        }
    }

    // MARK: Actions

    private func run(_ action: HistoryCell.Action, on e: CaptureHistory.Entry) {
        if action == .delete { CaptureHistory.delete(e); return }
        guard let image = NSImage(contentsOf: e.url) else { NSSound.beep(); return }
        switch action {
        case .copy:
            Output.copy(image)
            Sound.play("Pop")
        case .edit:
            hide()
            EditorWindowController(image: image).present()
        case .pin:
            hide()
            PinnedScreenshotController.pin(image)
        case .save:
            hide()
            NSApp.activate(ignoringOtherApps: true)
            Output.saveAs(image)
        case .delete: break
        }
    }

    @objc private func closeIt() { hide() }

    @objc private func openFolder() {
        hide()
        NSWorkspace.shared.open(CaptureHistory.directory)
    }

    @objc private func clearHistory() {
        removeMonitors()   // the alert would count as a click outside
        let a = NSAlert()
        a.messageText = "Clear capture history?"
        a.informativeText = "All \(CaptureHistory.entries().count) captures in the history will be deleted. Files you saved elsewhere are kept."
        a.addButton(withTitle: "Clear History")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { CaptureHistory.clear() }
        panel?.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    // MARK: Dismissal

    private func installMonitors() {
        removeMonitors()
        // A click in another app, or in one of Skreener's own windows, slides the panel away.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, let p = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 && event.window === p { self.hide(); return nil }
                return event
            }
            if event.window !== p { self.hide() }
            return event
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One capture in the history strip: thumbnail, relative time, and hover actions.
private final class HistoryCell: NSView, NSDraggingSource {
    enum Action { case edit, copy, save, pin, delete }

    let entry: CaptureHistory.Entry
    var onAction: ((Action) -> Void)?
    private let thumb = NSImageView()
    private let overlay = NSView()
    private static let thumbSize = NSSize(width: 220, height: 140)
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f
    }()
    private var downEvent: NSEvent?

    init(entry: CaptureHistory.Entry) {
        self.entry = entry
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        thumb.imageScaling = .scaleProportionallyDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        thumb.translatesAutoresizingMaskIntoConstraints = false
        let url = entry.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = CaptureHistory.thumbnail(url, maxPixels: 480)
            DispatchQueue.main.async { self?.thumb.image = img }
        }

        let time = NSTextField(labelWithString: Self.relative.localizedString(for: entry.date, relativeTo: Date()))
        time.font = .systemFont(ofSize: 11)
        time.textColor = .secondaryLabelColor
        time.alignment = .center
        time.translatesAutoresizingMaskIntoConstraints = false

        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = 8
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        overlay.isHidden = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        let buttons: [(String, String, Action)] = [("pencil", "Edit", .edit), ("doc.on.doc", "Copy", .copy),
                                                   ("square.and.arrow.down", "Save…", .save), ("pin", "Pin", .pin),
                                                   ("trash", "Delete", .delete)]
        var views: [NSView] = buttons.map { sym, tip, action in
            let b = HoverButton(symbol: sym, tip: tip)
            b.onClick = { [weak self] in self?.onAction?(action) }
            return b
        }
        // Shares the PNG file itself, so it keeps its name in Mail, AirDrop…
        let share = HoverButton(symbol: "square.and.arrow.up", tip: "Share…")
        share.onClick = { [weak self, weak share] in
            guard let self, let share else { return }
            Output.share(self.entry.url, from: share)
        }
        views.insert(share, at: 3)
        let row = NSStackView(views: views)
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(row)

        [thumb, overlay, time].forEach(addSubview)
        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: topAnchor),
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumb.widthAnchor.constraint(equalToConstant: Self.thumbSize.width),
            thumb.heightAnchor.constraint(equalToConstant: Self.thumbSize.height),
            overlay.topAnchor.constraint(equalTo: thumb.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: thumb.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: thumb.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: thumb.trailingAnchor),
            row.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            time.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 8),
            time.centerXAnchor.constraint(equalTo: centerXAnchor),
            time.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolTip = entry.url.deletingPathExtension().lastPathComponent
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { overlay.isHidden = false }
    override func mouseExited(with event: NSEvent) { overlay.isHidden = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { onAction?(.edit) }
    }

    /// Dragging a capture out drops its PNG file (into Finder, Mail, Slack…).
    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        downEvent = nil
        let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
        item.setDraggingFrame(thumb.frame, contents: thumb.image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

/// Round icon button for the history cell's hover overlay.
private final class HoverButton: NSButton {
    var onClick: (() -> Void)?

    init(symbol: String, tip: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .white
        toolTip = tip
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        target = self
        action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
