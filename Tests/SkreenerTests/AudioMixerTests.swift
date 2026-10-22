import AVFoundation
import XCTest
@testable import Skreener

final class AudioMixerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testMixesTwoAudioTracksIntoOne() async throws {
        let url = dir.appendingPathComponent("clip.mp4")
        try await writeClip(to: url, audioTracks: 2)
        try await AudioMixer.mixAudioTracks(of: url)

        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audio.count, 1)
        XCTAssertEqual(video.count, 1)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.1)
        let audioDuration = try await XCTUnwrap(audio.first).load(.timeRange).duration.seconds
        XCTAssertEqual(audioDuration, 1, accuracy: 0.1)
    }

    func testLeavesASingleAudioTrackAlone() async throws {
        let url = dir.appendingPathComponent("clip.mp4")
        try await writeClip(to: url, audioTracks: 1)
        let before = try Data(contentsOf: url)
        try await AudioMixer.mixAudioTracks(of: url)
        let after = try Data(contentsOf: url)
        XCTAssertEqual(after, before)
    }

    /// A one-second MP4: 30 gray H.264 frames plus `audioTracks` mono AAC tracks of a quiet constant signal.
    private func writeClip(to url: URL, audioTracks: Int) async throws {
        let width = 160, height = 120, fps: Int32 = 30, rate = 48_000
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)
        writer.add(video)
        let audio = (0..<audioTracks).map { _ in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            return input
        }
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        let samplesPerFrame = rate / Int(fps)
        for i in 0..<Int(fps) {
            while !video.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, 128, CVPixelBufferGetDataSize(pixels)) }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)))
            for input in audio {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
                let sample = try audioBuffer(frames: samplesPerFrame, at: i * samplesPerFrame, rate: rate)
                XCTAssertTrue(input.append(sample))
            }
        }
        video.markAsFinished()
        audio.forEach { $0.markAsFinished() }
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(fps), timescale: fps))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }

    /// `frames` mono 32-bit float samples of a constant level, starting at sample `start`.
    private func audioBuffer(frames: Int, at start: Int, rate: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
            mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let size = frames * 4
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: size,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        let data = try XCTUnwrap(block)
        let samples = [Float](repeating: 0.1, count: frames)
        samples.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                CMBlockBufferReplaceDataBytes(with: base, blockBuffer: data, offsetIntoDestination: 0, dataLength: size)
            }
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: data, formatDescription: try XCTUnwrap(format), sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(rate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        return try XCTUnwrap(sample)
    }
}
