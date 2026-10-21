import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Skreener

final class GIFExporterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testExportsLoopingGIF() async throws {
        let video = dir.appendingPathComponent("clip.mp4"), gif = dir.appendingPathComponent("clip.gif")
        try await writeVideo(to: video, width: 320, height: 240, frames: 30, fps: 30)
        try await GIFExporter.export(video, to: gif, fps: 10, maxPixelWidth: 160)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.gif.identifier)
        // One second at 10 fps (the last frame may fall just past the end).
        XCTAssertTrue((9...10).contains(CGImageSourceGetCount(source)), "\(CGImageSourceGetCount(source)) frames")
        let frame = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(frame[kCGImagePropertyPixelWidth as String] as? Int, 160)
        XCTAssertEqual(frame[kCGImagePropertyPixelHeight as String] as? Int, 120)
        let file = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let gifInfo = file?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        XCTAssertEqual(gifInfo?[kCGImagePropertyGIFLoopCount as String] as? Int, 0, "should loop forever")
    }

    /// An H.264 MP4 of `frames` frames whose gray level steps from black towards white.
    private func writeVideo(to url: URL, width: Int, height: Int, frames: Int, fps: Int32) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                memset(base, Int32(i * 255 / frames), CVPixelBufferGetDataSize(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }
}
