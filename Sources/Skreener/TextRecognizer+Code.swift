import AppKit
import Vision

extension TextRecognizer {
    /// Each recognized line of `image` with its box (image points, bottom-left origin), for Capture Code (#249).
    /// Language correction is off so symbols and identifiers stay as shown.
    static func codeLines(in image: NSImage) async -> [CodeText.Line] {
        var rect = CGRect(origin: .zero, size: image.size)
        let size = image.size
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            return (request.results ?? []).compactMap { obs in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                let b = obs.boundingBox
                return CodeText.Line(text: text, rect: CGRect(x: b.minX * size.width, y: b.minY * size.height,
                                                              width: b.width * size.width, height: b.height * size.height))
            }
        }.value
    }
}
