import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import SkreenerCore
import UniformTypeIdentifiers
import UserNotifications

/// Live scrolling capture of whatever is on screen (#456): stitches the broadcast's frames as the user scrolls by
/// hand, with the same `ScrollStitcher` as the Mac's scrolling capture, and writes the long screenshot to the App Group
/// container for the app to open.
///
/// A broadcast extension may use only about 50 MB, and one full iPhone frame is about 12 MB, so the stitched image
/// never stays in memory: after each movement the finished strips go to disk as PNGs
/// (`LiveCaptures/<id>/strip-0001.png`, ...), keeping only the newest half frame of rows, which a growing footer may
/// take back. At the end the rest and the footer are written too, then `manifest.json`, which marks the capture
/// complete; the app joins the strips top to bottom.
///
/// Frames arrive about 60 times a second; about 10 a second are used, one at a time, on one serial queue: a frame that
/// arrives while the last one is still being stitched is dropped.
final class LiveCapture: @unchecked Sendable {
    /// Called once, on the stitching queue, after the capture reached `ScrollStitcher.maxHeight` and was saved.
    var onFull: (() -> Void)?

    /// Seconds between the frames used.
    private static let interval = 0.1
    /// Still frames needed after a reseed before a movement starts the capture: the screen settled in the app the user
    /// scrolls, rather than an animation (Control Centre going away, an app opening).
    private static let stableBeforeStart = 2

    // Guarded by `lock` (`offer` runs on ReplayKit's queue, the rest on `queue`).
    private let lock = NSLock()
    private var busy = false
    private var lastTime = CMTime.invalid

    // Used on `queue` only.
    private let queue = DispatchQueue(label: "com.skreener.ios.broadcast.stitch", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let id = UUID().uuidString
    private var stitcher: ScrollStitcher?
    /// Something has scrolled since the last reseed: the capture is under way and its strips are on disk.
    private var stitched = false
    private var stableFrames = 0
    /// The pixels per point, guessed from the frame's width (see `seed`).
    private var scale = 3
    private var strips: [String] = []
    private var stripRows = 0
    /// A strip could not be written: the capture is abandoned.
    private var failed = false
    private var finished = false

    /// Removes captures a previous broadcast left without a manifest (the extension was stopped before it finished):
    /// only one broadcast runs at a time, so they are not being written.
    func start() {
        queue.async {
            guard let root = Self.root,
                  let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            else { return }
            for folder in folders where !FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    /// Takes a video frame, if it is time for one and the last one is done.
    func offer(_ sample: CMSampleBuffer) {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        lock.lock()
        let due = !busy && (!lastTime.isValid || !time.isValid || (time - lastTime).seconds >= Self.interval)
        if due {
            busy = true
            lastTime = time
        }
        lock.unlock()
        guard due else { return }
        let frame = Frame(pixels: pixels)
        queue.async {
            autoreleasepool { self.process(frame.pixels) }
            self.lock.lock()
            self.busy = false
            self.lock.unlock()
        }
    }

    /// Saves what was captured and posts the notification, once all frames handed over are done.
    func finish() {
        queue.sync { self.save(reachedMaximum: false) }
    }

    // MARK: Stitching

    /// The pixel buffer of a frame on its way to the stitching queue.
    private struct Frame: @unchecked Sendable {
        let pixels: CVPixelBuffer
    }

    private func process(_ pixels: CVPixelBuffer) {
        guard !finished, !failed else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let frame = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else { return }
        // A frame of another size (the phone turned) starts again until something has scrolled, and is ignored after.
        guard let stitcher, frame.width == stitcher.width, frame.height == stitcher.frameHeight else {
            if !stitched { seed(frame) }
            return
        }
        switch stitcher.add(frame) {
        case .unchanged:
            stableFrames += 1
        case .lost:
            // Before anything scrolled, the screen changed (Skreener, Control Centre, the countdown, then the app):
            // start again from what is on screen now. After, the user scrolled too fast or the content changed: the
            // next frames may match again.
            if !stitched { seed(frame) }
        case .moved(let shift):
            if !stitched {
                guard shift > 0, stableFrames >= Self.stableBeforeStart else { return seed(frame) }
                stitched = true
            }
            write(stitcher.takeFinishedPieces(keepingLast: stitcher.frameHeight / 2))
        case .full:
            stitched = true
            save(reachedMaximum: true)
            onFull?()
        }
    }

    /// Starts the capture again from `frame`. The scroll bar at the right edge (about 12 points) is left out of the
    /// matching. The scale is the frame width over about 400 points, which gives 3 or 2 for every iPhone (1179 / 393,
    /// 750 / 375, 828 / 414, 1080 / 360...).
    private func seed(_ frame: CGImage) {
        scale = max(1, Int((Double(frame.width) / 400).rounded()))
        stitcher = ScrollStitcher(first: frame, ignoreRight: 12 * scale)
        stableFrames = 0
    }

    // MARK: Saving

    /// The folder all captures go in: `LiveCaptures` in the App Group container, shared with the app.
    private static var root: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.skreener.ios")?
            .appendingPathComponent("LiveCaptures", isDirectory: true)
    }

    private var folder: URL? { Self.root?.appendingPathComponent(id, isDirectory: true) }

    /// Writes `pieces` as the next strips, top to bottom.
    private func write(_ pieces: [CGImage]) {
        guard !pieces.isEmpty, !failed, let folder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            failed = true
            return
        }
        for piece in pieces {
            let name = String(format: "strip-%04d.png", strips.count + 1)
            guard let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil)
            else {
                failed = true
                return
            }
            CGImageDestinationAddImage(destination, piece, nil)
            guard CGImageDestinationFinalize(destination) else {
                failed = true
                return
            }
            strips.append(name)
            stripRows += piece.height
        }
    }

    /// Writes the rest of the capture and its manifest, then tells the user. Nothing scrolled: nothing is kept.
    private func save(reachedMaximum: Bool) {
        guard !finished else { return }
        finished = true
        let width = stitcher?.width ?? 0
        let remaining = stitched ? stitcher?.takeRemaining() ?? [] : []
        stitcher = nil
        if stitched, !failed { write(remaining) }
        guard stitched, !failed, let folder, width > 0, !strips.isEmpty else {
            if let folder { try? FileManager.default.removeItem(at: folder) }
            if failed {
                notify(title: "Couldn't save the long screenshot", body: "There may not be enough space on the iPhone.")
            } else {
                notify(title: "Nothing scrolled", body: "Scroll slowly in the app you want to capture.")
            }
            return
        }
        let manifest = Manifest(id: id, strips: strips, width: width, height: stripRows, scale: scale, date: Date(),
                                complete: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            notify(title: "Couldn't save the long screenshot", body: "There may not be enough space on the iPhone.")
            return
        }
        notify(title: reachedMaximum ? "Long screenshot ready (maximum length)" : "Long screenshot ready",
               body: "Tap to edit it in Skreener.", captureID: id)
    }

    /// Posts a notification now, waiting a little for it to be accepted: iOS may end the extension soon after the
    /// broadcast finishes.
    private func notify(title: String, body: String, captureID: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let captureID { content.userInfo = ["captureID": captureID] }
        let request = UNNotificationRequest(identifier: "live-capture-\(id)", content: content, trigger: nil)
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 3)
    }
}

/// `manifest.json`: the strips of a finished capture, top to bottom, and its size in pixels. The app reads it in
/// `LiveScrollCapture.swift` (the same keys).
private struct Manifest: Codable {
    let id: String
    let strips: [String]
    let width: Int
    let height: Int
    let scale: Int
    let date: Date
    let complete: Bool
}
