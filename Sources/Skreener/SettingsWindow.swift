import AppKit

/// Settings window (⌘, or the menu bar icon or the editor's gear button), in the SK-1 look (#353): a chassis with an
/// LCD and a tray of keys down the side, one per category, and each category's options in sunken trays, with the kit's
/// switches, LCD steppers, segmented controls and knobs. Fixed 810 pt wide; only the height can be resized.
final class SettingsWindowController: NSWindowController {
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
    /// Space either side of a pane's groups.
    private static let paneMargin: CGFloat = 22

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

        /// The categories in the sidebar's list; About sits on its own at the bottom of the sidebar (#136).
        static let listed = allCases.filter { $0 != .about }
    }

    /// Target objects for the controls' closures (controls hold their targets weakly).
    private var actions: [ControlAction] = []
    private var viewActions: [ViewAction] = []
    private let folderLabel = NSTextField(labelWithString: "")
    private let loginSwitch = RetroSwitch()
    /// Capture Text's scratch pad, also switched from the editor's Copy Text strip.
    private let scratchPadSwitch = RetroSwitch()
    /// Kept so it can follow the setting when a link's prompt turns it on (`refreshURLScheme`).
    private let urlSchemeSwitch = RetroSwitch()
    private let shortcutsPane = ShortcutsPane()
    private let sendToPane = SendToPane()
    private let filingPane = FilingPane()
    /// Ask Claude's API key: typed into `apiKeyField`, saved to the Keychain; `apiKeyStatus` shows what is stored.
    private let apiKeyField = NSSecureTextField()
    private let apiKeyStatus = RetroUI.hint("", size: 12)
    private let apiKeyRemove = RetroUI.key("Remove")
    /// Each permission's status in Settings → General (and Paste Destinations), refreshed whenever Settings comes to
    /// the front (#112).
    private var permissionLabels: [(permission: Permission, label: NSTextField)] = []
    /// The remembered paste destinations (#327), rebuilt when one is removed and when Settings comes to the front.
    private let pasteList = NSStackView()
    /// The sidebar's keys, one per pane; About's sits in its own tray at the bottom (#136).
    private var navKeys: [Pane: SettingsNavKey] = [:]
    /// The LCD at the top of the sidebar, naming the pane shown.
    private let sideLCD = SettingsLCD()
    private let detail = NSScrollView()
    /// Each pane is built once, the first time it is shown.
    private var panes: [Pane: NSView] = [:]

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Skreener Settings"
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        super.init(window: w)
        Self.created = self

        // The chassis: the title bar (a caption and a grille), a groove under it, then the sidebar and the panes with
        // a groove between them.
        let chassis = RetroUI.useChassis(w)
        let badge = RetroLabel(caption: "Skreener Settings", tone: .soft)
        let grille = SpeakerGrille(columns: 6, rows: 2)
        let topGroove = RetroGroove()
        let sideGroove = RetroGroove(vertical: true)
        let side = buildSidebar()
        detail.hasVerticalScroller = true
        detail.drawsBackground = false
        for v in [badge, grille, topGroove, side, sideGroove, detail] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            chassis.addSubview(v)
        }
        let top = RetroUI.contentTop(of: w, in: chassis)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: chassis.leadingAnchor, constant: 84),
            badge.centerYAnchor.constraint(equalTo: chassis.topAnchor, constant: 14),
            grille.trailingAnchor.constraint(equalTo: chassis.trailingAnchor, constant: -16),
            grille.centerYAnchor.constraint(equalTo: chassis.topAnchor, constant: 14),
            topGroove.topAnchor.constraint(equalTo: top),
            topGroove.leadingAnchor.constraint(equalTo: chassis.leadingAnchor),
            topGroove.trailingAnchor.constraint(equalTo: chassis.trailingAnchor),
            side.topAnchor.constraint(equalTo: topGroove.bottomAnchor),
            side.leadingAnchor.constraint(equalTo: chassis.leadingAnchor),
            side.bottomAnchor.constraint(equalTo: chassis.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            sideGroove.topAnchor.constraint(equalTo: topGroove.bottomAnchor),
            sideGroove.leadingAnchor.constraint(equalTo: side.trailingAnchor),
            sideGroove.bottomAnchor.constraint(equalTo: chassis.bottomAnchor),
            detail.topAnchor.constraint(equalTo: topGroove.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: sideGroove.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: chassis.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: chassis.bottomAnchor),
        ])

        // Only the height is adjustable.
        w.contentMinSize = NSSize(width: Self.width, height: 520)
        w.contentMaxSize = NSSize(width: Self.width, height: .greatestFiniteMagnitude)
        w.setContentSize(NSSize(width: Self.width, height: 660))
        w.center()
        select(.general)

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
        if askClaude {
            select(.askClaude)
        } else if sendTo {
            select(.sendTo)
        } else if shortcuts {
            select(.shortcuts)
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

    // MARK: Sidebar

    /// The LCD naming the pane, the tray of the panes' keys, and About's key in a tray of its own at the bottom.
    private func buildSidebar() -> NSView {
        let side = NSView()
        let list = navTray(Pane.listed)
        let about = navTray([.about])
        for v in [sideLCD, list, about] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            side.addSubview(v)
            v.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 14).isActive = true
            v.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -12).isActive = true
        }
        NSLayoutConstraint.activate([
            sideLCD.topAnchor.constraint(equalTo: side.topAnchor, constant: 14),
            list.topAnchor.constraint(equalTo: sideLCD.bottomAnchor, constant: 12),
            list.bottomAnchor.constraint(lessThanOrEqualTo: about.topAnchor, constant: -12),
            about.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -14),
        ])
        return side
    }

    /// A sunken tray holding a key for each of `panes`.
    private func navTray(_ panes: [Pane]) -> NSView {
        var keys: [SettingsNavKey] = []
        for pane in panes {
            let key = SettingsNavKey(title: pane.title, symbol: pane.symbol) { [weak self] in self?.select(pane) }
            navKeys[pane] = key
            keys.append(key)
        }
        let stack = NSStackView(views: keys)
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 7, bottom: 8, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for k in keys { k.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -14).isActive = true }
        let well = RetroWell()
        well.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: well.topAnchor), stack.bottomAnchor.constraint(equalTo: well.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: well.leadingAnchor), stack.trailingAnchor.constraint(equalTo: well.trailingAnchor),
        ])
        return well
    }

    /// Shows `pane`, pressing its key and naming it on the LCD.
    private func select(_ pane: Pane) {
        for (p, key) in navKeys { key.isSelected = p == pane }
        sideLCD.title = pane.title
        show(pane)
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
            content.topAnchor.constraint(equalTo: doc.topAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: Self.paneMargin),
            content.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -Self.paneMargin),
            content.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -28),
        ])
        detail.contentView.scroll(to: .zero)
    }

    /// The pane's groups; its name is on the sidebar's LCD.
    private func buildPane(_ pane: Pane) -> NSView { verticalStack(groups(for: pane), spacing: 22) }

    private func groups(for pane: Pane) -> [NSView] {
        switch pane {
        case .general:
            bind(loginSwitch) { [weak self] c in
                LaunchAtLogin.set((c as? NSButton)?.state == .on)
                self?.refreshLogin()
            }
            loginSwitch.setAccessibilityLabel("Launch at login")
            refreshLogin()
            bind(urlSchemeSwitch) { c in Preferences.allowURLScheme = (c as? NSButton)?.state == .on }
            urlSchemeSwitch.setAccessibilityLabel("Allow URL scheme")
            refreshURLScheme()

            let choose = RetroUI.key("Choose…")
            bind(choose) { [weak self] _ in self?.chooseFolder() }
            folderLabel.lineBreakMode = .byTruncatingMiddle
            refreshFolder()
            let folder = NSStackView(views: [LCDFieldBox(folderLabel, width: 220), choose])
            folder.spacing = 10
            let resetTips = RetroUI.key("Reset Tips")
            bind(resetTips) { _ in Tips.resetAll() }

            return [
                group("App", [
                    row("Launch at login", loginSwitch),
                    toggle("Check for updates automatically",
                           "Looks for a new version once a day and asks before installing it.",
                           Preferences.checkForUpdates) { Preferences.checkForUpdates = $0; Updater.start() },
                ]),
                group("Appearance", [
                    row("Appearance", "Light is the cream SK-1 look, Dark the charcoal one. System follows macOS.",
                        appearancePopup()),
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
                group("Permissions", Permission.allCases.map { permissionRow($0) },
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
                group("Quick Access Preview", [
                    row("Buttons", "Close is always there.", checkboxes(QuickAccessButton.allCases.map { b -> Checkbox in
                        (b.title, !Preferences.hiddenQuickAccessButtons.contains(b), { (on: Bool) in
                            var hidden = Preferences.hiddenQuickAccessButtons
                            if on { hidden.remove(b) } else { hidden.insert(b) }
                            Preferences.hiddenQuickAccessButtons = hidden
                        })
                    }, columns: 3)),
                    row("Smart action buttons", "Shown when Smart actions after capture is on. The editor's Smart "
                        + "Actions menu has them all.", checkboxes(SmartChip.allCases.map { c -> Checkbox in
                        (c.title, !Preferences.hiddenSmartChips.contains(c), { (on: Bool) in
                            var hidden = Preferences.hiddenSmartChips
                            if on { hidden.remove(c) } else { hidden.insert(c) }
                            Preferences.hiddenSmartChips = hidden
                        })
                    }, columns: 2)),
                ], note: "Changes apply to the next preview."),
                group("Capture Text", [
                    toggle("Edit the text before copying",
                           "Opens what was read in a scratch pad; Copy to Clipboard (⌘Return) copies it. Off: copied straight away. "
                           + "The editor's Copy Text follows this too, and the switch in its toolbar's Read Text group flips it.",
                           Preferences.textScratchPad, using: scratchPadSwitch) { Preferences.textScratchPad = $0 },
                    toggle("Keep formatting as Markdown",
                           "Headings, bullet and numbered lists, bold and code, written as Markdown. Apps that take rich text (Notes, Mail, Pages) also get colored words. Bold, code and colors are read from the pixels, so they can be missed. Copies paste as formatted text in Google Docs, Notes, Mail and Pages, and as clean text (• bullets, no symbols) in plain fields; the scratch pad has Copy as Markdown for GitHub. Off: plain text.",
                           Preferences.keepTextFormatting) { Preferences.keepTextFormatting = $0 },
                ]),
                pasteDestinationsGroup(),
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
                    row("Captures kept", "Lowering it deletes the oldest captures now.", historyLimitKnob()),
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
            let preview = RetroUI.hint("", size: 11)
            preview.font = Retro.mono(11, weight: .medium)
            func showPreview() {
                preview.stringValue = "\(Output.filename(app: "Safari", title: "Pricing · Stripe")).\(Preferences.imageFormat.fileExtension)"
            }

            let format = segmented([("PNG", 0), ("JPEG", 1)], selected: Preferences.imageFormat == .png ? 0 : 1, name: "Format") {
                Preferences.imageFormat = $0 == 0 ? .png : .jpeg
                showPreview()
            }

            let template = NSTextField(string: Preferences.filenameTemplate)
            template.placeholderString = Preferences.defaultFilenameTemplate
            template.isContinuous = true
            template.setAccessibilityLabel("File name")
            bind(template) {
                Preferences.filenameTemplate = $0.stringValue
                showPreview()
            }
            showPreview()

            // A smooth knob: any padding up to 100 pt.
            let padding = RetroKnob(name: "Padding", min: 0, max: 100, value: Preferences.windowPadding, defaultValue: 0) {
                $0 == 0 ? "None" : "\($0) pt"
            }
            bind(padding) { Preferences.windowPadding = ($0 as? RetroKnob)?.value ?? 0 }

            let highlight = SwatchRow()
            highlight.color = Preferences.windowHighlightColor
            bind(highlight) { Preferences.windowHighlightColor = $0.color }

            let liveRate = RetroKnob(name: "Live Pin frame rate",
                                     stops: LivePinGeometry.frameRates.map { ("\($0) fps", $0) },
                                     selected: Preferences.livePinFrameRate, defaultTag: LivePinGeometry.frameRates[0])
            bind(liveRate) { Preferences.livePinFrameRate = ($0 as? RetroKnob)?.value ?? 5 }

            return [
                group("File", [
                    row("Format", "JPEG has no transparency: transparent areas become white.", format),
                    toggle("Save Retina screenshots at 1×", "Half the pixels each way: smaller files.", Preferences.downscaleRetina) {
                        Preferences.downscaleRetina = $0
                    },
                    toggle("Compress screenshots when saving",
                           "PNGs get a palette of up to 256 colors when it looks the same, and stay as they are when it doesn't.",
                           Preferences.compressScreenshots) { Preferences.compressScreenshots = $0 },
                    row("File name", "Tokens: %t what the capture shows (a web page's title, else its biggest text), "
                        + "%a the app, %Y %y %m %d %H %M %S", LCDFieldBox(template, width: 250)),
                    row("Example", preview),
                ]),
                group("Window Capture", [
                    toggle("Shadow", nil, Preferences.windowShadow) { Preferences.windowShadow = $0 },
                    toggle("Transparent around the window",
                           "The rounded corners, shadow and padding stay see-through in PNGs. Off: they're filled with white.",
                           Preferences.windowTransparentBackground) {
                        Preferences.windowTransparentBackground = $0
                    },
                    row("Padding", "Space around the window in the screenshot.", padding),
                    row("Highlight color", "Tints the window under the pointer while you pick one.", highlight),
                ]),
                group("Live Pin", [
                    row("Frame rate", "New Live Pins update this often. Lower uses less CPU; a pin's right-click menu changes its own.",
                        liveRate),
                ]),
            ]

        case .recording:
            let mic = RetroSwitch()
            mic.state = Preferences.recordMicrophone ? .on : .off
            mic.setAccessibilityLabel("Microphone")
            bind(mic) { Preferences.recordMicrophone = ($0 as? NSButton)?.state == .on }
            var micNote: String?
            if #unavailable(macOS 15.0) {
                mic.isEnabled = false
                micNote = "Needs macOS 15 or later."
            }
            let fps = segmented([("30 fps", 30), ("60 fps", 60)], selected: Preferences.recordFrameRate, name: "Frame rate") {
                Preferences.recordFrameRate = $0
            }

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
                    row("Past the screenshot's edge",
                        "Annotations dragged past the image grow the canvas. What fills it: white, nothing (see-through "
                        + "in PNGs, white in JPEGs), or the screenshot's top-left corner color.", extensionFillPopup()),
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
            apiKeyField.setAccessibilityLabel("API key")
            let save = RetroUI.key("Save", variant: .orange)
            bind(save) { [weak self] _ in self?.saveAPIKey() }
            bind(apiKeyField) { [weak self] _ in self?.saveAPIKey() }
            let entry = NSStackView(views: [LCDFieldBox(apiKeyField, width: 220), save])
            entry.spacing = 8

            bind(apiKeyRemove) { [weak self] _ in
                APIKeyStore.set(nil)
                self?.refreshAPIKey()
            }
            let stored = NSStackView(views: [apiKeyStatus, apiKeyRemove])
            stored.spacing = 10
            refreshAPIKey()

            let getKey = RetroUI.key("Get a Key…")
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
            let name = RetroLabel(text: "Skreener", tone: .ink, size: 18)
            name.font = .systemFont(ofSize: 18, weight: .semibold)
            let version = RetroUI.hint("Version \(Self.version)", size: 12)
            version.font = Retro.mono(11.5, weight: .medium)
            version.isSelectable = true
            let blurb = RetroUI.hint("Screenshots, annotations and screen recordings from the menu bar.", size: 12)
            let update = RetroUI.key("Check for Updates…", variant: .orange)
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

    private func confirmationPopup() -> PillPopUp {
        let popup = lcdPopUp()
        popup.setAccessibilityLabel("Confirmation style")
        for style in ConfirmationStyle.allCases {
            popup.addItem(withTitle: style.title); popup.lastItem?.representedObject = style.rawValue
        }
        popup.selectItem(at: ConfirmationStyle.allCases.firstIndex(of: Preferences.confirmationStyle) ?? 0)
        bind(popup) {
            let raw = ($0 as? PillPopUp)?.selectedItem?.representedObject as? String
            Preferences.confirmationStyle = raw.flatMap(ConfirmationStyle.init(rawValue:)) ?? .hud
        }
        return popup
    }

    /// A click-stop knob; it only takes effect once it stops turning, since lowering it deletes captures.
    private func historyLimitKnob() -> RetroKnob {
        let knob = RetroKnob(name: "Captures kept", stops: [25, 100, 500, 0].map { ($0 == 0 ? "All" : "\($0)", $0) },
                             selected: Preferences.historyLimit, defaultTag: 100)
        knob.sendsWhileTurning = false
        bind(knob) {
            Preferences.historyLimit = ($0 as? RetroKnob)?.value ?? 100
            CaptureHistory.prune()
            NotificationCenter.default.post(name: .skreenerHistoryChanged, object: nil)
        }
        return knob
    }

    private func extensionFillPopup() -> PillPopUp {
        let popup = lcdPopUp()
        popup.setAccessibilityLabel("Past the screenshot's edge")
        popup.addItems(withTitles: ExtensionFill.allCases.map(\.title))
        popup.selectItem(at: ExtensionFill.allCases.firstIndex(of: Preferences.extensionFill) ?? 0)
        bind(popup) {
            let i = ($0 as? PillPopUp)?.indexOfSelectedItem ?? 0
            Preferences.extensionFill = ExtensionFill.allCases[max(i, 0)]
            NotificationCenter.default.post(name: .skreenerPreferencesChanged, object: nil)
        }
        return popup
    }

    /// A checkbox's title, whether it starts checked, and what a click sets.
    private typealias Checkbox = (title: String, on: Bool, set: (Bool) -> Void)

    /// Toggles (an orange square and a title) in rows of `columns`, for picking several of a set.
    private func checkboxes(_ items: [Checkbox], columns: Int) -> NSView {
        let boxes = items.map { item -> PillButton in
            let box = RetroUI.toggle(item.title, isOn: item.on, target: nil, action: nil)
            bind(box) {
                guard let b = $0 as? PillButton else { return }
                b.isOn.toggle()
                item.set(b.isOn)
            }
            return box
        }
        let rows = stride(from: 0, to: boxes.count, by: columns).map { i -> [NSView] in
            let row: [NSView] = Array(boxes[i..<min(i + columns, boxes.count)])
            return row + Array(repeating: NSGridCell.emptyContentView, count: columns - row.count)
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 16
        return grid
    }

    private func quickAccessSidePopup() -> RetroSegmented {
        segmented([("Bottom Left", 0), ("Bottom Right", 1)], selected: Preferences.quickAccessOnRight ? 1 : 0,
                  name: "Quick Access position") {
            Preferences.quickAccessOnRight = $0 == 1
            QuickAccessController.refreshPosition()
        }
    }

    private func dockSidePopup() -> RetroSegmented {
        segmented([("Left", 0), ("Right", 1)], selected: Preferences.editorDockOnRight ? 1 : 0, name: "Screenshots dock") {
            Preferences.editorDockOnRight = $0 == 1
            EditorTabGroup.refreshAll()
        }
    }

    private func appearancePopup() -> RetroSegmented {
        let all = AppAppearance.allCases
        return segmented(all.enumerated().map { ($0.element.title, $0.offset) },
                         selected: all.firstIndex(of: Preferences.appearance) ?? 0, name: "Appearance") {
            Preferences.appearance = all.indices.contains($0) ? all[$0] : .default
            Preferences.applyAppearance()
        }
    }

    private func escPopup() -> PillPopUp {
        let popup = lcdPopUp()
        popup.setAccessibilityLabel("Esc with nothing selected")
        for action in EditorEscAction.allCases {
            popup.addItem(withTitle: action.title); popup.lastItem?.representedObject = action.rawValue
        }
        popup.selectItem(at: EditorEscAction.allCases.firstIndex(of: Preferences.editorEscAction) ?? 0)
        bind(popup) {
            let raw = ($0 as? PillPopUp)?.selectedItem?.representedObject as? String
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

    /// A caption over a sunken tray of rows, with grooves between them and an optional note under it.
    private func group(_ title: String, _ rows: [NSView], note: String? = nil) -> NSView {
        let header = RetroLabel(caption: title, tone: .soft)

        var items: [NSView] = []
        for (i, r) in rows.enumerated() {
            if i > 0 { items.append(RetroGroove()) }
            items.append(r)
        }
        let inner = verticalStack(items, spacing: 0, inset: 14)
        let box = RetroWell()
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])

        var views: [NSView] = [header, box]
        if let note {
            let n = RetroUI.hint(note, size: 11, wraps: true)
            n.preferredMaxLayoutWidth = Self.width - Self.sidebarWidth - 2 * Self.paneMargin
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
        let label = RetroLabel(text: title, tone: .ink, size: 12.5)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        let text = NSStackView(views: [label])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        if let subtitle {
            let s = RetroUI.hint(subtitle, size: 11, wraps: true)
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
            control.topAnchor.constraint(greaterThanOrEqualTo: v.topAnchor, constant: 8),
            text.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
        ])
        return v
    }

    private func toggle(_ title: String, _ subtitle: String?, _ on: Bool, using s: RetroSwitch = RetroSwitch(),
                        _ set: @escaping (Bool) -> Void) -> NSView {
        s.state = on ? .on : .off
        s.setAccessibilityLabel(title)
        bind(s) { set(($0 as? NSButton)?.state == .on) }
        return row(title, subtitle, s)
    }

    private func bind(_ control: NSControl, _ run: @escaping (NSControl) -> Void) {
        let a = ControlAction(run)
        actions.append(a)
        control.target = a; control.action = #selector(ControlAction.fire(_:))
    }

    /// `bind` for the kit's views that send an action without being controls.
    private func bind(_ segmented: RetroSegmented, _ run: @escaping (RetroSegmented) -> Void) {
        let a = ViewAction { [weak segmented] in if let segmented { run(segmented) } }
        viewActions.append(a)
        segmented.target = a; segmented.action = #selector(ViewAction.fire(_:))
    }

    private func bind(_ swatches: SwatchRow, _ run: @escaping (SwatchRow) -> Void) {
        let a = ViewAction { [weak swatches] in if let swatches { run(swatches) } }
        viewActions.append(a)
        swatches.target = a; swatches.action = #selector(ViewAction.fire(_:))
    }

    /// A row of choices in a sunken track, `(title, tag)`, on the one tagged `selected`.
    private func segmented(_ items: [(String, Int)], selected: Int, name: String,
                           _ run: @escaping (Int) -> Void) -> RetroSegmented {
        let s = RetroSegmented()
        for (title, tag) in items { s.addItem(title, tag: tag) }
        s.selectItem(withTag: selected)
        s.setAccessibilityLabel(name)
        bind(s) { run($0.selectedTag()) }
        return s
    }

    /// An LCD chip between ◀ ▶ for a longer list of choices; filled and bound by the caller like a pop-up.
    private func lcdPopUp() -> PillPopUp { RetroUI.stepper(target: nil, action: nil) }

    private func refreshLogin() { loginSwitch.state = LaunchAtLogin.isOn ? .on : .off }

    private func refreshSystemState() {
        refreshPermissions()
        scratchPadSwitch.state = Preferences.textScratchPad ? .on : .off   // may have been switched in the editor
        // A paste banner may have remembered a destination in the meantime.
        if pasteList.superview != nil { reloadPasteDestinations() }
        shortcutsPane.refreshMacShortcuts()
    }

    private func refreshPermissions() {
        for (permission, label) in permissionLabels { showStatus(permission, in: label) }
    }

    private func showStatus(_ permission: Permission, in label: NSTextField) {
        label.stringValue = permission.status
        label.textColor = Retro.color(permission.isGranted ? Retro.teal : Retro.orange)
    }

    /// Status and an Open System Settings button for one permission; `purpose` replaces its general one.
    private func permissionRow(_ permission: Permission) -> NSView { permissionRow(permission, purpose: permission.purpose) }

    private func permissionRow(_ permission: Permission, purpose: String) -> NSView {
        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12, weight: .medium)
        // Panes built after Settings came to the front would otherwise show no status until it comes to the front again.
        showStatus(permission, in: status)
        permissionLabels.append((permission, status))
        let open = RetroUI.key("Open System Settings")
        bind(open) { _ in
            // Adds Skreener to the Accessibility list (switched off) the first time, so it can just be turned on.
            if permission == .accessibility { AccessibilityAccess.request() }
            permission.openSettings()
        }
        let control = NSStackView(views: [status, open])
        control.spacing = 10
        return row(permission.title, purpose, control)
    }

    // MARK: Paste destinations

    /// Settings → After Capture → Paste Destinations (#327): the switch, the remembered destinations and Accessibility.
    private func pasteDestinationsGroup() -> NSView {
        pasteList.orientation = .vertical
        pasteList.alignment = .leading
        pasteList.spacing = 0
        reloadPasteDestinations()
        return group("Paste Destinations", [
            toggle("Choose clean text or Markdown when pasting",
                   "Capture Text copies paste as Markdown into GitHub, code editors (VS Code, Xcode, Zed, Sublime Text), "
                   + "Obsidian and terminals, and as clean text everywhere else. Off: always clean text.",
                   Preferences.choosePasteFormat) { on in
                Preferences.choosePasteFormat = on
                if !on { PasteWatcher.shared.disarm() } else if !AccessibilityAccess.granted { AccessibilityAccess.request() }
            },
            pasteList,
            row("Banner", "The banner appears the first time you paste into each app or site.", showBannerAgainButton()),
            permissionRow(.accessibility, purpose: "Needed to notice ⌘V. Without it, copies paste as clean text."),
        ], note: "After a paste, a banner says which text went where; its button switches that app or site (GitHub, "
            + "Google Docs) to the other one from then on. Copy as Markdown and Copy Plain Text Only in the scratch pad "
            + "always paste what they say.")
    }

    private func showBannerAgainButton() -> NSButton {
        let button = RetroUI.key("Show the banner again everywhere")
        bind(button) { _ in Preferences.pasteBannerShown = [] }
        return button
    }

    private func reloadPasteDestinations() {
        for v in pasteList.arrangedSubviews {
            pasteList.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let choices = Preferences.pasteChoices
        let names = Preferences.pasteDestinationNames
        let keys = choices.keys.sorted { (names[$0] ?? $0).localizedStandardCompare(names[$1] ?? $1) == .orderedAscending }
        var rows = keys.map { pasteDestinationRow(key: $0, name: names[$0] ?? $0, choice: choices[$0]) }
        if rows.isEmpty {
            rows = [row("No remembered destinations",
                        "Use the button on the banner after a paste to remember the other text for that app or site.",
                        NSTextField(labelWithString: ""))]
        }
        for (i, r) in rows.enumerated() {
            // The group puts grooves around the list; these go between its rows.
            let views: [NSView] = i > 0 ? [RetroGroove(), r] : [r]
            for v in views {
                pasteList.addArrangedSubview(v)
                v.widthAnchor.constraint(equalTo: pasteList.widthAnchor).isActive = true
            }
        }
    }

    /// One remembered destination: a Clean text / Markdown pop-up and a button that forgets it.
    private func pasteDestinationRow(key: String, name: String, choice: String?) -> NSView {
        let popup = lcdPopUp()
        popup.setAccessibilityLabel("\(name): paste as")
        for c in PasteDestination.Choice.allCases {
            popup.addItem(withTitle: c.title)
            popup.lastItem?.representedObject = c.rawValue
        }
        popup.selectItem(at: PasteDestination.Choice.allCases.firstIndex { $0.rawValue == choice } ?? 0)
        bind(popup) {
            let raw = ($0 as? PillPopUp)?.selectedItem?.representedObject as? String
            Preferences.rememberPasteChoice(raw.flatMap(PasteDestination.Choice.init(rawValue:)) ?? .clean, for: key, name: name)
        }
        let remove = RetroUI.key(symbol: "trash", tip: "Forget this destination", height: RetroUI.textKeyHeight)
        bind(remove) { [weak self] _ in
            Preferences.forgetPasteChoice(for: key)
            self?.reloadPasteDestinations()
        }
        let control = NSStackView(views: [popup, remove])
        control.spacing = 8
        return row(name, control)
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

/// A closure as the target of a kit view's action (`RetroSegmented`, `SwatchRow`), which aren't controls.
@MainActor private final class ViewAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire(_ sender: Any?) { run() }
}

/// A key in Settings' sidebar: a cream key with a lamp, the pane's symbol and its name. The pane shown has its key
/// pressed down with an orange bar along it and its lamp lit orange; under the pointer, a key's lamp glows teal.
private final class SettingsNavKey: NSButton {
    var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected ? 1 : 0) } }
    private var hovering = false { didSet { needsDisplay = true } }
    private let name: String
    private let symbol: String
    private let run: () -> Void

    init(title: String, symbol: String, run: @escaping () -> Void) {
        name = title
        self.symbol = symbol
        self.run = run
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        setAccessibilityLabel(title)
        setAccessibilityRole(.radioButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { run() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let p = Retro.palette(for: self)
        let colors = Retro.keyColors(.cream, p)
        let face = Retro.drawKey(in: bounds, radius: 6, colors: colors, down: isSelected || isHighlighted, flipped: isFlipped)

        let lamp = NSRect(x: face.minX + 9, y: face.midY - 3, width: 6, height: 6)
        Retro.drawLamp(in: lamp, color: Retro.color(isSelected ? Retro.orange : Retro.teal), lit: isSelected || hovering,
                       unlit: Retro.color(p.toggleOff))

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [colors.ink]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = image.size
            image.draw(in: NSRect(x: face.minX + 29 - s.width / 2, y: face.midY - s.height / 2, width: s.width, height: s.height))
        }

        let text = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: colors.ink,
        ])
        let t = text.size()
        text.draw(at: NSPoint(x: face.minX + 42, y: face.midY - t.height / 2))

        if isSelected {
            // The orange bar along the bottom of the pressed key's face.
            let bar = NSRect(x: face.minX + 10, y: isFlipped ? face.maxY - 5 : face.minY + 3, width: face.width - 20, height: 2)
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = Retro.color(Retro.orange)
            glow.shadowBlurRadius = 4
            glow.set()
            Retro.color(Retro.orange).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The LCD at the top of Settings' sidebar: "SK-1 · Settings" in small type over the pane's name.
private final class SettingsLCD: NSView {
    var title = "" { didSet { needsDisplay = true; setAccessibilityValue(title) } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Settings pane")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let glass = Retro.drawLCD(in: bounds.insetBy(dx: 0, dy: 0.5), radius: 8, inset: 4, palette: Retro.palette(for: self),
                                  flipped: true)
        let small = NSAttributedString(string: "SK-1 · SETTINGS", attributes: [
            .font: Retro.mono(8.5, weight: .semibold), .foregroundColor: Retro.color(Retro.lcdInk, alpha: 0.65), .kern: 0.6,
        ])
        let big = NSAttributedString(string: title.uppercased(), attributes: Retro.chipAttributes(size: 11.5))
        small.draw(at: NSPoint(x: glass.minX + 8, y: glass.minY + 5))
        big.draw(at: NSPoint(x: glass.minX + 8, y: glass.minY + 17))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
