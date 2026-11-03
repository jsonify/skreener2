import AppKit
import ImageIO

/// What a key under the capture keys does; the app delegate runs it (`MenuLauncher.onCommand`) once the menu has closed.
enum MenuCommand: Hashable {
    case showHistory, openClipboard, pinClipboard, settings, quit
    case openFile, pinFile, pinClickThrough, fromDevice
    case presenter, stepRecorder, stepGuide, watchArea
    case keyboardShortcuts, welcomeGuide, whatsNew, checkForUpdates, about
    /// A click on the LCD while it shows a newer release.
    case showUpdate

    /// The global shortcut that runs the same thing, shown on the LCD while the pointer is over the key.
    var hotKey: HotKeyAction? {
        switch self {
        case .showHistory: return .showHistory
        case .openClipboard: return .openClipboard
        case .pinClipboard: return .pinClipboard
        case .openFile: return .openFile
        case .pinFile: return .pinFile
        case .pinClickThrough: return .pinClickThrough
        case .presenter: return .presenter
        case .stepRecorder: return .stepRecorder
        case .watchArea: return .watchArea
        default: return nil
        }
    }

    /// The menu's own key equivalents, which work while it is open.
    var menuShortcut: String? {
        switch self {
        case .settings: return "⌘,"
        case .quit: return "⌘Q"
        default: return nil
        }
    }
}

/// The SK-1 menu-bar menu (#344, #371): a slim LCD strip (the version and whether an update is out, or the name and
/// shortcut of the key under the pointer), six everyday capture modes as keys in a sunken tray (Record the orange one),
/// the newest captures from the history in sunken wells, one click from the editor, and trays of small captioned keys:
/// the everyday ones in Compact mode, more grouped under captions in Expanded (Settings → Menu Bar). Every capture
/// mode is also on the radial menu and its global shortcut.
@MainActor final class MenuLauncher: NSView {
    struct Tile {
        let action: HotKeyAction
        let title: String
        let symbol: String
    }

    /// A small key: `caption` printed under it, `name` on the LCD and for VoiceOver. A key that turns something on and
    /// off has the `active` caption and name while it is on, and a lamp that is lit then.
    struct Key {
        let command: MenuCommand
        let caption: String
        let name: String
        let symbol: String
        var variant: Retro.KeyVariant = .cream
        var active: (caption: String, name: String)?
    }

    /// A tray of keys, with a caption over it (none for the everyday tray at the bottom).
    struct KeyGroup {
        let title: String?
        let keys: [Key]
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
    /// The most keys a tray of small keys holds in a row.
    static let maxKeysPerTray = 5

    /// The tray at the bottom, in both modes.
    static let everyday = KeyGroup(title: nil, keys: [
        Key(command: .showHistory, caption: "History", name: "Capture History", symbol: "clock.arrow.circlepath"),
        Key(command: .openClipboard, caption: "Open Clip", name: "Open from Clipboard", symbol: "doc.on.clipboard"),
        Key(command: .pinClipboard, caption: "Pin Clip", name: "Pin from Clipboard", symbol: "pin"),
        Key(command: .settings, caption: "Settings", name: "Settings", symbol: "gearshape", variant: .charcoal),
        Key(command: .quit, caption: "Quit", name: "Quit Skreener", symbol: "power", variant: .charcoal),
    ])

    /// Expanded mode's trays, over the everyday one.
    static let expandedGroups = [
        KeyGroup(title: "Open & Pin", keys: [
            Key(command: .openFile, caption: "Open", name: "Open…", symbol: "folder"),
            Key(command: .pinFile, caption: "Pin File", name: "Pin to the Screen…", symbol: "pin.circle"),
            Key(command: .pinClickThrough, caption: "Click-Thru", name: "Pin Click-Through", symbol: "cursorarrow.rays"),
            Key(command: .fromDevice, caption: "iPhone", name: "From iPhone or iPad", symbol: "iphone"),
        ]),
        KeyGroup(title: "Tools", keys: [
            Key(command: .presenter, caption: "Draw", name: "Zoom & Draw", symbol: "scribble.variable"),
            Key(command: .stepRecorder, caption: "Steps", name: "Step Recorder", symbol: "cursorarrow.click.2",
                active: ("Stop", "Stop Step Recorder")),
            Key(command: .stepGuide, caption: "Guide", name: "Step Guide", symbol: "list.number"),
            Key(command: .watchArea, caption: "Watch", name: "Watch This Area", symbol: "eye",
                active: ("Stop", "Stop Watching")),
        ]),
        KeyGroup(title: "Help", keys: [
            Key(command: .keyboardShortcuts, caption: "Keys", name: "Keyboard Shortcuts", symbol: "command"),
            Key(command: .welcomeGuide, caption: "Welcome", name: "Welcome Guide", symbol: "hand.wave"),
            Key(command: .whatsNew, caption: "New", name: "What's New", symbol: "sparkles"),
            Key(command: .checkForUpdates, caption: "Update", name: "Check for Updates", symbol: "arrow.down.circle"),
            Key(command: .about, caption: "About", name: "About Skreener", symbol: "info.circle"),
        ]),
    ]

    /// The trays under the recent captures, top to bottom. Compact has only the everyday tray, plus a Running tray
    /// while something `active` runs that only Expanded has a key for (a watch), so it can still be stopped.
    static func keyGroups(for mode: MenuBarMode, active: Set<MenuCommand> = []) -> [KeyGroup] {
        switch mode {
        case .expanded:
            return expandedGroups + [everyday]
        case .compact:
            let running = expandedGroups.flatMap(\.keys).filter { $0.active != nil && active.contains($0.command) }
            return (running.isEmpty ? [] : [KeyGroup(title: "Running", keys: running)]) + [everyday]
        }
    }

    /// The LCD's text with the pointer on no key.
    struct Resting: Equatable {
        let left: String
        let right: String
        /// A newer release is out: the lamp is lit and a click on the LCD shows it.
        let update: Bool
    }

    /// The version, and what the last update check found: "v1.11.2 · UP TO DATE", "UPDATE 1.12.0", or just the
    /// version before any check has finished.
    nonisolated static func resting(version: String, status: Updater.Status) -> Resting {
        let shown = version.first?.isNumber == true ? "v\(version)" : version.uppercased()
        switch status {
        case .unknown: return Resting(left: "Skreener", right: shown, update: false)
        case .upToDate: return Resting(left: "Skreener", right: "\(shown) · UP TO DATE", update: false)
        case .available(let new): return Resting(left: "Skreener", right: "UPDATE \(new)", update: true)
        }
    }

    private static let padding: CGFloat = 12
    private static let gap: CGFloat = 6
    private static let lcdHeight: CGFloat = 24
    /// The room between the tray's edge and the cells, and between cells.
    private static let trayPadding: CGFloat = 6
    private static let cellGap: CGFloat = 4
    private static let cellSize = NSSize(width: 85, height: 58)
    private static let headerHeight: CGFloat = 20
    /// Between the trays of small keys, and between a tray's caption and the tray.
    private static let groupGap: CGFloat = 10
    private static let groupCaptionHeight: CGFloat = 14
    static let width = padding * 2 + trayPadding * 2 + cellSize.width * CGFloat(columns) + cellGap * CGFloat(columns - 1)
    private static let thumbWidth = ((width - padding * 2 - gap * CGFloat(recentCount - 1)) / CGFloat(recentCount)).rounded(.down)

    /// Thumbnails already made, by file, with the file's modification date (an edited capture is written again).
    private static var thumbnails: [URL: (date: Date, image: NSImage)] = [:]
    /// Pixel sizes ("1440×900") already read, by file and the file's modification date.
    private static var sizes: [URL: (date: Date, text: String?)] = [:]

    /// Runs a tile's capture mode; set by the app delegate.
    var onTile: ((HotKeyAction) -> Void)?
    var onShowHistory: (() -> Void)?
    /// Runs a small key's command, or the LCD's `.showUpdate`; set by the app delegate.
    var onCommand: ((MenuCommand) -> Void)?
    /// Whether a key that turns something on and off is on now (a watch, the Step Recorder); asked as the menu opens.
    var isActive: ((MenuCommand) -> Bool)?

    private var tileViews: [LauncherTile] = []
    private let lcd = LauncherLCD()
    private let recentLabel = RetroLabel(caption: "Recent")
    private let showAll = LauncherChip(title: "Show All")
    private let emptyHint = RetroLabel(text: "Your captures will show up here.", size: 11)
    private var thumbViews: [RecentThumb] = []
    /// Where the sunken tray round the capture keys is.
    private var trayRect = NSRect.zero
    /// The small keys' trays as laid out by the last `refresh()`, with their captions and keys.
    private var keyWells: [NSRect] = []
    private var groupViews: [NSView] = []
    /// What to run once the menu has closed (`runAfterMenuCloses`).
    private var pending: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        lcd.frame = NSRect(x: Self.padding, y: Self.padding, width: Self.width - Self.padding * 2, height: Self.lcdHeight)
        lcd.onClick = { [weak self] in self?.runAfterMenuCloses { self?.onCommand?(.showUpdate) } }
        addSubview(lcd)
        let rows = (Self.tiles.count + Self.columns - 1) / Self.columns
        trayRect = NSRect(x: Self.padding, y: Self.padding + Self.lcdHeight + Self.gap + 2, width: Self.width - Self.padding * 2,
                          height: Self.trayPadding * 2 + Self.cellSize.height * CGFloat(rows) + Self.cellGap * CGFloat(rows - 1))
        for (i, tile) in Self.tiles.enumerated() {
            let view = LauncherTile(title: tile.title, symbol: tile.symbol, variant: tile.action == .recordScreen ? .orange : .cream)
            let col = i % Self.columns, row = i / Self.columns
            view.frame = NSRect(x: trayRect.minX + Self.trayPadding + CGFloat(col) * (Self.cellSize.width + Self.cellGap),
                                y: trayRect.minY + Self.trayPadding + CGFloat(row) * (Self.cellSize.height + Self.cellGap),
                                width: Self.cellSize.width, height: Self.cellSize.height)
            let action = tile.action
            view.onClick = { [weak self] in self?.runAfterMenuCloses { self?.onTile?(action) } }
            view.onHover = { [weak self] tile in self?.lcd.show(tile.map { ($0.title, $0.shortcut ?? "") }) }
            addSubview(view)
            tileViews.append(view)
        }

        // The labels are placed by frame, like the rest of the launcher.
        for label in [recentLabel, emptyHint] {
            label.translatesAutoresizingMaskIntoConstraints = true
            addSubview(label)
        }
        showAll.onClick = { [weak self] in self?.showAllClicked() }
        addSubview(showAll)

        for i in 0..<Self.recentCount {
            let thumb = RecentThumb(frame: NSRect(x: Self.padding + CGFloat(i) * (Self.thumbWidth + Self.gap), y: 0,
                                                  width: Self.thumbWidth, height: RecentThumb.height))
            addSubview(thumb)
            thumbViews.append(thumb)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        // Square: the menu has its own edge.
        Retro.drawPlate(bounds, radius: 0, palette: p, flipped: true)
        Retro.drawWell(trayRect, radius: 10, palette: p, flipped: true)
        for well in keyWells { Retro.drawWell(well, radius: 8, palette: p, flipped: true) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Called as the menu opens: the shortcuts as they are set now, the newest captures, the update check's news, and
    /// the trays of the mode chosen in Settings → Menu Bar.
    func refresh() {
        for (view, tile) in zip(tileViews, Self.tiles) {
            view.shortcut = ShortcutStore.combo(for: tile.action)?.displayString
            view.endHover()   // the menu closed under the pointer without a mouseExited
        }
        lcd.resting = Self.resting(version: Updater.currentVersion, status: Updater.status)
        lcd.show(nil)
        thumbViews.forEach { $0.endHover() }
        showAll.endHover()
        var bottom = layoutRecent(below: trayRect.maxY)
        bottom = layoutKeys(below: bottom)
        setFrameSize(NSSize(width: Self.width, height: bottom + Self.padding))
        needsDisplay = true
    }

    /// The Recent row under `top` (hidden when Capture History is off); returns its bottom.
    private func layoutRecent(below top: CGFloat) -> CGFloat {
        guard Preferences.keepHistory else {
            ([recentLabel, showAll, emptyHint] as [NSView]).forEach { $0.isHidden = true }
            thumbViews.forEach { $0.isHidden = true }
            return top
        }
        let entries = Array(CaptureHistory.entries().prefix(Self.recentCount))
        let headerY = top + Self.padding
        recentLabel.isHidden = false
        recentLabel.sizeToFit()
        recentLabel.setFrameOrigin(NSPoint(x: Self.padding, y: headerY + (Self.headerHeight - recentLabel.frame.height) / 2))
        showAll.isHidden = entries.isEmpty
        showAll.setFrameOrigin(NSPoint(x: Self.width - Self.padding - showAll.frame.width, y: headerY))
        let rowY = headerY + Self.headerHeight + Self.gap
        emptyHint.isHidden = !entries.isEmpty
        emptyHint.sizeToFit()
        emptyHint.setFrameOrigin(NSPoint(x: Self.padding, y: rowY))
        for (i, view) in thumbViews.enumerated() {
            view.setFrameOrigin(NSPoint(x: view.frame.minX, y: rowY))
            guard i < entries.count else { view.isHidden = true; view.url = nil; continue }
            let entry = entries[i]
            view.isHidden = false
            view.show(entry, image: Self.cachedThumbnail(entry.url), size: Self.pixelSize(entry.url))
            if view.image == nil { loadThumbnail(entry.url, into: view) }
            view.onClick = { [weak self] in self?.runAfterMenuCloses { MenuLauncher.open(entry.url) } }
        }
        return rowY + (entries.isEmpty ? emptyHint.frame.height : RecentThumb.height)
    }

    /// The trays of small keys under `top`, built afresh (the mode and what is running may have changed since the
    /// menu last opened); returns the bottom of the last.
    private func layoutKeys(below top: CGFloat) -> CGFloat {
        groupViews.forEach { $0.removeFromSuperview() }
        groupViews = []
        keyWells = []
        let active = Set(Self.expandedGroups.flatMap(\.keys).map(\.command).filter { isActive?($0) == true })
        var y = top
        for group in Self.keyGroups(for: Preferences.menuBarMode, active: active) {
            y += Self.groupGap
            if let title = group.title {
                let label = RetroLabel(caption: title, tone: .soft)
                label.translatesAutoresizingMaskIntoConstraints = true
                label.sizeToFit()
                label.setFrameOrigin(NSPoint(x: Self.padding + 2, y: y + (Self.groupCaptionHeight - label.frame.height) / 2))
                addSubview(label)
                groupViews.append(label)
                y += Self.groupCaptionHeight + 2
            }
            let well = NSRect(x: Self.padding, y: y, width: Self.width - Self.padding * 2,
                              height: Self.trayPadding * 2 + LauncherKey.height)
            keyWells.append(well)
            let count = CGFloat(max(group.keys.count, 1))
            let keyWidth = ((well.width - Self.trayPadding * 2 - Self.cellGap * (count - 1)) / count).rounded(.down)
            // Centred, so a tray of four keys sits as evenly as one of five.
            let used = keyWidth * count + Self.cellGap * (count - 1)
            var x = well.minX + (well.width - used) / 2
            for key in group.keys {
                let view = LauncherKey(key, active: active.contains(key.command))
                view.frame = NSRect(x: x, y: well.minY + Self.trayPadding, width: keyWidth, height: LauncherKey.height)
                view.shortcut = key.command.menuShortcut ?? key.command.hotKey.flatMap { ShortcutStore.combo(for: $0)?.displayString }
                let command = key.command
                view.onClick = { [weak self] in self?.runAfterMenuCloses { self?.onCommand?(command) } }
                view.onHover = { [weak self] key in self?.lcd.show(key.map { ($0.name, $0.shortcut ?? "") }) }
                addSubview(view)
                groupViews.append(view)
                x += keyWidth + Self.cellGap
            }
            y = well.maxY
        }
        return y
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func cachedThumbnail(_ url: URL) -> NSImage? {
        guard let cached = thumbnails[url], cached.date == modified(url) else { return nil }
        return cached.image
    }

    /// The capture's size in pixels as a label ("1440×900"), read from the file's header; nil if it has none.
    private static func pixelSize(_ url: URL) -> String? {
        let date = modified(url)
        if let known = sizes[url], known.date == date { return known.text }
        var text: String?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            text = "\(w)×\(h)"
        }
        // Forget captures that have left the history.
        if sizes.count > recentCount * 3 { sizes = sizes.filter { FileManager.default.fileExists(atPath: $0.key.path) } }
        sizes[url] = (date, text)
        return text
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

    private func showAllClicked() {
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

/// The strip of olive glass at the top: the version and the update check's news (`MenuLauncher.resting`), or the name
/// and shortcut of the key under the pointer. With a newer release out its lamp is lit and a click shows the update.
private final class LauncherLCD: NSView {
    var onClick: (() -> Void)?
    var resting = MenuLauncher.Resting(left: "Skreener", right: "", update: false) {
        didSet {
            guard resting != oldValue else { return }
            setAccessibilityElement(resting.update)
            setAccessibilityLabel(resting.update ? "\(resting.right.capitalized) available" : nil)
            setAccessibilityHelp(resting.update ? "Shows the update" : nil)
            toolTip = resting.update ? "Show the update" : nil
            needsDisplay = true
        }
    }
    /// The key under the pointer: its name and shortcut.
    private var hovered: (String, String)?

    override var isFlipped: Bool { true }
    /// Clicks go through to the plate unless there is an update to show.
    override func hitTest(_ point: NSPoint) -> NSView? { resting.update ? super.hitTest(point) : nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The name and shortcut of the key under the pointer, or nil for the resting text.
    func show(_ key: (String, String)?) {
        guard key?.0 != hovered?.0 || key?.1 != hovered?.1 else { return }
        hovered = key
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.drawGlass(bounds, radius: 6, brightness: p.lcdBrightness, shadowBlur: 3, flipped: true)
        let ink = Retro.color(Retro.lcdInk)
        let (left, right) = hovered ?? (resting.left, resting.right)
        let title = Retro.caption(left, color: ink, font: .systemFont(ofSize: 9.5, weight: .heavy), kern: 1.1)
        title.draw(at: NSPoint(x: 10, y: (bounds.height - title.size().height) / 2))
        let update = hovered == nil && resting.update
        let detail = NSAttributedString(string: right, attributes: [
            .font: Retro.mono(10, weight: update ? .bold : .semibold), .foregroundColor: ink.withAlphaComponent(update ? 1 : 0.8),
        ])
        let size = detail.size()
        let x = bounds.maxX - 10 - size.width
        detail.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
        if update {
            // No glow on the glass, as on the other LCDs' lamps.
            Retro.drawLamp(in: NSRect(x: x - 11, y: bounds.midY - 3, width: 6, height: 6), color: Retro.color(Retro.orange),
                           lit: true, glow: 0)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard resting.update, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard resting.update else { return false }
        onClick?()
        return true
    }
}

/// One capture mode: a cream key (orange for Record) with its symbol and a lamp that lights while the pointer is over it,
/// and the name and shortcut under it.
private final class LauncherTile: NSView {
    var onClick: (() -> Void)?
    /// The pointer came onto the tile, or (nil) left it.
    var onHover: ((LauncherTile?) -> Void)?
    let title: String
    var shortcut: String? {
        didSet {
            shortcutLabel.stringValue = shortcut ?? " "
            setAccessibilityHelp(shortcut.map { "Shortcut: \($0)" })
        }
    }

    private static let keyHeight: CGFloat = 34
    private let variant: Retro.KeyVariant
    private let icon = NSImageView()
    private let nameLabel: RetroLabel
    private let shortcutLabel = RetroLabel(text: " ", tone: .soft, size: 9)
    private var iconCenter: NSLayoutConstraint?
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            iconCenter?.constant = Self.iconY(down: hovering)
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    /// The symbol's centre from the tile's top: the middle of the key's face, which sinks onto the skirt when pressed.
    private static func iconY(down: Bool) -> CGFloat { (keyHeight - PillButton.keycapSkirt) / 2 + (down ? PillButton.keycapSkirt : 0) }

    init(title: String, symbol: String, variant: Retro.KeyVariant) {
        self.title = title
        self.variant = variant
        nameLabel = RetroLabel(caption: title)
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.imageScaling = .scaleNone
        shortcutLabel.font = Retro.mono(9, weight: .medium)
        nameLabel.alignment = .center
        shortcutLabel.alignment = .center
        nameLabel.setAccessibilityElement(false)
        shortcutLabel.setAccessibilityElement(false)
        for v in [icon, nameLabel, shortcutLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let center = icon.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.iconY(down: false))
        iconCenter = center
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            center,
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.keyHeight + 2),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            shortcutLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            shortcutLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
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
        icon.contentTintColor = Retro.keyColors(variant, Retro.palette(for: self)).ink
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = Retro.keyColors(variant, Retro.palette(for: self))
        let key = NSRect(x: 0, y: 0, width: bounds.width, height: Self.keyHeight)
        let face = Retro.drawKey(in: key, radius: PillButton.keycapRadius + 1, colors: colors, down: hovering, flipped: true)
        Retro.drawLamp(in: NSRect(x: face.maxX - 10, y: face.minY + 5, width: 4, height: 4),
                       color: Retro.color(variant == .orange ? 0xffffff : Retro.teal), lit: hovering)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        needsDisplay = true
    }

    func endHover() { hovering = false }
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover?(self)
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        onHover?(nil)
    }
    // A press that started on the menu-bar icon and was let go here counts too, as for any menu item.
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        hovering = false
        onClick?()
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// A small key in one of the trays under the recent captures: its symbol on it, a short caption under it, and a lamp
/// on keys that turn something on and off, lit while it is on. The LCD shows its full name and shortcut.
private final class LauncherKey: NSView {
    static let keyHeight: CGFloat = 26
    static let height: CGFloat = keyHeight + 14

    var onClick: (() -> Void)?
    /// The pointer came onto the key, or (nil) left it.
    var onHover: ((LauncherKey?) -> Void)?
    let name: String
    var shortcut: String? {
        didSet { setAccessibilityHelp(shortcut.map { "Shortcut: \($0)" }) }
    }

    private let caption: String
    private let variant: Retro.KeyVariant
    /// Whether the key has a lamp, and whether it is lit.
    private let hasLamp: Bool
    private let active: Bool
    private let icon = NSImageView()
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            needsLayout = true
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    init(_ key: MenuLauncher.Key, active: Bool) {
        let on = active ? key.active : nil
        name = on?.name ?? key.name
        caption = on?.caption ?? key.caption
        variant = key.variant
        hasLamp = key.active != nil
        self.active = active
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        icon.image = NSImage(systemSymbolName: key.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.imageScaling = .scaleNone
        addSubview(icon)
        applyColors()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(name)
        toolTip = name
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyColors() {
        icon.contentTintColor = Retro.keyColors(variant, Retro.palette(for: self)).ink
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // The middle of the key's face, which sinks onto the skirt while the pointer is over it.
        let face = Retro.keyFace(in: NSRect(x: 0, y: 0, width: bounds.width, height: Self.keyHeight), down: hovering, flipped: true)
        icon.frame = face
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let colors = Retro.keyColors(variant, p)
        let face = Retro.drawKey(in: NSRect(x: 0, y: 0, width: bounds.width, height: Self.keyHeight),
                                 radius: PillButton.keycapRadius, colors: colors, down: hovering, flipped: true)
        if hasLamp {
            Retro.drawLamp(in: NSRect(x: face.maxX - 8, y: face.minY + 4, width: 4, height: 4),
                           color: Retro.color(Retro.recRed), lit: active)
        }
        // The caption, made smaller until it fits the key's width.
        var size: CGFloat = 8
        var text = Retro.caption(caption, color: Retro.color(p.ink), font: .systemFont(ofSize: size, weight: .semibold), kern: 0.4)
        while text.size().width > bounds.width - 2, size > 6 {
            size -= 0.5
            text = Retro.caption(caption, color: Retro.color(p.ink), font: .systemFont(ofSize: size, weight: .semibold), kern: 0.3)
        }
        let extent = text.size()
        text.draw(at: NSPoint(x: (bounds.width - extent.width) / 2, y: Self.keyHeight + 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover?(self)
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        onHover?(nil)
    }
    // A press that started on the menu-bar icon and was let go here counts too, as for any menu item.
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        hovering = false
        onClick?()
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// A small cream key with a caption on it (Show All).
private final class LauncherChip: NSView {
    var onClick: (() -> Void)?
    private let title: String
    private var hovering = false {
        didSet { if hovering != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    init(title: String) {
        self.title = title
        let width = ceil(Retro.caption(title, color: .black, kern: 0.6).size().width) + 20
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 20))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        toolTip = "Show every capture in the history"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let colors = Retro.keyColors(.cream, Retro.palette(for: self))
        let face = Retro.drawKey(in: bounds, radius: PillButton.keycapRadius, colors: colors, down: hovering, flipped: true)
        let text = Retro.caption(title, color: colors.ink, kern: 0.6)
        let size = text.size()
        text.draw(at: NSPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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

/// One of the newest captures in a sunken well, with its size in mono under it; a click opens it in the editor.
private final class RecentThumb: NSView {
    /// The well's height, and with the size label under it the view's.
    private static let wellHeight: CGFloat = 46
    static let height: CGFloat = wellHeight + 14

    var onClick: (() -> Void)?
    var url: URL?
    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    private let imageView = NSImageView()
    private var size: String? { didSet { needsDisplay = true } }
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    private var hovering = false {
        didSet { if hovering != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.frame = NSRect(x: 4, y: 4, width: frame.width - 8, height: Self.wellHeight - 8)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 3
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ entry: CaptureHistory.Entry, image: NSImage?, size: String?) {
        url = entry.url
        self.image = image
        self.size = size
        let when = Self.relative.localizedString(for: entry.date, relativeTo: Date())
        toolTip = "Open in the editor (captured \(when))"
        setAccessibilityLabel("Capture from \(when)")
        setAccessibilityHelp(size.map { "\($0) pixels" })
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let well = NSRect(x: 0, y: 0, width: bounds.width, height: Self.wellHeight)
        Retro.drawWell(well, radius: 6, top: Retro.color(p.bezelTop), bottom: Retro.color(p.bezelBottom), shadow: p.wellShadow,
                       lip: p.wellLip, flipped: true)
        if hovering {
            let ring = NSBezierPath(roundedRect: well.insetBy(dx: 0.75, dy: 0.75), xRadius: 5.5, yRadius: 5.5)
            ring.lineWidth = 1.5
            Retro.color(Retro.orange).setStroke()
            ring.stroke()
        }
        if let size {
            let text = NSAttributedString(string: size, attributes: [.font: Retro.mono(8), .foregroundColor: Retro.color(p.inkSoft)])
            let extent = text.size()
            text.draw(at: NSPoint(x: bounds.midX - extent.width / 2, y: Self.wellHeight + 3))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
