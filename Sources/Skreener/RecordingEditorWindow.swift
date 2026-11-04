import AppKit
import AVFoundation
import UniformTypeIdentifiers
import SkreenerCore

/// The recording editor (#24), opened from a Record for editing recording's Quick Access preview (Edit, or a double
/// click): a preview with play/pause and a scrubber, and an inspector for Studio Mode's background (fill, padding,
/// corners, shadow, aspect ratio) and the effects from the event track. The preview is drawn by the same
/// `StudioCompositor` as the export, at a reduced size. Under the scrubber, the zoom track shows the auto-zoom sections
/// (made from the clicks the first time the recording is opened), which can be moved, resized, added and deleted, with
/// undo; the inspector sets the selected one's level and mode. Export makes the finished MP4 again and saves it over the
/// recording (the project keeps the clean video, so nothing is lost), then goes on as after recording: Compress when
/// that is on, the library, and a new Quick Access preview. The settings are saved in the project (`studio.json`);
/// closing without exporting asks before throwing changes away.
@MainActor final class RecordingEditorWindow: NSObject, NSWindowDelegate {
    private static var live: [RecordingEditorWindow] = []

    /// Opens the editor for the finished recording `file`, made from the project in `folder` (or brings it forward).
    /// False when the project can't be read.
    @discardableResult
    static func open(_ file: URL, project folder: URL) -> Bool {
        if let open = live.first(where: { $0.folder == folder }) {
            NSApp.activate(ignoringOtherApps: true)
            open.window.makeKeyAndOrderFront(nil)
            return true
        }
        let project: RecordingProject
        do {
            project = try RecordingProject.decode(Data(contentsOf: folder.appendingPathComponent(RecordingProject.projectFile)))
        } catch {
            NSLog("Couldn't open the recording project: \(error)")
            return false
        }
        let eventsData = try? Data(contentsOf: folder.appendingPathComponent(RecordingProject.eventsFile))
        let events = eventsData.flatMap { try? RecordingEvents.decode($0) }?.sorted() ?? RecordingEvents()
        let editor = RecordingEditorWindow(file: file, folder: folder, project: project, events: events)
        live.append(editor)
        editor.present()
        return true
    }

    /// The preview is at most this many pixels (it is scaled to the window).
    private static let previewMax = CGSize(width: 1280, height: 800)

    private let file: URL
    private let folder: URL
    private var project: RecordingProject
    private let events: RecordingEvents
    /// What is on screen, and what is saved in the project (and in the finished MP4).
    private var settings: StudioSettings { didSet { if settings != oldValue { settingsChanged() } } }
    private var saved: StudioSettings
    private let window: EditorPanel
    private let preview = StudioPreview()
    private let zoomTrack = ZoomTrackView()

    // Playback: the player plays (with sound) and its video output gives the frames; while paused or scrubbing the
    // frame at the playhead comes from the image generator.
    private let player: AVPlayer
    private let videoOutput: AVPlayerItemVideoOutput
    private let generator: AVAssetImageGenerator
    private var duration: Double = 0
    private var time: Double = 0
    private var playing = false
    private var source: CGImage?
    private var frameRequest = 0
    private var ticker: Timer?
    private var compositor: StudioCompositor

    // Export
    private var exportTask: Task<Void, Never>?
    private var exportProgress: ExportProgress?
    private var progressTimer: Timer?
    private var closeAfterExport = false

    // Transport
    private let playButton = RetroUI.key(symbol: "play.fill", tip: "Play (Space)")
    private let scrubber = NSSlider()
    private let timeField = NSTextField(labelWithString: "0:00.0 / 0:00.0")

    // Background
    private let backgroundSwitch = RetroSwitch()
    private let fillPopup = PillPopUp(pullsDown: false, height: RetroUI.textKeyHeight, style: .keycap)
    private let directionPopup = RetroUI.stepper(tip: "Gradient direction", target: nil, action: nil)
    private let gradientFrom = ColorPill()
    private let gradientTo = ColorPill()
    private let chooseImageButton = RetroUI.key("Choose…")
    private let blurPopup = RetroUI.stepper(tip: "Blur", target: nil, action: nil)
    private let paddingPopup = RetroUI.stepper(tip: "Padding", target: nil, action: nil)
    private let cornerPopup = RetroUI.stepper(tip: "Corner radius", target: nil, action: nil)
    private let shadowSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let aspectPopup = PillPopUp(pullsDown: false, height: RetroUI.textKeyHeight, style: .keycap)
    private var directionRow = NSView(), colorsRow = NSView(), pictureRow = NSView()

    // Effects
    private let cursorSwitch = RetroSwitch()
    private let clicksSwitch = RetroSwitch()
    private let clickColor = ColorPill()
    private let clickSizePopup = RetroUI.stepper(tip: "Click ring size", target: nil, action: nil)
    private let keysSwitch = RetroSwitch()
    private let keySizePopup = RetroUI.stepper(tip: "Keystroke size", target: nil, action: nil)
    private let keyPositionPopup = RetroUI.stepper(tip: "Where the keystrokes show", target: nil, action: nil)
    private let spotlightSwitch = RetroSwitch()

    // Zoom
    private let autoZoomSwitch = RetroSwitch()
    private let addZoomButton = RetroUI.key("+ Zoom")
    private let regenerateButton = RetroUI.key("Regenerate")
    private let levelPopup = RetroUI.stepper(tip: "How far the selected zoom goes in", target: nil, action: nil)
    private let modePopup = RetroUI.stepper(tip: "Whether the selected zoom follows the pointer or stays on one spot",
                                            target: nil, action: nil)
    private let zoomHint = RetroUI.hint(wraps: true)
    /// The selected zoom section (an index into `settings.zoomSections`).
    private var selectedZoom: Int?
    /// While a section is dragged: the sections before the drag, and what the drag is called for Undo.
    private var zoomDrag: (before: [ZoomSection], name: String)?

    // Export bar
    private let exportButton = RetroUI.key("Export", variant: .orange)
    private let cancelButton = RetroUI.key("Cancel")
    private let progressBar = NSProgressIndicator()
    private let status = RetroUI.hint()

    // What the event track has, so effects that weren't recorded can't be switched on.
    private var hasCursor: Bool { !events.cursor.isEmpty && !events.cursorImages.isEmpty }
    private var hasClicks: Bool { events.clicks.contains { $0.down } }
    private var hasKeys: Bool { !events.keys.isEmpty }
    private var hasSpotlight: Bool { !events.cursor.isEmpty && (events.spotlightAtStart || events.spotlight.contains { $0.on }) }

    private init(file: URL, folder: URL, project: RecordingProject, events: RecordingEvents) {
        self.file = file
        self.folder = folder
        self.project = project
        self.events = events
        let loaded = StudioSettings.load(folder: folder, project: project)
        settings = loaded
        saved = loaded
        let asset = AVURLAsset(url: folder.appendingPathComponent(RecordingProject.videoFile))
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        let item = AVPlayerItem(asset: asset)
        item.add(output)
        videoOutput = output
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player
        let compositor = RecordingEditorWindow.previewCompositor(project: project, events: events, folder: folder, settings: loaded)
        self.compositor = compositor
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Frames no bigger than the preview ever draws them (the largest is without a background).
        let most = StudioLayout.previewScale(canvas: project.videoSize, fitting: RecordingEditorWindow.previewMax)
        generator.maximumSize = CGSize(width: (project.videoSize.width * most).rounded(.up),
                                       height: (project.videoSize.height * most).rounded(.up))
        self.generator = generator
        window = EditorPanel(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edit \(file.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.delegate = self
        window.onEscape = { [weak self] in self?.window.performClose(nil) }
        window.onSpace = { [weak self] in self?.togglePlay() }
        window.onUndo = { [weak self] redo in self?.undoKey(redo: redo) }
        build()
        refreshControls()
        window.center()
    }

    private static func previewCompositor(project: RecordingProject, events: RecordingEvents, folder: URL,
                                          settings: StudioSettings) -> StudioCompositor {
        let canvas = StudioLayout.make(videoSize: project.videoSize, pixelsPerPoint: project.pixelScale,
                                       background: settings.backgroundOn ? settings.background : nil).canvas
        let scale = StudioLayout.previewScale(canvas: canvas, fitting: previewMax)
        return StudioCompositor(project: project, events: events, folder: folder, settings: settings, scale: scale)
    }

    private func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        redraw()
        let asset = generator.asset
        Task { [weak self] in
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            guard let self else { return }
            self.duration = seconds.isFinite ? max(seconds, 0) : 0
            self.scrubber.maxValue = max(self.duration, 0.01)
            self.zoomTrack.duration = self.duration
            // The zoom track's time scale lines up with the scrubber's track, which is inset by half its knob.
            if let cell = self.scrubber.cell as? NSSliderCell {
                self.zoomTrack.inset = cell.knobRect(flipped: self.scrubber.isFlipped).width / 2
            }
            self.generateZoomIfNeeded()
            self.refreshZoomControls()
            self.refreshTime()
            self.requestFrame()
        }
    }

    // MARK: Layout

    private func build() {
        let content = RetroUI.useChassis(window)

        // Preview, on a sunken well, with the transport under it.
        let well = RetroWell()
        preview.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(preview)
        preview.onClick = { [weak self] in self?.togglePlay() }
        preview.onOptionClick = { [weak self] p in self?.aimZoom(at: p) }

        playButton.target = self; playButton.action = #selector(togglePlay)
        scrubber.controlSize = .small
        scrubber.minValue = 0
        scrubber.maxValue = 1
        scrubber.isContinuous = true
        scrubber.target = self; scrubber.action = #selector(scrubbed)
        scrubber.toolTip = "Move through the recording"
        let timeBox = LCDTextBox(timeField, width: 140)
        timeField.alignment = .center
        let transport = NSStackView(views: [playButton, scrubber, timeBox])
        transport.spacing = 10
        transport.alignment = .centerY
        setUpZoomTrack()

        // The inspector, scrolling when the window is too short for it.
        let inspector = NSStackView(views: buildBackground() + [RetroGroove()] + buildEffects() + [RetroGroove()] + buildZoom())
        inspector.orientation = .vertical
        inspector.alignment = .leading
        inspector.spacing = 8
        inspector.subviews.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        for v in inspector.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: inspector.widthAnchor).isActive = true
        }
        let document = InspectorDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        inspector.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(inspector)
        let inspectorScroll = NSScrollView()
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.autohidesScrollers = true
        inspectorScroll.drawsBackground = false
        inspectorScroll.borderType = .noBorder
        inspectorScroll.automaticallyAdjustsContentInsets = false
        inspectorScroll.documentView = document
        let clip = inspectorScroll.contentView
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            inspector.topAnchor.constraint(equalTo: document.topAnchor),
            inspector.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            inspector.widthAnchor.constraint(equalToConstant: 300),
            inspector.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4),
        ])

        // The export bar.
        exportButton.toolTip = "Make the finished video again with these settings and save it over the recording"
        exportButton.target = self; exportButton.action = #selector(export)
        cancelButton.toolTip = "Stop exporting; the recording stays as it was"
        cancelButton.target = self; cancelButton.action = #selector(cancelExport)
        cancelButton.isHidden = true
        progressBar.style = .bar
        progressBar.controlSize = .small
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isHidden = true
        progressBar.widthAnchor.constraint(equalToConstant: 180).isActive = true
        status.stringValue = "Export saves over \(file.lastPathComponent); the original stays in the project."
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        status.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [status, spacer, progressBar, cancelButton, exportButton])
        bar.spacing = 10
        bar.alignment = .centerY

        [well, transport, zoomTrack, inspectorScroll, bar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        let top = RetroUI.contentTop(of: window, in: content)
        NSLayoutConstraint.activate([
            well.topAnchor.constraint(equalTo: top, constant: 10),
            well.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            well.trailingAnchor.constraint(equalTo: inspectorScroll.leadingAnchor, constant: -16),
            preview.topAnchor.constraint(equalTo: well.topAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -8),
            preview.bottomAnchor.constraint(equalTo: well.bottomAnchor, constant: -8),
            transport.topAnchor.constraint(equalTo: well.bottomAnchor, constant: 10),
            transport.leadingAnchor.constraint(equalTo: well.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: well.trailingAnchor),
            zoomTrack.topAnchor.constraint(equalTo: transport.bottomAnchor, constant: 8),
            zoomTrack.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),
            zoomTrack.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),
            zoomTrack.heightAnchor.constraint(equalToConstant: 26),
            inspectorScroll.topAnchor.constraint(equalTo: top, constant: 10),
            inspectorScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            inspectorScroll.widthAnchor.constraint(equalToConstant: 306),
            inspectorScroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10),
            bar.topAnchor.constraint(equalTo: zoomTrack.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    /// A caption on the left (a fixed width, so the controls line up) and `views` after it.
    private func row(_ title: String, _ views: [NSView]) -> NSStackView {
        let label = RetroLabel(text: title, tone: .ink, size: 12)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label] + views + [spacer])
        row.spacing = 8
        row.alignment = .centerY
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return row
    }

    private func header(_ title: String) -> NSView {
        RetroLabel(caption: title)
    }

    private func setUp(_ popup: PillPopUp, _ choices: [(String, Int)], action: Selector) {
        popup.target = self
        popup.action = action
        for (title, tag) in choices { popup.addItem(withTitle: title); popup.lastItem?.tag = tag }
    }

    private func setUp(_ s: RetroSwitch, _ name: String) {
        s.setAccessibilityLabel(name)
        s.target = self
        s.action = #selector(switchToggled(_:))
    }

    private func buildBackground() -> [NSView] {
        setUp(backgroundSwitch, "Background")
        backgroundSwitch.toolTip = "A background with padding, rounded corners and a shadow around the recording"

        fillPopup.toolTip = "Fill"
        fillPopup.target = self; fillPopup.action = #selector(fillPicked)
        fillPopup.menu?.autoenablesItems = false
        for (i, preset) in Background.presets.enumerated() {
            fillPopup.addItem(withTitle: preset.name)
            fillPopup.lastItem?.tag = i
            var b = Background()
            b.fill = i
            fillPopup.lastItem?.image = b.swatch()
        }
        fillPopup.menu?.addItem(.separator())
        for (title, tag) in [("Custom Gradient", Background.customFill), ("Desktop Wallpaper", Background.wallpaperFill),
                             ("Image…", Background.imageFill)] {
            fillPopup.addItem(withTitle: title); fillPopup.lastItem?.tag = tag
        }

        setUp(directionPopup, Background.GradientDirection.allCases.map { ($0.name, $0.rawValue) },
              action: #selector(backgroundOptionPicked(_:)))
        for (pill, tip) in [(gradientFrom, "Gradient start color"), (gradientTo, "Gradient end color")] {
            pill.toolTip = tip
            pill.target = self; pill.action = #selector(gradientColorChanged)
        }
        chooseImageButton.toolTip = "Choose the picture for the background"
        chooseImageButton.target = self; chooseImageButton.action = #selector(chooseImage)
        setUp(blurPopup, [("No Blur", 0), ("Light", 6), ("Blur", 15), ("Strong", 35)], action: #selector(backgroundOptionPicked(_:)))
        setUp(paddingPopup, [0, 16, 32, 48, 64, 96, 128].map { ("\($0) pt", $0) }, action: #selector(backgroundOptionPicked(_:)))
        setUp(cornerPopup, [0, 6, 10, 16, 24].map { ("\($0) pt", $0) }, action: #selector(backgroundOptionPicked(_:)))
        aspectPopup.toolTip = "Aspect ratio of the whole video"
        setUp(aspectPopup, [("Any Ratio", -1)] + Background.aspects.enumerated().map { ($1.name, $0) },
              action: #selector(backgroundOptionPicked(_:)))
        shadowSlider.controlSize = .small
        shadowSlider.isContinuous = true
        shadowSlider.toolTip = "Shadow under the recording"
        shadowSlider.target = self; shadowSlider.action = #selector(shadowChanged)
        shadowSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true

        directionRow = row("Direction", [directionPopup])
        colorsRow = row("Colors", [gradientFrom, gradientTo])
        pictureRow = row("Picture", [chooseImageButton, blurPopup])
        return [
            row("Background", [backgroundSwitch]),
            row("Fill", [fillPopup]),
            directionRow, colorsRow, pictureRow,
            row("Padding", [paddingPopup]),
            row("Corners", [cornerPopup]),
            row("Shadow", [shadowSlider]),
            row("Aspect", [aspectPopup]),
        ]
    }

    private func buildEffects() -> [NSView] {
        setUp(cursorSwitch, "Cursor")
        setUp(clicksSwitch, "Click rings")
        setUp(keysSwitch, "Keystrokes")
        setUp(spotlightSwitch, "Spotlight")
        cursorSwitch.toolTip = hasCursor ? "Draw the pointer" : "No pointer was recorded"
        clicksSwitch.toolTip = hasClicks ? "A ring at every click" : "No clicks were recorded"
        keysSwitch.toolTip = hasKeys ? "The keys pressed, in a pill" : "No keystrokes were recorded (turn on Show Keystrokes before recording)"
        spotlightSwitch.toolTip = hasSpotlight ? "Dim around the pointer where the spotlight was on while recording"
            : "The spotlight wasn't on while recording"
        clickColor.toolTip = "Click ring color"
        clickColor.target = self; clickColor.action = #selector(clickColorChanged)
        let style = settings.effects
        setUp(clickSizePopup, Self.sizes([32, 48, 64, 80], with: style.clickSize, saved: project.style.clickSize),
              action: #selector(effectOptionPicked(_:)))
        setUp(keySizePopup, Self.sizes([18, 24, 32, 40], with: style.keystrokeSize, saved: project.style.keystrokeSize),
              action: #selector(effectOptionPicked(_:)))
        setUp(keyPositionPopup, [("Bottom", 0), ("Top", 1)], action: #selector(effectOptionPicked(_:)))
        return [
            header("Effects"),
            row("Cursor", [cursorSwitch]),
            row("Clicks", [clicksSwitch, clickColor, clickSizePopup]),
            row("Keystrokes", [keysSwitch, keySizePopup]),
            row("", [keyPositionPopup]),
            row("Spotlight", [spotlightSwitch]),
        ]
    }

    private func buildZoom() -> [NSView] {
        setUp(autoZoomSwitch, "Auto-zoom")
        autoZoomSwitch.toolTip = "Zoom in where the zoom sections are; off shows the whole recording but keeps the sections"
        addZoomButton.toolTip = "Add a zoom section at the playhead"
        addZoomButton.target = self; addZoomButton.action = #selector(addZoomAtPlayhead)
        regenerateButton.toolTip = "Make the zoom sections from the clicks again"
        regenerateButton.target = self; regenerateButton.action = #selector(regenerateZoom)
        setUp(levelPopup, AutoZoom.levels.map { (ZoomTrackView.levelText($0), Self.levelTag($0)) },
              action: #selector(zoomOptionPicked(_:)))
        setUp(modePopup, [("Follow Pointer", 0), ("Fixed", 1)], action: #selector(zoomOptionPicked(_:)))
        zoomHint.preferredMaxLayoutWidth = 290
        return [
            header("Zoom"),
            row("Auto-zoom", [autoZoomSwitch]),
            row("", [addZoomButton, regenerateButton]),
            row("Level", [levelPopup]),
            row("Mode", [modePopup]),
            zoomHint,
        ]
    }

    private static func levelTag(_ level: Double) -> Int { Int((level * 100).rounded()) }

    private func setUpZoomTrack() {
        zoomTrack.onSelect = { [weak self] index in self?.selectZoom(index) }
        zoomTrack.onDragBegan = { [weak self] _ in
            guard let self else { return }
            self.zoomDrag = (self.settings.zoomSections, "Move Zoom")
        }
        zoomTrack.onDrag = { [weak self] index, kind, t in self?.dragZoom(index, kind, to: t) }
        zoomTrack.onDragEnded = { [weak self] in self?.endZoomDrag() }
        zoomTrack.onAdd = { [weak self] t in self?.addZoom(at: t) }
        zoomTrack.onDelete = { [weak self] in self?.deleteZoom() }
    }

    /// Size choices in points, with the ones in use added.
    private static func sizes(_ base: [Int], with current: Double, saved: Double) -> [(String, Int)] {
        Array(Set(base + [Int(current.rounded()), Int(saved.rounded())])).sorted().map { ("\($0) pt", $0) }
    }

    // MARK: Showing the settings

    private func refreshControls() {
        let b = settings.background.background
        let on = settings.backgroundOn
        backgroundSwitch.state = on ? .on : .off
        refreshPictureItems(b)
        fillPopup.selectItem(withTag: b.fill)
        let custom = b.fill == Background.customFill
        let picture = b.fill == Background.wallpaperFill || b.fill == Background.imageFill
        let gradient = custom || (Background.presets.indices.contains(b.fill) && Background.presets[b.fill].colors.count > 1)
        directionRow.isHidden = !gradient
        colorsRow.isHidden = !custom
        pictureRow.isHidden = !picture
        chooseImageButton.isHidden = b.fill != Background.imageFill
        directionPopup.selectItem(withTag: b.direction.rawValue)
        if b.colors.count == 2 { gradientFrom.color = b.colors[0].nsColor; gradientTo.color = b.colors[1].nsColor }
        blurPopup.selectItem(withTag: Int(b.imageBlur))
        paddingPopup.selectItem(withTag: Int(b.padding))
        cornerPopup.selectItem(withTag: Int(b.cornerRadius))
        shadowSlider.doubleValue = Double(b.shadow)
        aspectPopup.selectItem(withTag: Background.aspects.firstIndex { $0.aspect == b.aspect } ?? -1)
        let backgroundControls: [NSControl] = [fillPopup, directionPopup, gradientFrom, gradientTo, chooseImageButton, blurPopup,
                                               paddingPopup, cornerPopup, shadowSlider, aspectPopup]
        let exporting = exportTask != nil
        backgroundControls.forEach { $0.isEnabled = on && !exporting }
        backgroundSwitch.isEnabled = !exporting

        let e = settings.effects
        cursorSwitch.state = e.cursor && hasCursor ? .on : .off
        clicksSwitch.state = e.clicks && hasClicks ? .on : .off
        keysSwitch.state = e.keystrokes && hasKeys ? .on : .off
        spotlightSwitch.state = settings.spotlight && hasSpotlight ? .on : .off
        cursorSwitch.isEnabled = hasCursor && !exporting
        clicksSwitch.isEnabled = hasClicks && !exporting
        keysSwitch.isEnabled = hasKeys && !exporting
        spotlightSwitch.isEnabled = hasSpotlight && !exporting
        clickColor.color = NSColor(cgColor: e.clickColor.cgColor) ?? .systemYellow
        clickSizePopup.selectItem(withTag: Int(e.clickSize.rounded()))
        keySizePopup.selectItem(withTag: Int(e.keystrokeSize.rounded()))
        keyPositionPopup.selectItem(withTag: e.keystrokesAtTop ? 1 : 0)
        [clickColor, clickSizePopup].forEach { $0.isEnabled = e.clicks && hasClicks && !exporting }
        [keySizePopup, keyPositionPopup].forEach { $0.isEnabled = e.keystrokes && hasKeys && !exporting }

        refreshZoomControls()
    }

    private func refreshZoomControls() {
        let exporting = exportTask != nil
        let sections = settings.zoomSections
        if let i = selectedZoom, !sections.indices.contains(i) { selectedZoom = nil }
        zoomTrack.sections = sections
        zoomTrack.selected = selectedZoom
        zoomTrack.dimmed = !settings.autoZoom
        zoomTrack.isEnabled = !exporting
        autoZoomSwitch.state = settings.autoZoom ? .on : .off
        autoZoomSwitch.isEnabled = !exporting
        addZoomButton.isEnabled = !exporting && duration > 0
        regenerateButton.isEnabled = !exporting && duration > 0
        let section = selectedZoom.map { sections[$0] }
        levelPopup.isEnabled = section != nil && !exporting
        modePopup.isEnabled = section != nil && !exporting
        if let section {
            let tag = Self.levelTag(section.level)
            if levelPopup.menu?.item(withTag: tag) == nil {
                levelPopup.addItem(withTitle: ZoomTrackView.levelText(section.level))
                levelPopup.lastItem?.tag = tag
            }
            levelPopup.selectItem(withTag: tag)
            modePopup.selectItem(withTag: section.mode == .fixed ? 1 : 0)
        }
        if let section {
            zoomHint.stringValue = section.mode == .fixed ? "Option-click the preview to aim this zoom."
                : "This zoom follows the pointer."
        } else if sections.isEmpty {
            zoomHint.stringValue = "No zoom sections. Double-click the track under the scrubber, or press + Zoom."
        } else {
            zoomHint.stringValue = "Click a zoom on the track under the scrubber to change it."
        }
        window.isDocumentEdited = settings != saved
    }

    /// The wallpaper item shows whether there is a still wallpaper; the custom and picture items show the current ones.
    private func refreshPictureItems(_ bg: Background) {
        let items = fillPopup.menu?.items ?? []
        if let item = items.first(where: { $0.tag == Background.wallpaperFill }) {
            let available = Background.wallpaper != nil
            item.isEnabled = available
            item.title = available ? "Desktop Wallpaper" : "Desktop Wallpaper (unavailable)"
            var b = bg
            b.fill = Background.wallpaperFill
            item.image = available ? b.swatch() : nil
        }
        if let item = items.first(where: { $0.tag == Background.customFill }) {
            var b = bg
            b.fill = Background.customFill
            item.image = b.swatch()
        }
        if let item = items.first(where: { $0.tag == Background.imageFill }) {
            let name = bg.imageURL?.deletingPathExtension().lastPathComponent ?? ""
            item.title = name.isEmpty ? "Image…" : "Image: " + (name.count > 16 ? name.prefix(15) + "…" : name)
            var b = bg
            b.fill = Background.imageFill
            item.image = bg.imageURL == nil ? nil : b.swatch()
        }
        fillPopup.synchronizeTitleAndSelectedItem()
    }

    private func settingsChanged() {
        if settings.withoutZoom == compositor.settings.withoutZoom {
            // Only the zoom changed (e.g. a section dragged): keep the background and effects.
            compositor = compositor.zoomed(settings)
            refreshZoomControls()
        } else {
            compositor = Self.previewCompositor(project: project, events: events, folder: folder, settings: settings)
            refreshControls()
        }
        redraw()
    }

    // MARK: Editing

    private func changeBackground(_ change: (inout Background) -> Void) {
        var b = settings.background.background
        change(&b)
        settings.background = StudioBackground(b)
    }

    @objc private func switchToggled(_ sender: RetroSwitch) {
        let on = sender.state == .on
        switch sender {
        case backgroundSwitch:
            // The first time, start from the background the screenshot editor used last.
            if on, !settings.backgroundOn, settings.background == StudioBackground(), saved.background == StudioBackground() {
                settings.background = StudioBackground(Preferences.lastBackground)
            }
            settings.backgroundOn = on
        case cursorSwitch: settings.effects.cursor = on
        case clicksSwitch: settings.effects.clicks = on
        case keysSwitch: settings.effects.keystrokes = on
        case spotlightSwitch: settings.spotlight = on
        case autoZoomSwitch: settings.autoZoom = on
        default: break
        }
    }

    @objc private func fillPicked() {
        let fill = fillPopup.selectedTag()
        if fill == Background.imageFill, settings.background.imagePath == nil {
            chooseImage()
            return
        }
        changeBackground { $0.fill = fill }
    }

    @objc private func backgroundOptionPicked(_ popup: PillPopUp) {
        let tag = popup.selectedTag()
        switch popup {
        case directionPopup: changeBackground { $0.direction = Background.GradientDirection(rawValue: tag) ?? .diagonal }
        case blurPopup: changeBackground { $0.imageBlur = CGFloat(tag) }
        case paddingPopup: changeBackground { $0.padding = CGFloat(tag) }
        case cornerPopup: changeBackground { $0.cornerRadius = CGFloat(tag) }
        case aspectPopup:
            changeBackground { $0.aspect = Background.aspects.indices.contains(tag) ? Background.aspects[tag].aspect : nil }
        default: break
        }
    }

    @objc private func gradientColorChanged() {
        let colors = [RGBColor(gradientFrom.color), RGBColor(gradientTo.color)]
        changeBackground { b in
            b.fill = Background.customFill
            b.colors = colors
        }
    }

    @objc private func shadowChanged() {
        let v = CGFloat(shadowSlider.doubleValue)
        changeBackground { $0.shadow = v }
    }

    /// Picks the picture for the background; cancelling leaves the background as it was.
    @objc private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture for the background"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url {
                self.changeBackground { b in
                    b.fill = Background.imageFill
                    b.imageURL = url
                }
            } else {
                self.refreshControls()
            }
        }
    }

    @objc private func clickColorChanged() {
        guard let c = clickColor.color.usingColorSpace(.sRGB) else { return }
        settings.effects.clickColor = RGBA(red: Double(c.redComponent), green: Double(c.greenComponent),
                                           blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }

    @objc private func effectOptionPicked(_ popup: PillPopUp) {
        let tag = popup.selectedTag()
        switch popup {
        case clickSizePopup: settings.effects.clickSize = Double(tag)
        case keySizePopup: settings.effects.keystrokeSize = Double(tag)
        case keyPositionPopup: settings.effects.keystrokesAtTop = tag == 1
        default: break
        }
    }

    // MARK: Zoom

    /// The zoom sections made from the clicks.
    private func generatedZoom() -> [ZoomSection] {
        AutoZoom.sections(from: events, videoSize: project.videoSize, duration: duration)
    }

    /// The first time the editor opens a recording (one from before auto-zoom too), its zoom sections are made from
    /// the clicks. That is part of opening it, not a change to ask about when closing.
    private func generateZoomIfNeeded() {
        guard !settings.zoomGenerated else { return }
        let sections = generatedZoom()
        if !saved.zoomGenerated {
            saved.zoomSections = sections
            saved.zoomGenerated = true
        }
        settings.zoomSections = sections
        settings.zoomGenerated = true
    }

    private func selectZoom(_ index: Int?) {
        selectedZoom = index
        refreshZoomControls()
    }

    /// Replaces the sections as one step Undo takes back, named `name`, and selects `select`.
    private func setZoom(_ sections: [ZoomSection], select: Int?, undo name: String) {
        let before = settings.zoomSections
        selectedZoom = select
        settings.zoomSections = sections
        registerZoomUndo(before, name: name)
        refreshZoomControls()
    }

    private func registerZoomUndo(_ before: [ZoomSection], name: String) {
        guard before != settings.zoomSections, let undo = window.undoManager else { return }
        undo.registerUndo(withTarget: self, selector: #selector(restoreZoom(_:)), object: ZoomUndoStep(before, name: name))
        undo.setActionName(name)
    }

    /// Undo and redo: puts back the sections in `step`, registering the ones now showing to go back to.
    @objc private func restoreZoom(_ step: ZoomUndoStep) {
        let current = settings.zoomSections
        if let undo = window.undoManager {
            undo.registerUndo(withTarget: self, selector: #selector(restoreZoom(_:)), object: ZoomUndoStep(current, name: step.name))
            undo.setActionName(step.name)
        }
        if let i = selectedZoom, !step.sections.indices.contains(i) { selectedZoom = nil }
        settings.zoomSections = step.sections
        refreshZoomControls()
    }

    /// ⌘Z and ⇧⌘Z (not while exporting).
    private func undoKey(redo: Bool) {
        guard exportTask == nil, zoomDrag == nil, let undo = window.undoManager else { return }
        if redo {
            if undo.canRedo { undo.redo() } else { NSSound.beep() }
        } else {
            if undo.canUndo { undo.undo() } else { NSSound.beep() }
        }
    }

    private func dragZoom(_ index: Int, _ kind: ZoomTrackView.Drag, to t: Double) {
        guard let drag = zoomDrag else { return }
        switch kind {
        case .move:
            settings.zoomSections = AutoZoom.move(drag.before, index: index, to: t, duration: duration)
        case .resize(let edge):
            zoomDrag?.name = "Resize Zoom"
            settings.zoomSections = AutoZoom.resize(drag.before, index: index, edge: edge, to: t, duration: duration)
        }
    }

    private func endZoomDrag() {
        guard let drag = zoomDrag else { return }
        zoomDrag = nil
        registerZoomUndo(drag.before, name: drag.name)
    }

    @objc private func addZoomAtPlayhead() { addZoom(at: time) }

    /// Adds a section at `t`, aimed at the pointer there (for Fixed); beeps when `t` is in a section or there is no room.
    private func addZoom(at t: Double) {
        guard exportTask == nil else { return }
        var center = CGPoint(x: project.videoSize.width / 2, y: project.videoSize.height / 2)
        if let c = events.cursorState(at: t), c.visible, RecordingGeometry.contains(c.point, videoSize: project.videoSize) {
            center = c.point
        }
        guard let added = AutoZoom.add(to: settings.zoomSections, at: t, duration: duration, center: center) else {
            NSSound.beep()
            return
        }
        setZoom(added.sections, select: added.index, undo: "Add Zoom")
    }

    private func deleteZoom() {
        guard exportTask == nil, let i = selectedZoom, settings.zoomSections.indices.contains(i) else { return }
        var sections = settings.zoomSections
        sections.remove(at: i)
        setZoom(sections, select: nil, undo: "Delete Zoom")
    }

    @objc private func zoomOptionPicked(_ popup: PillPopUp) {
        guard let i = selectedZoom, settings.zoomSections.indices.contains(i) else { return }
        let tag = popup.selectedTag()
        var sections = settings.zoomSections
        switch popup {
        case levelPopup:
            sections[i].level = AutoZoom.clampLevel(Double(tag) / 100)
            setZoom(sections, select: i, undo: "Change Zoom Level")
        case modePopup:
            sections[i].mode = tag == 1 ? .fixed : .follow
            setZoom(sections, select: i, undo: "Change Zoom Mode")
        default: break
        }
    }

    /// Option-click on the preview: aims the selected Fixed zoom at that spot of the recording.
    private func aimZoom(at p: CGPoint) {
        guard exportTask == nil, let i = selectedZoom, settings.zoomSections.indices.contains(i),
              settings.zoomSections[i].mode == .fixed else { return }
        let size = compositor.size, box = preview.bounds
        let k = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        guard k > 0 else { return }
        let shown = CGRect(x: box.midX - size.width * k / 2, y: box.midY - size.height * k / 2,
                           width: size.width * k, height: size.height * k)
        let canvas = CGPoint(x: (p.x - shown.minX) / k / compositor.scale, y: (p.y - shown.minY) / k / compositor.scale)
        let v = compositor.layout.videoPoint(canvas: canvas, crop: compositor.crop(at: time))
        let video = project.videoSize
        var sections = settings.zoomSections
        sections[i].x = Double(min(max(v.x, 0), video.width))
        sections[i].y = Double(min(max(v.y, 0), video.height))
        setZoom(sections, select: i, undo: "Aim Zoom")
    }

    /// Makes the sections from the clicks again; asks first when that would replace sections that were changed.
    @objc private func regenerateZoom() {
        guard exportTask == nil else { return }
        let fresh = generatedZoom()
        if settings.zoomSections != fresh {
            let alert = NSAlert()
            alert.messageText = "Make the zoom sections from the clicks again?"
            alert.informativeText = "This replaces the zoom sections you changed. You can undo it."
            alert.addButton(withTitle: "Regenerate")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        setZoom(fresh, select: nil, undo: "Regenerate Zooms")
    }

    // MARK: Preview

    /// Draws the frame at the playhead with the current settings.
    private func redraw() {
        let size = compositor.size
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        compositor.draw(in: ctx, source: source, at: time)
        preview.image = ctx.makeImage()
    }

    /// Fetches the recording's frame at the playhead (the latest one at or before it), then redraws.
    private func requestFrame() {
        frameRequest += 1
        let id = frameRequest
        let at = CMTime(seconds: min(time, max(duration - 0.001, 0)), preferredTimescale: 600)
        let generator = generator
        Task { [weak self] in
            let image = try? await generator.image(at: at).image
            guard let self, id == self.frameRequest, !self.playing, let image else { return }
            self.source = image
            self.redraw()
        }
    }

    private func refreshTime() {
        timeField.stringValue = "\(StudioLayout.timecode(time)) / \(StudioLayout.timecode(duration))"
        scrubber.doubleValue = time
        zoomTrack.time = time
    }

    @objc private func togglePlay() {
        guard exportTask == nil else { return }
        setPlaying(!playing)
    }

    private func setPlaying(_ on: Bool) {
        guard on != playing else { return }
        playing = on
        playButton.setContent(title: nil, symbol: on ? "pause.fill" : "play.fill")
        playButton.toolTip = on ? "Pause (Space)" : "Play (Space)"
        playButton.setAccessibilityLabel(on ? "Pause" : "Play")
        if on {
            if time >= duration - 0.05 { time = 0 }
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else {
            player.pause()
            ticker?.invalidate(); ticker = nil
            requestFrame()
        }
    }

    /// While playing: the newest frame from the player, and the effects at its time.
    private func tick() {
        let now = player.currentTime()
        let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            source = StudioCompositor.image(of: buffer) ?? source
        }
        if now.isNumeric { time = min(max(now.seconds, 0), duration) }
        if player.rate == 0, time >= duration - 0.05 { setPlaying(false) }
        refreshTime()
        redraw()
    }

    @objc private func scrubbed() {
        if playing { setPlaying(false) }
        time = min(max(scrubber.doubleValue, 0), duration)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        refreshTime()
        redraw()
        requestFrame()
    }

    // MARK: Export

    @objc private func export() {
        guard exportTask == nil else { return }
        setPlaying(false)
        let settings = settings
        let target = AutoFiling.current(file)
        let folder = folder, fps = project.fps
        // Full size, made here: the background is drawn with AppKit.
        let full = StudioCompositor(project: project, events: events, folder: folder, settings: settings)
        let box = ExportProgress()
        exportProgress = box
        exportTask = Task { [weak self] in
            var failure: Error?
            do {
                if full.changesTheVideo {
                    try await RecordingRenderer.render(folder: folder, fps: fps, compositor: full, to: target) { box.set($0) }
                } else {
                    // Nothing to draw: the clean video is the finished one.
                    try Self.replace(target, with: folder.appendingPathComponent(RecordingProject.videoFile))
                }
            } catch {
                failure = error
            }
            self?.exportFinished(settings: settings, target: target, error: failure)
        }
        refreshExporting()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.progressBar.doubleValue = self?.exportProgress?.value ?? 0 }
        }
    }

    /// Copies `source` over `file`, replacing it only once the copy is complete.
    private nonisolated static func replace(_ file: URL, with source: URL) throws {
        let fm = FileManager.default
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        defer { try? fm.removeItem(at: dir) }
        let tmp = dir.appendingPathComponent(file.lastPathComponent)
        try fm.copyItem(at: source, to: tmp)
        if fm.fileExists(atPath: file.path) { _ = try fm.replaceItemAt(file, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: file) }
    }

    @objc private func cancelExport() {
        exportTask?.cancel()
        status.stringValue = "Cancelling…"
    }

    private func refreshExporting() {
        let exporting = exportTask != nil
        exportButton.isEnabled = !exporting
        cancelButton.isHidden = !exporting
        progressBar.isHidden = !exporting
        progressBar.doubleValue = 0
        playButton.isEnabled = !exporting
        scrubber.isEnabled = !exporting
        if exporting { status.stringValue = "Exporting…" }
        refreshControls()
    }

    private func exportFinished(settings exported: StudioSettings, target: URL, error: Error?) {
        exportTask = nil
        exportProgress = nil
        progressTimer?.invalidate(); progressTimer = nil
        refreshExporting()
        if error is CancellationError {
            status.stringValue = "Export cancelled. The recording is unchanged."
            if closeAfterExport { window.close() }
            return
        }
        if let error {
            NSLog("Exporting the recording failed: \(error)")
            status.stringValue = "Export failed. The recording is unchanged."
            NSAlert(error: error).beginSheetModal(for: window)
            return
        }
        // Saved: the settings, and where the finished MP4 is, in the project.
        saved = exported
        do { try exported.save(folder: folder) } catch { NSLog("Couldn't save the recording's editor settings: \(error)") }
        project.exported = target.path
        do {
            try project.encoded().write(to: folder.appendingPathComponent(RecordingProject.projectFile), options: .atomic)
        } catch {
            NSLog("Couldn't update the recording project: \(error)")
        }
        refreshControls()
        window.close()
        // Then as after recording: Compress when that is on, the library, and a new preview.
        Task { @MainActor in
            await RecordingController.compress(target)
            SavedLibrary.shared.note(target)
            Sound.play("Glass")
            QuickAccessController.show(recording: target)
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if exportTask != nil {
            // Closing while exporting cancels the export first.
            closeAfterExport = true
            cancelExport()
            return false
        }
        guard settings != saved else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard your changes to this recording?"
        alert.informativeText = "They haven't been exported. Export saves them into \(file.lastPathComponent)."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        ticker?.invalidate(); ticker = nil
        progressTimer?.invalidate(); progressTimer = nil
        exportTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        window.undoManager?.removeAllActions(withTarget: self)
        Self.live.removeAll { $0 === self }
    }
}

/// The export's progress, written on the renderer's queue and read by the window's timer.
private final class ExportProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var fraction = 0.0

    func set(_ value: Double) {
        lock.lock()
        fraction = value
        lock.unlock()
    }

    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return fraction
    }
}

/// The editor's window: Esc closes it (asking first if there are changes), Space plays and pauses.
private final class EditorPanel: NSWindow {
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    /// ⌘Z (false) and ⇧⌘Z (true).
    var onUndo: ((Bool) -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if event.charactersIgnoringModifiers?.lowercased() == "z", mods == [.command] || mods == [.command, .shift],
           let onUndo {
            onUndo(mods.contains(.shift))
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onSpace?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The undo step for zoom section edits: the sections to go back to.
private final class ZoomUndoStep: NSObject {
    let sections: [ZoomSection]
    let name: String
    init(_ sections: [ZoomSection], name: String) {
        self.sections = sections
        self.name = name
    }
}

/// The inspector's scrolling content, from the top.
private final class InspectorDocument: NSView {
    override var isFlipped: Bool { true }
}

/// The preview: the composed frame scaled to fit, on black. A click plays or pauses; an Option-click passes on where
/// (in the view's coordinates).
private final class StudioPreview: NSView {
    var image: CGImage? { didSet { layer?.contents = image } }
    var onClick: (() -> Void)?
    var onOptionClick: ((CGPoint) -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Preview")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            onOptionClick?(convert(event.locationInWindow, from: nil))
        } else {
            onClick?()
        }
    }
}
