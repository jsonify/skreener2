import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecordingError: Error { case noDisplay, noFrames, writerFailed }

/// Records a display, or an area of it, to an H.264 MP4: ScreenCaptureKit frames (and optionally system audio
/// and, on macOS 15+, the microphone) go straight into an AVAssetWriter; with both audio sources the two audio
/// tracks are mixed into one afterwards (`AudioMixer`). Skreener's own windows (HUD, area frame) are left out of
/// the recording, except those named in `start` or `include`. Sample buffers arrive on `queue`; everything the
/// writer touches stays there.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Options {
        var systemAudio = Preferences.recordSystemAudio
        var microphone = Preferences.recordMicrophone
        var showsCursor = Preferences.recordShowsCursor
        var fps = Preferences.recordFrameRate
    }

    /// H.264 can't encode frames much bigger than 4K, so larger areas are scaled down to fit.
    static let maxPixels = 4096 * 2304

    /// The video's size in pixels for `rect` (or the whole of `screen`).
    static func videoSize(screen: NSScreen, rect: CGRect?) -> CGSize {
        RecordingGeometry.videoSize(area: (rect ?? screen.frame).size, backingScale: screen.backingScaleFactor, maxPixels: maxPixels)
    }

    let url: URL
    /// Called once on the main queue when the file is finished (or recording failed).
    var onFinish: ((Result<URL, Error>) -> Void)?
    /// Called on the recorder's queue for each video frame written, with its time in the video (seconds from the
    /// first frame, time paused left out). Set it before `start`.
    var onFrame: (@Sendable (Double) -> Void)?

    private let queue = DispatchQueue(label: "com.skreener.recorder")
    private var stream: SCStream?
    private var display: SCDisplay?
    /// The Skreener windows that are in the video (see `start` and `include`); nil until either sets them.
    private var included: [CGWindowID]?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var finished = false
    // Pausing drops samples; on resume, later samples are shifted back by the time spent paused.
    private var paused = false
    private var pauseStart = CMTime.invalid
    private var pausedTotal = CMTime.zero
    private var sessionStart = CMTime.zero
    // The same pause bookkeeping in seconds, for `videoTime(hostTime:)` from any thread.
    private let clockLock = NSLock()
    private var clock = RecordingClock()

    init(url: URL) { self.url = url }

    /// Starts recording `screen`, or the part of it at `rect` (global, bottom-left origin coordinates).
    /// `including` names Skreener windows that should be in the video after all (the click/keystroke overlay).
    func start(screen: NSScreen, rect: CGRect?, options: Options = Options(), including: [CGWindowID] = []) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw RecordingError.noDisplay }
        let filter = Self.filter(content, display: display, including: including)

        let size = Self.videoSize(screen: screen, rect: rect)
        let width = Int(size.width), height = Int(size.height)

        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        if let rect {
            cfg.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                                    width: rect.width, height: rect.height)
        }
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        cfg.showsCursor = options.showsCursor
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 6
        cfg.capturesAudio = options.systemAudio
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48_000
        cfg.channelCount = 2
        var microphone = false
        if #available(macOS 15.0, *), options.microphone, await Self.microphoneAllowed() {
            cfg.captureMicrophone = true
            microphone = true
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, Int(Double(width * height * options.fps) * 0.12)),
                AVVideoExpectedSourceFrameRateKey: options.fps,
                AVVideoMaxKeyFrameIntervalKey: options.fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        func audio(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: channels * 64_000,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            return input
        }
        // System audio and the microphone go to separate tracks while recording; `finish` mixes them into one.
        let systemAudio = options.systemAudio ? audio(channels: 2) : nil
        let mic = microphone ? audio(channels: 1) : nil
        guard writer.startWriting() else { throw writer.error ?? RecordingError.writerFailed }

        let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if #available(macOS 15.0, *), microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        queue.sync {
            self.writer = writer
            self.videoInput = video
            self.audioInput = systemAudio
            self.micInput = mic
            self.stream = stream
            self.display = display
            if self.included == nil { self.included = including }
        }
        do { try await stream.startCapture() } catch {
            writer.cancelWriting()
            throw error
        }
        // Stopped while starting up: nothing else will stop the stream now.
        if queue.sync(execute: { finished }) { try? await stream.stopCapture(); return }
        // `include` called while starting up found no stream to update.
        let now = queue.sync { included ?? including }
        if now != including { include(now) }
    }

    /// Everything on `display` except Skreener's windows, but with the Skreener windows in `including`.
    private static func filter(_ content: SCShareableContent, display: SCDisplay, including: [CGWindowID]) -> SCContentFilter {
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let keep = content.windows.filter { including.contains($0.windowID) }
        return SCContentFilter(display: display, excludingApplications: me, exceptingWindows: keep)
    }

    /// Puts exactly these Skreener windows in the video from now on, e.g. the presenter overlay opened or closed while
    /// recording (#266). The shareable content is fetched again, as a window that just opened is only in a fresh one.
    func include(_ windows: [CGWindowID]) {
        Task { [self] in
            let (stream, display) = queue.sync { () -> (SCStream?, SCDisplay?) in
                included = windows
                return (finished ? nil : self.stream, self.display)
            }
            guard let stream, let display else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try await stream.updateContentFilter(Self.filter(content, display: display, including: windows))
            } catch {
                NSLog("Couldn't update the recorded windows: \(error)")
            }
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func setPaused(_ on: Bool) {
        queue.async { [self] in
            guard on != paused else { return }
            paused = on
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            if on {
                pauseStart = now
            } else if pauseStart.isValid {
                pausedTotal = CMTimeAdd(pausedTotal, CMTimeSubtract(now, pauseStart))
                pauseStart = .invalid
            }
            clockLock.lock()
            if on { clock.pause(at: now.seconds) } else { clock.resume(at: now.seconds) }
            clockLock.unlock()
        }
    }

    /// Where a host-clock time (`CMClockGetTime(CMClockGetHostTimeClock())`) falls in the video: seconds from the
    /// first frame, time paused left out. Nil before the first frame and while paused, unless `holdWhilePaused`
    /// (then the moment the pause began). Safe from any thread.
    func videoTime(hostTime: CMTime, holdWhilePaused: Bool = false) -> Double? {
        clockLock.lock()
        defer { clockLock.unlock() }
        return clock.videoTime(host: hostTime.seconds, holdWhilePaused: holdWhilePaused)
    }

    func stop() {
        Task { [self] in
            let stream = queue.sync { self.stream }
            try? await stream?.stopCapture()
            queue.async { self.finish(nil) }
        }
    }

    // MARK: SCStreamOutput / SCStreamDelegate (on `queue`, or ScreenCaptureKit's own queue for errors)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, !paused, !finished else { return }
        switch type {
        case .screen: appendVideo(sampleBuffer)
        case .audio: appendAudio(sampleBuffer, to: audioInput)
        default:
            if #available(macOS 15.0, *), type == .microphone { appendAudio(sampleBuffer, to: micInput) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.finish(error) }
    }

    // MARK: Writing (on `queue`)

    private func appendVideo(_ sb: CMSampleBuffer) {
        // Only complete frames carry an image; idle frames (nothing changed) just extend the previous one.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let writer, let input = videoInput, let shifted = retimed(sb) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(shifted)
        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
            sessionStart = pts
            clockLock.lock()
            clock.firstFrame(at: CMSampleBufferGetPresentationTimeStamp(sb).seconds)
            clockLock.unlock()
        }
        if input.isReadyForMoreMediaData, input.append(shifted) {
            onFrame?(CMTimeSubtract(pts, sessionStart).seconds)
        }
    }

    private func appendAudio(_ sb: CMSampleBuffer, to input: AVAssetWriterInput?) {
        // Audio before the first frame would start the file with a black picture.
        guard sessionStarted, let input, input.isReadyForMoreMediaData, let sb = retimed(sb) else { return }
        input.append(sb)
    }

    /// `sb` shifted back by the time spent paused (or `sb` itself when there was no pause).
    private func retimed(_ sb: CMSampleBuffer) -> CMSampleBuffer? {
        guard pausedTotal != .zero else { return sb }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in timing.indices {
            timing[i].presentationTimeStamp = CMTimeSubtract(timing[i].presentationTimeStamp, pausedTotal)
            if timing[i].decodeTimeStamp.isValid {
                timing[i].decodeTimeStamp = CMTimeSubtract(timing[i].decodeTimeStamp, pausedTotal)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sb, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &out)
        return out
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        guard let writer, sessionStarted else {
            writer?.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            report(.failure(error ?? RecordingError.noFrames))
            return
        }
        [videoInput, audioInput, micInput].forEach { $0?.markAsFinished() }
        writer.finishWriting { [self] in
            queue.async { [self] in
                guard let writer = self.writer else { return }
                guard writer.status == .completed else { report(.failure(writer.error ?? RecordingError.writerFailed)); return }
                guard audioInput != nil, micInput != nil else { report(.success(url)); return }
                // Players that only play the first audio track would miss the mic, so both are mixed into one.
                Task { [self] in
                    do { try await AudioMixer.mixAudioTracks(of: self.url) } catch {
                        NSLog("Mixing the audio tracks failed, keeping them separate: \(error)")
                    }
                    self.report(.success(self.url))
                }
            }
        }
    }

    private func report(_ result: Result<URL, Error>) {
        DispatchQueue.main.async { [self] in onFinish?(result) }
    }
}
