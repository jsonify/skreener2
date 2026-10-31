import AppKit
import ImageIO

/// The top of the menu-bar menu, in the SK-1 look (#344): a slim LCD strip, six everyday capture modes as keys in a sunken
/// tray (Record the orange one), each with its name and shortcut under it, and the newest captures from the history in
/// sunken wells, one click from the editor. Every capture mode is still under All Capture Modes below it, where the
/// keyboard reaches them.
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
    private static let lcdHeight: CGFloat = 24
    /// The room between the tray's edge and the cells, and between cells.
    private static let trayPadding: CGFloat = 6
    private static let cellGap: CGFloat = 4
    private static let cellSize = NSSize(width: 85, height: 58)
    private static let headerHeight: CGFloat = 20
    static let width = padding * 2 + trayPadding * 2 + cellSize.width * CGFloat(columns) + cellGap * CGFloat(columns - 1)
    private static let thumbWidth = ((width - padding * 2 - gap * CGFloat(recentCount - 1)) / CGFloat(recentCount)).rounded(.down)

    /// Thumbnails already made, by file, with the file's modification date (an edited capture is written again).
    private static var thumbnails: [URL: (date: Date, image: NSImage)] = [:]
    /// Pixel sizes ("1440×900") already read, by file and the file's modification date.
    private static var sizes: [URL: (date: Date, text: String?)] = [:]

    /// Runs a tile's capture mode; set by the app delegate.
    var onTile: ((HotKeyAction) -> Void)?
    var onShowHistory: (() -> Void)?

    private var tileViews: [LauncherTile] = []
    private let lcd = LauncherLCD()
    private let recentLabel = RetroLabel(caption: "Recent")
    private let showAll = LauncherChip(title: "Show All")
    private let emptyHint = RetroLabel(text: "Your captures will show up here.", size: 11)
    private var thumbViews: [RecentThumb] = []
    /// Where the sunken tray round the keys is.
    private var trayRect = NSRect.zero
    /// What to run once the menu has closed (`runAfterMenuCloses`).
    private var pending: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        lcd.frame = NSRect(x: Self.padding, y: Self.padding, width: Self.width - Self.padding * 2, height: Self.lcdHeight)
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
            view.onHover = { [weak self] tile in self?.lcd.show(tile) }
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
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Called as the menu opens: the shortcuts as they are set now, and the newest captures.
    func refresh() {
        for (view, tile) in zip(tileViews, Self.tiles) {
            view.shortcut = ShortcutStore.combo(for: tile.action)?.displayString
            view.endHover()   // the menu closed under the pointer without a mouseExited
        }
        lcd.show(nil)
        thumbViews.forEach { $0.endHover() }
        showAll.endHover()
        let gridBottom = trayRect.maxY
        guard Preferences.keepHistory else {
            ([recentLabel, showAll, emptyHint] as [NSView]).forEach { $0.isHidden = true }
            thumbViews.forEach { $0.isHidden = true }
            setFrameSize(NSSize(width: Self.width, height: gridBottom + Self.padding))
            return
        }
        let entries = Array(CaptureHistory.entries().prefix(Self.recentCount))
        let headerY = gridBottom + Self.padding
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
        let rowHeight = entries.isEmpty ? emptyHint.frame.height : RecentThumb.height
        setFrameSize(NSSize(width: Self.width, height: rowY + rowHeight + Self.padding))
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

/// The strip of olive glass at the top: READY, or the name and shortcut of the key under the pointer.
private final class LauncherLCD: NSView {
    private var left = "Ready"
    private var right = "Pick a mode"

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The key under the pointer, or nil for the resting text.
    func show(_ tile: LauncherTile?) {
        let new = tile.map { ($0.title, $0.shortcut ?? "") } ?? ("Ready", "Pick a mode")
        guard new.0 != left || new.1 != right else { return }
        (left, right) = new
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        Retro.drawGlass(bounds, radius: 6, brightness: p.lcdBrightness, shadowBlur: 3, flipped: true)
        let ink = Retro.color(Retro.lcdInk)
        let title = Retro.caption(left, color: ink, font: .systemFont(ofSize: 9.5, weight: .heavy), kern: 1.1)
        title.draw(at: NSPoint(x: 10, y: (bounds.height - title.size().height) / 2))
        let detail = NSAttributedString(string: right, attributes: [.font: Retro.mono(10), .foregroundColor: ink.withAlphaComponent(0.8)])
        let size = detail.size()
        detail.draw(at: NSPoint(x: bounds.maxX - 10 - size.width, y: (bounds.height - size.height) / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
