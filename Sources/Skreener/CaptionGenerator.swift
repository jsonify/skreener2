import AVFoundation
import Foundation
import Speech

/// Makes captions from a recording's microphone track with the `Speech` framework, on the device (#386): the track is
/// read into a 16 kHz mono file, recognized, and its words grouped into lines (`Captions.lines`).
enum CaptionGenerator {
    enum GenerateError: LocalizedError {
        case notAllowed, unavailable, noAudio, noSpeech

        var errorDescription: String? {
            switch self {
            case .notAllowed:
                return "Skreener isn't allowed to use speech recognition. Turn it on in System Settings › Privacy & Security › Speech Recognition."
            case .unavailable:
                return "Speech recognition on this Mac isn't available for your language. Turn on Dictation in System Settings › Keyboard to download it, then try again."
            case .noAudio: return "This recording has no microphone sound to make captions from."
            case .noSpeech: return "No speech was recognized in the recording."
            }
        }
    }

    static let sampleRate = 16_000.0

    /// The captions for the recording's clean video at `video`, whose audio tracks hold `sources`.
    static func generate(video: URL, sources known: [AudioSource]?) async throws -> [Caption] {
        guard await authorize() else { throw GenerateError.notAllowed }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else { throw GenerateError.unavailable }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("SkreenerCaptions-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let audio = dir.appendingPathComponent("voice.caf")
        try await extractVoice(from: video, sources: known, to: audio)
        try Task.checkCancellation()
        let words = try await recognize(audio, with: recognizer)
        let lines = Captions.lines(words)
        guard !lines.isEmpty else { throw GenerateError.noSpeech }
        return lines
    }

    private static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        default: return false
        }
    }

    /// Writes the microphone track (or, without one, the first audio track) as 16 kHz mono, its samples placed by
    /// their time so the words line up with the video.
    private static func extractVoice(from video: URL, sources known: [AudioSource]?, to out: URL) async throws {
        let asset = AVURLAsset(url: video)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw GenerateError.noAudio }
        let kinds = AudioFinisher.sources(known, trackCount: tracks.count)
        let index = kinds.firstIndex { $0 != .system } ?? 0
        guard kinds[index] != .system else { throw GenerateError.noAudio }
        let duration = try await asset.load(.duration).seconds
        let frames = max(1, Int((duration.isFinite ? duration : 0) * sampleRate))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[index], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw GenerateError.noAudio }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? GenerateError.noAudio }
        var samples = [Float](repeating: 0, count: frames)
        while let sb = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            let start = pts.isNumeric ? Int((pts.seconds * sampleRate).rounded()) : 0
            try sb.withAudioBufferList { list, _ in
                guard let buffer = list.first, let data = buffer.mData else { return }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let p = data.assumingMemoryBound(to: Float.self)
                for i in 0..<count where start + i >= 0 && start + i < frames { samples[start + i] = p[i] }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? GenerateError.noAudio }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { throw GenerateError.noAudio }
        let file = try AVAudioFile(forWriting: out, settings: format.settings)
        let chunk = 65_536
        var at = 0
        while at < frames {
            let n = min(chunk, frames - at)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
                  let channel = buffer.floatChannelData?[0] else { throw GenerateError.noAudio }
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { channel.update(from: base + at, count: n) }
            }
            buffer.frameLength = AVAudioFrameCount(n)
            try file.write(from: buffer)
            at += n
        }
    }

    /// Resumes a continuation once, from whichever of the recognizer's callbacks comes first, and holds the task so
    /// cancelling the caller cancels it.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }

        func hold(_ t: SFSpeechRecognitionTask) {
            lock.lock()
            task = t
            let cancel = cancelled
            lock.unlock()
            if cancel { t.cancel() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let t = task
            lock.unlock()
            t?.cancel()
        }
    }

    private static func recognize(_ audio: URL, with recognizer: SFSpeechRecognizer) async throws -> [Captions.Word] {
        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        let once = Once()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<[Captions.Word], Error>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        guard once.claim() else { return }
                        c.resume(returning: result.bestTranscription.segments.map {
                            Captions.Word(start: $0.timestamp, duration: $0.duration, text: $0.substring)
                        })
                    } else if let error {
                        guard once.claim() else { return }
                        // "No speech detected" comes back as an error.
                        let ns = error as NSError
                        if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 {
                            c.resume(throwing: GenerateError.noSpeech)
                        } else {
                            c.resume(throwing: error)
                        }
                    }
                }
                once.hold(task)
            }
        } onCancel: {
            once.cancel()
        }
    }
}
