import AppKit

/// The top of the menu-bar menu: big tiles for the six everyday capture modes, each with its shortcut, and the newest
/// captures from the history, one click from the editor. Every capture mode is still under All Capture Modes below it,
/// where the keyboard reaches them.
@MainActor final class MenuLauncher: NSView {
    struct Tile {
        let action: HotKeyAction
        let title: String
        let symbol: String
    }

    /// Fills the 3 × 2 grid, in reading order.
    static let tiles = [
        Tile(action: .captureArea, title: "Area", symbol: "viewfinder"),
        Tile(action: .captureWindow, title: "Window", symbol: "macwindow"),
        Tile(action: .captureFullscreen, title: "Fullscreen", symbol: "display"),
        Tile(action: .captureScrolling, title: "Scrolling", symbol: "arrow.up.and.down.text.horizontal"),
        Tile(action: .captureText, title: "Text", symbol: "text.viewfinder"),
        Tile(action: .recordScreen, title: "Record", symbol: "record.circle"),
    ]
    static let columns = 3
    /// How many of the newest captures the strip shows.
    static let recentCount = 4

    private static let padding: CGFloat = 12
    private static let gap: CGFloat = 6
    private static let tileSize = NSSize(width: 88, height: 62)
    private static let thumbHeight: CGFloat = 46
    private static let headerHeight: CGFloat = 16
    static let width = padding * 2 + tileSize.width * CGFloat(columns) + gap * CGFloat(columns - 1)

    /// Thumbnails already made, by file, with the file's modification date (an edited capture is written again).
    private static var thumbnails: [URL: (date: Date, image: NSImage)] = [:]

    /// Runs a tile's capture mode; set by the app delegate.
    var onTile: ((HotKeyAction) -> Void)?
    var onShowHistory: (() -> Void)?

    private var tileViews: [LauncherTile] = []
    private let recentLabel = NSTextField(labelWithString: "Recent")
    private let showAll = NSButton(title: "Show All", target: nil, action: nil)
    private let emptyHint = NSTextField(labelWithString: "Your captures will show up here.")
    private var thumbViews: [RecentThumb] = []
    /// What to run once the menu has closed (`runAfterMenuCloses`).
    private var pending: (() -> Void)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        for (i, tile) in Self.tiles.enumerated() {
            let view = LauncherTile(title: tile.title, symbol: tile.symbol)
            let col = i % Self.columns, row = i / Self.columns
            view.frame = NSRect(x: Self.padding + CGFloat(col) * (Self.tileSize.width + Self.gap),
                                y: Self.padding + CGFloat(row) * (Self.tileSize.height + Self.gap),
                                width: Self.tileSize.width, height: Self.tileSize.height)
            let action = tile.action
            view.onClick = { [weak self] in self?.runAfterMenuCloses { self?.onTile?(action) } }
            addSubview(view)
            tileViews.append(view)
        }

        recentLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        recentLabel.textColor = .secondaryLabelColor
        addSubview(recentLabel)
        showAll.isBordered = false
        showAll.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        showAll.contentTintColor = .controlAccentColor
        showAll.target = self
        showAll.action = #selector(showAllClicked)
        showAll.sizeToFit()
        addSubview(showAll)
        emptyHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyHint.textColor = .tertiaryLabelColor
        addSubview(emptyHint)

        let thumbWidth = (Self.width - Self.padding * 2 - Self.gap * CGFloat(Self.recentCount - 1)) / CGFloat(Self.recentCount)
        for i in 0..<Self.recentCount {
            let thumb = RecentThumb(frame: NSRect(x: Self.padding + CGFloat(i) * (thumbWidth + Self.gap), y: 0,
                                                  width: thumbWidth.rounded(.down), height: Self.thumbHeight))
            addSubview(thumb)
            thumbViews.append(thumb)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Called as the menu opens: the shortcuts as they are set now, and the newest captures.
    func refresh() {
        for (view, tile) in zip(tileViews, Self.tiles) {
            view.shortcut = ShortcutStore.combo(for: tile.action)?.displayString
            view.endHover()   // the menu closed under the pointer without a mouseExited
        }
        thumbViews.forEach { $0.endHover() }
        let gridBottom = Self.padding + Self.tileSize.height * 2 + Self.gap
        guard Preferences.keepHistory else {
            ([recentLabel, showAll, emptyHint] as [NSView]).forEach { $0.isHidden = true }
            thumbViews.forEach { $0.isHidden = true }
            setFrameSize(NSSize(width: Self.width, height: gridBottom + Self.padding))
            return
        }
        let entries = Array(CaptureHistory.entries().prefix(Self.recentCount))
        let headerY = gridBottom + Self.padding + 2
        recentLabel.isHidden = false
        recentLabel.sizeToFit()
        recentLabel.setFrameOrigin(NSPoint(x: Self.padding, y: headerY))
        showAll.isHidden = entries.isEmpty
        showAll.setFrameOrigin(NSPoint(x: Self.width - Self.padding - showAll.frame.width,
                                       y: headerY + (recentLabel.frame.height - showAll.frame.height) / 2))
        let rowY = headerY + Self.headerHeight + Self.gap
        emptyHint.isHidden = !entries.isEmpty
        emptyHint.sizeToFit()
        emptyHint.setFrameOrigin(NSPoint(x: Self.padding, y: rowY))
        for (i, view) in thumbViews.enumerated() {
            view.setFrameOrigin(NSPoint(x: view.frame.minX, y: rowY))
            guard i < entries.count else { view.isHidden = true; view.url = nil; continue }
            let entry = entries[i]
            view.isHidden = false
            view.show(entry, image: Self.cachedThumbnail(entry.url))
            if view.image == nil { loadThumbnail(entry.url, into: view) }
            view.onClick = { [weak self] in self?.runAfterMenuCloses { MenuLauncher.open(entry.url) } }
        }
        let rowHeight = entries.isEmpty ? emptyHint.frame.height : Self.thumbHeight
        setFrameSize(NSSize(width: Self.width, height: rowY + rowHeight + Self.padding))
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func cachedThumbnail(_ url: URL) -> NSImage? {
        guard let cached = thumbnails[url], cached.date == modified(url) else { return nil }
        return cached.image
    }

    /// Makes the thumbnail in the background; it shows up even while the menu is open.
    private func loadThumbnail(_ url: URL, into view: RecentThumb) {
        let date = Self.modified(url)
        CaptureHistory.thumbnail(url, maxPixels: 240) { [weak view] img in
            guard let img else { return }
            Self.thumbnails[url] = (date, img)
            // Forget captures that have left the history.
            if Self.thumbnails.count > Self.recentCount * 3 {
                Self.thumbnails = Self.thumbnails.filter { FileManager.default.fileExists(atPath: $0.key.path) }
            }
            if let view, view.url == url { view.image = img }
        }
    }

    /// Opens a capture from the history in the editor, with its annotations still editable, like the history panel.
    static func open(_ png: URL) {
        let saved = CaptureHistory.document(for: png)
        guard let image = saved?.base ?? NSImage(contentsOf: png) else { NSSound.beep(); return }
        let editor = EditorWindowController(image: image)
        editor.attachHistory(png, document: saved?.document)
        editor.present()
    }

    @objc private func showAllClicked() {
        runAfterMenuCloses { [weak self] in self?.onShowHistory?() }
    }

    /// Closes the menu first, so it is gone from the screen (and from the capture) before `run` starts.
    private func runAfterMenuCloses(_ run: @escaping () -> Void) {
        pending = run
        enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()
        perform(#selector(runPending), with: nil, afterDelay: 0)
    }

    @objc private func runPending() {
        let run = pending
        pending = nil
        run?()
    }
}

/// One capture mode: a symbol over its name and shortcut, filled with the accent colour under the pointer.
private final class LauncherTile: NSView {
    var onClick: (() -> Void)?
    var shortcut: String? {
        didSet {
            shortcutLabel.stringValue = shortcut ?? ""
            setAccessibilityHelp(shortcut.map { "Shortcut: \($0)" })
        }
    }

    private let icon = NSImageView()
    private let titleLabel: NSTextField
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            applyColors()
            needsDisplay = true
        }
    }

    init(title: String, symbol: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.imageScaling = .scaleNone
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.alignment = .center
        shortcutLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        shortcutLabel.alignment = .center
        for v in [icon, titleLabel, shortcutLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -6),
            shortcutLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
        ])
        applyColors()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyColors() {
        icon.contentTintColor = hovering ? .white : .controlAccentColor
        titleLabel.textColor = hovering ? .white : .labelColor
        shortcutLabel.textColor = hovering ? NSColor.white.withAlphaComponent(0.8) : .tertiaryLabelColor
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        (hovering ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.07)).setFill()
        path.fill()
    }

    func endHover() { hovering = false }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    // A press that started on the menu-bar icon and was let go here counts too, as for any menu item.
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        hovering = false
        onClick?()
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// One of the newest captures; a click opens it in the editor.
private final class RecentThumb: NSView {
    var onClick: (() -> Void)?
    var url: URL?
    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    private let imageView = NSImageView()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    private var hovering = false {
        didSet { layer?.borderWidth = hovering ? 2 : 1; updateBorder() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ entry: CaptureHistory.Entry, image: NSImage?) {
        url = entry.url
        self.image = image
        let when = Self.relative.localizedString(for: entry.date, relativeTo: Date())
        toolTip = "Open in the editor (captured \(when))"
        setAccessibilityLabel("Capture from \(when)")
        updateBorder()
    }

    private func updateBorder() {
        // Layer colours don't follow the appearance by themselves.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            layer?.borderColor = (hovering ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.12)).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    func endHover() { hovering = false }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        hovering = false
        onClick?()
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}
