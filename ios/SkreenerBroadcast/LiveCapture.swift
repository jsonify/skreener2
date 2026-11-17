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
    /// Until something has scrolled, a movement starts the capture only once the screen has settled in the app the
    /// user scrolls, rather than during an animation (the sheet or Control Centre going away, an app opening), so
    /// none of those end up at the top of the picture. ReplayKit sends a frame only when the screen changes, so a still
    /// screen can't be told from still frames, which may never come (#456). It counts as settled when this many seconds
    /// of frame time have passed since the stitcher last started again...
    private static let settle = 0.4
    /// ...or when no frame came for this long before the movement: nothing changed on screen in between...
    private static let pause = 0.3
    /// ...or when the content has kept moving forward for this long: a slow drag begun straight after the switch to
    /// the app. The system's animations are over sooner.
    private static let sustained = 0.6

    // Guarded by `lock` (`offer` runs on ReplayKit's queue, the rest on `queue`).
    private let lock = NSLock()
    private var busy = false
    private var lastTime = CMTime.invalid
    /// The time of the last frame ReplayKit sent, used or not, and whether a pause came since the last frame used.
    private var lastReceived: Double?
    private var paused = false
    private var received = 0

    // Used on `queue` only.
    private let queue = DispatchQueue(label: "com.skreener.ios.broadcast.stitch", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let id = UUID().uuidString
    private var stitcher: ScrollStitcher?
    /// Something has scrolled since the last reseed: the capture is under way and its strips are on disk.
    private var stitched = false
    /// The frame time of the last reseed, and of the first of the forward movements since it, if the last frames moved.
    private var seededAt = 0.0
    private var movingSince: Double?
    /// What happened to the frames, for the "Nothing scrolled" notification: the owner tests through TestFlight and
    /// can send only screenshots (#456). `early` counts movements before the screen settled (also in `moved`).
    private var counts = (frames: 0, still: 0, moved: 0, early: 0, lost: 0, reseeds: 0)
    private var frameSize = ""
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
        // ReplayKit stamps every frame; the wall clock stands in for a frame without a time.
        let seconds = time.isValid ? time.seconds : Date().timeIntervalSinceReferenceDate
        lock.lock()
        received += 1
        if let lastReceived, seconds - lastReceived >= Self.pause { paused = true }
        lastReceived = seconds
        let due = !busy && (!lastTime.isValid || !time.isValid || (time - lastTime).seconds >= Self.interval)
        let afterPause = paused
        if due {
            busy = true
            lastTime = time
            paused = false
        }
        lock.unlock()
        guard due else { return }
        let frame = Frame(pixels: pixels)
        queue.async {
            autoreleasepool { self.process(frame.pixels, at: seconds, afterPause: afterPause) }
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

    private func process(_ pixels: CVPixelBuffer, at time: Double, afterPause: Bool) {
        guard !finished, !failed else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let frame = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else { return }
        counts.frames += 1
        // A frame of another size (the phone turned) starts again until something has scrolled, and is ignored after.
        guard let stitcher, frame.width == stitcher.width, frame.height == stitcher.frameHeight else {
            if !stitched { seed(frame, at: time) }
            return
        }
        switch stitcher.add(frame) {
        case .unchanged:
            counts.still += 1
            movingSince = nil
        case .lost:
            // Before anything scrolled, the screen changed (Skreener, Control Centre, then the app): start again from
            // what is on screen now. After, the user scrolled too fast or the content changed: the next frames may
            // match again.
            counts.lost += 1
            if !stitched { seed(frame, at: time) }
        case .moved(let shift):
            counts.moved += 1
            if !stitched {
                // The first change after the broadcast starts is always leaving Skreener's sheet or Control Centre.
                let settled = counts.reseeds > 0
                    && (afterPause || time - seededAt >= Self.settle || time - (movingSince ?? time) >= Self.sustained)
                guard shift > 0, settled else {
                    counts.early += 1
                    let since = shift > 0 ? movingSince ?? time : nil
                    seed(frame, at: time)
                    movingSince = since
                    return
                }
                stitched = true
            }
            write(stitcher.takeFinishedPieces(keepingLast: stitcher.frameHeight / 2))
        case .full:
            stitched = true
            save(reachedMaximum: true)
            onFull?()
        }
    }

    /// Starts the capture again from `frame`, taken at `time`. The scroll bar at the right edge (about 12 points) is
    /// left out of the matching. The scale is the frame width over about 400 points, which gives 3 or 2 for every
    /// iPhone (1179 / 393, 750 / 375, 828 / 414, 1080 / 360...).
    ///
    /// The status bar is left out of the matching too, and always comes from the first frame: its clock, the
    /// recording pill and a Live Activity in the Dynamic Island change while the content scrolls, and would otherwise
    /// hide the navigation bar under them from `ScrollStitcher`'s header search. On an iPhone with a notch or a Dynamic
    /// Island (taller than 2:1) the status bar is 44 to 62 points tall, so 62 are ignored; on the others (and iPad),
    /// 20 to 24, so 24. Ignoring a little of the navigation bar under it does no harm: that stays put, so it comes from
    /// the first frame either way. Turned sideways, an iPhone shows no status bar.
    private func seed(_ frame: CGImage, at time: Double) {
        if stitcher != nil { counts.reseeds += 1 }
        scale = max(1, Int((Double(frame.width) / 400).rounded()))
        let statusBar = frame.height <= frame.width ? 0 : frame.height > 2 * frame.width ? 62 : 24
        stitcher = ScrollStitcher(first: frame, ignoreRight: 12 * scale, ignoreTop: statusBar * scale)
        frameSize = "\(frame.width)×\(frame.height)"
        seededAt = time
        movingSince = nil
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
                notify(title: "Nothing scrolled", body: "Scroll slowly in the app you want to capture.\n" + diagnostics)
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

    /// A short line of what happened to the frames, for the owner's TestFlight tests (#456); it can go once live
    /// capture is known to work on many phones.
    private var diagnostics: String {
        lock.lock()
        let sent = received
        lock.unlock()
        let size = frameSize.isEmpty ? "no frames" : frameSize
        return "(frames \(counts.frames) of \(sent) · still \(counts.still) · moved \(counts.moved) · early "
            + "\(counts.early) · lost \(counts.lost) · reseeds \(counts.reseeds) · \(size))"
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
