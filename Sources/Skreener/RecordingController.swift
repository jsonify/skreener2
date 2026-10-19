import AppKit
import AVFoundation

/// Runs one screen recording at a time: the frame around the recorded area, the HUD (elapsed time,
/// pause/resume, stop), and the thumbnail shown when the file is ready. Skreener's own windows are left out of
/// the recording, so the HUD and frame never show up in the video.
final class RecordingController {
    private var recorder: ScreenRecorder?
    private var hud: NSPanel?
    private var frame: NSPanel?
    private var timeLabel: NSTextField?
    private var dot: NSView?
    private var pauseButton: NSButton?
    private var ticker: Timer?
    private var startedAt = Date()
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    var isRecording: Bool { recorder != nil }
    /// Called with true on start and false when the recording ends (saved, failed or never started).
    var onStateChange: ((Bool) -> Void)?

    /// Records `screen`, or the area `rect` on it (global, bottom-left origin coordinates).
    func start(screen: NSScreen, rect: CGRect?) {
        guard recorder == nil else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = Preferences.saveDirectory.appendingPathComponent("Skreener Recording \(f.string(from: Date())).mp4")
        let r = ScreenRecorder(url: url)
        r.onFinish = { [weak self] result in self?.finished(result) }
        recorder = r
        startedAt = Date(); pausedAt = nil; pausedTotal = 0
        showFrame(rect, on: screen)
        showHUD(near: rect ?? screen.frame, on: screen, fullscreen: rect == nil)
        onStateChange?(true)
        Task { @MainActor [weak self] in
            do {
                try await r.start(screen: screen, rect: rect)
                self?.startedAt = Date()
            } catch {
                NSLog("Recording failed to start: \(error)")
                NSSound.beep()
                self?.tearDown()
            }
        }
    }

    func stop() {
        guard let recorder else { return }
        ticker?.invalidate(); ticker = nil
        hud?.orderOut(nil); frame?.orderOut(nil)
        recorder.stop()
    }

    @objc func togglePause() {
        guard let recorder else { return }
        if let p = pausedAt {
            pausedTotal += Date().timeIntervalSince(p)
            pausedAt = nil
        } else {
            pausedAt = Date()
        }
        let paused = pausedAt != nil
        recorder.setPaused(paused)
        pauseButton?.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill", accessibilityDescription: paused ? "Resume" : "Pause")
        pauseButton?.toolTip = paused ? "Resume" : "Pause"
        dot?.layer?.backgroundColor = (paused ? NSColor.systemOrange : NSColor.systemRed).cgColor
        tick()
    }

    @objc private func stopClicked() { stop() }

    private func finished(_ result: Result<URL, Error>) {
        tearDown()
        switch result {
        case .success(let url):
            NSSound(named: "Glass")?.play()
            if Preferences.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
            RecordingQuickAccess.show(url)
        case .failure(let error):
            NSLog("Recording failed: \(error)")
            NSSound.beep()
        }
    }

    private func tearDown() {
        ticker?.invalidate(); ticker = nil
        hud?.orderOut(nil); hud = nil
        frame?.orderOut(nil); frame = nil
        recorder = nil
        onStateChange?(false)
    }

    // MARK: Elapsed time

    private func tick() {
        var elapsed = Date().timeIntervalSince(startedAt) - pausedTotal
        if let p = pausedAt { elapsed -= Date().timeIntervalSince(p) }
        let s = max(0, Int(elapsed))
        timeLabel?.stringValue = String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Windows

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

    /// The control pill: below the area if there's room, else above it, else inside its bottom edge.
    private func showHUD(near area: CGRect, on screen: NSScreen, fullscreen: Bool) {
        let size = NSSize(width: 156, height: 36)
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

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = size.height / 2; bg.layer?.masksToBounds = true

        let d = NSView(frame: NSRect(x: 14, y: size.height / 2 - 5, width: 10, height: 10))
        d.wantsLayer = true
        d.layer?.cornerRadius = 5
        d.layer?.backgroundColor = NSColor.systemRed.cgColor
        let l = NSTextField(labelWithString: "00:00")
        l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        l.frame = NSRect(x: 30, y: size.height / 2 - 9, width: 50, height: 18)
        let pause = hudButton("pause.fill", "Pause", #selector(togglePause), x: 84)
        let stop = hudButton("stop.fill", "Stop Recording", #selector(stopClicked), x: 118)
        stop.contentTintColor = .systemRed
        [d, l, pause, stop].forEach(bg.addSubview)
        p.contentView = bg
        p.orderFrontRegardless()
        hud = p; timeLabel = l; dot = d; pauseButton = pause
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func hudButton(_ sym: String, _ tip: String, _ action: Selector, x: CGFloat) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: sym, accessibilityDescription: tip) ?? NSImage(), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.controlSize = .small
        b.imagePosition = .imageOnly
        b.toolTip = tip
        b.frame = NSRect(x: x, y: 6, width: 30, height: 24)
        return b
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

/// Floating thumbnail for a finished recording: open, show in Finder, copy the file, dismiss.
final class RecordingQuickAccess {
    private static var live: [RecordingQuickAccess] = []
    private var panel: NSPanel?
    private var timer: Timer?
    private let url: URL

    private init(url: URL) { self.url = url }

    static func show(_ url: URL) {
        let qa = RecordingQuickAccess(url: url)
        live.append(qa)
        qa.present()
    }

    private func present() {
        let size = NSSize(width: 236, height: 164)
        guard let screen = NSScreen.main else { return }
        let p = NSPanel(contentRect: NSRect(origin: NSPoint(x: screen.visibleFrame.minX + 16, y: screen.visibleFrame.minY + 16), size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = 12; bg.layer?.masksToBounds = true
        let iv = NSImageView(frame: NSRect(x: 8, y: 36, width: size.width - 16, height: size.height - 44))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = NSImage(systemSymbolName: "film", accessibilityDescription: "Recording")
        bg.addSubview(iv)
        var x: CGFloat = 8
        for (title, sel) in [("Open", #selector(openIt)), ("Show", #selector(showIt)), ("Copy", #selector(copyIt)), ("✕", #selector(closeIt))] {
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded; b.controlSize = .small
            b.frame = NSRect(x: x, y: 6, width: title == "✕" ? 28 : 54, height: 24)
            bg.addSubview(b); x += b.frame.width + 6
        }
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in self?.closeIt() }

        // First frame as the thumbnail.
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 440, height: 300)
        Task { @MainActor in
            if let cg = try? await gen.image(at: .zero).image { iv.image = NSImage(cgImage: cg, size: .zero) }
        }
    }

    @objc private func openIt() { NSWorkspace.shared.open(url); closeIt() }
    @objc private func showIt() { NSWorkspace.shared.activateFileViewerSelecting([url]); closeIt() }
    @objc private func copyIt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        NSSound(named: "Pop")?.play()
    }
    @objc private func closeIt() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        RecordingQuickAccess.live.removeAll { $0 === self }
    }
}
