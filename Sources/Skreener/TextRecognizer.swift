import AppKit
import Vision

/// On-device OCR via Vision.
enum TextRecognizer {
    /// The text in `image`, one recognized line per line. `region` limits it to part of the image (normalized,
    /// bottom-left origin, like Vision's own coordinates).
    static func recognize(_ image: NSImage, region: CGRect? = nil) async -> String {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let region { request.regionOfInterest = region }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    /// What Redact looks for.
    enum Sensitive { case allText, emails, phoneNumbers, links }

    /// Boxes (image points, bottom-left origin) around recognized text: whole lines for `.allText`, otherwise just
    /// the matching words.
    static func boxes(in image: NSImage, matching kind: Sensitive) async -> [CGRect] {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        let size = image.size
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // keep addresses and numbers exactly as shown
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            // Vision boxes are normalized with a bottom-left origin, like the editor's image coordinates.
            func points(_ b: CGRect) -> CGRect {
                CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
            }
            var out: [CGRect] = []
            for obs in request.results ?? [] {
                guard let candidate = obs.topCandidates(1).first else { continue }
                if kind == .allText { out.append(points(obs.boundingBox)); continue }
                for range in matches(kind, in: candidate.string) {
                    if let box = try? candidate.boundingBox(for: range) { out.append(points(box.boundingBox)) }
                }
            }
            return out
        }.value
    }

    private static func matches(_ kind: Sensitive, in text: String) -> [Range<String.Index>] {
        let ns = NSRange(text.startIndex..., in: text)
        let found: [NSTextCheckingResult]
        switch kind {
        case .allText:
            return [text.startIndex..<text.endIndex]
        case .emails:
            let re = try? NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: .caseInsensitive)
            found = re?.matches(in: text, range: ns) ?? []
        case .phoneNumbers:
            found = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue))?.matches(in: text, range: ns) ?? []
        case .links:
            found = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue))?.matches(in: text, range: ns) ?? []
        }
        return found.compactMap { Range($0.range, in: text) }
    }

    static func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
