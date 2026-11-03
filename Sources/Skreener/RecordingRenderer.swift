import AppKit
import AVFoundation
import CoreText
import ImageIO

/// Makes a finished MP4 from a recording's clean video (#380): every frame is drawn over with `draw` (the effects
/// at that moment, see `EffectsOverlay`), at a constant frame rate, since the effects move while the screen may not.
/// Audio is copied as is. The recording editor (#24) builds on this with its background, padding and zoom.
enum RecordingRenderer {
    enum RenderError: Error { case noVideo, cannotRead, cannotWrite }

    /// Draws `project`'s effects from `events` over its clean video into a new MP4 at `out`.
    static func render(project: RecordingProject, events: RecordingEvents, folder: URL, to out: URL) async throws {
        let overlay = EffectsOverlay(project: project, events: events, folder: folder)
        try await render(video: folder.appendingPathComponent(RecordingProject.videoFile), fps: project.fps, to: out) { ctx, t in
            overlay.draw(in: ctx, at: t)
        }
    }

    /// Re-encodes `video` as H.264 at `fps` into `out` (replacing it), calling `draw` for each frame with a context
    /// on the frame (bottom-left origin, in pixels) and the frame's time from the first frame. Each output frame
    /// shows the latest source frame at or before its time. On failure `out` is left alone.
    static func render(video: URL, fps: Int, to out: URL,
                       draw: @escaping @Sendable (CGContext, Double) -> Void) async throws {
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RenderError.noVideo }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let size = try await track.load(.naturalSize)
        let range = try await track.load(.timeRange)
        // To the end of the recording: a video whose screen stopped changing holds its last frame to there (#380).
        let end = CMTimeMaximum(range.end, try await asset.load(.duration))
        let width = Int(size.width), height = Int(size.height)
        let rate = max(1, fps)

        // A temporary folder on the same volume, so the finished file can be moved into place.
        let fm = FileManager.default
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: out, create: true)
        defer { try? fm.removeItem(at: dir) }
        let tmp = dir.appendingPathComponent(out.lastPathComponent)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        guard reader.canAdd(frames) else { throw RenderError.cannotRead }
        reader.add(frames)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // As `ScreenRecorder` encodes.
                AVVideoAverageBitRateKey: max(2_000_000, Int(Double(width * height * rate) * 0.12)),
                AVVideoExpectedSourceFrameRateKey: rate,
                AVVideoMaxKeyFrameIntervalKey: rate * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw RenderError.cannotWrite }
        writer.add(input)
        var pumps: [AudioMixer.Pump] = []
        for track in audioTracks {
            // No output settings on either side: the compressed audio is passed through.
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let format = try await track.load(.formatDescriptions).first
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            guard reader.canAdd(output) else { throw RenderError.cannotRead }
            guard writer.canAdd(audio) else { throw RenderError.cannotWrite }
            reader.add(output)
            writer.add(audio)
            pumps.append(AudioMixer.Pump(output: output, input: audio))
        }

        guard reader.startReading() else { throw reader.error ?? RenderError.cannotRead }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? RenderError.cannotWrite
        }
        guard let first = frames.copyNextSampleBuffer() else {
            reader.cancelReading()
            writer.cancelWriting()
            throw reader.error ?? RenderError.noVideo
        }
        let start = CMSampleBufferGetPresentationTimeStamp(first)
        writer.startSession(atSourceTime: start)
        let painter = FramePainter(output: frames, adaptor: adaptor, first: first, start: start, end: end,
                                   fps: Int32(rate), draw: draw)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            group.enter()
            painter.run { group.leave() }
            for pump in pumps {
                group.enter()
                pump.run { group.leave() }
            }
            group.notify(queue: .global()) { done.resume() }
        }
        guard !painter.failed, reader.status == .completed else {
            reader.cancelReading()
            writer.cancelWriting()
            throw reader.error ?? writer.error ?? RenderError.cannotWrite
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RenderError.cannotWrite }
        if fm.fileExists(atPath: out.path) { _ = try fm.replaceItemAt(out, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: out) }
    }

    /// Writes the output frames on its own queue: copies the source frame showing at each output time, draws on it
    /// and appends it.
    private final class FramePainter: @unchecked Sendable {
        private let output: AVAssetReaderOutput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let start: CMTime
        private let end: CMTime
        private let fps: Int32
        private let draw: @Sendable (CGContext, Double) -> Void
        private let queue = DispatchQueue(label: "com.skreener.renderer")
        private var next: CMSampleBuffer?
        private var current: CVPixelBuffer?
        private var frame: Int64 = 0
        private var done = false
        private(set) var failed = false

        init(output: AVAssetReaderOutput, adaptor: AVAssetWriterInputPixelBufferAdaptor, first: CMSampleBuffer,
             start: CMTime, end: CMTime, fps: Int32, draw: @escaping @Sendable (CGContext, Double) -> Void) {
            self.output = output
            self.adaptor = adaptor
            self.start = start
            self.end = end
            self.fps = fps
            self.draw = draw
            next = first
        }

        /// Calls `finished` once, when every frame is written or writing failed.
        func run(_ finished: @escaping @Sendable () -> Void) {
            adaptor.assetWriterInput.requestMediaDataWhenReady(on: queue) { [self] in
                while adaptor.assetWriterInput.isReadyForMoreMediaData, !done {
                    let time = CMTimeAdd(start, CMTime(value: frame, timescale: fps))
                    // Always at least one frame, even for a video shorter than a frame.
                    guard frame == 0 || CMTimeCompare(time, end) < 0 else { complete(finished); return }
                    while let n = next, CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(n), time) <= 0 {
                        if let image = CMSampleBufferGetImageBuffer(n) { current = image }
                        next = output.copyNextSampleBuffer()
                    }
                    guard let source = current else { frame += 1; continue }
                    guard let pool = adaptor.pixelBufferPool, let out = Self.copy(source, from: pool) else {
                        failed = true
                        complete(finished)
                        return
                    }
                    paint(out, at: CMTimeSubtract(time, start).seconds)
                    guard adaptor.append(out, withPresentationTime: time) else {
                        failed = true
                        complete(finished)
                        return
                    }
                    frame += 1
                }
            }
        }

        private func complete(_ finished: @Sendable () -> Void) {
            guard !done else { return }
            done = true
            adaptor.assetWriterInput.markAsFinished()
            // Reads what is left (less than a frame's time), so the reader completes.
            next = nil
            while !failed, output.copyNextSampleBuffer() != nil {}
            finished()
        }

        private func paint(_ buffer: CVPixelBuffer, at t: Double) {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer),
                                      height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            draw(ctx, t)
        }

        /// A copy of `source` (32BGRA) in a buffer from `pool`.
        private static func copy(_ source: CVPixelBuffer, from pool: CVPixelBufferPool) -> CVPixelBuffer? {
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let out = made else { return nil }
            CVPixelBufferLockBaseAddress(source, .readOnly)
            CVPixelBufferLockBaseAddress(out, [])
            defer {
                CVPixelBufferUnlockBaseAddress(out, [])
                CVPixelBufferUnlockBaseAddress(source, .readOnly)
            }
            guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(out) else { return nil }
            let rows = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(out))
            let fromStride = CVPixelBufferGetBytesPerRow(source), toStride = CVPixelBufferGetBytesPerRow(out)
            let bytes = min(fromStride, toStride)
            for y in 0..<rows { memcpy(to + y * toStride, from + y * fromStride, bytes) }
            return out
        }
    }
}

/// Draws a recording's effects as they look at a moment of the video: the spotlight, the keystroke pill, click rings
/// and the cursor, in that order (back to front), matching the live overlay (`RecordingEffects`, `EffectsLook`).
/// Thread-safe: everything is fixed at init.
final class EffectsOverlay: @unchecked Sendable {
    let events: RecordingEvents
    let style: EffectsStyle
    let videoSize: CGSize
    /// Video pixels per screen point: the overlay's sizes are in points.
    let scale: CGFloat
    private let pills: [KeystrokePill]
    private let cursors: [CGImage?]
    private let font: NSFont

    /// `folder` holds the cursor images (none drawn without it).
    init(project: RecordingProject, events: RecordingEvents, folder: URL?) {
        self.events = events
        style = project.style
        videoSize = project.videoSize
        scale = project.pixelScale
        pills = events.keystrokePills()
        cursors = events.cursorImages.map { image in
            guard let folder else { return nil }
            let url = folder.appendingPathComponent(RecordingProject.cursorsFolder).appendingPathComponent(image.file)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        font = .systemFont(ofSize: CGFloat(project.style.keystrokeSize) * project.pixelScale, weight: .semibold)
    }

    /// Whether any effect would be drawn at all; if not, the clean video is the finished one.
    var drawsAnything: Bool {
        let cursor = style.cursor && !events.cursor.isEmpty && !events.cursorImages.isEmpty
        let clicks = style.clicks && events.clicks.contains { $0.down }
        let keys = style.keystrokes && !events.keys.isEmpty
        let spotlight = !events.cursor.isEmpty && (events.spotlightAtStart || events.spotlight.contains { $0.on })
        return cursor || clicks || keys || spotlight
    }

    /// Draws the effects at video time `t` into `ctx`, which covers the video with a bottom-left origin, in pixels.
    func draw(in ctx: CGContext, at t: Double) {
        let bounds = CGRect(origin: .zero, size: videoSize)
        let cursor = events.cursorState(at: t)
        if let cursor, events.isSpotlightOn(at: t) { drawSpotlight(in: ctx, at: flip(cursor.point), bounds: bounds) }
        if style.keystrokes, let text = events.keystroke(at: t, pills: pills) { drawPill(text, in: ctx, bounds: bounds) }
        if style.clicks { events.rings(at: t, videoSize: videoSize).forEach { drawRing($0, in: ctx) } }
        if style.cursor, let cursor, cursor.visible, let i = cursor.image, cursors.indices.contains(i), let image = cursors[i] {
            let info = events.cursorImages[i]
            let p = flip(cursor.point)
            let w = CGFloat(info.width) * scale, h = CGFloat(info.height) * scale
            let rect = CGRect(x: p.x - CGFloat(info.hotspotX) * scale, y: p.y + CGFloat(info.hotspotY) * scale - h, width: w, height: h)
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        }
    }

    /// A video point (top-left origin) in the context's bottom-left origin.
    private func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: videoSize.height - p.y) }

    private func drawSpotlight(in ctx: CGContext, at center: CGPoint, bounds: CGRect) {
        let radius = CGFloat(style.spotlightRadius) * scale
        let dim = CGFloat(min(max(style.spotlightDim, 0), 1))
        let square = Spotlight.square(center: center, radius: radius)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: dim))
        Spotlight.surround(of: square, in: bounds).forEach { ctx.fill($0) }
        let inside = square.intersection(bounds)
        guard !inside.isNull, !inside.isEmpty else { return }
        let stops = Spotlight.stops(dim: dim)
        let colors = stops.map { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: $0.alpha) } as CFArray
        var locations = stops.map { $0.location }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                        locations: &locations) else { return }
        ctx.clip(to: inside)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                               options: [.drawsAfterEndLocation])
    }

    private func drawPill(_ text: String, in ctx: CGContext, bounds: CGRect) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // A label adds 2 pt on each side of its text.
        let inset = 2 * scale
        let textSize = CGSize(width: ceil(width + inset * 2), height: ceil(ascent + descent + leading))
        let pad = EffectsLook.pillPadding(fontSize: CGFloat(style.keystrokeSize) * scale)
        let frame = EffectsLook.pillFrame(textSize: textSize, padding: pad, edgeInset: EffectsLook.pillEdgeInset * scale,
                                          in: bounds, atTop: style.keystrokesAtTop)
        let radius = min(EffectsLook.pillCornerRadius * scale, frame.height / 2, frame.width / 2)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: EffectsLook.pillAlpha))
        ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: frame.minX + pad + inset, y: frame.minY + pad / 2 + descent + leading)
        CTLineDraw(line, ctx)
    }

    private func drawRing(_ ring: RingState, in ctx: CGContext) {
        let color = style.clickColor.cgColor
        let d = CGFloat(style.clickSize) * scale * CGFloat(ring.scale)
        let c = flip(ring.center)
        let rect = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Faded as a whole, like the live ring layer.
        ctx.setAlpha(CGFloat(ring.opacity))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(color.copy(alpha: EffectsLook.ringFillAlpha) ?? color)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(EffectsLook.ringLineWidth * scale * CGFloat(ring.scale))
        ctx.strokeEllipse(in: rect)
        ctx.endTransparencyLayer()
    }
}
