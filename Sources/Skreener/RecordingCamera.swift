import AppKit
import AVFoundation

// The webcam overlay (#25). While recording, the camera shows in a bubble on screen that can be dragged anywhere.
// Recorded as usual, the bubble is in the video. With Record for editing, the bubble stays out of the video and the
// camera is recorded to its own file in the project (`camera.mp4`, on the screen video's timeline); the recording
// editor draws it at export (`CameraOverlay`), so where it goes, its size, its shape and when it shows can change.

/// Where the camera bubble was on the recorded area when recording stopped, saved in the project: its center and its
/// diameter as fractions of the area (bottom-left origin). The editor starts the overlay there.
struct CameraPlacement: Codable, Equatable {
    var x: Double
    var y: Double
    var size: Double
}

/// A stretch of the recording with the camera hidden.
struct CameraHide: Codable, Equatable {
    var start: Double
    var end: Double
}

/// How the recording editor draws the camera, saved in `studio.json`.
struct CameraOverlay: Codable, Equatable {
    enum Shape: String, Codable, CaseIterable {
        case circle, rounded

        var name: String { self == .circle ? "Circle" : "Rounded Rectangle" }
    }

    /// The camera is drawn at all.
    var shown = true
    var shape = Shape.circle
    /// The bubble's center as fractions of the canvas, bottom-left origin.
    var x = 0.85
    var y = 0.2
    /// The bubble's height as a fraction of the canvas's shorter side.
    var size = 0.25
    /// Flipped left to right, as the camera bubble showed it while recording.
    var mirrored = true
    /// Where the camera is hidden, in time order and apart.
    var hidden: [CameraHide] = []

    static let sizes: [(name: String, value: Double)] = [("Small", 0.18), ("Medium", 0.25), ("Large", 0.34), ("Huge", 0.45)]
    static let minSize = 0.08
    static let maxSize = 0.6
    /// How long the camera takes to fade out or in around a hidden stretch.
    static let fade = 0.25

    init() {}

    /// Starts where the bubble was while recording.
    init(placement: CameraPlacement?) {
        guard let p = placement else { return }
        x = p.x
        y = p.y
        size = min(max(p.size, Self.minSize), Self.maxSize)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shown = try c.decodeIfPresent(Bool.self, forKey: .shown) ?? true
        shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? .circle
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.85
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.2
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.25
        mirrored = try c.decodeIfPresent(Bool.self, forKey: .mirrored) ?? true
        hidden = try c.decodeIfPresent([CameraHide].self, forKey: .hidden) ?? []
        self = tidy
    }

    /// Values in range and the hidden stretches sorted, merged where they touch, without empty ones.
    var tidy: CameraOverlay {
        var o = self
        o.x = o.x.isFinite ? min(max(o.x, 0), 1) : 0.85
        o.y = o.y.isFinite ? min(max(o.y, 0), 1) : 0.2
        o.size = o.size.isFinite ? min(max(o.size, Self.minSize), Self.maxSize) : 0.25
        o.hidden = Self.merged(o.hidden)
        return o
    }

    private static func merged(_ ranges: [CameraHide]) -> [CameraHide] {
        var out: [CameraHide] = []
        for r in ranges.filter({ $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = out.last, r.start <= last.end {
                out[out.count - 1].end = max(last.end, r.end)
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// With the camera hidden from `start` to `end` too.
    func hiding(from start: Double, to end: Double) -> CameraOverlay {
        var o = self
        o.hidden = Self.merged(hidden + [CameraHide(start: min(start, end), end: max(start, end))])
        return o
    }

    /// With the camera showing from `start` to `end` again.
    func showing(from start: Double, to end: Double) -> CameraOverlay {
        let a = min(start, end), b = max(start, end)
        var out: [CameraHide] = []
        for r in hidden {
            if r.end <= a || r.start >= b { out.append(r); continue }
            if r.start < a { out.append(CameraHide(start: r.start, end: a)) }
            if r.end > b { out.append(CameraHide(start: b, end: r.end)) }
        }
        var o = self
        o.hidden = Self.merged(out)
        return o
    }

    /// Whether any of `start`…`end` is hidden.
    func hides(from start: Double, to end: Double) -> Bool {
        hidden.contains { $0.end > min(start, end) && $0.start < max(start, end) }
    }

    /// 0 (hidden) to 1 (showing) at `t`: fades out over `fade` before a hidden stretch and in over `fade` after it.
    func opacity(at t: Double) -> Double {
        guard shown else { return 0 }
        var o = 1.0
        for r in hidden {
            if t >= r.start, t < r.end { return 0 }
            if t < r.start { o = min(o, (r.start - t) / Self.fade) }
            if t >= r.end { o = min(o, (t - r.end) / Self.fade) }
        }
        return min(max(o, 0), 1)
    }

    /// The bubble on `canvas` for a camera picture of `aspect` (width / height): kept inside the canvas.
    func rect(canvas: CGSize, aspect: CGFloat) -> CGRect {
        let short = min(canvas.width, canvas.height)
        let h = min(CGFloat(size) * short, canvas.height)
        let w = shape == .circle ? h : min(h * max(aspect, 0.1), canvas.width)
        let cx = min(max(CGFloat(x) * canvas.width, w / 2), canvas.width - w / 2)
        let cy = min(max(CGFloat(y) * canvas.height, h / 2), canvas.height - h / 2)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Moved so its center is at `center` on `canvas`.
    func moved(to center: CGPoint, canvas: CGSize) -> CameraOverlay {
        var o = self
        o.x = Double(center.x / max(canvas.width, 1))
        o.y = Double(center.y / max(canvas.height, 1))
        return o.tidy
    }

    /// The bubble's outline.
    func path(in r: CGRect) -> CGPath {
        switch shape {
        case .circle: return CGPath(ellipseIn: r, transform: nil)
        case .rounded:
            let radius = min(r.width, r.height) * 0.12
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    /// Draws `image` in the bubble on `canvas` (in `ctx`'s units), filling it, with a thin light ring and a soft shadow.
    func draw(_ image: CGImage, in ctx: CGContext, canvas: CGSize, opacity: Double) {
        guard opacity > 0 else { return }
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let r = rect(canvas: canvas, aspect: aspect)
        let outline = path(in: r)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setAlpha(CGFloat(opacity))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // The shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -r.height * 0.02), blur: r.height * 0.08,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.addPath(outline)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        // The picture, filling the bubble.
        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip()
        let k = max(r.width / CGFloat(image.width), r.height / CGFloat(image.height))
        let w = CGFloat(image.width) * k, h = CGFloat(image.height) * k
        let box = CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        if mirrored {
            // Flipped about the bubble's middle; the picture is centered on it, so it stays in place.
            ctx.translateBy(x: r.midX, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -r.midX, y: 0)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: box)
        ctx.restoreGState()
        // The ring.
        ctx.addPath(outline)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setLineWidth(max(1, r.height * 0.015))
        ctx.strokePath()
        ctx.endTransparencyLayer()
    }
}

/// The recorded camera's pictures by time, for drawing frames: read in order with an `AVAssetReader` (started again when
/// asked for an earlier time, or one far ahead). Safe from any thread; make a `fresh()` one for each user that reads
/// at its own pace (the preview and an export).
final class CameraFeed: @unchecked Sendable {
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    /// Width / height of the camera's pictures.
    let aspect: CGFloat
    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var next: CMSampleBuffer?
    private var current: (t: Double, buffer: CVPixelBuffer)?
    private var currentImage: CGImage?
    /// The time the reader was started from.
    private var readFrom = 0.0

    private init(asset: AVURLAsset, track: AVAssetTrack, aspect: CGFloat) {
        self.asset = asset
        self.track = track
        self.aspect = aspect
    }

    /// The camera recorded in a project `folder`, or nil when there is none.
    static func open(folder: URL) async -> CameraFeed? {
        let url = folder.appendingPathComponent(RecordingProject.cameraFile)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 else { return nil }
        return CameraFeed(asset: asset, track: track, aspect: size.width / size.height)
    }

    /// Another reader of the same camera file.
    func fresh() -> CameraFeed { CameraFeed(asset: asset, track: track, aspect: aspect) }

    /// The camera's picture showing at `t` (the latest one at or before it); nil before the first one.
    func image(at t: Double) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let shownAt = current?.t ?? readFrom
        if reader == nil || t < shownAt - 0.0005 || t > shownAt + 3 { restart(at: t) }
        while let n = next {
            let pts = CMSampleBufferGetPresentationTimeStamp(n).seconds
            guard pts <= t + 0.0005 else { break }
            if let buffer = CMSampleBufferGetImageBuffer(n) { current = (pts, buffer); currentImage = nil }
            next = output?.copyNextSampleBuffer()
        }
        guard let current else { return nil }
        if currentImage == nil { currentImage = StudioCompositor.image(of: current.buffer) }
        return currentImage
    }

    private func restart(at t: Double) {
        reader?.cancelReading()
        reader = nil; output = nil; next = nil; current = nil; currentImage = nil
        // A little before `t`, so the picture showing at `t` is read too.
        readFrom = max(0, t - 0.5)
        guard let r = try? AVAssetReader(asset: asset) else { return }
        r.timeRange = CMTimeRange(start: CMTime(seconds: readFrom, preferredTimescale: 600), duration: .positiveInfinity)
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        o.alwaysCopiesSampleData = false
        guard r.canAdd(o) else { return }
        r.add(o)
        guard r.startReading() else { return }
        reader = r
        output = o
        next = o.copyNextSampleBuffer()
    }

    deinit { reader?.cancelReading() }
}

/// The camera while recording: shows it in the bubble, and with `record` writes it to an MP4 on the screen video's
/// timeline (`time` maps a host-clock time to it; nil drops the picture, before the first screen frame and while paused).
final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.skreener.camera")
    private let output = AVCaptureVideoDataOutput()
    private var url: URL?
    private var time: (@Sendable (CMTime) -> Double?)?
    // On `queue`:
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInputPixelBufferAdaptor?
    private var last = -1.0
    private var finished = false

    /// Whether the camera may be used, asking the first time.
    static func allowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Sets up the session with the Mac's default camera; false when there is none.
    func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    /// Starts the camera; with `url`, writes it there, timed with `time`.
    func start(recordingTo url: URL?, time: (@Sendable (CMTime) -> Double?)?) {
        queue.sync {
            self.url = url
            self.time = time
        }
        if url != nil { output.setSampleBufferDelegate(self, queue: queue) }
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    /// Stops the camera and finishes the file; true when a file with pictures was written.
    func stop() async -> Bool {
        let session = session
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
                done.resume()
            }
        }
        let (writer, input, last) = queue.sync { () -> (AVAssetWriter?, AVAssetWriterInputPixelBufferAdaptor?, Double) in
            finished = true
            return (self.writer, self.input, self.last)
        }
        guard let writer, let input, writer.status == .writing else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return false
        }
        input.assetWriterInput.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: last + 1.0 / 30, preferredTimescale: 600))
        await writer.finishWriting()
        return writer.status == .completed
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !finished, let url, let time, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let clock = session.synchronizationClock {
            pts = CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock())
        }
        guard let t = time(pts), t > last else { return }
        if writer == nil {
            guard let made = Self.makeWriter(url: url, width: CVPixelBufferGetWidth(pixels),
                                             height: CVPixelBufferGetHeight(pixels)) else { finished = true; return }
            writer = made.writer
            input = made.adaptor
        }
        guard let input, input.assetWriterInput.isReadyForMoreMediaData else { return }
        if input.append(pixels, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)) { last = t }
    }

    private static func makeWriter(url: URL, width: Int, height: Int) -> (writer: AVAssetWriter, adaptor: AVAssetWriterInputPixelBufferAdaptor)? {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(1_500_000, width * height * 3)] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        return (writer, adaptor)
    }
}

/// The camera bubble on screen while recording: round, mirrored, on top of everything, dragged anywhere.
final class CameraBubble {
    static let diameter: CGFloat = 200
    let panel: NSPanel

    /// In the bottom-right corner of `area` (global, bottom-left origin coordinates).
    init(session: AVCaptureSession, area: CGRect) {
        let d = min(Self.diameter, area.width / 2, area.height / 2)
        let frame = CGRect(x: area.maxX - d - 24, y: area.minY + 24, width: d, height: d)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        if let c = preview.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        view.layer?.addSublayer(preview)
        view.layer?.cornerRadius = d / 2
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        view.toolTip = "Camera: drag to move it"
        panel.contentView = view
    }

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }

    /// Where it is on `area`, for the editor to start from.
    func placement(on area: CGRect) -> CameraPlacement {
        let f = panel.frame
        return CameraPlacement(x: Double((f.midX - area.minX) / max(area.width, 1)),
                               y: Double((f.midY - area.minY) / max(area.height, 1)),
                               size: Double(f.height / max(min(area.width, area.height), 1)))
    }
}
