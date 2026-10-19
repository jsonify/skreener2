import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a recorded MP4 into a looping animated GIF: frames are sampled at `fps` and scaled to at most
/// `maxPixelWidth` wide, which keeps GIFs a sensible size.
enum GIFExporter {
    enum ExportError: Error { case cannotCreate, cannotFinalize }

    static func export(_ video: URL, to out: URL, fps: Double = 15, maxPixelWidth: CGFloat = 960) async throws {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixelWidth, height: maxPixelWidth * 4)
        let tolerance = CMTime(value: 1, timescale: CMTimeScale(fps * 2))
        gen.requestedTimeToleranceBefore = tolerance
        gen.requestedTimeToleranceAfter = tolerance

        let count = max(1, Int(duration.seconds * fps))
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw ExportError.cannotCreate }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String:
                                                [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]] as CFDictionary
        for i in 0..<count {
            let image = try await gen.image(at: CMTime(seconds: Double(i) / fps, preferredTimescale: 600)).image
            CGImageDestinationAddImage(dest, image, frame)
        }
        guard CGImageDestinationFinalize(dest) else { throw ExportError.cannotFinalize }
    }
}
