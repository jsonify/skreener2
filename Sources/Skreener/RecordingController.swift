import AppKit

/// Runs one screen recording at a time: the optional countdown, the frame around the recorded area, the
/// dimming outside it, the HUD (elapsed time, pause/resume, stop), the click/keystroke effects, and the Quick
/// Access preview shown when the file is ready. Skreener's own windows are left out of the recording, except the
/// effects overlay, so the HUD, frame and dimming never show up in the video.
final class RecordingController {
    private var recorder: ScreenRecorder?
    private let countdown = SelfTimer()
    private let effects = RecordingEffects()
    private var hud: NSPanel?
    private var frame: NSPanel?
    private var dims: [NSPanel] = []
    private var timeLabel: NSTextField?
    private var dot: NSView?
    private var pauseButton: PillButton?
    private var ticker: Timer?
    private var startedAt = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    /// Where the GIF goes when this recording is a GIF (the video is then a temporary file).
    private var gifURL: URL?

    var isRecording: Bool { recorder != nil }
    /// Called with true on start and false when the recording ends (saved, failed, cancelled or never started).
    var onStateChange: ((Bool) -> Void)?
    /// The elapsed time ("01:23") while recording, about twice a second.
    var onTick: ((String) -> Void)?

    /// Records `screen`, or the area `rect` on it (global, bottom-left origin coordinates), as a video or a GIF.
    func start(screen: NSScreen, rect: CGRect?, gif: Bool = false) {
        guard recorder == nil else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Skreener Recording \(f.string(from: Date()))"
        gifURL = gif ? Preferences.saveDirectory.appendingPathComponent(name + ".gif") : nil
        let video = (gif ? FileManager.default.temporaryDirectory : Preferences.saveDirectory).appendingPathComponent(name + ".mp4")
        let r = ScreenRecorder(url: video)
        r.onFinish = { [weak self] result in self?.finished(result) }
        recorder = r
        showFrame(rect, on: screen)
        if let rect, Preferences.recordDimScreen { showDim(around: rect) }
        onStateChange?(true)
        guard Preferences.recordCountdown else { capture(r, screen: screen, rect: rect, gif: gif); return }
        countdown.start(seconds: 3, completion: { [weak self] in self?.capture(r, screen: screen, rect: rect, gif: gif) },
                        cancelled: { [weak self] in self?.tearDown() })
    }

    private func capture(_ r: ScreenRecorder, screen: NSScreen, rect: CGRect?, gif: Bool) {
        effects.start(area: rect ?? screen.frame, clicks: Preferences.recordHighlightClicks,
                      keys: Preferences.recordShowKeystrokes && AccessibilityAccess.granted)
        var options = ScreenRecorder.Options()
        if gif { options.systemAudio = false; options.microphone = false }
        let keep = effects.panel.map { [CGWindowID($0.windowNumber)] } ?? []
        if Preferences.recordShowControls { showHUD(near: rect ?? screen.frame, on: screen, fullscreen: rect == nil) }
        startedAt = Date(); pausedAt = nil; pausedTotal = 0
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        Task { @MainActor [weak self] in
            do {
                try await r.start(screen: screen, rect: rect, options: options, including: keep)
                self?.startedAt = Date()
            } catch {
                NSLog("Recording failed to start: \(error)")
                NSSound.beep()
                self?.tearDown()
            }
        }
    }

    func stop() {
        if countdown.isRunning { countdown.cancel(); return }
        guard let recorder else { return }
        ticker?.invalidate(); ticker = nil
        hideWindows()
        recorder.stop()
    }

    func togglePause() {
        guard let recorder else { return }
        if let p = pausedAt {
            pausedTotal += Date().timeIntervalSince(p)
            pausedAt = nil
        } else {
            pausedAt = Date()
        }
        let paused = pausedAt != nil
        recorder.setPaused(paused)
        pauseButton?.toolTip = paused ? "Resume" : "Pause"
        pauseButton?.setContent(title: nil, symbol: paused ? "play.fill" : "pause.fill")
        dot?.layer?.backgroundColor = (paused ? NSColor.systemOrange : NSColor.systemRed).cgColor
        tick()
    }

    private func finished(_ result: Result<URL, Error>) {
        let gif = gifURL
        tearDown()
        switch result {
        case .success(let url):
            guard let gif else { delivered(url); return }
            Task { @MainActor [weak self] in
                do {
                    try await GIFExporter.export(url, to: gif)
                    self?.delivered(gif, video: url)
                } catch {
                    NSLog("GIF export failed: \(error)")
                    NSSound.beep()
                    try? FileManager.default.removeItem(at: url)
                }
            }
        case .failure(let error):
            NSLog("Recording failed: \(error)")
            NSSound.beep()
        }
    }

    /// `video` is the temporary MP4 a GIF was made from: the preview keeps it for Trim, else it is deleted here.
    private func delivered(_ url: URL, video: URL? = nil) {
        NSSound(named: "Glass")?.play()
        if Preferences.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
        if Preferences.showQuickAccess {
            QuickAccessController.show(recording: url, video: video)
        } else if let video {
            try? FileManager.default.removeItem(at: video)
        }
    }

    private func hideWindows() {
        hud?.orderOut(nil); hud = nil
        frame?.orderOut(nil); frame = nil
        dims.forEach { $0.orderOut(nil) }; dims.removeAll()
        effects.stop()
    }

    private func tearDown() {
        ticker?.invalidate(); ticker = nil
        hideWindows()
        recorder = nil
        gifURL = nil
        onStateChange?(false)
    }

    // MARK: Elapsed time

    private func tick() {
        var elapsed = Date().timeIntervalSince(startedAt) - pausedTotal
        if let p = pausedAt { elapsed -= Date().timeIntervalSince(p) }
        let s = max(0, Int(elapsed))
        let text = String(format: "%02d:%02d", s / 60, s % 60)
        timeLabel?.stringValue = text
        onTick?(text)
    }

    // MARK: Windows

    /// Dims every screen except the recorded area. Click-through, and not in the video.
    private func showDim(around rect: CGRect) {
        for screen in NSScreen.screens {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.hole = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            p.contentView = v
            p.orderFrontRegardless()
            dims.append(p)
        }
    }

    /// A dashed outline just outside the recorded area (not shown for fullscreen).
    private func showFrame(_ rect: CGRect?, on screen: NSScreen) {
        guard let rect else { return }
        let p = NSPanel(contentRect: rect.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = RecordingFrameView()
        p.orderFrontRegardless()
        frame = p
    }

    /// The control bar: below the area if there's room, else above it, else inside its bottom edge. The same dark
    /// capsule and pill buttons as the scrolling-capture bar.
    private func showHUD(near area: CGRect, on screen: NSScreen, fullscreen: Bool) {
        let d = NSView()
        d.wantsLayer = true
        d.layer?.cornerRadius = 5
        d.layer?.backgroundColor = NSColor.systemRed.cgColor
        d.translatesAutoresizingMaskIntoConstraints = false
        d.widthAnchor.constraint(equalToConstant: 10).isActive = true
        d.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let l = NSTextField(labelWithString: "00:00")
        l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        l.textColor = NSColor.white.withAlphaComponent(0.9)
        let pause = PillButton(title: nil, symbol: "pause.fill", style: .tinted) { [weak self] in self?.togglePause() }
        pause.toolTip = "Pause"
        let stop = PillButton(title: "Stop", symbol: "stop.fill", style: .filled) { [weak self] in self?.stop() }
        stop.toolTip = "Stop Recording (⌃⇧7)"
        let row = NSStackView(views: [d, l, pause, stop])
        row.spacing = 8
        row.setCustomSpacing(14, after: l)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 7)

        let size = NSSize(width: ceil(row.fittingSize.width), height: 44)
        let vis = screen.visibleFrame
        var y = area.minY - size.height - 10
        if fullscreen || y < vis.minY { y = area.maxY + 10 }
        if fullscreen || y + size.height > vis.maxY { y = max(vis.minY, area.minY) + 16 }
        let x = min(max(area.midX - size.width / 2, vis.minX + 8), vis.maxX - size.width - 8)
        let p = NSPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSAppearance(named: .darkAqua)

        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = PillButton.barColor.cgColor
        bg.layer?.cornerRadius = size.height / 2; bg.layer?.cornerCurve = .continuous; bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0.5; bg.layer?.borderColor = PillButton.barBorderColor.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        p.contentView = bg
        p.orderFrontRegardless()
        hud = p; timeLabel = l; dot = d; pauseButton = pause
    }
}

private final class DimView: NSView {
    var hole = NSRect.zero
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: hole))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
    }
}

private final class RecordingFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}
