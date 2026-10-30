import AppKit
import ImageIO
import QuickLookThumbnailing

extension Notification.Name {
    /// Posted when a capture is added to or removed from the history.
    static let skreenerHistoryChanged = Notification.Name("SkreenerHistoryChanged")
}

/// Every capture is kept as a PNG in Application Support, newest first, so the history panel can show,
/// copy, re-open or delete it. Only the newest `limit` captures are kept (Settings → After Capture).
enum CaptureHistory {
    struct Entry {
        let url: URL
        let date: Date
    }

    /// How many captures are kept; nil keeps them all.
    static var limit: Int? { Preferences.historyLimit > 0 ? Preferences.historyLimit : nil }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Skreener/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writing and document saving share one queue, so a document is never saved before its capture's PNG exists.
    private static let queue = DispatchQueue(label: "skreener.history", qos: .utility)

    /// Encodes and writes in the background so a large capture never holds up the Quick Access thumbnail. Returns the
    /// file the capture will be in, for the editor to save its document against (#30).
    @discardableResult
    static func add(_ image: NSImage) -> URL? {
        guard Preferences.keepHistory, let tiff = image.tiffRepresentation else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let url = directory.appendingPathComponent("Skreener \(f.string(from: Date())).png")
        queue.async {
            guard let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            do { try data.write(to: url) } catch { NSLog("History save failed: \(error)"); return }
            prune()
            DispatchQueue.main.async { NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil) }
        }
        return url
    }

    /// Keeps the web page the capture in `png` came from (#269) as the file's "Where from", which the panel reads back.
    /// On the writing queue, so it comes after the PNG exists.
    static func noteSource(_ page: SourcePage.Page, for png: URL) {
        queue.async {
            guard FileManager.default.fileExists(atPath: png.path) else { return }
            SourcePage.writeWhereFroms(page.url, to: png)
            DispatchQueue.main.async { NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil) }
        }
    }

    // MARK: Editable documents (#30)

    /// Where the editor document of the capture in `png` lives: a folder beside it, which `entries()` doesn't list.
    static func documentFolder(for png: URL) -> URL { png.deletingPathExtension().appendingPathExtension("skreener") }

    /// The capture's saved screenshot and annotations, if the editor kept them.
    static func document(for png: URL) -> (base: NSImage, document: EditorDocument)? {
        EditorDocument.read(from: documentFolder(for: png))
    }

    /// Keeps `document` for the capture in `png` and replaces the PNG with `flattened`, the capture as it now looks (for
    /// thumbnails, copying and Add Image). `base` is the editor's screenshot, passed only when it changed since last time.
    static func saveDocument(_ document: EditorDocument, base: NSImage?, flattened: NSImage, for png: URL) {
        let tiff = flattened.tiffRepresentation
        let baseTIFF = base?.tiffRepresentation
        queue.async {
            let fm = FileManager.default
            // Pruned or deleted since the editor opened: leave nothing behind.
            guard fm.fileExists(atPath: png.path) else { return }
            let folder = documentFolder(for: png)
            do {
                try document.write(to: folder, base: baseTIFF.flatMap { NSImage(data: $0) })
                // In place (not atomically), so the capture keeps its creation date and its place in the history.
                if let data = tiff.flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }) {
                    try data.write(to: png)
                }
            } catch { NSLog("History document save failed: \(error)"); return }
            if !fm.fileExists(atPath: png.path) { try? fm.removeItem(at: folder) }
            DispatchQueue.main.async { NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil) }
        }
    }

    /// Removes a capture and its editor document.
    static func remove(_ png: URL) {
        try? FileManager.default.removeItem(at: png)
        try? FileManager.default.removeItem(at: documentFolder(for: png))
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

    /// Deletes the oldest captures past `limit` (right away when the limit is lowered).
    static func prune() {
        guard let limit else { return }
        for old in entries().dropFirst(limit) { remove(old.url) }
    }

    static func delete(_ entry: Entry) {
        remove(entry.url)
        NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil)
    }

    static func clear() {
        entries().forEach { remove($0.url) }
        NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil)
    }

    /// A small thumbnail of any file the panel shows: images decode only what they need; recordings and anything
    /// ImageIO can't read go through Quick Look. Calls back on the main thread.
    static func thumbnail(_ url: URL, maxPixels: Int, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let img = thumbnail(url, maxPixels: maxPixels) {
                DispatchQueue.main.async { completion(img) }
                return
            }
            let side = CGFloat(maxPixels) / 2
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2,
                                                       representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                let img = rep?.nsImage
                DispatchQueue.main.async { completion(img) }
            }
        }
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
    /// The panel hangs from the top of the screen: the chassis behind it must not drag it away (#344).
    override func performDrag(with event: NSEvent) {}
}

/// CleanShot-style capture history that slides down from the top of the screen, with two views: History (recent
/// captures) and Saved Files (the export location, indexed by `SavedLibrary`, with search and filters, #117).
/// Hover a capture for its actions, double-click to edit, right-click for more, ⌘-click to select several, drag it out
/// as a file. Esc, a click elsewhere, or the menu item again slides it away.
final class CaptureHistoryPanel: NSObject, NSSearchFieldDelegate {
    static let shared = CaptureHistoryPanel()
    /// Capture buttons along the top (set by the app): symbol, name, action. The panel slides away before they run.
    static var captureActions: [(symbol: String, title: String, run: () -> Void)] = []

    enum Mode: Int { case history, library }
    /// One thing the panel shows: a capture in the history, or a file in the export location.
    struct Item {
        let url: URL
        let date: Date
        let kind: SavedLibrary.Kind
        let inLibrary: Bool
        /// The web page a browser capture came from (#269).
        let sourceURL: URL?
    }

    private var panel: HistoryPanel?
    private let strip = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let modeControl = RetroSegmented()
    private let filterRow = NSStackView()
    private let searchField = NSSearchField()
    private let monthPopup = RetroUI.menuKey(tip: "Only files from this month", target: nil, action: nil)
    private let appPopup = RetroUI.menuKey(tip: "Only captures of this app", target: nil, action: nil)
    private let sitePopup = RetroUI.menuKey(tip: "Only captures of this site", target: nil, action: nil)
    private let kindPopup = RetroUI.menuKey(tip: "Only this type of file", target: nil, action: nil)
    private let editedBox = RetroUI.toggle("Edited", tip: "Only files edited in Skreener", target: nil, action: nil)
    private let countLabel = RetroUI.hint()
    private var filterHeight: NSLayoutConstraint?
    private var cells: [HistoryCell] = []
    private var selection: Set<URL> = []
    private var monitors: [Any] = []
    private var shownFrame = NSRect.zero
    /// Bumped on every show, so a slide-out that finishes after the panel was shown again leaves it on screen.
    private var generation = 0
    /// At most this many files show at once; the search and filters narrow it down.
    private static let maxShown = 300

    private var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: "historyPanelMode")) ?? .history }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "historyPanelMode") }
    }
    private var tileSize: NSSize { HistoryCell.sizes[min(max(Preferences.libraryTileSize, 0), HistoryCell.sizes.count - 1)] }
    private var height: CGFloat { tileSize.height + 112 + (mode == .library ? 26 : 0) }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        shownFrame = frame(on: screen)
        let p = panel ?? makePanel()
        panel = p
        generation += 1
        selection = []
        applyMode()
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

    private func frame(on screen: NSScreen) -> NSRect {
        let width = min(screen.visibleFrame.width - 40, 1600)
        return NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.maxY - height - 8, width: width, height: height)
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

        // The SK-1 chassis, rounded at the corners; the thumbnails stay as they were.
        let bg = ChassisView()
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 16
        bg.layer?.masksToBounds = true

        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.addItem("History", tag: Mode.history.rawValue, help: "Recent captures")
        modeControl.addItem("Saved Files", tag: Mode.library.rawValue, help: "Screenshots in the export location")
        modeControl.setAccessibilityLabel("View")

        // Capture buttons, like the menu's; the panel slides away first.
        let captures = KeycapTray(Self.captureActions.enumerated().map { i, a in
            let b = RetroUI.key(symbol: a.symbol, tip: a.title, target: self, action: #selector(captureClicked(_:)))
            b.tag = i
            return b
        })
        captures.setAccessibilityLabel("Capture")

        // The menu is the pull-down's own: its first item (an ellipsis) is the face, a corner triangle says it opens.
        let more = PillPopUp(pullsDown: true, height: RetroUI.iconKeyHeight, style: .keycap)
        let menu = NSMenu()
        menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.item(at: 0)?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        menu.addItem(.sectionHeader(title: "Thumbnails"))
        for (i, t) in ["Small", "Medium", "Large"].enumerated() {
            let item = NSMenuItem(title: t, action: #selector(tileSizePicked(_:)), keyEquivalent: "")
            item.target = self; item.tag = i
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (t, sel) in [("Open History Folder", #selector(openFolder)), ("Open Export Location", #selector(openSaveFolder)),
                         ("Clear History…", #selector(clearHistory))] {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; menu.addItem(i)
        }
        menu.delegate = self
        more.menu = menu
        more.synchronizeTitleAndSelectedItem()
        more.toolTip = "More"
        more.setAccessibilityLabel("More")

        let close = RetroUI.key(symbol: "xmark", tip: "Close (Esc)", target: self, action: #selector(closeIt))

        buildFilterRow()
        filterHeight = filterRow.heightAnchor.constraint(equalToConstant: 0)

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

        [modeControl, captures, more, close, filterRow, scroll, emptyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; bg.addSubview($0)
        }
        NSLayoutConstraint.activate([
            modeControl.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 18),
            captures.topAnchor.constraint(equalTo: bg.topAnchor, constant: 10),
            captures.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            modeControl.centerYAnchor.constraint(equalTo: captures.centerYAnchor, constant: -1),
            close.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            close.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            more.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            more.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            filterRow.topAnchor.constraint(equalTo: captures.bottomAnchor, constant: 10),
            filterRow.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 18),
            filterRow.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -18),
            filterHeight!,
            scroll.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 10),
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

        let nc = NotificationCenter.default
        nc.addObserver(forName: .skreenerHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            if self?.isVisible == true, self?.mode == .history { self?.reload() }
        }
        nc.addObserver(forName: .skreenerLibraryChanged, object: nil, queue: .main) { [weak self] _ in
            if self?.isVisible == true, self?.mode == .library { self?.refreshFilters(); self?.reload() }
        }
        return p
    }

    private func buildFilterRow() {
        searchField.placeholderString = "Search names, apps, pages and text in screenshots"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        for popup in [monthPopup, appPopup, sitePopup, kindPopup] {
            popup.target = self; popup.action = #selector(filterChanged)
        }
        editedBox.target = self; editedBox.action = #selector(editedToggled(_:))
        filterRow.alignment = .centerY
        [searchField, monthPopup, appPopup, sitePopup, kindPopup, editedBox, countLabel].forEach(filterRow.addArrangedSubview)
        filterRow.spacing = 8
    }

    /// Shows the view picked (History or Saved Files) at the current tile size.
    private func applyMode() {
        modeControl.selectItem(withTag: mode.rawValue)
        filterRow.isHidden = mode != .library
        filterHeight?.constant = mode == .library ? 26 : 0
        if mode == .library {
            SavedLibrary.shared.refresh()
            refreshFilters()
        }
        if let p = panel, p.isVisible || shownFrame.height != height, let screen = p.screen ?? NSScreen.main {
            shownFrame = frame(on: screen)
            if p.isVisible { p.setFrame(shownFrame, display: true, animate: true) }
        }
        reload()
    }

    /// Fills the Month, App, Site and Type filters from the files there, with how many each has; keeps what was picked.
    private func refreshFilters() {
        let entries = SavedLibrary.shared.entries
        func fill(_ popup: PillPopUp, all: String, _ values: [(value: String, count: Int)], title: (String) -> String) {
            let picked = popup.selectedItem?.representedObject as? String
            popup.removeAllItems()
            popup.addItem(withTitle: all)
            for v in values {
                popup.addItem(withTitle: "\(title(v.value)) (\(v.count))")
                popup.lastItem?.representedObject = v.value
            }
            if let picked, let i = popup.itemArray.firstIndex(where: { $0.representedObject as? String == picked }) {
                popup.selectItem(at: i)
            }
        }
        let monthName = DateFormatter()
        monthName.dateFormat = "MMMM yyyy"
        let months = SavedLibrary.counts(entries) { $0.month }.sorted { $0.value > $1.value }
        fill(monthPopup, all: "Any Month", months) { key in
            SavedLibrary.Entry.monthKey.date(from: key).map(monthName.string(from:)) ?? key
        }
        fill(appPopup, all: "Any App", SavedLibrary.counts(entries) { $0.meta.app }) { $0 }
        fill(sitePopup, all: "Any Site", SavedLibrary.counts(entries) { $0.meta.host }) { $0 }
        fill(kindPopup, all: "Any Type", SavedLibrary.counts(entries) { $0.kind.rawValue }) {
            SavedLibrary.Kind(rawValue: $0)?.title ?? $0
        }
    }

    private var query: SavedLibrary.Query {
        SavedLibrary.Query(text: searchField.stringValue,
                           month: monthPopup.selectedItem?.representedObject as? String,
                           app: appPopup.selectedItem?.representedObject as? String,
                           site: sitePopup.selectedItem?.representedObject as? String,
                           kind: (kindPopup.selectedItem?.representedObject as? String).flatMap(SavedLibrary.Kind.init(rawValue:)),
                           editedOnly: editedBox.isOn)
    }

    private func reload() {
        strip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items: [Item]
        switch mode {
        case .history:
            items = CaptureHistory.entries().map {
                Item(url: $0.url, date: $0.date, kind: .image, inLibrary: false,
                     sourceURL: SourcePage.readWhereFroms(of: $0.url).flatMap(Self.pageURL))
            }
            emptyLabel.stringValue = "No captures yet. Screenshots you take show up here."
        case .library:
            let lib = SavedLibrary.shared
            let found = SavedLibrary.filter(lib.entries, query)
            items = found.prefix(Self.maxShown).map { Item(url: $0.url, date: $0.date, kind: $0.kind, inLibrary: true, sourceURL: Self.pageURL($0.meta.url)) }
            let total = lib.entries.count
            countLabel.stringValue = found.count > Self.maxShown ? "Showing \(Self.maxShown) of \(found.count): search to narrow it down"
                : found.count == total ? "\(total) files" : "\(found.count) of \(total) files"
            emptyLabel.stringValue = lib.isIndexing && total == 0 ? "Looking through the export location…"
                : total == 0 ? "No screenshots in the export location yet." : "Nothing matches."
        }
        selection = selection.filter { url in items.contains { $0.url == url } }
        emptyLabel.isHidden = !items.isEmpty
        cells = items.map { item in
            let cell = HistoryCell(item: item, size: tileSize)
            cell.onAction = { [weak self] action in self?.run(action, on: item) }
            cell.onClick = { [weak self] extend in self?.click(item, extend: extend) }
            cell.menuProvider = { [weak self] in self?.contextMenu(for: item) }
            cell.isSelected = selection.contains(item.url)
            strip.addArrangedSubview(cell)
            return cell
        }
    }

    /// The address as a link, if it is a web page.
    private static func pageURL(_ address: String?) -> URL? {
        address.flatMap { SourcePage.Page(url: $0) }.flatMap { URL(string: $0.url) }
    }

    // MARK: Selection

    /// A click selects just that capture; ⌘-click adds it to the selection or takes it out.
    private func click(_ item: Item, extend: Bool) {
        if extend {
            if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
        } else {
            selection = [item.url]
        }
        for c in cells { c.isSelected = selection.contains(c.item.url) }
    }

    /// What a right-click acts on: the selection when the item is part of it, else the item alone.
    private func targets(for item: Item) -> [Item] {
        guard selection.contains(item.url), selection.count > 1 else { return [item] }
        return cells.map(\.item).filter { selection.contains($0.url) }
    }

    // MARK: Actions

    private func run(_ action: HistoryCell.Action, on item: Item) {
        switch action {
        case .delete:
            delete([item])
            return
        case .reveal:
            reveal([item])
            return
        case .openSource:
            openSource(item)
            return
        case .edit where item.kind != .image, .copy where item.kind != .image:
            // Recordings and GIFs open in their own app; copying them copies the file.
            if action == .edit { hide(); NSWorkspace.shared.open(item.url) } else { copyFiles([item]) }
            return
        default:
            break
        }
        // A capture the editor kept a document for reopens with its annotations still editable (#30).
        let saved = item.inLibrary ? nil : CaptureHistory.document(for: item.url)
        guard let image = saved?.base ?? NSImage(contentsOf: item.url) else { NSSound.beep(); return }
        switch action {
        case .copy:
            Output.copy(image)
            Sound.play("Pop")
        case .edit:
            hide()
            // A saved file is saved again over itself (#118); a history capture is a copy, so it isn't.
            let editor = EditorWindowController(image: image, file: item.inLibrary ? item.url : nil)
            if !item.inLibrary { editor.attachHistory(item.url, document: saved?.document) }
            editor.present()
        case .pin:
            hide()
            PinnedScreenshotController.pin(image)
        case .save:
            hide()
            NSApp.activate(ignoringOtherApps: true)
            Output.saveAs(image)
        case .delete, .reveal, .openSource: break
        }
    }

    private func reveal(_ items: [Item]) {
        hide()
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    /// Opens the Combine Screenshots sheet with `items` ticked (#273).
    private func combine(_ items: [Item]) {
        hide()
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let candidates = items.map { item in
            var c = CombineScreenshots.candidate(url: item.url, title: f.localizedString(for: item.date, relativeTo: Date()))
            c.selected = true
            return c
        }
        CombineScreenshots.present(candidates, from: nil)
    }

    private func openSource(_ item: Item) {
        guard let url = item.sourceURL else { return }
        hide()
        NSWorkspace.shared.open(url)
    }

    private func copyFiles(_ items: [Item]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
        Sound.play("Pop")
    }

    /// History captures are deleted; files in the export location go to the Trash.
    private func delete(_ items: [Item]) {
        for item in items {
            if item.inLibrary {
                NSWorkspace.shared.recycle([item.url])
            } else {
                CaptureHistory.delete(CaptureHistory.Entry(url: item.url, date: item.date))
            }
        }
    }

    /// Compresses the files in the background, then says how much was saved (#279).
    private func compress(_ items: [Item]) {
        let files = items.map(\.url)
        let name = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        MessageHUD.show("Compressing…", detail: name, symbol: "arrow.down.right.and.arrow.up.left", placement: .top)
        Task { @MainActor in
            let savings = await Compressor.compress(files)
            Notifier.compressed(savings, name: name)
        }
    }

    private func contextMenu(for item: Item) -> NSMenu {
        let items = targets(for: item)
        let m = NSMenu()
        let n = items.count
        func add(_ title: String, _ run: @escaping () -> Void) {
            let i = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            let action = MenuAction(run)
            i.target = action; i.representedObject = action
            m.addItem(i)
        }
        if n == 1 {
            add(item.kind == .image ? "Open in Editor" : "Open") { [weak self] in self?.run(.edit, on: item) }
        }
        add(n == 1 ? "Open in Default App" : "Open \(n) Files in Default App") { [weak self] in
            self?.hide()
            items.forEach { NSWorkspace.shared.open($0.url) }
        }
        add("Show in Finder") { [weak self] in self?.reveal(items) }
        if n == 1, item.sourceURL != nil { add("Open Source Page") { [weak self] in self?.openSource(item) } }
        // Only files in the export folder: a history capture is the editor's base and stays uncompressed.
        let smaller = items.filter { $0.inLibrary && Compressor.canCompress($0.url) }
        if !smaller.isEmpty {
            add(smaller.count == 1 ? "Compress" : "Compress \(smaller.count) Files") { [weak self] in self?.compress(smaller) }
        }
        add(n == 1 ? "Copy File" : "Copy \(n) Files") { [weak self] in self?.copyFiles(items) }
        if n == 1 {
            let sendTo = NSMenuItem(title: "Send To", action: nil, keyEquivalent: "")
            // (Assigned inside, as an NSMenu can't be handed out of the main-actor closure.)
            MainActor.assumeIsolated {
                sendTo.submenu = SendTo.menu(for: SendTo.Source(file: item.url, isImage: item.kind == .image))
            }
            m.addItem(sendTo)
        }
        let images = items.filter { $0.kind == .image }
        if CombineLayout.countRange.contains(images.count) {
            add("Combine \(images.count) Captures…") { [weak self] in self?.combine(images) }
        }
        m.addItem(.separator())
        let trash = item.inLibrary
        add(trash ? (n == 1 ? "Move to Trash" : "Move \(n) Files to Trash") : (n == 1 ? "Delete" : "Delete \(n) Captures")) {
            [weak self] in self?.delete(items)
        }
        return m
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedTag()) ?? .history
        selection = []
        applyMode()
    }

    @objc private func filterChanged() { reload() }

    @objc private func editedToggled(_ sender: PillButton) {
        sender.isOn.toggle()
        reload()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    @objc private func tileSizePicked(_ item: NSMenuItem) {
        Preferences.libraryTileSize = item.tag
        applyMode()
    }

    @objc private func captureClicked(_ sender: NSButton) {
        guard Self.captureActions.indices.contains(sender.tag) else { return }
        let run = Self.captureActions[sender.tag].run
        hide()
        // Once the panel is off the screen, so it isn't in the capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { run() }
    }

    @objc private func closeIt() { hide() }

    @objc private func openFolder() {
        hide()
        NSWorkspace.shared.open(CaptureHistory.directory)
    }

    @objc private func openSaveFolder() {
        hide()
        NSWorkspace.shared.open(Preferences.saveDirectory)
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

extension CaptureHistoryPanel: NSMenuDelegate {
    /// Ticks the current thumbnail size in the ⋯ menu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(tileSizePicked(_:)) {
            item.state = item.tag == Preferences.libraryTileSize ? .on : .off
        }
    }
}

/// A menu item's action as a closure (the item keeps it alive through `representedObject`).
private final class MenuAction: NSObject {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One capture or saved file in the panel: thumbnail, relative time, and hover actions.
private final class HistoryCell: NSView, NSDraggingSource {
    enum Action { case edit, copy, save, pin, openSource, delete, reveal }
    /// Thumbnail sizes: small, medium, large.
    static let sizes = [NSSize(width: 150, height: 96), NSSize(width: 220, height: 140), NSSize(width: 300, height: 190)]

    let item: CaptureHistoryPanel.Item
    var onAction: ((Action) -> Void)?
    /// A plain click (false) or a ⌘-click (true).
    var onClick: ((Bool) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var isSelected = false {
        didSet {
            thumb.layer?.borderWidth = isSelected ? 3 : 0
            thumb.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }
    private let thumb = NSImageView()
    private let overlay = NSView()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f
    }()
    private var downEvent: NSEvent?

    init(item: CaptureHistoryPanel.Item, size: NSSize) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        thumb.imageScaling = .scaleProportionallyDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        thumb.translatesAutoresizingMaskIntoConstraints = false
        CaptureHistory.thumbnail(item.url, maxPixels: Int(size.width * 2)) { [weak self] img in self?.thumb.image = img }

        let caption = item.inLibrary ? item.url.deletingPathExtension().lastPathComponent
                                     : Self.relative.localizedString(for: item.date, relativeTo: Date())
        let time = NSTextField(labelWithString: caption)
        time.font = .systemFont(ofSize: 11)
        time.textColor = .secondaryLabelColor
        time.alignment = .center
        time.lineBreakMode = .byTruncatingMiddle
        time.translatesAutoresizingMaskIntoConstraints = false

        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = 8
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        overlay.isHidden = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        let still = item.kind == .image
        var buttons: [(String, String, Action)] = [(still ? "pencil" : "play", still ? "Edit" : "Open", .edit),
                                                   ("doc.on.doc", "Copy", .copy)]
        if item.inLibrary {
            buttons.append(("folder", "Show in Finder", .reveal))
        } else {
            buttons.append(("square.and.arrow.down", "Save…", .save))
        }
        if still { buttons.append(("pin", "Pin", .pin)) }
        if item.sourceURL != nil { buttons.append(("globe", "Open Source Page", .openSource)) }
        buttons.append(("trash", item.inLibrary ? "Move to Trash" : "Delete", .delete))
        var views: [NSView] = buttons.map { sym, tip, action in
            let b = HoverButton(symbol: sym, tip: tip)
            b.onClick = { [weak self] in self?.onAction?(action) }
            return b
        }
        // Shares the file itself, so it keeps its name in Mail, AirDrop…
        let share = HoverButton(symbol: "square.and.arrow.up", tip: "Share…")
        share.onClick = { [weak self, weak share] in
            guard let self, let share else { return }
            Output.share(self.item.url, from: share)
        }
        views.insert(share, at: 3)
        let row = NSStackView(views: views)
        row.spacing = size.width < 200 ? 2 : 6
        row.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(row)

        [thumb, overlay, time].forEach(addSubview)
        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: topAnchor),
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumb.widthAnchor.constraint(equalToConstant: size.width),
            thumb.heightAnchor.constraint(equalToConstant: size.height),
            overlay.topAnchor.constraint(equalTo: thumb.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: thumb.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: thumb.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: thumb.trailingAnchor),
            row.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            time.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 8),
            time.centerXAnchor.constraint(equalTo: centerXAnchor),
            time.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            time.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolTip = item.url.deletingPathExtension().lastPathComponent
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
        if event.clickCount == 2 { onAction?(.edit); return }
        onClick?(event.modifierFlags.contains(.command))
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    /// Dragging a capture out drops its file (into Finder, Mail, Slack…).
    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        downEvent = nil
        let drag = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        drag.setDraggingFrame(thumb.frame, contents: thumb.image)
        beginDraggingSession(with: [drag], event: down, source: self)
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
