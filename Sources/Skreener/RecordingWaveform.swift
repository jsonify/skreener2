import AVFoundation
import Foundation

/// The recording's sound as a waveform on the editor's timeline (#385): the loudest sample of each of `buckets` equal
/// stretches of the recording, over all its audio tracks.
struct WaveformPeaks: Equatable {
    /// 0 to 1, one per bucket.
    private(set) var peaks: [Float]
    let frames: Int

    /// For audio `frames` samples long (per channel).
    init(buckets: Int, frames: Int) {
        peaks = [Float](repeating: 0, count: max(1, buckets))
        self.frames = max(1, frames)
    }

    /// Adds interleaved samples with `channels` channels whose first frame is frame `start` of the recording.
    mutating func add(_ samples: UnsafeBufferPointer<Float>, channels: Int, start: Int) {
        let channels = max(1, channels)
        let count = samples.count / channels
        let n = peaks.count
        for i in 0..<count {
            let frame = start + i
            guard frame >= 0, frame < frames else { continue }
            var loudest: Float = 0
            for c in 0..<channels { loudest = max(loudest, abs(samples[i * channels + c])) }
            let b = frame * n / frames
            if loudest > peaks[b] { peaks[b] = min(1, loudest) }
        }
    }

    /// How tall a bucket's bar is drawn, from 0 to 1: in decibels from -48 dBFS, so quiet speech still shows.
    static func height(_ peak: Float) -> Double {
        let db = MicLevel.decibels(peak)
        return min(1, max(0, (db + 48) / 48))
    }

    /// The waveform of every audio track of the file at `url`, read at a low sample rate. Empty without audio or
    /// when it can't be read.
    static func load(_ url: URL, buckets: Int) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return [] }
        let rate = 8_000.0
        var waveform = WaveformPeaks(buckets: buckets, frames: Int((duration * rate).rounded(.up)))
        for track in tracks {
            guard let reader = try? AVAssetReader(asset: asset) else { continue }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            guard reader.startReading() else { continue }
            while let sb = output.copyNextSampleBuffer() {
                if Task.isCancelled { reader.cancelReading(); return [] }
                let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                let start = pts.isNumeric ? Int((pts.seconds * rate).rounded()) : 0
                try? sb.withAudioBufferList { list, _ in
                    guard let buffer = list.first, let data = buffer.mData else { return }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
                    waveform.add(samples, channels: 1, start: start)
                }
            }
        }
        return waveform.peaks
    }
}
