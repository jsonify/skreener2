import AppKit
import AVFoundation

// Joining clips (#384): the recording editor can put this recording in a sequence with title cards, screenshots and
// other finished recordings, cut or crossfaded, and export it all as one video. The recording is rendered as always;
// title cards and screenshots are drawn on the Studio Mode background (`StudioCompositor.drawSlate`) into short silent
// videos; then everything is laid out on one timeline (`ClipSequence.layout`) and exported once (`SequenceJoiner`).

/// One clip of the sequence, saved in `studio.json`.
struct SequenceClip: Codable, Equatable {
    enum Kind: String, Codable {
        /// The recording being edited, with its edits and effects.
        case recording
        /// Another finished video (e.g. another recording, exported from its own editor).
        case video
        /// A picture (e.g. an annotated screenshot), shown for `duration`.
        case still
        /// Text on the background, shown for `duration`.
        case title
    }

    var id = UUID()
    var kind: Kind
    /// The file of a video or still.
    var path: String?
    /// A title card's heading and the smaller line under it.
    var title = ""
    var subtitle = ""
    /// How long a still or title card shows, in seconds.
    var duration = ClipSequence.defaultStill
    /// Crossfades from the clip before into this one; off, it cuts.
    var crossfade = true

    init(kind: Kind, path: String? = nil, title: String = "", subtitle: String = "",
         duration: Double = ClipSequence.defaultStill, crossfade: Bool = true) {
        self.kind = kind
        self.path = path
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
        self.crossfade = crossfade
    }

    /// Missing values keep their defaults; a clip of an unknown kind (from a newer Skreener) reads as a title card.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .title
        path = try c.decodeIfPresent(String.self, forKey: .path)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? ClipSequence.defaultStill
        crossfade = try c.decodeIfPresent(Bool.self, forKey: .crossfade) ?? true
    }

    var url: URL? { path.map { URL(fileURLWithPath: $0) } }

    /// What the sequence list calls it.
    var name: String {
        switch kind {
        case .recording: return "This recording"
        case .video: return url?.lastPathComponent ?? "Video"
        case .still: return url?.lastPathComponent ?? "Picture"
        case .title: return title.isEmpty ? "Title card" : "Title: \(title)"
        }
    }

    /// Stills and title cards have a length of their own; videos are as long as they are.
    var hasDuration: Bool { kind == .still || kind == .title }
}

/// The sequence's timing, pure so it can be tested.
enum ClipSequence {
    /// How long a crossfade takes (less between short clips).
    static let crossfade = 0.6
    static let defaultStill = 3.0
    static let minStill = 1.0
    static let maxStill = 30.0
    /// The lengths offered for stills and title cards.
    static let stillLengths = [1.0, 2, 3, 4, 5, 7, 10, 15]

    /// Where a clip goes on the joined timeline.
    struct Placement: Equatable {
        var start: Double
        var duration: Double
        /// How long it overlaps the clip before, fading in over it (0 for a cut).
        var fadeIn: Double
        var end: Double { start + duration }
    }

    /// The clips of `durations` one after another, each overlapping the one before by a crossfade where `crossfades`
    /// says so (the first clip's is ignored). A crossfade never takes more than half of either clip, so at most two
    /// clips ever show at once.
    static func layout(durations: [Double], crossfades: [Bool], fade: Double = crossfade) -> [Placement] {
        var out: [Placement] = []
        for (i, d) in durations.enumerated() {
            let length = max(0, d.isFinite ? d : 0)
            guard let before = out.last else {
                out.append(Placement(start: 0, duration: length, fadeIn: 0))
                continue
            }
            let fades = i < crossfades.count && crossfades[i]
            let overlap = fades ? max(0, min(fade, before.duration / 2, length / 2)) : 0
            out.append(Placement(start: before.end - overlap, duration: length, fadeIn: overlap))
        }
        return out
    }

    static func total(_ placements: [Placement]) -> Double { placements.map(\.end).max() ?? 0 }

    /// The sequence as it is used: with exactly one `.recording` clip (added at the start when missing, later copies
    /// left out), still lengths in range and no crossfade into the first clip. Empty stays empty: just the recording.
    static func tidy(_ clips: [SequenceClip]) -> [SequenceClip] {
        guard !clips.isEmpty else { return [] }
        var seen = false
        var out: [SequenceClip] = []
        for var c in clips {
            if c.kind == .recording {
                if seen { continue }
                seen = true
            }
            if (c.kind == .video || c.kind == .still), (c.path ?? "").isEmpty { continue }
            c.duration = c.duration.isFinite ? min(max(c.duration, minStill), maxStill) : defaultStill
            out.append(c)
        }
        if !seen { out.insert(SequenceClip(kind: .recording), at: 0) }
        out[0].crossfade = false
        return out
    }

    /// Whether the sequence is more than the recording alone.
    static func joins(_ clips: [SequenceClip]) -> Bool { clips.contains { $0.kind != .recording } }

    /// "3 s".
    static func lengthText(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds)) s" : String(format: "%.1f s", seconds)
    }
}

/// Makes the sequence's video: title cards and stills drawn into short videos, then every clip placed on one
/// timeline with its crossfades and exported once.
enum SequenceJoiner {
    enum JoinError: LocalizedError {
        case missing(String), cannotWrite

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "\(name) couldn't be found, so the sequence couldn't be made."
            case .cannotWrite: return "The joined video couldn't be written."
            }
        }
    }

    /// A video of `seconds` showing `image` (silent, at `fps`), in `out`.
    static func writeStill(_ image: CGImage, seconds: Double, fps: Int, to out: URL) async throws {
        let width = image.width, height = image.height
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw JoinError.cannotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? JoinError.cannotWrite }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw JoinError.cannotWrite }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pixels = buffer else { throw JoinError.cannotWrite }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                               space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        // The same picture once a second (so the video seeks well), and once more at the end.
        let rate = Int32(max(1, fps))
        var t = 0.0
        while t < seconds {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(pixels, withPresentationTime: CMTime(seconds: t, preferredTimescale: rate * 100))
            t += 1
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: rate * 100))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? JoinError.cannotWrite }
    }

    /// Joins `clips` (videos, in order, each crossfading into the one before where `crossfades` says) into one MP4 of
    /// `canvas` pixels at `fps` in `out`. A clip of another size is fitted inside the canvas, centered.
    static func join(_ clips: [URL], crossfades: [Bool], canvas: CGSize, fps: Int, to out: URL) async throws {
        let assets = clips.map { AVURLAsset(url: $0) }
        var durations: [Double] = []
        for asset in assets { durations.append(try await asset.load(.duration).seconds) }
        let placements = ClipSequence.layout(durations: durations, crossfades: crossfades)
        let composition = AVMutableComposition()
        // Two tracks of each, taking turns, so neighbouring clips can overlap.
        guard let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw JoinError.cannotWrite }
        let video = [videoA, videoB], audio = [audioA, audioB]
        func time(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 6000) }

        var transforms: [CGAffineTransform] = []
        var audioRamps: [[(at: Double, from: Float, to: Float, length: Double)]] = [[], []]
        for (i, asset) in assets.enumerated() {
            let p = placements[i], lane = i % 2
            let range = CMTimeRange(start: .zero, duration: time(p.duration))
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw JoinError.missing(clips[i].lastPathComponent)
            }
            try video[lane].insertTimeRange(range, of: track, at: time(p.start))
            let natural = try await track.load(.naturalSize)
            let preferred = try await track.load(.preferredTransform)
            let shown = CGRect(origin: .zero, size: natural).applying(preferred)
            let k = min(canvas.width / max(abs(shown.width), 1), canvas.height / max(abs(shown.height), 1))
            let fitted = CGSize(width: abs(shown.width) * k, height: abs(shown.height) * k)
            transforms.append(preferred
                .concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
                .concatenating(CGAffineTransform(scaleX: k, y: k))
                .concatenating(CGAffineTransform(translationX: (canvas.width - fitted.width) / 2,
                                                 y: (canvas.height - fitted.height) / 2)))
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                try audio[lane].insertTimeRange(range, of: sound, at: time(p.start))
            }
            // The sound crossfades with the picture.
            if p.fadeIn > 0 {
                audioRamps[lane].append((p.start, 0, 1, p.fadeIn))
                audioRamps[1 - lane].append((p.start, 1, 0, p.fadeIn))
            }
        }

        // The picture: each clip alone, then each crossfade with the incoming clip fading in on top.
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        for (i, p) in placements.enumerated() {
            let lane = i % 2
            let fadeOut = i + 1 < placements.count ? placements[i + 1].fadeIn : 0
            let alone = CMTimeRange(start: time(p.start + p.fadeIn), end: time(p.end - fadeOut))
            if alone.duration.seconds > 0 {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = alone
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video[lane])
                layer.setTransform(transforms[i], at: alone.start)
                instruction.layerInstructions = [layer]
                instructions.append(instruction)
            }
            if fadeOut > 0 {
                let overlap = CMTimeRange(start: time(p.end - fadeOut), end: time(p.end))
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = overlap
                let incoming = AVMutableVideoCompositionLayerInstruction(assetTrack: video[1 - lane])
                incoming.setTransform(transforms[i + 1], at: overlap.start)
                incoming.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: overlap)
                let outgoing = AVMutableVideoCompositionLayerInstruction(assetTrack: video[lane])
                outgoing.setTransform(transforms[i], at: overlap.start)
                instruction.layerInstructions = [incoming, outgoing]
                instructions.append(instruction)
            }
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        videoComposition.instructions = instructions

        // A lane no clip has sound on is left out.
        var sounding: [(lane: Int, track: AVMutableCompositionTrack)] = []
        for (lane, track) in audio.enumerated() {
            if track.segments.isEmpty { composition.removeTrack(track) } else { sounding.append((lane, track)) }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = sounding.map { lane, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(1, at: .zero)
            for ramp in audioRamps[lane] {
                parameters.setVolumeRamp(fromStartVolume: ramp.from, toEndVolume: ramp.to,
                                         timeRange: CMTimeRange(start: time(ramp.at), duration: time(ramp.length)))
            }
            return parameters
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw JoinError.cannotWrite }
        session.videoComposition = videoComposition
        session.audioMix = mix
        if #available(macOS 15, *) {
            try await session.export(to: out, as: .mp4)
        } else {
            session.outputURL = out
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else { throw session.error ?? JoinError.cannotWrite }
        }
    }
}
