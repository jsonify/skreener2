import CoreGraphics
import Foundation
import Vision

/// On-device OCR via Vision. The Mac app adds NSImage versions and the clipboard in `TextRecognizer+AppKit.swift`.
/// `size` below is the image's size in points (an NSImage's, which can differ from the pixel size on Retina).
public enum TextRecognizer {
    /// The text in `cg`, one recognized line per line. `region` limits it to part of the image (normalized,
    /// bottom-left origin, like Vision's own coordinates).
    public static func recognize(_ cg: CGImage, region: CGRect? = nil) async -> String {
        await Task.detached(priority: .userInitiated) {
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
    public enum Sensitive { case allText, emails, phoneNumbers, links }

    /// Boxes (image points, bottom-left origin) around recognized text: whole lines for `.allText`, otherwise just
    /// the matching words.
    public static func boxes(in cg: CGImage, size: CGSize, matching kind: Sensitive) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // keep addresses and numbers exactly as shown
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            var out: [CGRect] = []
            for obs in request.results ?? [] {
                guard let candidate = obs.topCandidates(1).first else { continue }
                if kind == .allText { out.append(points(obs.boundingBox, in: size)); continue }
                for range in matches(kind, in: candidate.string) {
                    if let box = try? candidate.boundingBox(for: range) { out.append(points(box.boundingBox, in: size)) }
                }
            }
            return out
        }.value
    }

    /// Boxes (image points, bottom-left origin) around each line of text inside `area` (image points), for the
    /// Text Only option of pixelate, blur and erase. Only that part of the image is read, so small text still counts.
    public static func lineBoxes(in cg: CGImage, size: CGSize, area: CGRect) async -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        let area = area.intersection(CGRect(origin: .zero, size: size))
        let sx = CGFloat(cg.width) / size.width, sy = CGFloat(cg.height) / size.height
        // CGImage crops in pixels from the top-left.
        let pixels = CGRect(x: area.minX * sx, y: (size.height - area.maxY) * sy,
                            width: area.width * sx, height: area.height * sy).integral
        guard !area.isEmpty, let crop = cg.cropping(to: pixels) else { return [] }
        // The crop's own size and place in points (it may be a little larger than `area` after rounding).
        let frame = CGRect(x: pixels.minX / sx, y: size.height - pixels.maxY / sy,
                           width: CGFloat(crop.width) / sx, height: CGFloat(crop.height) / sy)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: crop, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            // Normalized to the crop, bottom-left origin.
            return (request.results ?? []).map { obs in
                let b = obs.boundingBox
                return CGRect(x: frame.minX + b.minX * frame.width, y: frame.minY + b.minY * frame.height,
                              width: b.width * frame.width, height: b.height * frame.height)
            }
        }.value
    }

    /// Every line of text in a screenshot, and a way to box any part of one, for the Redact Text tool (#295).
    /// Vision's results are kept because only they can place a range of a line; nothing changes them after `init`.
    public final class TextIndex: @unchecked Sendable {
        /// Each line as read; the ranges `box(line:range:)` takes index these strings.
        public let lines: [String]
        /// Each line's box (image points, bottom-left origin).
        public let lineBoxes: [CGRect]
        private let candidates: [VNRecognizedText]
        private let size: CGSize

        init(_ observations: [VNRecognizedTextObservation], size: CGSize) {
            let read = observations.compactMap { obs in obs.topCandidates(1).first.map { (obs.boundingBox, $0) } }
            candidates = read.map { $0.1 }
            lines = read.map { $0.1.string }
            lineBoxes = read.map { TextRecognizer.points($0.0, in: size) }
            self.size = size
        }

        /// An index with no text, for an image that can't be read.
        public convenience init(size: CGSize) {
            self.init([], size: size)
        }

        /// The box (image points, bottom-left origin) around `range` of line `line`. When Vision can't place the
        /// range, the whole line stands in if the range is most of it; otherwise nil, and that part is left out.
        public func box(line: Int, range: Range<String.Index>) -> CGRect? {
            guard candidates.indices.contains(line) else { return nil }
            if let b = try? candidates[line].boundingBox(for: range) { return TextRecognizer.points(b.boundingBox, in: size) }
            let text = lines[line]
            return text[range].count * 2 > text.count ? lineBoxes[line] : nil
        }
    }

    /// Reads all the text in `cg` once (language correction off, so names and numbers stay as shown).
    public static func index(of cg: CGImage, size: CGSize) async -> TextIndex {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return TextIndex(size: size) }
            return TextIndex(request.results ?? [], size: size)
        }.value
    }

    /// A normalized Vision box (bottom-left origin, like the editor's image coordinates) in image points.
    static func points(_ b: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
    }

    /// The ranges of `text` that `kind` matches. Redact and Safe Check (`LeakScan`) share these rules.
    static func matches(_ kind: Sensitive, in text: String) -> [Range<String.Index>] {
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
}
