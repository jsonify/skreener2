import AVFoundation
import AudioToolbox

/// Applies the recording editor's audio settings (#385) to an exported MP4: decodes each audio track, cleans up the
/// microphone (`VoiceIsolation` for High noise removal, then `VoiceChain`), sets the volumes, mixes everything into
/// one stereo AAC track and writes the file again with the video copied as is. With nothing to change it only mixes
/// the tracks, as `AudioMixer` always has.
enum AudioFinisher {
    enum FinishError: Error { case cannotRead, cannotWrite }

    static let sampleRate = 48_000.0

    /// What was done, for the editor's status line.
    struct Outcome: Equatable {
        /// High noise removal was asked for, but Apple's Voice Isolation couldn't run, so only the noise gate was used.
        var isolationUnavailable = false
    }

    /// The tracks' sources: as the project says, or for a recording made before #385, one mixed track (or system
    /// audio and the microphone, in that order, when mixing them failed back then).
    static func sources(_ known: [AudioSource]?, trackCount: Int) -> [AudioSource] {
        if let known, known.count == trackCount { return known }
        if trackCount == 2 { return [.system, .microphone] }
        return Array(repeating: .mixed, count: trackCount)
    }

    /// Rewrites `url` with its audio cleaned up as `settings` say. `sources` says what each audio track holds. With
    /// `edits` (#381) the audio, still on the source timeline, is laid out on the edited one first (cuts left out,
    /// sped-up ranges silent).
    @discardableResult
    static func finish(_ url: URL, sources known: [AudioSource]?, settings: AudioSettings,
                       edits: EditTimeline? = nil) async throws -> Outcome {
        let timeline = edits.flatMap { $0.isEmpty ? nil : $0 }
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return Outcome() }
        guard !settings.isNeutral || timeline != nil else {
            try await AudioMixer.mixAudioTracks(of: url)
            return Outcome()
        }
        let kinds = Self.sources(known, trackCount: audioTracks.count)
        let duration = try await asset.load(.duration)
        let sourceFrames = max(0, Int((duration.seconds * sampleRate).rounded(.up)))
        let frames = timeline.map { Int(($0.outputDuration * sampleRate).rounded()) } ?? sourceFrames
        guard sourceFrames > 0, frames > 0 else { return Outcome() }
        func laidOut(_ x: [Float]) -> [Float] { timeline?.remap(x, sampleRate: sampleRate) ?? x }

        var outcome = Outcome()
        var mono: [(samples: [Float], gain: Float)] = []
        var stereo: [(samples: [[Float]], gain: Float)] = []
        let chain = VoiceChain(tuning: settings.effectiveTuning, sampleRate: sampleRate)
        for (track, source) in zip(audioTracks, kinds) {
            try Task.checkCancellation()
            let channels = try decode(track, of: asset, frames: sourceFrames)
            switch source {
            case .system:
                stereo.append((channels.map(laidOut), Float(settings.systemVolume)))
            case .microphone, .mixed:
                var voice = [Float](repeating: 0, count: sourceFrames)
                for i in 0..<sourceFrames { voice[i] = (channels[0][i] + channels[1][i]) / 2 }
                voice = laidOut(voice)
                if settings.noiseRemoval == .high {
                    do { voice = try VoiceIsolation.process(voice, sampleRate: sampleRate) } catch {
                        NSLog("Voice Isolation couldn't run, using the noise gate only: \(error)")
                        outcome.isolationUnavailable = true
                    }
                }
                try Task.checkCancellation()
                chain.process(&voice, sampleRate: sampleRate)
                mono.append((voice, Float(settings.micVolume)))
            }
        }
        try Task.checkCancellation()
        let mix = AudioMix.stereo(mono: mono, stereo: stereo, frames: frames, sampleRate: sampleRate)
        try await write(url, asset: asset, audio: mix)
        return outcome
    }

    /// A sample of the voice cleaned up as `settings` say, to listen to in the editor before exporting: `seconds` of
    /// the microphone from `start` (seconds), written as a temporary audio file. Nil when the recording has no voice.
    static func preview(_ url: URL, sources known: [AudioSource]?, settings: AudioSettings, from start: Double,
                        seconds: Double = 15) async throws -> URL? {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let kinds = Self.sources(known, trackCount: audioTracks.count)
        guard let index = kinds.firstIndex(where: { $0 != .system }) else { return nil }
        let total = try await asset.load(.duration).seconds
        guard total.isFinite, total > 0 else { return nil }
        // The last `seconds` of a recording when the playhead is near its end.
        let from = max(0, min(start, total - seconds))
        let range = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 48_000),
                                duration: CMTime(seconds: min(seconds, total - from), preferredTimescale: 48_000))
        let frames = max(1, Int((range.duration.seconds * sampleRate).rounded(.up)))
        let channels = try decode(audioTracks[index], of: asset, frames: frames, range: range)
        try Task.checkCancellation()
        var voice = [Float](repeating: 0, count: frames)
        for i in 0..<frames { voice[i] = (channels[0][i] + channels[1][i]) / 2 }
        if settings.noiseRemoval == .high { voice = (try? VoiceIsolation.process(voice, sampleRate: sampleRate)) ?? voice }
        VoiceChain(tuning: settings.effectiveTuning, sampleRate: sampleRate).process(&voice, sampleRate: sampleRate)
        var out = [voice]
        Limiter.process(&out, sampleRate: sampleRate)
        try Task.checkCancellation()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { throw FinishError.cannotWrite }
        out[0].withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel.update(from: base, count: frames) }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerVoicePreview-\(UUID().uuidString).caf")
        let writer = try AVAudioFile(forWriting: file, settings: format.settings)
        try writer.write(from: buffer)
        return file
    }

    /// The whole of `track` (or its `range`) as two channels of 48 kHz float samples, placed by their time (so a track
    /// that starts late stays in sync), `frames` long.
    private static func decode(_ track: AVAssetTrack, of asset: AVAsset, frames: Int, range: CMTimeRange? = nil) throws -> [[Float]] {
        let reader = try AVAssetReader(asset: asset)
        if let range { reader.timeRange = range }
        let offset = range.map { $0.start.seconds } ?? 0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw FinishError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? FinishError.cannotRead }
        var left = [Float](repeating: 0, count: frames), right = left
        while let sb = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            let start = pts.isNumeric ? Int(((pts.seconds - offset) * sampleRate).rounded()) : 0
            try sb.withAudioBufferList { list, _ in
                guard let buffer = list.first, let data = buffer.mData else { return }
                let count = Int(buffer.mDataByteSize) / (2 * MemoryLayout<Float>.size)
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<count {
                    let j = start + i
                    guard j >= 0, j < frames else { continue }
                    left[j] = p[2 * i]
                    right[j] = p[2 * i + 1]
                }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? FinishError.cannotRead }
        return [left, right]
    }

    /// Writes `url` again: its video tracks copied as is, and `audio` (two channels) as one stereo AAC track.
    private static func write(_ url: URL, asset: AVAsset, audio: [[Float]]) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let fm = FileManager.default
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fm.removeItem(at: dir) }
        let out = dir.appendingPathComponent(url.lastPathComponent)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        var pumps: [AudioMixer.Pump] = []
        for track in videoTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let format = try await track.load(.formatDescriptions).first
            let transform = try await track.load(.preferredTransform)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            input.transform = transform
            guard reader.canAdd(output) else { throw FinishError.cannotRead }
            guard writer.canAdd(input) else { throw FinishError.cannotWrite }
            reader.add(output)
            writer.add(input)
            pumps.append(AudioMixer.Pump(output: output, input: input))
        }
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
        ])
        guard writer.canAdd(audioInput) else { throw FinishError.cannotWrite }
        writer.add(audioInput)
        let feeder = try PCMFeeder(input: audioInput, channels: audio, sampleRate: sampleRate)

        guard reader.startReading() else { throw reader.error ?? FinishError.cannotRead }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? FinishError.cannotWrite
        }
        writer.startSession(atSourceTime: .zero)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for pump in pumps {
                group.enter()
                pump.run { group.leave() }
            }
            group.enter()
            feeder.run { group.leave() }
            group.notify(queue: .global()) { done.resume() }
        }
        guard reader.status == .completed, !feeder.failed else {
            reader.cancelReading()
            writer.cancelWriting()
            throw reader.error ?? writer.error ?? FinishError.cannotWrite
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FinishError.cannotWrite }
        _ = try fm.replaceItemAt(url, withItemAt: out)
    }

    /// Feeds interleaved float PCM to a writer input in chunks, on its own queue.
    private final class PCMFeeder: @unchecked Sendable {
        private let input: AVAssetWriterInput
        private let channels: [[Float]]
        private let sampleRate: Double
        private let format: CMAudioFormatDescription
        private let queue = DispatchQueue(label: "com.skreener.audiofinisher")
        private var position = 0
        private(set) var failed = false
        private static let chunk = 4096

        init(input: AVAssetWriterInput, channels: [[Float]], sampleRate: Double) throws {
            self.input = input
            self.channels = channels
            self.sampleRate = sampleRate
            var asbd = AudioStreamBasicDescription(
                mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2,
                mBitsPerChannel: 32, mReserved: 0)
            var format: CMAudioFormatDescription?
            let status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                                        magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                        formatDescriptionOut: &format)
            guard status == noErr, let format else { throw FinishError.cannotWrite }
            self.format = format
        }

        func run(_ finished: @escaping @Sendable () -> Void) {
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    guard let sb = nextBuffer() else {
                        input.markAsFinished()
                        finished()
                        return
                    }
                    if !input.append(sb) {
                        failed = true
                        input.markAsFinished()
                        finished()
                        return
                    }
                }
            }
        }

        /// The next chunk as a sample buffer, or nil at the end (or when one can't be made, which sets `failed`).
        private func nextBuffer() -> CMSampleBuffer? {
            let total = channels.first?.count ?? 0
            guard position < total else { return nil }
            let count = min(Self.chunk, total - position)
            var interleaved = [Float](repeating: 0, count: count * 2)
            for i in 0..<count {
                interleaved[2 * i] = channels[0][position + i]
                interleaved[2 * i + 1] = channels[1][position + i]
            }
            let bytes = count * 2 * MemoryLayout<Float>.size
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                     blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                     offsetToData: 0, dataLength: bytes,
                                                     flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
                  let block,
                  interleaved.withUnsafeBytes({ raw in
                      CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                                    dataLength: bytes)
                  }) == noErr else { failed = true; return nil }
            var sb: CMSampleBuffer?
            let pts = CMTime(value: CMTimeValue(position), timescale: CMTimeScale(sampleRate))
            guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block,
                                                                      formatDescription: format, sampleCount: count,
                                                                      presentationTimeStamp: pts, packetDescriptions: nil,
                                                                      sampleBufferOut: &sb) == noErr,
                  let sb else { failed = true; return nil }
            position += count
            return sb
        }
    }
}

/// Apple's Voice Isolation (the AUSoundIsolation audio unit, as in Final Cut Pro and the Mic Mode in Control Center):
/// a machine-learning model that keeps the voice and takes out the rest. Run offline over a whole mono track.
enum VoiceIsolation {
    enum IsolationError: Error { case unavailable, cannotRender }

    /// 'vois', made by Apple.
    static let component = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0x766f_6973,
                                                     componentManufacturer: kAudioUnitManufacturer_Apple,
                                                     componentFlags: 0, componentFlagsMask: 0)

    static var isAvailable: Bool { !AVAudioUnitComponentManager.shared().components(matching: component).isEmpty }

    static func process(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        guard isAvailable else { throw IsolationError.unavailable }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let inputData = input.floatChannelData else { throw IsolationError.cannotRender }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { inputData[0].update(from: base, count: samples.count) }
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let unit = AVAudioUnitEffect(audioComponentDescription: component)
        engine.attach(player)
        engine.attach(unit)
        engine.connect(player, to: unit, format: format)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        let chunk: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()

        // The unit runs a little behind; render that much longer and drop it from the start.
        let latency = max(0, Int((unit.auAudioUnit.latency * sampleRate).rounded()))
        let total = samples.count + latency
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else {
            throw IsolationError.cannotRender
        }
        var out: [Float] = []
        out.reserveCapacity(total)
        var stalls = 0
        while out.count < total {
            let n = AVAudioFrameCount(min(Int(chunk), total - out.count))
            switch try engine.renderOffline(n, to: buffer) {
            case .success:
                guard let data = buffer.floatChannelData else { throw IsolationError.cannotRender }
                out.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
                stalls = 0
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                stalls += 1
                if stalls > 100 { throw IsolationError.cannotRender }
            case .error:
                throw IsolationError.cannotRender
            @unknown default:
                throw IsolationError.cannotRender
            }
        }
        let trimmed = Array(out.dropFirst(latency).prefix(samples.count))
        return trimmed.count == samples.count ? trimmed : trimmed + [Float](repeating: 0, count: samples.count - trimmed.count)
    }
}
