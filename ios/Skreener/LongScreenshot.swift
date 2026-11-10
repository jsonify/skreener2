import AVFoundation
import CoreImage
import CoreTransferable
import ImageIO
import SkreenerCore
import SkreenerEditor
import UniformTypeIdentifiers

// Long screenshots on iPhone (#456): the Mac's Scrolling capture grabs the screen while the user scrolls; iOS lets an
// app do neither, so the frames come from a screen recording made while scrolling (Control Centre > Screen
// Recording), or from several screenshots that overlap. `ScrollStitcher` (SkreenerCore) lines the frames up and
// keeps the sticky status, navigation and tab bars once. This file is the work without any UI: the home screen shows
// its progress and opens the result in the editor.

/// A stitched long screenshot: the PNG, and a notice to show over the editor when part of it could not be stitched.
struct LongShot: Sendable {
    let png: Data
    let notice: String?
}

/// Why no long screenshot was made. `title` goes on the home screen's LCD and `detail` under it.
enum LongShotError: Error, Equatable {
    case unreadableRecording
    /// Screenshot N (counted from 1) could not be read.
    case unreadableScreenshot(Int)
    case tooFewScreenshots
    case nothingScrolled(recording: Bool)
    case sizesDiffer
    /// Screenshot N (counted from 1) doesn't overlap the one next to it, and nothing else lined up either.
    case noOverlap(Int)
    case couldNotEncode

    var title: String {
        switch self {
        case .unreadableRecording: return "COULD NOT READ THE RECORDING"
        case .unreadableScreenshot(let n): return "COULD NOT READ SCREENSHOT \(n)"
        case .tooFewScreenshots: return "PICK TWO OR MORE SCREENSHOTS"
        case .nothingScrolled(let recording):
            return recording ? "NOTHING SCROLLED IN THIS RECORDING" : "NOTHING SCROLLED IN THESE SCREENSHOTS"
        case .sizesDiffer: return "SCREENSHOTS MUST BE THE SAME SIZE"
        case .noOverlap(let n): return "SCREENSHOT \(n) DOESN’T OVERLAP"
        case .couldNotEncode: return "COULD NOT MAKE THE LONG SCREENSHOT"
        }
    }

    var detail: String? {
        switch self {
        case .unreadableRecording:
            return "Pick a screen recording from Photos."
        case .nothingScrolled(let recording):
            return recording
                ? "Record with Control Centre > Screen Recording while you scroll the page, then pick that recording."
                : "Take the screenshots as you scroll, each one sharing a few lines with the one before."
        case .sizesDiffer:
            return "Pick screenshots taken on the same iPhone, held the same way."
        case .noOverlap(let n):
            return "Screenshot \(n) doesn’t overlap the one before it. Take screenshots that share a few lines."
        case .tooFewScreenshots:
            return "Pick the screenshots top to bottom, each one sharing a few lines with the one before."
        case .unreadableScreenshot, .couldNotEncode:
            return nil
        }
    }
}

/// The numbers the stitching works by, and the wording of its notices.
enum LongShotRules {
    /// Seconds between the recording's frames that are stitched: about ten a second, as the Mac grabs about eight.
    static let sampleInterval = 0.1
    /// Frames held back between two tries, at most, for a retry after a fast flick (a 60 fps recording holds five).
    static let maxHeldFrames = 12

    /// Columns at the right edge left out of the matching: iOS's scroll indicator moves against the content. About
    /// 12 pt at 3× on a 393 pt wide iPhone; worked out from the frame, as recordings are often smaller than the screen.
    static func scrollBarWidth(frameWidth: Int) -> Int {
        max(8, Int((Double(frameWidth) * 0.03).rounded()))
    }

    /// A part of a recording counts as scrolled once it is a quarter of a frame taller than one frame.
    static func scrolled(_ stitcher: ScrollStitcher) -> Bool {
        stitcher.height > stitcher.frameHeight + stitcher.frameHeight / 4
    }

    /// "0:07", "1:12".
    static func timestamp(_ seconds: Double) -> String {
        let s = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The notice over the editor when only part of a recording stitched.
    static func recordingNotice(from start: Double, to end: Double) -> String {
        "Scrolling went too fast to follow in places, so this is the longest part that stitched "
            + "(\(timestamp(start))–\(timestamp(end))). Scroll a little slower, or use overlapping screenshots."
    }

    /// The notice over the editor when some screenshots were left out. `numbers` count from 1 in the picked order;
    /// `before` is false when the screenshots were stitched in reverse (picked bottom to top).
    static func overlapNotice(_ numbers: [Int], before: Bool) -> String {
        let side = before ? "before" : "after"
        guard numbers.count > 1 else {
            return "Screenshot \(numbers.first ?? 0) doesn’t overlap the one \(side) it, so it is left out. "
                + "Take screenshots that share a few lines."
        }
        let list = numbers.dropLast().map(String.init).joined(separator: ", ") + " and \(numbers.last ?? 0)"
        return "Screenshots \(list) don’t overlap the ones \(side) them, so they are left out. "
            + "Take screenshots that share a few lines."
    }
}

// MARK: Recording

/// Picks which of a recording's frames are tried, about one every `interval` seconds, and holds back the ones in
/// between: when a tried frame doesn't line up (a fast flick moved further than the stitcher can follow), those are
/// tried first, in order, to bridge the gap.
struct FramePicker<Frame> {
    let interval: Double
    let maxHeld: Int
    /// The frames since the last one tried, oldest first.
    private(set) var held: [Frame] = []
    private var lastTry: Double

    init(start: Double, interval: Double = LongShotRules.sampleInterval, maxHeld: Int = LongShotRules.maxHeldFrames) {
        self.interval = interval
        self.maxHeld = maxHeld
        lastTry = start
    }

    /// Whether `frame`, shown at `time` seconds, is to be tried now. If not, it is held back. Past `maxHeld`, every
    /// other held frame is dropped, keeping the oldest (closest to the last frame that lined up).
    mutating func isDue(_ frame: Frame, at time: Double) -> Bool {
        // A little slack: frame times are rounded, and 6 frames at 60 fps should count as a tenth of a second.
        if time - lastTry >= interval - 0.002 { return true }
        held.append(frame)
        if held.count > maxHeld {
            held = held.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        }
        return false
    }

    /// The frame at `time` was tried: the held frames are no longer needed.
    mutating func tried(at time: Double) {
        held.removeAll()
        lastTry = time
    }
}

/// Stitches a recording's frames, in order. Each tried frame goes to the stitcher; if it doesn't line up, the frames
/// held back since the last try go first, then it again. If it still doesn't line up, the current part ends and a
/// new part starts from that frame: a recording starts with Control Centre closing and ends with it opening, and a
/// flick too fast to follow breaks the page in two. The tallest part is the long screenshot.
///
/// `convert` turns a frame into an upright image; frames are only converted when they are tried. Not thread-safe.
final class RecordingStitch<Frame> {
    /// One stretch of the recording that stitched together.
    struct Part {
        let stitcher: ScrollStitcher
        let start: Double
        var end: Double
    }

    private let convert: (Frame) -> CGImage?
    private var part: Part?
    private var best: Part?
    private var picker = FramePicker<Frame>(start: 0)
    /// The newest frame, when it was held back: tried at the end, so the bottom of the page is in.
    private var newest: (frame: Frame, time: Double)?
    /// Parts that scrolled, so far.
    private var scrolledParts = 0

    init(convert: @escaping (Frame) -> CGImage?) {
        self.convert = convert
    }

    /// Takes the recording's next frame, shown at `time` seconds. Returns false once the image is full: stop reading.
    func add(_ frame: Frame, at time: Double) -> Bool {
        guard part != nil else {
            if let image = convert(frame) { begin(image, at: time) }
            picker = FramePicker(start: time)
            return true
        }
        guard picker.isDue(frame, at: time) else {
            newest = (frame, time)
            return true
        }
        newest = nil
        let full = attempt(frame, at: time)
        picker.tried(at: time)
        return !full
    }

    /// Tries the last frame if it was held back, and gives the tallest part, with a notice when the recording broke
    /// into more than one part that scrolled.
    func finish() -> (stitcher: ScrollStitcher, notice: String?)? {
        if let newest {
            _ = attempt(newest.frame, at: newest.time)
            self.newest = nil
        }
        close()
        guard let best else { return nil }
        let notice = scrolledParts > 1 ? LongShotRules.recordingNotice(from: best.start, to: best.end) : nil
        return (best.stitcher, notice)
    }

    /// Feeds `frame`, bridging a gap with the held frames if it doesn't line up. Returns true when the image is full.
    private func attempt(_ frame: Frame, at time: Double) -> Bool {
        guard let stitcher = part?.stitcher, let image = convert(frame) else { return false }
        var step = stitcher.add(image)
        if case .lost = step, !picker.held.isEmpty {
            for held in picker.held {
                let bridged: ScrollStitcher.Step? = autoreleasepool { convert(held).map { stitcher.add($0) } }
                // The rest are further still from the last frame that lined up.
                if case .lost? = bridged { break }
                if case .full? = bridged {
                    part?.end = time
                    return true
                }
            }
            step = stitcher.add(image)
        }
        switch step {
        case .full:
            part?.end = time
            return true
        case .lost:
            close()
            begin(image, at: time)
            return false
        case .moved, .unchanged:
            part?.end = time
            return false
        }
    }

    private func begin(_ image: CGImage, at time: Double) {
        let stitcher = ScrollStitcher(first: image, ignoreRight: LongShotRules.scrollBarWidth(frameWidth: image.width))
        part = Part(stitcher: stitcher, start: time, end: time)
    }

    /// Ends the current part, keeping it if it is the tallest yet.
    private func close() {
        guard let part else { return }
        self.part = nil
        if LongShotRules.scrolled(part.stitcher) { scrolledParts += 1 }
        if best.map({ $0.stitcher.height < part.stitcher.height }) ?? true { best = part }
    }
}

/// Turns a recording's decoded frames into upright images. Screen recordings are upright; a rotated video (its
/// track's preferred transform turns it) is turned the same way.
final class FrameConverter {
    /// No colour matching: the frames are compared with each other and kept as they are.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    private let orientation: CGImagePropertyOrientation
    private let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(transform: CGAffineTransform) {
        orientation = Self.orientation(of: transform)
    }

    func image(_ buffer: CVPixelBuffer) -> CGImage? {
        var image = CIImage(cvPixelBuffer: buffer)
        if orientation != .up { image = image.oriented(orientation) }
        return context.createCGImage(image, from: image.extent, format: .BGRA8, colorSpace: space)
    }

    /// The quarter turn a track's preferred transform makes, as an image orientation.
    static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}

/// A movie picked in Photos, copied to a folder of its own in the temporary directory (the picker's file goes away
/// when the transfer ends). `remove()` deletes the copy.
struct PickedMovie: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("LongShot-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

// MARK: Making

/// Makes long screenshots. The functions are not main-actor: they run on the caller's task, off the main thread,
/// and stop with `CancellationError` when it is cancelled. `progress` gets 0...1, at most a hundred times.
enum LongShotMaker {
    /// Stitches a screen recording made while scrolling.
    static func fromRecording(at url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> LongShot {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else {
            throw LongShotError.unreadableRecording
        }
        let result = try stitch(asset: asset, track: track, transform: transform,
                                seconds: max(duration.seconds, 0.001), progress: progress)
        // Less than a quarter of a frame is Control Centre going away or a nudge, not a page scrolled.
        guard let result, LongShotRules.scrolled(result.stitcher) else {
            throw LongShotError.nothingScrolled(recording: true)
        }
        guard let image = result.stitcher.makeImage(), let png = png(image) else { throw LongShotError.couldNotEncode }
        return LongShot(png: png, notice: result.notice)
    }

    /// Reads the recording's frames in order and stitches them.
    private static func stitch(asset: AVAsset, track: AVAssetTrack, transform: CGAffineTransform, seconds: Double,
                               progress: @Sendable (Double) -> Void) throws
        -> (stitcher: ScrollStitcher, notice: String?)? {
        guard let reader = try? AVAssetReader(asset: asset) else { throw LongShotError.unreadableRecording }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        guard reader.canAdd(output) else { throw LongShotError.unreadableRecording }
        reader.add(output)
        guard reader.startReading() else { throw LongShotError.unreadableRecording }
        defer {
            if reader.status == .reading { reader.cancelReading() }
        }
        let converter = FrameConverter(transform: transform)
        let stitching = RecordingStitch<CVPixelBuffer>(convert: converter.image)
        var reported = -1
        while true {
            try Task.checkCancellation()
            // Each frame is released before the next is read; only the held ones (a few) stay.
            let more: Bool = autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return false }
                guard let buffer = sample.imageBuffer else { return true }
                let time = sample.presentationTimeStamp.seconds
                let percent = min(Int(time / seconds * 100), 100)
                if percent > reported {
                    reported = percent
                    progress(Double(percent) / 100)
                }
                return stitching.add(buffer, at: time)
            }
            if !more { break }
        }
        if reader.status == .failed { throw LongShotError.unreadableRecording }
        return stitching.finish()
    }

    /// Stitches screenshots (encoded image files), top to bottom in the order given. If nothing lines up that way,
    /// they are tried bottom to top, in case they were picked that way round.
    static func fromScreenshots(_ files: [Data], progress: @escaping @Sendable (Double) -> Void) async throws
        -> LongShot {
        guard files.count >= 2 else { throw LongShotError.tooFewScreenshots }
        var result = try stitch(files, reversed: false) { progress($0 * 0.8) }
        if !LongShotRules.scrolled(result.stitcher),
           let back = try? stitch(files, reversed: true, progress: { _ in }),
           back.stitcher.height > result.stitcher.height {
            result = back
        }
        guard result.stitcher.height > result.stitcher.frameHeight else {
            if let first = result.missing.first { throw LongShotError.noOverlap(first) }
            throw LongShotError.nothingScrolled(recording: false)
        }
        guard let image = result.stitcher.makeImage(), let png = png(image) else { throw LongShotError.couldNotEncode }
        progress(1)
        let notice = result.missing.isEmpty
            ? nil : LongShotRules.overlapNotice(result.missing.sorted(), before: !result.reversed)
        return LongShot(png: png, notice: notice)
    }

    /// Feeds the screenshots to a stitcher in order. `missing` are the ones (counted from 1) that didn't line up.
    private static func stitch(_ files: [Data], reversed: Bool, progress: (Double) -> Void) throws
        -> (stitcher: ScrollStitcher, missing: [Int], reversed: Bool) {
        let order = reversed ? Array(files.indices.reversed()) : Array(files.indices)
        var stitcher: ScrollStitcher?
        var missing: [Int] = []
        for (done, index) in order.enumerated() {
            try Task.checkCancellation()
            let full: Bool = try autoreleasepool {
                guard let image = decode(files[index]) else { throw LongShotError.unreadableScreenshot(index + 1) }
                guard let current = stitcher else {
                    stitcher = ScrollStitcher(first: image,
                                              ignoreRight: LongShotRules.scrollBarWidth(frameWidth: image.width))
                    return false
                }
                guard image.width == current.width, image.height == current.frameHeight else {
                    throw LongShotError.sizesDiffer
                }
                switch current.add(image) {
                case .lost:
                    missing.append(index + 1)
                    return false
                case .full:
                    return true
                case .moved, .unchanged:
                    return false
                }
            }
            progress(Double(done + 1) / Double(order.count))
            if full { break }
        }
        guard let stitcher else { throw LongShotError.unreadableScreenshot(1) }
        return (stitcher, missing, reversed)
    }

    /// Decodes a screenshot at full size, upright.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The editor's source for a long screenshot, decoded at full size. `ImageSource.data` stops at 4096 px on the
    /// long side, which would shrink a long screenshot to a sliver; this one is only used in the app, which has the
    /// memory (30 000 px tall by 1179 wide is about 140 MB).
    static func source(_ png: Data) -> ImageSource {
        ImageSource {
            guard let image = decode(png) else { throw LongShotError.couldNotEncode }
            return image
        }
    }
}
