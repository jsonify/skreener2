import AppKit

/// Settings window (⌘, or the menu bar icon or the editor's gear button), CleanShot-style: a sidebar of categories with
/// colored icons, and each category's options in rounded groups. Fixed 810 pt wide; only the height can be resized.
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    @MainActor static let shared = SettingsWindowController()
    /// Whether the Settings window is on screen (without creating it).
    @MainActor static var isOpen: Bool { created?.window?.isVisible == true }
    @MainActor private static weak var created: SettingsWindowController?

    /// "0.2.0 (412, 48db438)": the version, build number and git commit build_app.sh stamps in from git (#135).
    nonisolated static var version: String { versionLine(Bundle.main.infoDictionary) }

    nonisolated static func versionLine(_ info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let details = [info?["CFBundleVersion"], info?["SkreenerCommit"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
        return details.isEmpty ? short : "\(short) (\(details.joined(separator: ", ")))"
    }

    private static let width: CGFloat = 810
    private static let sidebarWidth: CGFloat = 200

    private enum Pane: Int, CaseIterable {
        case general, afterCapture, sendTo, shortcuts, screenshots, recording, annotate, askClaude, about

        var title: String {
            switch self {
            case .general: return "General"
            case .afterCapture: return "After Capture"
            case .sendTo: return "Send To"
            case .shortcuts: return "Shortcuts"
            case .screenshots: return "Screenshots"
            case .recording: return "Screen Recording"
            case .annotate: return "Annotate"
            case .askClaude: return "Ask Claude"
            case .about: return "About"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .afterCapture: return "rectangle.stack.fill"
            case .sendTo: return "paperplane.fill"
            case .shortcuts: return "command"
            case .screenshots: return "camera.fill"
            case .recording: return "video.fill"
            case .annotate: return "pencil.tip"
            case .askClaude: return "sparkles"
            case .about: return "info"
            }
        }
        var color: NSColor {
            switch self {
            case .general: return .systemGray
            case .afterCapture: return .systemGreen
            case .sendTo: return .systemTeal
            case .shortcuts: return .systemIndigo
            case .screenshots: return .systemBlue
            case .recording: return .systemRed
            case .annotate: return .systemOrange
            case .askClaude: return .systemPurple
            case .about: return .systemGray
            }
        }

        /// The categories in the sidebar's list; About sits on its own at the bottom of the sidebar (#136).
        static let listed = allCases.filter { $0 != .about }
    }

    /// Target objects for the controls' closures (controls hold their targets weakly).
    private var actions: [ControlAction] = []
    private let folderLabel = NSTextField(labelWithString: "")
    private let loginSwitch = NSSwitch()
    /// Kept so it can follow the setting when a link's prompt turns it on (`refreshURLScheme`).
    private let urlSchemeSwitch = NSSwitch()
    private let shortcutsPane = ShortcutsPane()
    private let sendToPane = SendToPane()
    private let filingPane = FilingPane()
    /// Ask Claude's API key: typed into `apiKeyField`, saved to the Keychain; `apiKeyStatus` shows what is stored.
    private let apiKeyField = NSSecureTextField()
    private let apiKeyStatus = NSTextField(labelWithString: "")
    private let apiKeyRemove = NSButton(title: "Remove", target: nil, action: nil)
    /// Each permission's status in Settings → General, refreshed whenever Settings comes to the front (#112).
    private var permissionLabels: [Permission: NSTextField] = [:]
    private let sidebar = NSTableView()
    /// One-row list pinned to the bottom of the sidebar, below a divider, holding About (#136).
    private let footer = NSTableView()
    private let detail = NSScrollView()
    /// Each pane is built once, the first time it is shown.
    private var panes: [Pane: NSView] = [:]

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Skreener Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        super.init(window: w)
        Self.created = self

        let split = NSSplitViewController()
        let side = NSSplitViewItem(sidebarWithViewController: viewController(buildSidebar()))
        side.minimumThickness = Self.sidebarWidth
        side.maximumThickness = Self.sidebarWidth
        side.canCollapse = false
        split.addSplitViewItem(side)
        detail.hasVerticalScroller = true
        detail.drawsBackground = false
        split.addSplitViewItem(NSSplitViewItem(viewController: viewController(detail)))
        w.contentViewController = split

        // Only the height is adjustable.
        w.contentMinSize = NSSize(width: Self.width, height: 420)
        w.contentMaxSize = NSSize(width: Self.width, height: .greatestFiniteMagnitude)
        w.setContentSize(NSSize(width: Self.width, height: 660))
        w.center()
        sidebar.reloadData()
        footer.reloadData()
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        show(.general)

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Task { @MainActor in DockPresence.update() }
        }
        // Permissions and macOS's own shortcuts may have changed in System Settings in the meantime.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSystemState() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Brings Settings to the front; `askClaude` opens it on the Ask Claude pane, where the API key goes.
    func present(askClaude: Bool = false, sendTo: Bool = false, shortcuts: Bool = false) {
        if askClaude, let row = Pane.listed.firstIndex(of: .askClaude) {
            sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if sendTo, let row = Pane.listed.firstIndex(of: .sendTo) {
            sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if shortcuts, let row = Pane.listed.firstIndex(of: .shortcuts) {
            sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshFolder()
        refreshLogin()   // may have changed in System Settings
        refreshURLScheme()   // may have been allowed from a link's prompt
        refreshSystemState()
        refreshAPIKey()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        DockPresence.update()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func viewController(_ view: NSView) -> NSViewController {
        let vc = NSViewController()
        vc.view = view
        return vc
    }

    // MARK: Sidebar

    private func buildSidebar() -> NSView {
        let list = sidebarList(sidebar)
        let bottom = sidebarList(footer)
        let divider = NSBox()
        divider.boxType = .separator
        let side = NSView()
        [list, divider, bottom].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; side.addSubview($0) }
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: side.topAnchor),
            list.leadingAnchor.constraint(equalTo: side.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: side.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -6),
            divider.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -14),
            divider.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -6),
            bottom.leadingAnchor.constraint(equalTo: side.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: side.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -10),
            // One 32 pt row plus the source list's own row padding.
            bottom.heightAnchor.constraint(equalToConstant: 42),
        ])
        return side
    }

    /// A source-list table of panes in a scroll view, styled the same for the main list and the About footer.
    private func sidebarList(_ table: NSTableView) -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        column.width = Self.sidebarWidth - 20
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 32
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        return scroll
    }

    private func panes(in table: NSTableView) -> [Pane] { table === footer ? [.about] : Pane.listed }

    func numberOfRows(in tableView: NSTableView) -> Int { panes(in: tableView).count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let list = panes(in: tableView)
        guard list.indices.contains(row) else { return nil }
        let pane = list[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: Self.icon(pane.symbol, pane.color))
        let label = NSTextField(labelWithString: pane.title)
        label.font = .systemFont(ofSize: 13)
        [icon, label].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
        ])
        cell.imageView = icon
        cell.textField = label
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        let list = panes(in: table)
        guard list.indices.contains(table.selectedRow) else { return }
        // Only one row is highlighted across the two lists.
        (table === footer ? sidebar : footer).deselectAll(nil)
        show(list[table.selectedRow])
    }

    /// White symbol on a rounded square of `color`, with a soft top highlight.
    private static func icon(_ symbol: String, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 22, height: 22), flipped: false) { r in
            let path = NSBezierPath(roundedRect: r, xRadius: 5.5, yRadius: 5.5)
            color.setFill()
            path.fill()
            NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))?
                .draw(in: path, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                s.draw(in: NSRect(x: r.midX - s.size.width / 2, y: r.midY - s.size.height / 2,
                                  width: s.size.width, height: s.size.height))
            }
            return true
        }
    }

    // MARK: Panes

    private func show(_ pane: Pane) {
        let content = panes[pane] ?? buildPane(pane)
        panes[pane] = content
        let doc = FlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(content)
        doc.translatesAutoresizingMaskIntoConstraints = false
        detail.documentView = doc
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: detail.contentView.leadingAnchor),
            doc.topAnchor.constraint(equalTo: detail.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: detail.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: doc.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -28),
            content.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -28),
        ])
        detail.contentView.scroll(to: .zero)
    }

    private func buildPane(_ pane: Pane) -> NSView {
        let title: NSView = {
            let l = NSTextField(labelWithString: pane.title)
            l.font = .systemFont(ofSize: 20, weight: .bold)
            return l
        }()
        return verticalStack([title] + groups(for: pane), spacing: 24)
    }

    private func groups(for pane: Pane) -> [NSView] {
        switch pane {
        case .general:
            bind(loginSwitch) { [weak self] c in
                LaunchAtLogin.set((c as? NSSwitch)?.state == .on)
                self?.refreshLogin()
            }
            loginSwitch.controlSize = .small
            refreshLogin()
            bind(urlSchemeSwitch) { c in Preferences.allowURLScheme = (c as? NSSwitch)?.state == .on }
            urlSchemeSwitch.controlSize = .small
            refreshURLScheme()

            let choose = NSButton(title: "Choose…", target: nil, action: nil)
            bind(choose) { [weak self] _ in self?.chooseFolder() }
            folderLabel.lineBreakMode = .byTruncatingMiddle
            folderLabel.textColor = .secondaryLabelColor
            folderLabel.translatesAutoresizingMaskIntoConstraints = false
            folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
            refreshFolder()
            let folder = NSStackView(views: [folderLabel, choose])
            folder.spacing = 10
            let resetTips = NSButton(title: "Reset Tips", target: nil, action: nil)
            bind(resetTips) { _ in Tips.resetAll() }

            return [
                group("App", [
                    row("Launch at login", loginSwitch),
                    toggle("Check for updates automatically",
                           "Looks for a new version once a day and asks before installing it.",
                           Preferences.checkForUpdates) { Preferences.checkForUpdates = $0; Updater.start() },
                ]),
                group("Tips", [
                    toggle("Show tips and hints", "One-time tips, a hint line under the editor's canvas, and \"New\" dots on "
                        + "features you haven't tried yet.", Preferences.showTipsAndHints) {
                        Preferences.showTipsAndHints = $0
                        NotificationCenter.default.post(name: .skreenerPreferencesChanged, object: nil)
                    },
                    row("Reset tips", "Shows every tip and \"New\" dot again.", resetTips),
                ]),
                group("Capture", [
                    toggle("Freeze screen while selecting", "Shows a still frame while you pick an area and captures from it.",
                           Preferences.freezeScreen) { Preferences.freezeScreen = $0 },
                    toggle("Show magnifier while selecting",
                           "A zoomed view of the pixels around the pointer while you pick an area.",
                           Preferences.showMagnifier) { Preferences.showMagnifier = $0 },
                    toggle("Show crosshair lines while selecting",
                           "A horizontal and a vertical line through the pointer, across the whole screen.",
                           Preferences.showCrosshairLines) { Preferences.showCrosshairLines = $0 },
                    toggle("Adjust the area before capturing",
                           "The selection stays after the drag: drag its handles, move it or use the keys, then press "
                           + "Return or double-click it to capture. Esc cancels.",
                           Preferences.adjustAreaBeforeCapture) { Preferences.adjustAreaBeforeCapture = $0 },
                    toggle("Show cursor in screenshots", nil, Preferences.showCursor) { Preferences.showCursor = $0 },
                    toggle("Hide desktop icons while capturing", nil, Preferences.hideIconsWhileCapturing) {
                        Preferences.hideIconsWhileCapturing = $0
                    },
                ]),
                group("Permissions", Permission.allCases.map(permissionRow),
                      note: "Skreener asks for these when it first needs them. A permission turned on in System Settings "
                        + "may need Skreener to be quit and reopened."),
                group("Export", [row("Export location", folder)],
                      note: "Where screenshots are saved after a capture, and where screen recordings go."),
                group("Automation", [
                    row("Allow URL scheme", "For Raycast, Alfred, Shortcuts and scripts.", urlSchemeSwitch),
                ], note: "Links like skreener://grab/area?then=copy,save start a capture; then= picks copy, save, edit, pin "
                    + "and quickaccess for that capture. Other commands: grab/fullscreen, grab/window, grab/previous, "
                    + "grab/window/active, grab/scrolling, grab/delayed/area?delay=5, ocr, record, load/clipboard, pin/clipboard, pin/live, history, settings."),
            ]

        case .afterCapture:
            var views: [NSView] = [
                group("Screenshots", [
                    toggle("Copy to clipboard", nil, Preferences.copyToClipboard) { Preferences.copyToClipboard = $0 },
                    toggle("Save to the export location", nil, Preferences.autoSave) { Preferences.autoSave = $0 },
                    toggle("Open in the editor", nil,
                           Preferences.openEditorAfterCapture) { Preferences.openEditorAfterCapture = $0 },
                    toggle("Show Quick Access preview",
                           "A thumbnail in a bottom corner that stays until you copy, save, edit, pin, share or close it.",
                           Preferences.showQuickAccess) { Preferences.showQuickAccess = $0 },
                    toggle("Smart actions after capture",
                           "Finds dates, addresses, phone numbers, links and QR codes in the screenshot, and adds buttons for them to its Quick Access preview. The editor's text menu always has Smart Actions.",
                           Preferences.smartActions) { Preferences.smartActions = $0 },
                    toggle("Remember the web page of browser captures",
                           "Safari, Chrome, Arc, Edge and Brave are asked for the tab's address, so Saved Files can open and search it. Needs Automation access, asked once per browser.",
                           Preferences.rememberSourcePage) { Preferences.rememberSourcePage = $0 },
                    row("Quick Access position", "The corner the previews stack up from, on the screen with the pointer.",
                        quickAccessSidePopup()),
                ], note: "Capture Text and Capture Area & Pin skip these. Actions set to run after every capture "
                    + "(Settings → Send To) run once the screenshot is saved."),
                group("Capture Text", [
                    toggle("Edit the text before copying",
                           "Opens what was read in a scratch pad; Copy to Clipboard (⌘Return) copies it. Off: copied straight away.",
                           Preferences.textScratchPad) { Preferences.textScratchPad = $0 },
                    toggle("Keep formatting as Markdown",
                           "Headings, bullet and numbered lists, bold and code, written as Markdown. Apps that take rich text (Notes, Mail, Pages) also get colored words. Bold, code and colors are read from the pixels, so they can be missed. Copies paste as formatted text in Google Docs, Notes, Mail and Pages, and as clean text (• bullets, no symbols) in plain fields; the scratch pad has Copy as Markdown for GitHub. Off: plain text.",
                           Preferences.keepTextFormatting) { Preferences.keepTextFormatting = $0 },
                ]),
                group("Capture Code", [
                    toggle("Copy as a Markdown code block",
                           "Wraps the code in ``` fences. Off: copied as plain code.",
                           Preferences.codeAsMarkdown) { Preferences.codeAsMarkdown = $0 },
                ]),
                group("Confirmation", [
                    row("Confirmation style", "When a capture opens no editor, Quick Access preview or pin (for example "
                        + "with only Copy or Save on, or Capture Text).", confirmationPopup()),
                    toggle("Play sounds", "When something is copied, a recording is saved, or a capture is cancelled.",
                           Preferences.playSounds) { Preferences.playSounds = $0 },
                ]),
                group("History", [
                    toggle("Keep capture history", "Recent captures, in the History panel (⌃⇧H).",
                           Preferences.keepHistory) { Preferences.keepHistory = $0 },
                    row("Captures kept", "Lowering it deletes the oldest captures now.", historyLimitPopup()),
                ], note: "The panel's Saved Files view shows everything in the export location, with search."),
            ]
            // Filing rules, tags and Spotlight (#277) come after what happens to the screenshot.
            views.insert(contentsOf: filingPane.build(paneTools), at: 1)
            return views

        case .sendTo:
            // Kept by the pane to rebuild its list when an action changes; Settings lives as long as the app.
            return sendToPane.build(paneTools)

        case .shortcuts:
            return shortcutsPane.build(group: { group($0, $1, note: $2) }, row: { row($0, $1, $2) })

        case .screenshots:
            // Example file name under the template field, updated as the template or the format changes.
            let preview = NSTextField(labelWithString: "")
            preview.textColor = .secondaryLabelColor
            preview.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            func showPreview() { preview.stringValue = "\(Output.filename()).\(Preferences.imageFormat.fileExtension)" }

            let format = NSPopUpButton(frame: .zero, pullsDown: false)
            for f in [ImageFormat.png, .jpeg] {
                format.addItem(withTitle: f == .png ? "PNG" : "JPEG"); format.lastItem?.representedObject = f.rawValue
            }
            format.selectItem(at: Preferences.imageFormat == .png ? 0 : 1)
            bind(format) {
                let raw = ($0 as? NSPopUpButton)?.selectedItem?.representedObject as? String
                Preferences.imageFormat = raw.flatMap(ImageFormat.init(rawValue:)) ?? .png
                showPreview()
            }

            let template = NSTextField(string: Preferences.filenameTemplate)
            template.placeholderString = Preferences.defaultFilenameTemplate
            template.isContinuous = true
            template.translatesAutoresizingMaskIntoConstraints = false
            template.widthAnchor.constraint(equalToConstant: 240).isActive = true
            bind(template) {
                Preferences.filenameTemplate = $0.stringValue
                showPreview()
            }
            showPreview()

            let padding = NSPopUpButton(frame: .zero, pullsDown: false)
            for pts in [0, 16, 32, 64] { padding.addItem(withTitle: pts == 0 ? "None" : "\(pts) pt"); padding.lastItem?.tag = pts }
            padding.selectItem(withTag: Preferences.windowPadding)
            bind(padding) { Preferences.windowPadding = ($0 as? NSPopUpButton)?.selectedTag() ?? 0 }

            let highlight = NSColorWell(style: .minimal)
            highlight.color = Preferences.windowHighlightColor
            highlight.supportsAlpha = false
            bind(highlight) { Preferences.windowHighlightColor = ($0 as? NSColorWell)?.color ?? .systemBlue }

            let liveRate = NSPopUpButton(frame: .zero, pullsDown: false)
            for rate in LivePinGeometry.frameRates { liveRate.addItem(withTitle: "\(rate) fps"); liveRate.lastItem?.tag = rate }
            liveRate.selectItem(withTag: Preferences.livePinFrameRate)
            bind(liveRate) { Preferences.livePinFrameRate = ($0 as? NSPopUpButton)?.selectedTag() ?? 5 }

            return [
                group("File", [
                    row("Format", "JPEG has no transparency: transparent areas become white.", format),
                    toggle("Save Retina screenshots at 1×", "Half the pixels each way: smaller files.", Preferences.downscaleRetina) {
                        Preferences.downscaleRetina = $0
                    },
                    toggle("Compress screenshots when saving",
                           "PNGs get a palette of up to 256 colors when it looks the same, and stay as they are when it doesn't.",
                           Preferences.compressScreenshots) { Preferences.compressScreenshots = $0 },
                    row("File name", "Tokens: %Y %y %m %d %H %M %S", template),
                    row("Example", preview),
                ]),
                group("Window Capture", [
                    toggle("Shadow", nil, Preferences.windowShadow) { Preferences.windowShadow = $0 },
                    toggle("Transparent around the window",
                           "The rounded corners, shadow and padding stay see-through in PNGs. Off: they're filled with white.",
                           Preferences.windowTransparentBackground) {
                        Preferences.windowTransparentBackground = $0
                    },
                    row("Padding", padding),
                    row("Highlight color", "Tints the window under the pointer while you pick one.", highlight),
                ]),
                group("Live Pin", [
                    row("Frame rate", "New Live Pins update this often. Lower uses less CPU; a pin's right-click menu changes its own.",
                        liveRate),
                ]),
            ]

        case .recording:
            let mic = NSSwitch()
            mic.controlSize = .small
            mic.state = Preferences.recordMicrophone ? .on : .off
            bind(mic) { Preferences.recordMicrophone = ($0 as? NSSwitch)?.state == .on }
            var micNote: String?
            if #unavailable(macOS 15.0) {
                mic.isEnabled = false
                micNote = "Needs macOS 15 or later."
            }
            let fps = NSPopUpButton(frame: .zero, pullsDown: false)
            for rate in [30, 60] { fps.addItem(withTitle: "\(rate) fps"); fps.lastItem?.tag = rate }
            fps.selectItem(withTag: Preferences.recordFrameRate)
            bind(fps) { Preferences.recordFrameRate = ($0 as? NSPopUpButton)?.selectedTag() ?? 30 }

            return [
                group("Audio", [
                    toggle("System audio", "Sound from other apps.", Preferences.recordSystemAudio) { Preferences.recordSystemAudio = $0 },
                    row("Microphone", micNote, mic),
                ], note: "With both on, they are mixed into one audio track."),
                group("Video", [
                    row("Frame rate", fps),
                    toggle("Show cursor", nil, Preferences.recordShowsCursor) { Preferences.recordShowsCursor = $0 },
                    toggle("Compress recordings after stopping",
                           "Re-encodes as HEVC when that makes the file smaller. Takes a while for long recordings; GIFs are not changed.",
                           Preferences.compressRecordings) { Preferences.compressRecordings = $0 },
                ], note: "Recordings are saved to the export location as MP4. More options are in the record panel's sliders menu."),
            ]

        case .annotate:
            return [
                group("Annotations", [
                    toggle("Drop shadow", "A subtle shadow under shapes, arrows, pen and text.", Preferences.annotationShadow) {
                        Preferences.annotationShadow = $0
                        NotificationCenter.default.post(name: .skreenerPreferencesChanged, object: nil)
                    },
                    toggle("Match screenshot color past the edge",
                           "Annotations dragged past the image grow the canvas. Fill it with the image's corner color; white when off.",
                           Preferences.matchExtensionColor) {
                        Preferences.matchExtensionColor = $0
                        NotificationCenter.default.post(name: .skreenerPreferencesChanged, object: nil)
                    },
                    toggle("Snap to objects", "Boxes, ellipses, blur, pixelate, erase and spotlight snap to the edges of "
                        + "buttons, fields and other shapes in the screenshot while drawn or resized. Hold ⌘ to draw freely.",
                           Preferences.snapToObjects) { Preferences.snapToObjects = $0 },
                ]),
                group("Editor Window", [
                    toggle("Open screenshots as tabs", "New screenshots join the open editor window instead of opening their own.",
                           Preferences.editorTabs) { Preferences.editorTabs = $0 },
                    row("Screenshots dock", "With several screenshots open, their thumbnails line this side of the "
                        + "window. Hide it with its button or ⌃⌘S.", dockSidePopup()),
                    row("Esc with nothing selected", "Esc first deselects; pressed again, it can copy or save the "
                        + "screenshot and close it.", escPopup()),
                    toggle("Save over the saved file", "Save (⌘S) on a screenshot that was already saved, or opened from a "
                        + "file, updates that file instead of making a new one. Save As… (⇧⌘S) always asks.",
                           Preferences.saveOverExisting) { Preferences.saveOverExisting = $0 },
                    toggle("Zoom, zoom", "For fans of a little bounce: the editor window zooms in when it opens and "
                        + "whenever you switch screenshots, and so does the screen when a capture starts.",
                           Preferences.editorWindowZoom) { Preferences.editorWindowZoom = $0 },
                ]),
            ]

        case .askClaude:
            apiKeyField.placeholderString = "sk-ant-…"
            apiKeyField.translatesAutoresizingMaskIntoConstraints = false
            apiKeyField.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let save = NSButton(title: "Save", target: nil, action: nil)
            bind(save) { [weak self] _ in self?.saveAPIKey() }
            bind(apiKeyField) { [weak self] _ in self?.saveAPIKey() }
            let entry = NSStackView(views: [apiKeyField, save])
            entry.spacing = 8

            apiKeyStatus.textColor = .secondaryLabelColor
            apiKeyRemove.controlSize = .small
            bind(apiKeyRemove) { [weak self] _ in
                APIKeyStore.set(nil)
                self?.refreshAPIKey()
            }
            let stored = NSStackView(views: [apiKeyStatus, apiKeyRemove])
            stored.spacing = 10
            refreshAPIKey()

            let getKey = NSButton(title: "Get a Key…", target: nil, action: nil)
            bind(getKey) { _ in NSWorkspace.shared.open(AskClaude.keysPage) }

            return [
                group("Anthropic API", [
                    row("API key", "Your own key from the Claude Console. It's kept in your Keychain.", entry),
                    row("Saved key", stored),
                    row("New to the API?", "Make a key in the Claude Console. Use of the API is billed to that account.",
                        getKey),
                ], note: "In the editor footer, the sparkles button asks Claude to explain the screenshot, summarize it, write "
                    + "alt text for it, or answer your own question. Only when you press Ask is the screenshot, with its "
                    + "annotations, sent to Anthropic with the question. Skreener sends nothing else, and nothing "
                    + "automatically. No key? With a Claude plan, Open in Claude copies the screenshot and opens Claude "
                    + "in your browser with the question filled in; Anthropic doesn't let other apps sign in with a "
                    + "Claude subscription."),
            ]

        case .about:
            let icon = NSImageView(image: NSApp.applicationIconImage)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
            let name = NSTextField(labelWithString: "Skreener")
            name.font = .systemFont(ofSize: 18, weight: .semibold)
            let version = NSTextField(labelWithString: "Version \(Self.version)")
            version.textColor = .secondaryLabelColor
            version.isSelectable = true
            let blurb = NSTextField(labelWithString: "Screenshots, annotations and screen recordings from the menu bar.")
            blurb.textColor = .secondaryLabelColor
            let update = NSButton(title: "Check for Updates…", target: nil, action: nil)
            bind(update) { _ in Updater.check(userInitiated: true) }
            let stack = NSStackView(views: [icon, name, version, blurb, update])
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = 8
            stack.setCustomSpacing(4, after: name)
            stack.setCustomSpacing(16, after: blurb)
            return [stack]
        }
    }

    private func confirmationPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for style in ConfirmationStyle.allCases {
            popup.addItem(withTitle: style.title); popup.lastItem?.representedObject = style.rawValue
        }
        popup.selectItem(at: ConfirmationStyle.allCases.firstIndex(of: Preferences.confirmationStyle) ?? 0)
        bind(popup) {
            let raw = ($0 as? NSPopUpButton)?.selectedItem?.representedObject as? String
            Preferences.confirmationStyle = raw.flatMap(ConfirmationStyle.init(rawValue:)) ?? .hud
        }
        return popup
    }

    private func historyLimitPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for n in [25, 100, 500, 0] { popup.addItem(withTitle: n == 0 ? "All" : "\(n)"); popup.lastItem?.tag = n }
        popup.selectItem(withTag: Preferences.historyLimit)
        bind(popup) {
            Preferences.historyLimit = ($0 as? NSPopUpButton)?.selectedTag() ?? 100
            CaptureHistory.prune()
            NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil)
        }
        return popup
    }

    private func quickAccessSidePopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Bottom Left", "Bottom Right"])
        popup.selectItem(at: Preferences.quickAccessOnRight ? 1 : 0)
        bind(popup) {
            Preferences.quickAccessOnRight = ($0 as? NSPopUpButton)?.indexOfSelectedItem == 1
            QuickAccessController.refreshPosition()
        }
        return popup
    }

    private func dockSidePopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Left", "Right"])
        popup.selectItem(at: Preferences.editorDockOnRight ? 1 : 0)
        bind(popup) {
            Preferences.editorDockOnRight = ($0 as? NSPopUpButton)?.indexOfSelectedItem == 1
            EditorTabGroup.refreshAll()
        }
        return popup
    }

    private func escPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for action in EditorEscAction.allCases {
            popup.addItem(withTitle: action.title); popup.lastItem?.representedObject = action.rawValue
        }
        popup.selectItem(at: EditorEscAction.allCases.firstIndex(of: Preferences.editorEscAction) ?? 0)
        bind(popup) {
            let raw = ($0 as? NSPopUpButton)?.selectedItem?.representedObject as? String
            Preferences.editorEscAction = raw.flatMap(EditorEscAction.init(rawValue:)) ?? .nothing
        }
        return popup
    }

    // MARK: Building blocks

    /// The building blocks below, for the panes that live in their own files.
    private var paneTools: SendToPane.Tools {
        .init(group: { self.group($0, $1, note: $2) }, row: { self.row($0, $1, $2) },
              toggle: { self.toggle($0, $1, $2, $3) }, bind: { self.bind($0, $1) }, window: { self.window })
    }

    /// A titled rounded box of rows, with separators between them and an optional note under it.
    private func group(_ title: String, _ rows: [NSView], note: String? = nil) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        var items: [NSView] = []
        for (i, r) in rows.enumerated() {
            if i > 0 {
                let line = NSBox()
                line.boxType = .separator
                items.append(line)
            }
            items.append(r)
        }
        let inner = verticalStack(items, spacing: 0, inset: 14)
        let box = GroupBox()
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])

        var views: [NSView] = [header, box]
        if let note {
            let n = NSTextField(wrappingLabelWithString: note)
            n.font = .systemFont(ofSize: 11)
            n.textColor = .secondaryLabelColor
            n.preferredMaxLayoutWidth = Self.width - Self.sidebarWidth - 2 * 28
            views.append(n)
        }
        return verticalStack(views, spacing: 8)
    }

    /// Vertical stack whose arranged views all take its full width (less `inset` on each side).
    private func verticalStack(_ views: [NSView], spacing: CGFloat, inset: CGFloat = 0) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: inset > 0 ? 2 : 0, left: inset, bottom: inset > 0 ? 2 : 0, right: inset)
        for v in views { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * inset).isActive = true }
        return stack
    }

    private func row(_ title: String, _ control: NSView) -> NSView { row(title, nil, control) }

    /// Title (and optional subtitle) on the left, `control` on the right.
    private func row(_ title: String, _ subtitle: String?, _ control: NSView) -> NSView {
        let v = NSView()
        let text = NSStackView(views: [NSTextField(labelWithString: title)])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        if let subtitle {
            let s = NSTextField(wrappingLabelWithString: subtitle)
            s.font = .systemFont(ofSize: 11)
            s.textColor = .secondaryLabelColor
            s.preferredMaxLayoutWidth = 300
            text.addArrangedSubview(s)
        }
        [text, control].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; v.addSubview($0) }
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            text.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            text.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: v.topAnchor, constant: 9),
            text.bottomAnchor.constraint(lessThanOrEqualTo: v.bottomAnchor, constant: -9),
            control.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: v.topAnchor, constant: 6),
            text.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
        ])
        return v
    }

    private func toggle(_ title: String, _ subtitle: String?, _ on: Bool, _ set: @escaping (Bool) -> Void) -> NSView {
        let s = NSSwitch()
        s.controlSize = .small
        s.state = on ? .on : .off
        bind(s) { set(($0 as? NSSwitch)?.state == .on) }
        return row(title, subtitle, s)
    }

    private func bind(_ control: NSControl, _ run: @escaping (NSControl) -> Void) {
        let a = ControlAction(run)
        actions.append(a)
        control.target = a; control.action = #selector(ControlAction.fire(_:))
    }

    private func refreshLogin() { loginSwitch.state = LaunchAtLogin.isOn ? .on : .off }

    private func refreshSystemState() {
        refreshPermissions()
        shortcutsPane.refreshMacShortcuts()
    }

    private func refreshPermissions() {
        for (permission, label) in permissionLabels {
            label.stringValue = permission.status
            label.textColor = permission.isGranted ? .systemGreen : .systemOrange
        }
    }

    /// Status and an Open System Settings button for one permission.
    private func permissionRow(_ permission: Permission) -> NSView {
        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12, weight: .medium)
        permissionLabels[permission] = status
        let open = NSButton(title: "Open System Settings", target: nil, action: nil)
        open.controlSize = .small
        bind(open) { _ in permission.openSettings() }
        let control = NSStackView(views: [status, open])
        control.spacing = 10
        return row(permission.title, permission.purpose, control)
    }
    func refreshURLScheme() { urlSchemeSwitch.state = Preferences.allowURLScheme ? .on : .off }

    // MARK: Ask Claude

    private func saveAPIKey() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if APIKeyStore.set(key) {
            apiKeyField.stringValue = ""
        } else {
            NSSound.beep()
        }
        refreshAPIKey()
    }

    private func refreshAPIKey() {
        let key = APIKeyStore.key
        apiKeyStatus.stringValue = key.map(APIKeyStore.masked) ?? "None"
        apiKeyRemove.isHidden = key == nil
    }

    // MARK: Export location

    private func refreshFolder() {
        folderLabel.stringValue = (Preferences.saveDirectory.path as NSString).abbreviatingWithTildeInPath
        folderLabel.toolTip = Preferences.saveDirectory.path
    }

    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.directoryURL = Preferences.saveDirectory
        guard let w = window else { return }
        p.beginSheetModal(for: w) { [weak self] r in
            if r == .OK, let u = p.url { Preferences.saveDirectory = u; self?.refreshFolder() }
        }
    }
}

@MainActor private final class ControlAction: NSObject {
    let run: (NSControl) -> Void
    init(_ run: @escaping (NSControl) -> Void) { self.run = run }
    @objc func fire(_ sender: NSControl) { run(sender) }
}

/// Rounded, faintly filled background for a group of rows (redrawn when the appearance changes).
private final class GroupBox: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
