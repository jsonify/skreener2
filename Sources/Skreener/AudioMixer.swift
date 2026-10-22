import AVFoundation

/// Mixes the audio tracks of a recording (system audio and microphone are recorded to separate tracks) into a
/// single stereo AAC track, since many players only play the first audio track. The video is copied as is,
/// not re-encoded.
enum AudioMixer {
    enum MixError: Error { case cannotRead, cannotWrite }

    /// Replaces the MP4 at `url` with a copy whose audio tracks are mixed into one. Leaves a file with fewer than
    /// two audio tracks alone; on failure the original file is kept.
    static func mixAudioTracks(of url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1 else { return }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        // A temporary folder on the same volume, so the finished file can be moved into place.
        let dir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                              appropriateFor: url, create: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent(url.lastPathComponent)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        var pumps: [Pump] = []
        func connect(_ output: AVAssetReaderOutput, _ input: AVAssetWriterInput) throws {
            guard reader.canAdd(output) else { throw MixError.cannotRead }
            guard writer.canAdd(input) else { throw MixError.cannotWrite }
            reader.add(output)
            writer.add(input)
            pumps.append(Pump(output: output, input: input))
        }
        for track in videoTracks {
            // No output settings on either side: the compressed frames are passed through.
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let format = try await track.load(.formatDescriptions).first
            let transform = try await track.load(.preferredTransform)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            input.transform = transform
            try connect(output, input)
        }
        let mix = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        try connect(mix, AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
        ]))

        guard reader.startReading() else { throw reader.error ?? MixError.cannotRead }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? MixError.cannotWrite
        }
        writer.startSession(atSourceTime: .zero)
        // Every track is copied at the same time: the writer interleaves them and waits for the slowest.
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for pump in pumps {
                group.enter()
                pump.run { group.leave() }
            }
            group.notify(queue: .global()) { done.resume() }
        }
        guard reader.status == .completed else {
            reader.cancelReading()
            writer.cancelWriting()
            throw reader.error ?? writer.error ?? MixError.cannotRead
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? MixError.cannotWrite }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: out)
    }

    /// Copies one reader output into one writer input on its own queue.
    private final class Pump: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        private let queue = DispatchQueue(label: "com.skreener.audiomixer")

        init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
            self.output = output
            self.input = input
        }

        /// Calls `finished` once, when the output has run dry or the writer stopped taking samples.
        func run(_ finished: @escaping @Sendable () -> Void) {
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    guard let sb = output.copyNextSampleBuffer(), input.append(sb) else {
                        input.markAsFinished()
                        finished()
                        return
                    }
                }
            }
        }
    }
}
