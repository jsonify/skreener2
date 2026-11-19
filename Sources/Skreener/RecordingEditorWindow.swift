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
    // Cursor (#382)
    private let smoothingPopup = RetroUI.stepper(tip: "How much the cursor's movement is smoothed (it still lands on every click)",
                                                 target: nil, action: nil)
    private let cursorSizeSlider = NSSlider(value: 1, minValue: CursorSettings.minSize, maxValue: CursorSettings.maxSize,
                                            target: nil, action: nil)
    private let cursorSizeLabel = RetroUI.hint()
    private let idleSwitch = RetroSwitch()
    private let idleDelayPopup = RetroUI.stepper(tip: "How long the cursor stays after it stops moving", target: nil, action: nil)

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

    // Cuts and speed (#381)
    private let editTrack = EditTrackView()
    private let markInButton = RetroUI.key("Set In")
    private let markOutButton = RetroUI.key("Set Out")
    private let clearMarksButton = RetroUI.key("Clear")
    private let cutButton = RetroUI.key("Cut")
    private let muteButton = RetroUI.key("Mute")
    private let speedPopup = RetroUI.stepper(tip: "How much faster the In–Out range plays", target: nil, action: nil)
    private let speedButton = RetroUI.key("Speed Up")
    private let idleButton = RetroUI.key("Speed Up Idle")
    private let removeEditButton = RetroUI.key("Remove")
    private let editHint = RetroUI.hint(wraps: true)
    private var markIn: Double?
    private var markOut: Double?
    /// The selected cut or speed change (an index into `settings.edits`).
    private var selectedEdit: Int?
    private var timeline: EditTimeline { EditTimeline(edits: settings.edits, duration: duration) }

    // Audio (#385)
    private let presetPopup = RetroUI.stepper(tip: "What is done to your voice when exporting", target: nil, action: nil)
    private let noisePopup = RetroUI.stepper(tip: "How much background noise is taken out of the microphone", target: nil,
                                             action: nil)
    private let micSlider = NSSlider(value: 1, minValue: 0, maxValue: AudioSettings.maxVolume, target: nil, action: nil)
    private let systemSlider = NSSlider(value: 1, minValue: 0, maxValue: AudioSettings.maxVolume, target: nil, action: nil)
    private let micVolumeLabel = RetroUI.hint()
    private let systemVolumeLabel = RetroUI.hint()
    private var micRow = NSView(), systemRow = NSView()
    private let audioHint = RetroUI.hint(wraps: true)
    // Fine-tuning the voice: each slider changes one part of the preset.
    private let noiseReductionSlider = NSSlider(value: 0, minValue: 0, maxValue: VoiceTuning.maxNoiseReduction, target: nil, action: nil)
    private let pauseSlider = NSSlider(value: 0, minValue: 0, maxValue: VoiceTuning.maxPauseSilence, target: nil, action: nil)
    private let warmthSlider = NSSlider(value: 0, minValue: VoiceTuning.warmthRange.lowerBound,
                                        maxValue: VoiceTuning.warmthRange.upperBound, target: nil, action: nil)
    private let claritySlider = NSSlider(value: 0, minValue: VoiceTuning.clarityRange.lowerBound,
                                         maxValue: VoiceTuning.clarityRange.upperBound, target: nil, action: nil)
    private let deEssSlider = NSSlider(value: 0, minValue: VoiceTuning.deEssRange.lowerBound,
                                       maxValue: VoiceTuning.deEssRange.upperBound, target: nil, action: nil)
    private let airSlider = NSSlider(value: 0, minValue: VoiceTuning.airRange.lowerBound,
                                     maxValue: VoiceTuning.airRange.upperBound, target: nil, action: nil)
    private var tuningLabels: [NSSlider: NSTextField] = [:]
    private let compressionPopup = RetroUI.stepper(tip: "How much loud and quiet passages are evened out", target: nil, action: nil)
    private let loudnessPopup = RetroUI.stepper(tip: "How loud the voice ends up", target: nil, action: nil)
    private let listenButton = RetroUI.key("Listen")
    private let resetTuningButton = RetroUI.key("Reset")
    private let saveVoiceButton = RetroUI.key("Save as My Voice")
    private var tuningRows: [NSView] = []
    private var voicePreviewTask: Task<Void, Never>?
    private var voicePlayer: AVAudioPlayer?
    /// The clean video's audio tracks, for the preview's volumes, once loaded.
    private var previewAudioTracks: [AVAssetTrack] = []
    /// What each audio track holds.
    private var audioSources: [AudioSource] { AudioFinisher.sources(project.audioTracks, trackCount: previewAudioTracks.count) }
    private var hasVoice: Bool { audioSources.contains { $0 != .system } }
    private var hasSystemAudio: Bool { audioSources.contains(.system) }

    // Captions (#386)
    private let generateCaptionsButton = RetroUI.key("Generate")
    private let captionsShownSwitch = RetroSwitch()
    private let captionsFileSwitch = RetroSwitch()
    private let captionField = NSTextField(string: "")
    private let captionStartButton = RetroUI.key("Start Here")
    private let captionEndButton = RetroUI.key("End Here")
    private let addCaptionButton = RetroUI.key("+ Line")
    private let deleteCaptionButton = RetroUI.key("Delete")
    private let captionHint = RetroUI.hint(wraps: true)
    private var captionTask: Task<Void, Never>?
    /// The caption showing in `captionField` (an index into `settings.captions`).
    private var shownCaption: Int?

    // Callouts (#383).
    private let calloutTrack = CalloutTrackView()
    private let calloutKindPopup = RetroUI.stepper(tip: "What to add", target: nil, action: nil)
    private let addCalloutButton = RetroUI.key("+ Add")
    private let calloutField = NSTextField(string: "")
    private let calloutColor = ColorPill()
    private let calloutFollowSwitch = RetroSwitch()
    private let calloutStartButton = RetroUI.key("Start Here")
    private let calloutEndButton = RetroUI.key("End Here")
    private let deleteCalloutButton = RetroUI.key("Delete")
    private let calloutHint = RetroUI.hint(wraps: true)
    private var selectedCallout: UUID?
    /// A callout being dragged, on the track or in the preview: the callouts before it, for Undo.
    private var calloutDrag: (before: [Callout], name: String)?
    /// A drag in the preview: the callout, and either where it was grabbed (video pixels from its anchor) or its handle.
    private var previewDrag: (id: UUID, grab: CGPoint?)?

    // Export bar
    private let exportButton = RetroUI.key("Export", variant: .orange)
    private let cancelButton = RetroUI.key("Cancel")
    private let exportPresetPopup = RetroUI.stepper(tip: "What Export makes: the recording at its own size, a size for a video site or social media, or a GIF",
                                                    target: nil, action: nil)
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
        var loaded = StudioSettings.load(folder: folder, project: project)
        // A recording opened for the first time starts with My Voice, when one was saved.
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent(StudioSettings.file).path),
           let mine = Preferences.myVoice {
            loaded.audio.preset = .mine
            loaded.audio.tuning = mine
        }
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
        window.onMark = { [weak self] isIn in self?.mark(isIn) }
        build()
        refreshControls()
        window.center()
    }

    private static func previewCompositor(project: RecordingProject, events: RecordingEvents, folder: URL,
                                          settings: StudioSettings) -> StudioCompositor {
        let canvas = StudioLayout.make(videoSize: project.videoSize, pixelsPerPoint: project.pixelScale,
                                       background: settings.backgroundOn ? settings.background : nil,
                                       frame: settings.exportPreset.frame).canvas
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
            let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            guard let self else { return }
            self.previewAudioTracks = audio
            self.refreshAudioControls()
            self.updatePreviewMix()
            self.duration = seconds.isFinite ? max(seconds, 0) : 0
            self.scrubber.maxValue = max(self.duration, 0.01)
            self.zoomTrack.duration = self.duration
            self.editTrack.duration = self.duration
            self.calloutTrack.duration = self.duration
            // The zoom track's time scale lines up with the scrubber's track, which is inset by half its knob.
            if let cell = self.scrubber.cell as? NSSliderCell {
                self.zoomTrack.inset = cell.knobRect(flipped: self.scrubber.isFlipped).width / 2
                self.editTrack.inset = self.zoomTrack.inset
                self.calloutTrack.inset = self.zoomTrack.inset
            }
            self.generateZoomIfNeeded()
            self.loadWaveform()
            self.refreshEditControls()
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
        preview.onPress = { [weak self] p in self?.pressPreview(at: p) ?? false }
        preview.onDrag = { [weak self] p in self?.dragPreview(to: p) }
        preview.onRelease = { [weak self] in self?.endCalloutDrag() }

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
        let inspector = NSStackView(views: buildBackground() + [RetroGroove()] + buildEffects() + [RetroGroove()] + buildZoom()
                                    + [RetroGroove()] + buildEdits() + [RetroGroove()] + buildAudio()
                                    + [RetroGroove()] + buildCaptions() + [RetroGroove()] + buildCallouts())
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
        exportButton.target = self; exportButton.action = #selector(export)
        setUp(exportPresetPopup, ExportPreset.allCases.enumerated().map { ($1.name, $0) }, action: #selector(exportPresetPicked))
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
        status.stringValue = exportHint
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        status.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [status, spacer, progressBar, cancelButton, exportPresetPopup, exportButton])
        bar.spacing = 10
        bar.alignment = .centerY

        setUpEditTrack()
        setUpCalloutTrack()
        [well, transport, zoomTrack, editTrack, calloutTrack, inspectorScroll, bar].forEach {
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
            editTrack.topAnchor.constraint(equalTo: zoomTrack.bottomAnchor, constant: 4),
            editTrack.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),
            editTrack.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),
            editTrack.heightAnchor.constraint(equalToConstant: 30),
            calloutTrack.topAnchor.constraint(equalTo: editTrack.bottomAnchor, constant: 4),
            calloutTrack.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),
            calloutTrack.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),
            calloutTrack.heightAnchor.constraint(equalToConstant: 30),
            inspectorScroll.topAnchor.constraint(equalTo: top, constant: 10),
            inspectorScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            inspectorScroll.widthAnchor.constraint(equalToConstant: 306),
            inspectorScroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10),
            bar.topAnchor.constraint(equalTo: calloutTrack.bottomAnchor, constant: 12),
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
        setUp(smoothingPopup, CursorSmoothing.allCases.enumerated().map { ($1.name, $0) }, action: #selector(cursorOptionPicked(_:)))
        setUp(idleDelayPopup, CursorSettings.idleDelays.map { ("after \(Int($0)) s", Int($0 * 10)) },
              action: #selector(cursorOptionPicked(_:)))
        setUp(idleSwitch, "Hide when idle")
        idleSwitch.toolTip = "Fade the cursor out when it hasn't moved for a while, and back in when it moves"
        cursorSizeSlider.controlSize = .small
        cursorSizeSlider.isContinuous = true
        cursorSizeSlider.numberOfTickMarks = 9
        cursorSizeSlider.allowsTickMarkValuesOnly = true
        cursorSizeSlider.toolTip = "Cursor size"
        cursorSizeSlider.setAccessibilityLabel("Cursor size")
        cursorSizeSlider.target = self; cursorSizeSlider.action = #selector(cursorSizeChanged)
        cursorSizeSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        cursorSizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        return [
            header("Effects"),
            row("Cursor", [cursorSwitch]),
            row("Smoothing", [smoothingPopup]),
            row("Size", [cursorSizeSlider, cursorSizeLabel]),
            row("Hide idle", [idleSwitch, idleDelayPopup]),
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

    private func buildEdits() -> [NSView] {
        for (button, tip, action) in [
            (markInButton, "Start the range at the playhead (I)", #selector(markInPressed)),
            (markOutButton, "End the range at the playhead (O)", #selector(markOutPressed)),
            (clearMarksButton, "Clear the In and Out marks", #selector(clearMarks)),
            (cutButton, "Leave the In–Out range out of the video", #selector(cutRange)),
            (muteButton, "Silence the In–Out range: the microphone and the system audio, with short fades", #selector(muteRange)),
            (speedButton, "Play the In–Out range faster (its sound is muted)", #selector(speedUpRange)),
            (idleButton, "Speed up every stretch of 3 seconds or more where nothing happens: no pointer movement, clicks or keys",
             #selector(speedUpIdle)),
            (removeEditButton, "Remove the selected cut or speed change (Delete)", #selector(removeSelectedEdit)),
        ] {
            button.toolTip = tip
            button.target = self
            button.action = action
        }
        for speed in TimelineEdit.speeds {
            speedPopup.addItem(withTitle: "\(Int(speed))×")
            speedPopup.lastItem?.tag = Int(speed)
        }
        speedPopup.selectItem(withTag: 4)
        editHint.preferredMaxLayoutWidth = 290
        return [
            header("Cut & Speed"),
            row("Range", [markInButton, markOutButton, clearMarksButton]),
            row("", [cutButton, speedPopup, speedButton]),
            row("", [muteButton, idleButton, removeEditButton]),
            editHint,
        ]
    }

    private func setUpEditTrack() {
        editTrack.onSelect = { [weak self] index in
            self?.selectedEdit = index
            self?.refreshEditControls()
        }
        editTrack.onDelete = { [weak self] in self?.removeSelectedEdit() }
    }

    private func refreshEditControls() {
        let exporting = exportTask != nil
        if let i = selectedEdit, !settings.edits.indices.contains(i) { selectedEdit = nil }
        editTrack.edits = settings.edits
        editTrack.selected = selectedEdit
        editTrack.markIn = markIn
        editTrack.markOut = markOut
        editTrack.isEnabled = !exporting
        let ready = !exporting && duration > 0
        [markInButton, markOutButton].forEach { $0.isEnabled = ready }
        clearMarksButton.isEnabled = ready && (markIn != nil || markOut != nil)
        let range = markedRange
        cutButton.isEnabled = ready && range != nil
        muteButton.isEnabled = ready && range != nil
        speedPopup.isEnabled = ready
        speedButton.isEnabled = ready && range != nil
        idleButton.isEnabled = ready && !events.cursor.isEmpty
        removeEditButton.isEnabled = ready && selectedEdit != nil
        var lines: [String] = []
        if let range {
            lines.append("In \(StudioLayout.timecode(range.start)) – Out \(StudioLayout.timecode(range.end)): Cut it, Speed it up or Mute it.")
        } else if markIn != nil || markOut != nil {
            lines.append("Set the other end of the range too (I and O mark at the playhead).")
        } else {
            lines.append("Set In and Out at the playhead (I, O), then Cut the range, Speed it up or Mute it.")
        }
        let t = timeline
        if t.changesTime {
            lines.append("Exported length \(StudioLayout.timecode(t.outputDuration)) of \(StudioLayout.timecode(duration)).")
        }
        editHint.stringValue = lines.joined(separator: " ")
        window.isDocumentEdited = settings != saved
    }

    /// The In–Out range, when both are set and apart.
    private var markedRange: (start: Double, end: Double)? {
        guard let a = markIn, let b = markOut, abs(b - a) >= TimelineEdit.minLength else { return nil }
        return (min(a, b), max(a, b))
    }

    private func mark(_ isIn: Bool) {
        guard exportTask == nil, duration > 0 else { return }
        if isIn { markIn = time } else { markOut = time }
        refreshEditControls()
    }

    @objc private func markInPressed() { mark(true) }
    @objc private func markOutPressed() { mark(false) }

    @objc private func clearMarks() {
        markIn = nil; markOut = nil
        refreshEditControls()
    }

    private func setEdits(_ edits: [TimelineEdit], name: String) {
        let before = settings.edits
        settings.edits = EditTimeline.tidy(edits, duration: duration)
        guard before != settings.edits else { return }
        if let undo = window.undoManager {
            undo.registerUndo(withTarget: self, selector: #selector(restoreEdits(_:)), object: EditUndoStep(before, name: name))
            undo.setActionName(name)
        }
        refreshEditControls()
    }

    @objc private func restoreEdits(_ step: EditUndoStep) {
        let current = settings.edits
        if let undo = window.undoManager {
            undo.registerUndo(withTarget: self, selector: #selector(restoreEdits(_:)), object: EditUndoStep(current, name: step.name))
            undo.setActionName(step.name)
        }
        selectedEdit = nil
        settings.edits = step.edits
        refreshEditControls()
    }

    private func addEdit(speed: Double, name: String) {
        guard let range = markedRange else { return }
        setEdits(EditTimeline.adding(TimelineEdit(start: range.start, end: range.end, speed: speed), to: settings.edits), name: name)
        markIn = nil; markOut = nil
        selectedEdit = settings.edits.firstIndex { $0.start == range.start && $0.speed == speed }
        refreshEditControls()
    }

    /// Draws the recording's sound on the edit track once it has been read (#385).
    private func loadWaveform() {
        let url = folder.appendingPathComponent(RecordingProject.videoFile)
        Task { [weak self] in
            let peaks = await WaveformPeaks.load(url, buckets: 2000)
            self?.editTrack.waveform = peaks
        }
    }

    @objc private func cutRange() { addEdit(speed: 0, name: "Cut") }
    @objc private func muteRange() { addEdit(speed: TimelineEdit.mute, name: "Mute") }

    @objc private func speedUpRange() {
        let speed = Double(speedPopup.selectedTag())
        addEdit(speed: TimelineEdit.speeds.contains(speed) ? speed : 4, name: "Speed Up")
    }

    @objc private func speedUpIdle() {
        let speed = Double(speedPopup.selectedTag())
        let idle = EditTimeline.idleRanges(events, duration: duration)
        guard !idle.isEmpty else {
            editHint.stringValue = "No stretches of 3 seconds or more without pointer movement, clicks or keys."
            return
        }
        // Existing edits win where they overlap, so a cut stays a cut.
        let added = idle.map { TimelineEdit(start: $0.start, end: $0.end, speed: TimelineEdit.speeds.contains(speed) ? speed : 4) }
        setEdits(added + settings.edits, name: "Speed Up Idle")
    }

    @objc private func removeSelectedEdit() {
        guard let i = selectedEdit, settings.edits.indices.contains(i) else { return }
        var edits = settings.edits
        edits.remove(at: i)
        selectedEdit = nil
        setEdits(edits, name: "Remove \(settings.edits[i].kind)")
    }

    private func buildAudio() -> [NSView] {
        setUp(presetPopup, AudioPreset.allCases.enumerated().map { ($1.name, $0) }, action: #selector(audioOptionPicked(_:)))
        setUp(noisePopup, NoiseRemoval.allCases.enumerated().map { ($1.name, $0) }, action: #selector(audioOptionPicked(_:)))
        for (slider, tip) in [(micSlider, "Microphone volume"), (systemSlider, "System audio volume")] {
            slider.controlSize = .small
            slider.isContinuous = true
            slider.toolTip = tip
            slider.setAccessibilityLabel(tip)
            slider.target = self; slider.action = #selector(volumeChanged(_:))
            slider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        }
        for label in [micVolumeLabel, systemVolumeLabel] {
            label.widthAnchor.constraint(equalToConstant: 40).isActive = true
        }
        audioHint.preferredMaxLayoutWidth = 290
        micRow = row("Voice", [micSlider, micVolumeLabel])
        systemRow = row("System", [systemSlider, systemVolumeLabel])
        tuningRows = buildTuning()
        return [
            header("Audio"),
            row("Preset", [presetPopup]),
            row("Noise", [noisePopup]),
            micRow,
            systemRow,
        ] + tuningRows + [audioHint]
    }

    /// The fine-tune controls: each changes one part of what the preset does, and Listen plays a sample of the result.
    private func buildTuning() -> [NSView] {
        let sliders: [(NSSlider, String, String)] = [
            (noiseReductionSlider, "Hiss", "How much steady background noise (hiss, fans, room tone) is taken out"),
            (pauseSlider, "Pauses", "How far the sound between words is turned down; high values make the pauses silent"),
            (warmthSlider, "Warmth", "More or less low end: a fuller voice, or a thinner one"),
            (claritySlider, "Clarity", "More or less presence in the upper mids: a clearer, more forward voice"),
            (deEssSlider, "De-ess", "How much harsh \"s\" and \"t\" sounds are softened"),
            (airSlider, "Air", "More or less sparkle at the top"),
        ]
        var rows: [NSView] = [RetroLabel(caption: "Fine-tune")]
        for (slider, name, tip) in sliders {
            slider.controlSize = .small
            slider.isContinuous = true
            slider.toolTip = tip
            slider.setAccessibilityLabel(name)
            slider.target = self; slider.action = #selector(tuningChanged(_:))
            slider.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let label = RetroUI.hint()
            label.widthAnchor.constraint(equalToConstant: 52).isActive = true
            tuningLabels[slider] = label
            rows.append(row(name, [slider, label]))
        }
        setUp(compressionPopup, VoiceTuning.compressionRatios.enumerated().map { (VoiceTuning.ratioText($1), $0) },
              action: #selector(tuningChanged(_:)))
        setUp(loudnessPopup, [("Off", 0)] + VoiceTuning.loudnessTargets.enumerated().map { ($1.name, $0 + 1) },
              action: #selector(tuningChanged(_:)))
        for (button, tip, action) in [
            (listenButton, "Play 15 seconds of your voice from the playhead with these settings", #selector(listenToVoice)),
            (resetTuningButton, "Go back to what the preset does", #selector(resetTuning)),
            (saveVoiceButton, "Keep these settings as the My Voice preset; new recordings start with it", #selector(saveMyVoice)),
        ] {
            button.toolTip = tip
            button.target = self
            button.action = action
        }
        rows += [
            row("Levelling", [compressionPopup]),
            row("Loudness", [loudnessPopup]),
            row("", [listenButton, resetTuningButton]),
            row("", [saveVoiceButton]),
        ]
        return rows
    }

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
        let c = settings.cursor
        smoothingPopup.selectItem(withTag: CursorSmoothing.allCases.firstIndex(of: c.smoothing) ?? 0)
        cursorSizeSlider.doubleValue = c.size
        cursorSizeLabel.stringValue = CursorSettings.sizeText(c.size)
        idleSwitch.state = c.hideWhenIdle ? .on : .off
        if idleDelayPopup.itemArray.contains(where: { $0.tag == Int((c.idleDelay * 10).rounded()) }) {
            idleDelayPopup.selectItem(withTag: Int((c.idleDelay * 10).rounded()))
        }
        let cursorOn = e.cursor && hasCursor && !exporting
        let cursorControls: [NSControl] = [smoothingPopup, cursorSizeSlider, idleSwitch]
        cursorControls.forEach { $0.isEnabled = cursorOn }
        idleDelayPopup.isEnabled = cursorOn && c.hideWhenIdle

        let preset = settings.exportPreset
        exportPresetPopup.selectItem(withTag: ExportPreset.allCases.firstIndex(of: preset) ?? 0)
        exportPresetPopup.isEnabled = !exporting
        exportButton.toolTip = preset.replacesRecording
            ? "Make the finished video again with these settings and save it over the recording"
            : "Make \(preset.destination(for: file).lastPathComponent) with these settings, next to the recording"

        refreshAudioControls()
        refreshEditControls()
        refreshZoomControls()
        refreshCaptionControls()
        refreshCalloutControls()
    }

    @objc private func exportPresetPicked() {
        let i = exportPresetPopup.selectedTag()
        guard ExportPreset.allCases.indices.contains(i) else { return }
        settings.exportPreset = ExportPreset.allCases[i]
        status.stringValue = exportHint
    }

    /// Where Export saves, for the status line.
    private var exportHint: String {
        let preset = settings.exportPreset
        return preset.replacesRecording
            ? "Export saves over \(file.lastPathComponent); the original stays in the project."
            : "Export saves \(preset.destination(for: file).lastPathComponent) next to the recording."
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

    private func buildCaptions() -> [NSView] {
        for (button, tip, action) in [
            (generateCaptionsButton, "Make captions from your voice with speech recognition on this Mac (replaces any there are)",
             #selector(generateCaptions)),
            (captionStartButton, "Start the caption at the playhead here", #selector(captionStartHere)),
            (captionEndButton, "End the caption at the playhead here", #selector(captionEndHere)),
            (addCaptionButton, "Add a caption line at the playhead", #selector(addCaption)),
            (deleteCaptionButton, "Delete the caption at the playhead", #selector(deleteCaption)),
        ] {
            button.toolTip = tip
            button.target = self
            button.action = action
        }
        setUp(captionsShownSwitch, "Show captions in the video")
        captionsShownSwitch.toolTip = "Draw the captions into the exported video"
        setUp(captionsFileSwitch, "Save captions file")
        captionsFileSwitch.toolTip = "Save the captions as an .srt file next to the exported video, for YouTube and the like"
        captionField.placeholderString = "No caption at the playhead"
        captionField.font = .systemFont(ofSize: 12)
        captionField.lineBreakMode = .byTruncatingTail
        captionField.cell?.sendsActionOnEndEditing = true
        captionField.target = self
        captionField.action = #selector(captionTextChanged)
        captionField.setAccessibilityLabel("Caption at the playhead")
        captionField.widthAnchor.constraint(equalToConstant: 290).isActive = true
        captionHint.preferredMaxLayoutWidth = 290
        return [
            header("Captions"),
            row("Captions", [generateCaptionsButton]),
            row("In video", [captionsShownSwitch]),
            row(".srt file", [captionsFileSwitch]),
            captionField,
            row("", [captionStartButton, captionEndButton]),
            row("", [addCaptionButton, deleteCaptionButton]),
            captionHint,
        ]
    }

    private func refreshCaptionControls() {
        let exporting = exportTask != nil
        let busy = captionTask != nil
        let current = Captions.index(at: time, in: settings.captions)
        generateCaptionsButton.isEnabled = !exporting && !busy && hasVoice
        captionsShownSwitch.state = settings.captionsShown ? .on : .off
        captionsFileSwitch.state = settings.captionsFile ? .on : .off
        captionsShownSwitch.isEnabled = !exporting
        captionsFileSwitch.isEnabled = !exporting
        captionField.isEnabled = !exporting && current != nil
        // Moving off the line being edited ends the edit (which saves it) and shows the line now at the playhead.
        if captionField.currentEditor() != nil, current != shownCaption { window.makeFirstResponder(nil) }
        if captionField.currentEditor() == nil {
            let now = Captions.index(at: time, in: settings.captions)
            captionField.stringValue = now.map { settings.captions[$0].text } ?? ""
            shownCaption = now
        }
        let captions = settings.captions
        [captionStartButton, captionEndButton, deleteCaptionButton].forEach { $0.isEnabled = !exporting && current != nil }
        addCaptionButton.isEnabled = !exporting && current == nil && duration > 0
        if busy {
            captionHint.stringValue = "Listening to your voice… this takes a little while for a long recording."
        } else if captions.isEmpty {
            captionHint.stringValue = hasVoice ? "Generate makes captions from your voice, on this Mac. Then edit each line at the playhead."
                : "No microphone was recorded, so there's nothing to make captions from."
        } else {
            var text = "\(captions.count) caption lines. Play or scrub to a line to change its text or timing."
            if settings.captionsShown && settings.exportPreset == .gif { text += " A GIF gets the captions drawn in but no .srt." }
            captionHint.stringValue = text
        }
    }

    private func setCaptions(_ captions: [Caption], name: String) {
        let before = settings.captions
        settings.captions = Captions.tidy(captions)
        guard before != settings.captions else { return }
        if let undo = window.undoManager {
            undo.registerUndo(withTarget: self, selector: #selector(restoreCaptions(_:)), object: CaptionUndoStep(before, name: name))
            undo.setActionName(name)
        }
        shownCaption = nil
        refreshCaptionControls()
    }

    @objc private func restoreCaptions(_ step: CaptionUndoStep) {
        setCaptions(step.captions, name: step.name)
    }

    @objc private func generateCaptions() {
        guard captionTask == nil, exportTask == nil else { return }
        setPlaying(false)
        let video = folder.appendingPathComponent(RecordingProject.videoFile)
        let sources = project.audioTracks
        captionTask = Task { [weak self] in
            let result: Result<[Caption], Error>
            do { result = .success(try await CaptionGenerator.generate(video: video, sources: sources)) } catch { result = .failure(error) }
            guard let self else { return }
            self.captionTask = nil
            switch result {
            case .success(let captions): self.setCaptions(captions, name: "Generate Captions")
            case .failure(let error) where error is CancellationError: break
            case .failure(let error):
                NSLog("Making captions failed: \(error)")
                NSAlert(error: error).beginSheetModal(for: self.window, completionHandler: nil)
            }
            self.refreshCaptionControls()
        }
        refreshCaptionControls()
    }

    /// Changes the caption at the playhead.
    private func changeCurrentCaption(_ name: String, _ change: (inout Caption) -> Void) {
        guard let i = Captions.index(at: time, in: settings.captions) else { return }
        var captions = settings.captions
        change(&captions[i])
        setCaptions(captions, name: name)
    }

    @objc private func captionTextChanged() {
        guard let i = shownCaption, settings.captions.indices.contains(i) else { return }
        let text = captionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != settings.captions[i].text else { return }
        var captions = settings.captions
        if text.isEmpty { captions.remove(at: i) } else { captions[i].text = text }
        setCaptions(captions, name: text.isEmpty ? "Delete Caption" : "Edit Caption")
    }

    @objc private func captionStartHere() {
        let t = time
        changeCurrentCaption("Move Caption Start") { $0.start = t }
    }

    @objc private func captionEndHere() {
        let t = time
        // At the playhead itself would hide it at once; a moment later keeps it showing here.
        changeCurrentCaption("Move Caption End") { $0.end = max($0.start + TimelineEdit.minLength, t + 0.05) }
    }

    @objc private func addCaption() {
        guard Captions.index(at: time, in: settings.captions) == nil else { return }
        let next = settings.captions.first { $0.start > time }?.start ?? duration
        let end = min(time + 2, next)
        guard end - time >= TimelineEdit.minLength else { return }
        setCaptions(settings.captions + [Caption(start: time, end: end, text: "New caption")], name: "Add Caption")
        window.makeFirstResponder(captionField)
        captionField.currentEditor()?.selectAll(nil)
    }

    @objc private func deleteCaption() {
        guard let i = Captions.index(at: time, in: settings.captions) else { return }
        var captions = settings.captions
        captions.remove(at: i)
        setCaptions(captions, name: "Delete Caption")
    }

    // MARK: Callouts

    private func buildCallouts() -> [NSView] {
        setUp(calloutKindPopup, Callout.Kind.allCases.enumerated().map { ($1.name, $0) }, action: #selector(calloutKindPicked))
        for (button, tip, action) in [
            (addCalloutButton, "Add the callout at the playhead; then drag it in the preview, and its bar on the timeline",
             #selector(addCallout)),
            (calloutStartButton, "Start the selected callout at the playhead", #selector(calloutStartHere)),
            (calloutEndButton, "End the selected callout at the playhead", #selector(calloutEndHere)),
            (deleteCalloutButton, "Delete the selected callout", #selector(deleteCallout)),
        ] {
            button.toolTip = tip
            button.target = self
            button.action = action
        }
        calloutColor.toolTip = "The selected callout's color"
        calloutColor.target = self; calloutColor.action = #selector(calloutColorChanged)
        setUp(calloutFollowSwitch, "Follow zoom")
        calloutFollowSwitch.toolTip = "Move with a zoom section, staying on what it points at; off, it stays put in the frame"
        calloutField.placeholderString = "Text"
        calloutField.font = .systemFont(ofSize: 12)
        calloutField.cell?.sendsActionOnEndEditing = true
        calloutField.target = self
        calloutField.action = #selector(calloutTextChanged)
        calloutField.setAccessibilityLabel("Callout text")
        calloutField.widthAnchor.constraint(equalToConstant: 290).isActive = true
        calloutHint.preferredMaxLayoutWidth = 290
        return [
            header("Callouts"),
            row("Add", [calloutKindPopup, addCalloutButton]),
            calloutField,
            row("Color", [calloutColor]),
            row("Follow zoom", [calloutFollowSwitch]),
            row("", [calloutStartButton, calloutEndButton]),
            row("", [deleteCalloutButton]),
            calloutHint,
        ]
    }

    private func setUpCalloutTrack() {
        calloutTrack.onSelect = { [weak self] id in self?.selectCallout(id) }
        calloutTrack.onDragBegan = { [weak self] _ in
            guard let self else { return }
            self.calloutDrag = (self.settings.callouts, "Move Callout")
        }
        calloutTrack.onDrag = { [weak self] id, kind, t in self?.dragCalloutTime(id, kind, to: t) }
        calloutTrack.onDragEnded = { [weak self] in self?.endCalloutDrag() }
        calloutTrack.onDelete = { [weak self] in self?.deleteCallout() }
    }

    private var selectedCalloutIndex: Int? { settings.callouts.firstIndex { $0.id == selectedCallout } }

    private func refreshCalloutControls() {
        let exporting = exportTask != nil
        calloutTrack.callouts = settings.callouts
        calloutTrack.selected = selectedCallout
        calloutTrack.isEnabled = !exporting
        calloutKindPopup.isEnabled = !exporting
        addCalloutButton.isEnabled = !exporting && duration > 0
        let selected = selectedCalloutIndex.map { settings.callouts[$0] }
        [calloutStartButton, calloutEndButton, deleteCalloutButton, calloutColor].forEach {
            $0.isEnabled = !exporting && selected != nil
        }
        calloutFollowSwitch.isEnabled = !exporting && selected != nil && selected?.kind != .blur
        calloutFollowSwitch.state = selected?.follows ?? true ? .on : .off
        if let c = selected { calloutColor.color = NSColor(cgColor: c.cgColor) ?? .systemRed }
        let isText = selected?.kind == .text
        calloutField.isHidden = !isText
        if isText, calloutField.currentEditor() == nil { calloutField.stringValue = selected?.text ?? "" }
        if let c = selected {
            calloutHint.stringValue = "\(c.kind.name), \(StudioLayout.timecode(c.start))–\(StudioLayout.timecode(c.end)). "
                + "Drag it in the preview; drag its corner or tip to resize. Drag its bar to change when it shows."
        } else if settings.callouts.isEmpty {
            calloutHint.stringValue = "Point things out: pick a kind and press + Add to put it on the video at the playhead."
        } else {
            calloutHint.stringValue = "\(settings.callouts.count) callouts. Click one in the preview or on its bar to change it."
        }
    }

    private func selectCallout(_ id: UUID?) {
        guard selectedCallout != id else { return }
        if calloutField.currentEditor() != nil { window.makeFirstResponder(nil) }
        selectedCallout = id
        refreshCalloutControls()
        redraw()
    }

    /// Replaces the callouts as one step Undo takes back, named `name`.
    private func setCallouts(_ callouts: [Callout], name: String) {
        let before = settings.callouts
        settings.callouts = Callouts.tidy(callouts, duration: duration > 0 ? duration : nil)
        registerCalloutUndo(before, name: name)
        refreshCalloutControls()
    }

    private func registerCalloutUndo(_ before: [Callout], name: String) {
        guard before != settings.callouts, let undo = window.undoManager else { return }
        undo.registerUndo(withTarget: self, selector: #selector(restoreCallouts(_:)), object: CalloutUndoStep(before, name: name))
        undo.setActionName(name)
    }

    @objc private func restoreCallouts(_ step: CalloutUndoStep) {
        let current = settings.callouts
        if let undo = window.undoManager {
            undo.registerUndo(withTarget: self, selector: #selector(restoreCallouts(_:)), object: CalloutUndoStep(current, name: step.name))
            undo.setActionName(step.name)
        }
        settings.callouts = step.callouts
        if selectedCalloutIndex == nil { selectedCallout = nil }
        refreshCalloutControls()
        redraw()
    }

    /// Changes the selected callout as one undoable step.
    private func changeSelectedCallout(_ name: String, _ change: (inout Callout) -> Void) {
        guard let i = selectedCalloutIndex else { return }
        var callouts = settings.callouts
        change(&callouts[i])
        setCallouts(callouts, name: name)
    }

    @objc private func calloutKindPicked() {}

    @objc private func addCallout() {
        guard exportTask == nil, duration > 0 else { return }
        setPlaying(false)
        let i = calloutKindPopup.selectedTag()
        guard Callout.Kind.allCases.indices.contains(i) else { return }
        let kind = Callout.Kind.allCases[i]
        // At the pointer when it is over the recording, so the callout starts on what is being shown.
        var point: CGPoint?
        if let c = events.cursorState(at: time), c.visible, RecordingGeometry.contains(c.point, videoSize: project.videoSize) {
            point = c.point
        }
        let start = min(time, max(0, duration - Callouts.minLength))
        let c = Callouts.make(kind, at: start, duration: duration, videoSize: project.videoSize,
                              pixelsPerPoint: compositor.videoPointScale, around: point)
        selectedCallout = c.id
        setCallouts(settings.callouts + [c], name: "Add \(kind.name)")
        if kind == .text {
            window.makeFirstResponder(calloutField)
            calloutField.currentEditor()?.selectAll(nil)
        }
    }

    @objc private func calloutTextChanged() {
        guard let i = selectedCalloutIndex, settings.callouts[i].kind == .text else { return }
        let text = calloutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != settings.callouts[i].text else { return }
        changeSelectedCallout("Edit Callout Text") { $0.text = text }
    }

    @objc private func calloutColorChanged() {
        guard let c = calloutColor.color.usingColorSpace(.sRGB) else { return }
        let rgba = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
        changeSelectedCallout("Change Callout Color") { $0.color = rgba }
    }

    @objc private func calloutStartHere() {
        let t = time
        changeSelectedCallout("Move Callout Start") { $0.start = min(t, $0.end - Callouts.minLength) }
    }

    @objc private func calloutEndHere() {
        let t = time
        changeSelectedCallout("Move Callout End") { $0.end = max(t, $0.start + Callouts.minLength) }
    }

    @objc private func deleteCallout() {
        guard exportTask == nil, let i = selectedCalloutIndex else { return }
        var callouts = settings.callouts
        callouts.remove(at: i)
        selectedCallout = nil
        setCallouts(callouts, name: "Delete Callout")
    }

    private func dragCalloutTime(_ id: UUID, _ kind: CalloutTrackView.Drag, to t: Double) {
        guard let drag = calloutDrag, let i = drag.before.firstIndex(where: { $0.id == id }) else { return }
        var callouts = drag.before
        switch kind {
        case .move:
            callouts[i] = Callouts.moved(callouts[i], to: t, duration: duration)
        case .resize(let start):
            calloutDrag?.name = "Change Callout Timing"
            callouts[i] = Callouts.resized(callouts[i], start: start, to: t, duration: duration)
        }
        settings.callouts = callouts
    }

    private func endCalloutDrag() {
        previewDrag = nil
        guard let drag = calloutDrag else { return }
        calloutDrag = nil
        registerCalloutUndo(drag.before, name: drag.name)
    }

    /// Where a point in the preview view is on the canvas (output pixels, bottom-left origin).
    private func canvasPoint(preview p: CGPoint) -> CGPoint? {
        let size = compositor.size, box = preview.bounds
        let k = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        guard k > 0, compositor.scale > 0 else { return nil }
        let shown = CGRect(x: box.midX - size.width * k / 2, y: box.midY - size.height * k / 2,
                           width: size.width * k, height: size.height * k)
        return CGPoint(x: (p.x - shown.minX) / k / compositor.scale, y: (p.y - shown.minY) / k / compositor.scale)
    }

    /// A press in the preview: on a callout showing now, selects it and starts moving it (or resizing it, on its
    /// handle). Elsewhere, deselects and leaves the click to play or pause.
    private func pressPreview(at p: CGPoint) -> Bool {
        guard exportTask == nil, !playing, let canvas = canvasPoint(preview: p) else { return false }
        let crop = compositor.crop(at: time)
        guard let hit = Callouts.hit(settings.callouts, at: canvas, time: time, layout: compositor.layout, crop: crop,
                                     pixelsPerPoint: compositor.videoPointScale, slop: 6 / max(compositor.scale, 0.05))
        else {
            if selectedCallout != nil { selectCallout(nil); return true }
            return false
        }
        let c = settings.callouts[hit.index]
        selectCallout(c.id)
        let v = Callouts.videoPoint(canvas, for: c, layout: compositor.layout, crop: crop)
        previewDrag = (c.id, hit.handle ? nil : CGPoint(x: v.x - CGFloat(c.x), y: v.y - CGFloat(c.y)))
        calloutDrag = (settings.callouts, hit.handle ? "Resize Callout" : "Move Callout")
        return true
    }

    private func dragPreview(to p: CGPoint) {
        guard let drag = previewDrag, let canvas = canvasPoint(preview: p),
              let i = settings.callouts.firstIndex(where: { $0.id == drag.id }) else { return }
        var c = settings.callouts[i]
        let v = Callouts.videoPoint(canvas, for: c, layout: compositor.layout, crop: compositor.crop(at: time))
        if let grab = drag.grab {
            c.x = Double(v.x - grab.x)
            c.y = Double(v.y - grab.y)
            c = Callouts.clamped(c, videoSize: project.videoSize)
        } else {
            let size = project.videoSize
            let clamped = CGPoint(x: min(max(v.x, 0), size.width), y: min(max(v.y, 0), size.height))
            c = Callouts.resizing(c, handleTo: clamped, minSize: 8 * compositor.videoPointScale)
        }
        var callouts = settings.callouts
        callouts[i] = c
        settings.callouts = callouts
    }

    /// The selected callout's outline and handle over the preview (not in the export).
    private func drawCalloutSelection(in ctx: CGContext) {
        guard let i = selectedCalloutIndex else { return }
        let c = settings.callouts[i]
        guard time >= c.start, time < c.end else { return }
        let layout = compositor.layout, ppp = compositor.videoPointScale
        let transform = layout.transform(crop: c.follows ? compositor.crop(at: time) : nil)
            .concatenating(CGAffineTransform(scaleX: compositor.scale, y: compositor.scale))
        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: layout.videoSize.height - r.maxY, width: r.width, height: r.height)
        }
        let box = flip(Callouts.bounds(c, pixelsPerPoint: ppp)).applying(transform).insetBy(dx: -3, dy: -3)
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(box)
        if let h = Callouts.handle(c) {
            let p = CGPoint(x: h.x, y: layout.videoSize.height - h.y).applying(transform)
            let dot = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6))
            ctx.strokeEllipse(in: dot)
        }
        ctx.restoreGState()
    }

    private func refreshAudioControls() {
        let exporting = exportTask != nil
        let a = settings.audio
        presetPopup.selectItem(withTag: AudioPreset.allCases.firstIndex(of: a.preset) ?? 0)
        noisePopup.selectItem(withTag: NoiseRemoval.allCases.firstIndex(of: a.noiseRemoval) ?? 0)
        micSlider.doubleValue = a.micVolume
        systemSlider.doubleValue = a.systemVolume
        micVolumeLabel.stringValue = AudioSettings.percent(a.micVolume)
        systemVolumeLabel.stringValue = AudioSettings.percent(a.systemVolume)
        let t = a.effectiveTuning
        noiseReductionSlider.doubleValue = t.noiseReduction
        pauseSlider.doubleValue = t.pauseSilence
        warmthSlider.doubleValue = t.warmth
        claritySlider.doubleValue = t.clarity
        deEssSlider.doubleValue = t.deEss
        airSlider.doubleValue = t.air
        for (slider, label) in tuningLabels {
            let v = slider.doubleValue
            if slider === noiseReductionSlider || slider === pauseSlider || slider === deEssSlider {
                // How far something is turned down.
                label.stringValue = v < 0.25 ? "Off" : VoiceTuning.decibels(-v)
            } else {
                label.stringValue = VoiceTuning.decibels(v)
            }
        }
        compressionPopup.selectItem(withTag: VoiceTuning.compressionRatios.enumerated()
            .min { abs($0.element - t.compression) < abs($1.element - t.compression) }?.offset ?? 0)
        loudnessPopup.selectItem(withTag: t.loudness.flatMap { l in
            VoiceTuning.loudnessTargets.firstIndex { abs($0.value - l) < 0.5 }.map { $0 + 1 }
        } ?? 0)
        let listening = voicePlayer?.isPlaying == true || voicePreviewTask != nil
        if listening != (listenButton.toolTip == "Stop listening") {
            listenButton.setContent(title: listening ? "Stop" : "Listen", symbol: nil)
            listenButton.toolTip = listening ? "Stop listening" : "Play 15 seconds of your voice from the playhead with these settings"
        }
        resetTuningButton.isEnabled = hasVoice && !exporting && a.tuning != nil
            && a.tuning != (a.preset == .mine ? Preferences.myVoice : nil)
        tuningRows.forEach { $0.isHidden = !hasVoice }
        let voiceControls: [NSControl] = [presetPopup, noisePopup, micSlider, noiseReductionSlider, pauseSlider, warmthSlider,
                                          claritySlider, deEssSlider, airSlider, compressionPopup, loudnessPopup,
                                          listenButton, saveVoiceButton]
        voiceControls.forEach { $0.isEnabled = hasVoice && !exporting }
        systemSlider.isEnabled = hasSystemAudio && !exporting
        // A recording from before #385 has one mixed track: its slider is the whole sound's.
        ((micRow as? NSStackView)?.arrangedSubviews.first as? NSTextField)?.stringValue = audioSources == [.mixed] ? "Volume" : "Voice"
        micRow.isHidden = !hasVoice
        systemRow.isHidden = !hasSystemAudio
        if previewAudioTracks.isEmpty {
            audioHint.stringValue = "This recording has no sound."
        } else if !hasVoice {
            audioHint.stringValue = "No microphone was recorded, so there's no voice to clean up."
        } else {
            var text = a.preset.detail
            if a.noiseRemoval == .high && !VoiceIsolation.isAvailable {
                text += " Voice Isolation isn't available on this Mac, so High uses Skreener's own noise reduction and silences the pauses."
            } else if a.noiseRemoval != .off {
                text += a.noiseRemoval == .high ? " Voice Isolation and noise reduction take out the background, and the pauses between words go silent."
                    : " Background hiss is reduced, and turned down further between words."
            }
            if a.tuning != nil && a.preset != .mine { text += " Fine-tuned." }
            if !a.isNeutral { text += " Listen plays 15 seconds of the result; volumes play along with the preview." }
            audioHint.stringValue = text
        }
    }

    /// The preview plays each track at its volume (presets and noise removal are applied at export).
    private func updatePreviewMix() {
        guard let item = player.currentItem, !previewAudioTracks.isEmpty else { return }
        let a = settings.audio
        let mix = AVMutableAudioMix()
        mix.inputParameters = zip(previewAudioTracks, audioSources).map { track, source in
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(Float(source == .system ? a.systemVolume : a.micVolume), at: .zero)
            return p
        }
        item.audioMix = mix
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
            refreshCalloutControls()
        } else {
            compositor = Self.previewCompositor(project: project, events: events, folder: folder, settings: settings)
            refreshControls()
        }
        refreshAudioControls()
        updatePreviewMix()
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
        case captionsShownSwitch: settings.captionsShown = on
        case captionsFileSwitch: settings.captionsFile = on
        case idleSwitch: settings.cursor.hideWhenIdle = on
        case autoZoomSwitch: settings.autoZoom = on
        case calloutFollowSwitch: changeSelectedCallout(on ? "Follow Zoom" : "Stay Put") { $0.followsZoom = on }
        default: break
        }
    }

    @objc private func audioOptionPicked(_ popup: PillPopUp) {
        let i = popup.selectedTag()
        switch popup {
        case presetPopup where AudioPreset.allCases.indices.contains(i):
            let preset = AudioPreset.allCases[i]
            var a = settings.audio
            a.preset = preset
            // A new preset starts from what it does (My Voice from what was saved), with the noise removal chosen.
            a.tuning = preset == .mine ? Preferences.myVoice : nil
            if a.tuning != nil { a.tuning?.setNoise(a.noiseRemoval) }
            settings.audio = a
        case noisePopup where NoiseRemoval.allCases.indices.contains(i):
            settings.audio.noiseRemoval = NoiseRemoval.allCases[i]
            settings.audio.tuning?.setNoise(NoiseRemoval.allCases[i])
        default: break
        }
    }

    /// A fine-tune control was changed: the preset's tuning with that one change.
    @objc private func tuningChanged(_ sender: NSControl) {
        var t = settings.audio.effectiveTuning
        func snapped(_ v: Double) -> Double { (v * 2).rounded() / 2 }
        switch sender {
        case noiseReductionSlider: t.noiseReduction = noiseReductionSlider.doubleValue.rounded()
        case pauseSlider: t.pauseSilence = pauseSlider.doubleValue.rounded()
        case warmthSlider: t.warmth = snapped(warmthSlider.doubleValue)
        case claritySlider: t.clarity = snapped(claritySlider.doubleValue)
        case deEssSlider: t.deEss = snapped(deEssSlider.doubleValue)
        case airSlider: t.air = snapped(airSlider.doubleValue)
        case compressionPopup:
            let i = compressionPopup.selectedTag()
            if VoiceTuning.compressionRatios.indices.contains(i) { t.compression = VoiceTuning.compressionRatios[i] }
        case loudnessPopup:
            let i = loudnessPopup.selectedTag() - 1
            t.loudness = VoiceTuning.loudnessTargets.indices.contains(i) ? VoiceTuning.loudnessTargets[i].value : nil
        default: return
        }
        if (t.noiseReduction > 0 || t.pauseSilence > 0), t.highPass == nil { t.highPass = 70 }
        settings.audio.tuning = t.clamped
    }

    @objc private func resetTuning() {
        settings.audio.tuning = settings.audio.preset == .mine ? Preferences.myVoice : nil
    }

    /// Keeps the fine-tuning as the My Voice preset, for this recording and the next ones.
    @objc private func saveMyVoice() {
        let t = settings.audio.effectiveTuning
        Preferences.myVoice = t
        settings.audio.preset = .mine
        settings.audio.tuning = t
        refreshAudioControls()
        status.stringValue = "Saved as My Voice. New recordings start with it."
    }

    /// Plays (or stops) 15 seconds of the voice from the playhead, cleaned up as the settings say.
    @objc private func listenToVoice() {
        if voicePreviewTask != nil || voicePlayer?.isPlaying == true {
            stopVoicePreview()
            return
        }
        setPlaying(false)
        let video = folder.appendingPathComponent(RecordingProject.videoFile)
        let sources = project.audioTracks, audio = settings.audio, from = time
        status.stringValue = "Preparing your voice with these settings…"
        voicePreviewTask = Task { [weak self] in
            let result: Result<URL?, Error>
            do {
                result = .success(try await AudioFinisher.preview(video, sources: sources, settings: audio, from: from))
            } catch { result = .failure(error) }
            guard let self, !Task.isCancelled else { return }
            self.voicePreviewTask = nil
            switch result {
            case .success(let file?):
                if let player = try? AVAudioPlayer(contentsOf: file) {
                    self.voicePlayer = player
                    player.play()
                    self.status.stringValue = "Playing your voice with these settings. Press Stop to stop."
                    let length = player.duration
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64((length + 0.2) * 1_000_000_000))
                        guard let self, self.voicePlayer === player else { return }
                        self.stopVoicePreview()
                    }
                }
                try? FileManager.default.removeItem(at: file)
            case .success(nil):
                self.status.stringValue = "This recording has no voice to listen to."
            case .failure(let error):
                NSLog("Couldn't prepare the voice preview: \(error)")
                self.status.stringValue = "Couldn't prepare the voice preview."
            }
            self.refreshAudioControls()
        }
        refreshAudioControls()
    }

    private func stopVoicePreview() {
        voicePreviewTask?.cancel()
        voicePreviewTask = nil
        voicePlayer?.stop()
        voicePlayer = nil
        if status.stringValue.hasPrefix("Playing your voice") || status.stringValue.hasPrefix("Preparing your voice") {
            status.stringValue = exportHint
        }
        refreshAudioControls()
    }

    @objc private func volumeChanged(_ slider: NSSlider) {
        // Snaps to 100% near it, so as recorded is easy to get back to.
        var v = AudioSettings.clamped(slider.doubleValue)
        if abs(v - 1) < 0.04 { v = 1 }
        if slider === micSlider { settings.audio.micVolume = v } else { settings.audio.systemVolume = v }
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

    @objc private func cursorOptionPicked(_ popup: PillPopUp) {
        let tag = popup.selectedTag()
        switch popup {
        case smoothingPopup where CursorSmoothing.allCases.indices.contains(tag): settings.cursor.smoothing = CursorSmoothing.allCases[tag]
        case idleDelayPopup: settings.cursor.idleDelay = Double(tag) / 10
        default: break
        }
    }

    @objc private func cursorSizeChanged() {
        settings.cursor.size = CursorSettings.clampedSize(cursorSizeSlider.doubleValue)
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
        guard exportTask == nil, zoomDrag == nil, calloutDrag == nil, let undo = window.undoManager else { return }
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
        drawCalloutSelection(in: ctx)
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
        editTrack.time = time
        calloutTrack.time = time
        refreshCaptionControls()
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
            if voicePlayer != nil || voicePreviewTask != nil { stopVoicePreview() }
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
        followEdits()
        if player.rate == 0, time >= duration - 0.05 { setPlaying(false) }
        refreshTime()
        redraw()
    }

    /// While playing, the preview plays the edited video (#381): it jumps over cuts and plays sped-up ranges faster.
    private func followEdits() {
        guard playing, !settings.edits.isEmpty else {
            if playing, player.rate != 0, player.rate != 1 { player.rate = 1 }
            if player.isMuted { player.isMuted = false }
            return
        }
        let edit = timeline.edit(at: time)
        // A muted range plays silently (the export fades in and out of it).
        let muted = edit?.isMute ?? false
        if player.isMuted != muted { player.isMuted = muted }
        if let edit, edit.isCut {
            time = min(edit.end, duration)
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if time >= duration - 0.05 { setPlaying(false) }
            return
        }
        let rate = Float(edit?.speed ?? 1)
        if player.rate != 0, player.rate != rate { player.rate = rate }
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
        let preset = settings.exportPreset
        let recording = AutoFiling.current(file)
        let target = preset.destination(for: recording)
        let folder = folder, fps = project.fps
        // Full size, made here: the background is drawn with AppKit.
        let full = StudioCompositor(project: project, events: events, folder: folder, settings: settings)
        let box = ExportProgress()
        exportProgress = box
        let sources = project.audioTracks
        let edits = timeline
        // The captions as an .srt next to the video (#386), on its edited timeline.
        let srt = settings.captionsFile && !settings.captions.isEmpty && preset != .gif
            ? Captions.srt(Captions.laidOut(settings.captions, on: edits)) : nil
        exportTask = Task { [weak self] in
            var failure: Error?
            var outcome = AudioFinisher.Outcome()
            do {
                // Made next to the recording, which is replaced only once the video and its audio are both done.
                let fm = FileManager.default
                let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
                defer { try? fm.removeItem(at: dir) }
                let made = dir.appendingPathComponent(recording.lastPathComponent)
                if full.changesTheVideo || edits.changesTime {
                    try await RecordingRenderer.render(folder: folder, fps: fps, compositor: full, to: made,
                                                       edits: edits) { box.set($0 * 0.85) }
                } else {
                    // Nothing to draw: the clean video is the finished one.
                    try fm.copyItem(at: folder.appendingPathComponent(RecordingProject.videoFile), to: made)
                }
                try Task.checkCancellation()
                box.set(0.9)
                if preset == .gif {
                    // A GIF has no sound (#386).
                    let gif = dir.appendingPathComponent(target.lastPathComponent)
                    try await GIFExporter.export(made, to: gif)
                    try Task.checkCancellation()
                    try Self.replace(target, with: gif)
                } else {
                    // The voice cleaned up, the volumes set and the tracks mixed into one (#385).
                    outcome = try await AudioFinisher.finish(made, sources: sources, settings: settings.audio, edits: edits)
                    try Task.checkCancellation()
                    try Self.replace(target, with: made)
                    if let srt { try srt.write(to: Captions.srtURL(for: target), atomically: true, encoding: .utf8) }
                }
            } catch {
                failure = error
            }
            self?.exportFinished(settings: settings, target: target, error: failure, audio: outcome)
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

    private func exportFinished(settings exported: StudioSettings, target: URL, error: Error?,
                                audio: AudioFinisher.Outcome = AudioFinisher.Outcome()) {
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
        guard exported.exportPreset.replacesRecording else {
            // A copy at another size, or a GIF, next to the recording (#386): the editor stays open for the next one.
            refreshControls()
            status.stringValue = "Saved \(target.lastPathComponent) next to the recording."
            let isGIF = exported.exportPreset == .gif
            if audio.isolationUnavailable {
                Notifier.problem("Voice Isolation couldn't run",
                                 detail: "Skreener's own noise reduction and noise gate cleaned up the background instead.")
            }
            Task { @MainActor in
                if !isGIF { await RecordingController.compress(target) }
                SavedLibrary.shared.note(target)
                Sound.play("Glass")
                if isGIF { NSWorkspace.shared.activateFileViewerSelecting([target]) } else { QuickAccessController.show(recording: target) }
            }
            if closeAfterExport { window.close() }
            return
        }
        project.exported = target.path
        do {
            try project.encoded().write(to: folder.appendingPathComponent(RecordingProject.projectFile), options: .atomic)
        } catch {
            NSLog("Couldn't update the recording project: \(error)")
        }
        refreshControls()
        window.close()
        if audio.isolationUnavailable {
            Notifier.problem("Voice Isolation couldn't run",
                             detail: "Skreener's own noise reduction and noise gate cleaned up the background instead.")
        }
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
        captionTask?.cancel()
        calloutDrag = nil
        stopVoicePreview()
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
    /// I (true) and O (false): set the In or Out mark at the playhead (#381).
    var onMark: ((Bool) -> Void)?

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
        let plain = event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onSpace?()
        } else if plain, let key = event.charactersIgnoringModifiers?.lowercased(), key == "i" || key == "o", let onMark {
            onMark(key == "i")
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The undo step for zoom section edits: the sections to go back to.
/// The undo step for cuts and speed changes: the edits to go back to.
private final class CalloutUndoStep: NSObject {
    let callouts: [Callout]
    let name: String
    init(_ callouts: [Callout], name: String) {
        self.callouts = callouts
        self.name = name
    }
}

private final class CaptionUndoStep: NSObject {
    let captions: [Caption]
    let name: String
    init(_ captions: [Caption], name: String) {
        self.captions = captions
        self.name = name
    }
}

private final class EditUndoStep: NSObject {
    let edits: [TimelineEdit]
    let name: String
    init(_ edits: [TimelineEdit], name: String) {
        self.edits = edits
        self.name = name
    }
}

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
    /// A press at a point (the view's coordinates); true when it was on a callout, which a drag then moves.
    var onPress: ((CGPoint) -> Bool)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: (() -> Void)?
    private var dragging = false

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
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) {
            onOptionClick?(p)
        } else if onPress?(p) == true {
            dragging = true
        } else {
            onClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onRelease?()
    }
}
