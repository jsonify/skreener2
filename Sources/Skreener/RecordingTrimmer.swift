import AppKit
import AVFoundation
import AVKit

/// Cutting the start and end off a finished recording. The trimmed recording replaces the saved file (a recording
/// is trimmed right after it is made, before it is shared, so a second copy would only be clutter). The video is
/// copied, not re-encoded (passthrough), so trimming is quick and loses no quality. A GIF is made again from the
/// trimmed video.
enum RecordingTrim {
    enum TrimError: Error { case cannotExport }

    /// The part of a `duration`-long video to keep, from AVPlayerView's trim handles: the player item's reverse and
    /// forward playback end times, which are invalid when that handle wasn't moved. Nil when nothing was cut off.
    static func keptRange(start: CMTime, end: CMTime, duration: CMTime) -> CMTimeRange? {
        guard duration.isNumeric, duration.seconds > 0 else { return nil }
        let s = start.isNumeric && start.seconds > 0 ? start : .zero
        let e = end.isNumeric && end.seconds < duration.seconds ? end : duration
        let slack = 0.01   // a handle closer than this to its end hasn't cut anything
        guard e.seconds - s.seconds > slack, s.seconds > slack || e.seconds < duration.seconds - slack else { return nil }
        return CMTimeRange(start: s, duration: CMTimeSubtract(e, s))
    }

    /// Copies `range` of the MP4 `video` to `out`, without re-encoding.
    static func export(_ video: URL, range: CMTimeRange, to out: URL) async throws {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: video), presetName: AVAssetExportPresetPassthrough)
        else { throw TrimError.cannotExport }
        session.timeRange = range
        if #available(macOS 15, *) {
            try await session.export(to: out, as: .mp4)
        } else {
            session.outputURL = out
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else { throw session.error ?? TrimError.cannotExport }
        }
    }

    /// Trims the recording `file` to `range` in place. `video` is the MP4 it was made from: the file itself, or
    /// for a GIF the video it was converted from. Returns the trimmed video: the file itself, or for a GIF a new
    /// temporary MP4 (so the GIF can be trimmed again). The file is only replaced once everything has worked.
    static func trim(_ file: URL, video: URL, range: CMTimeRange) async throws -> URL {
        let fm = FileManager.default
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        defer { try? fm.removeItem(at: scratch) }
        let cut = scratch.appendingPathComponent("Trimmed.mp4")
        try await export(video, range: range, to: cut)
        guard file.pathExtension.lowercased() == "gif" else {
            _ = try fm.replaceItemAt(file, withItemAt: cut)
            return file
        }
        let kept = fm.temporaryDirectory.appendingPathComponent("Skreener Trim \(UUID().uuidString).mp4")
        try fm.moveItem(at: cut, to: kept)
        do {
            let gif = scratch.appendingPathComponent("Trimmed.gif")
            try await GIFExporter.export(kept, to: gif)
            _ = try fm.replaceItemAt(file, withItemAt: gif)
        } catch {
            try? fm.removeItem(at: kept)
            throw error
        }
        return kept
    }
}

/// The trim editor, opened from a recording's thumbnail: a window playing the recording with AVKit's trim bar.
/// Drag the yellow handles, then Trim saves the shorter recording over the file and shows a new thumbnail for it;
/// Cancel (or closing the window) leaves the file as it was.
@MainActor final class RecordingTrimWindow: NSObject, NSWindowDelegate {
    private static var live: [RecordingTrimWindow] = []

    private let file: URL
    /// The MP4 shown and cut: `file` itself, or for a GIF the temporary video it was made from, deleted afterwards.
    private let video: URL
    private let window: NSWindow
    private let playerView: AVPlayerView
    /// The temporary video went on to a new thumbnail (or is already deleted), so closing mustn't delete it.
    private var videoHandedOn = false
    private var closed = false

    // Called from the recording thumbnail (not main-actor isolated itself), on the main thread.

    /// Opens the trim editor for the recording `file`, made from the MP4 `video` (the same file unless it's a GIF).
    nonisolated static func open(_ file: URL, video: URL) {
        MainActor.assumeIsolated {
            let t = RecordingTrimWindow(file: file, video: video)
            live.append(t)
            t.present()
        }
    }

    private init(file: URL, video: URL) {
        self.file = file
        self.video = video
        playerView = AVPlayerView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Trim \(file.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 300)
        window.delegate = self
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: video)
        window.contentView = playerView
        window.center()
    }

    private func present() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { [weak self] in await self?.runTrimming() }
    }

    private func runTrimming() async {
        // The trim bar needs the video loaded first; give it a few seconds.
        var waited = 0
        while !playerView.canBeginTrimming, waited < 50, !closed {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard !closed else { return }
        guard playerView.canBeginTrimming else { NSSound.beep(); window.close(); return }
        let result = await playerView.beginTrimming()
        guard !closed else { return }
        guard result == .okButton, let item = playerView.player?.currentItem,
              let range = RecordingTrim.keptRange(start: item.reversePlaybackEndTime, end: item.forwardPlaybackEndTime,
                                                  duration: item.duration)
        else { window.close(); return }

        // Let go of the file before it is replaced.
        playerView.player?.pause()
        playerView.player = nil
        window.title = "Saving \(file.lastPathComponent)…"
        window.styleMask.remove(.closable)   // the file is being replaced; let that finish
        do {
            let trimmed = try await RecordingTrim.trim(file, video: video, range: range)
            if video != file { try? FileManager.default.removeItem(at: video) }
            videoHandedOn = true
            QuickAccessController.show(recording: file, video: trimmed)
        } catch {
            NSLog("Trim failed: \(error)")
            NSAlert(error: error).runModal()
        }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        if video != file, !videoHandedOn { try? FileManager.default.removeItem(at: video) }
        videoHandedOn = true
        closed = true
        Self.live.removeAll { $0 === self }
    }
}
