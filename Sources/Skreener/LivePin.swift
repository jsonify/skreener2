import AppKit
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// The frames behind a Live Pin (#241): an SCStream of a screen area (Skreener's own windows left out, so the pin
/// never mirrors itself) or of one window (which keeps coming when the window is covered), at a low frame rate.
/// Sample buffers arrive on `queue`; `onFrame` and `onStop` are called on the main queue.
final class LivePinFeed: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// A new frame, `pointSize` points big.
    var onFrame: ((NSImage) -> Void)?
    /// The stream stopped by itself, e.g. the window closed or the display went away.
    var onStop: ((Error) -> Void)?

    /// The size the frames are shown at, at 100%.
    let pointSize: CGSize
    private let filter: SCContentFilter
    private let config: SCStreamConfiguration
    private let queue = DispatchQueue(label: "com.skreener.livepin")
    private var stream: SCStream?
    private var stopped = false

    /// The area `rect` (global, bottom-left origin coordinates) of `screen`.
    init(screen: NSScreen, rect: CGRect) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        let me = getpid()
        filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == me },
                                 exceptingWindows: [])
        pointSize = rect.size
        config = Self.config(points: rect.size, scale: screen.backingScaleFactor)
        config.sourceRect = LivePinGeometry.sourceRect(rect, in: screen.frame)
        super.init()
    }

    /// One window, wherever it is and whatever covers it.
    init(window: SCWindow, scale: CGFloat) {
        filter = SCContentFilter(desktopIndependentWindow: window)
        pointSize = window.frame.size
        config = Self.config(points: window.frame.size, scale: scale)
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true   // a window resized later still fits the frame
        config.backgroundColor = .clear
        config.shouldBeOpaque = false
        super.init()
    }

    private static func config(points: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let px = LivePinGeometry.pixelSize(points: points, scale: scale)
        let cfg = SCStreamConfiguration()
        cfg.width = px.width
        cfg.height = px.height
        cfg.minimumFrameInterval = LivePinGeometry.frameInterval(fps: Preferences.livePinFrameRate)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 3   // frames are copied out at once (`ownCopy`), so a short queue is enough
        cfg.showsCursor = false
        return cfg
    }

    /// A still of what the stream will show, for the pin to open with.
    func snapshot() async throws -> NSImage {
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cg, size: pointSize)
    }

    /// Starts the stream; failures come through `onStop`.
    func start() {
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            report(error)
            return
        }
        queue.sync { self.stream = stream }
        Task { [self] in
            do { try await stream.startCapture() } catch {
                report(error)
                return
            }
            // Stopped while starting up: nothing else will stop the stream now.
            if queue.sync(execute: { stopped }) { try? await stream.stopCapture() }
        }
    }

    /// Frames per second from now on (5, 10 or 15).
    func setFrameRate(_ fps: Int) {
        config.minimumFrameInterval = LivePinGeometry.frameInterval(fps: fps)
        Task { [self] in
            guard let stream = queue.sync(execute: { stopped ? nil : self.stream }) else { return }
            try? await stream.updateConfiguration(config)
        }
    }

    /// Ends the stream for good (Freeze, or the pin closed). No more frames or stops are reported.
    func stop() {
        onFrame = nil
        onStop = nil
        Task { [self] in
            let stream = queue.sync { () -> SCStream? in
                stopped = true
                return self.stream
            }
            try? await stream?.stopCapture()
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async { [self] in onStop?(error) }
    }

    // MARK: SCStreamOutput / SCStreamDelegate (on `queue`, or ScreenCaptureKit's own queue for errors)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only complete frames carry an image; idle frames (nothing changed) keep the one the pin shows.
        guard type == .screen, !stopped, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        guard let cg = Self.ownCopy(of: buffer) else { return }
        let frame = LiveFrame(image: cg)
        DispatchQueue.main.async { [self] in
            onFrame?(NSImage(cgImage: frame.image, size: pointSize))
        }
    }

    /// The frame in memory of its own, so the stream gets its buffer back right away (it only has `queueDepth` of
    /// them) even while the pin, an editor or the clipboard holds on to the image.
    private static func ownCopy(of buffer: CVPixelBuffer) -> CGImage? {
        var wrapped: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &wrapped)
        guard let wrapped,
              let ctx = CGContext(data: nil, width: wrapped.width, height: wrapped.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: wrapped.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(wrapped, in: CGRect(x: 0, y: 0, width: wrapped.width, height: wrapped.height))
        return ctx.makeImage()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !queue.sync(execute: { stopped }) else { return }
        report(error)
    }
}

/// A frame handed from the stream's queue to the main queue; nothing touches it on the way.
private struct LiveFrame: @unchecked Sendable {
    let image: CGImage
}

/// The numbers behind a Live Pin's stream (#241).
enum LivePinGeometry {
    /// The frame rates on offer; the first is the default.
    static let frameRates = [5, 10, 15]
    /// Bigger areas are streamed at fewer pixels, to keep the CPU low (about 2560 × 1440).
    static let maxPixels = 2560 * 1440

    /// `fps` if it is on offer, else the default.
    static func frameRate(_ fps: Int) -> Int { frameRates.contains(fps) ? fps : frameRates[0] }

    /// The shortest time between frames for `fps`.
    static func frameInterval(fps: Int) -> CMTime { CMTime(value: 1, timescale: CMTimeScale(frameRate(fps))) }

    /// The stream's pixel size for `points` on a `scale` display: full resolution, scaled down to `maxPixels`.
    static func pixelSize(points: CGSize, scale: CGFloat, maxPixels: Int = maxPixels) -> (width: Int, height: Int) {
        var s = max(scale, 1)
        let px = points.width * s * points.height * s
        if px > CGFloat(maxPixels) { s *= sqrt(CGFloat(maxPixels) / px) }
        return (max(1, Int((points.width * s).rounded())), max(1, Int((points.height * s).rounded())))
    }

    /// A global (bottom-left origin) rect as the stream's `sourceRect`: display-local points, top-left origin.
    static func sourceRect(_ r: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(x: r.minX - screenFrame.minX, y: screenFrame.maxY - r.maxY, width: r.width, height: r.height)
    }
}
