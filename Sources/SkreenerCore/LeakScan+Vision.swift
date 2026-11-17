import CoreGraphics
import Foundation
import Vision

extension LeakScan {
    /// One thing to cover: its kind and box (image points, bottom-left origin, like `TextRecognizer`).
    public struct Finding: Sendable, Equatable {
        public let kind: Kind
        public let box: CGRect

        public init(kind: Kind, box: CGRect) {
            self.kind = kind
            self.box = box
        }
    }

    /// Scans `cg` for the wanted `kinds`: one OCR pass for the text kinds, and face detection for `.face`.
    /// `size` is the image's size in points. Text is matched with `matches(inLines:)`, so every finding is part of
    /// one line, and a key wrapped onto two lines is two findings.
    public static func scan(_ cg: CGImage, size: CGSize, kinds: Set<Kind> = Set(Kind.allCases)) async -> [Finding] {
        await scanReadingText(cg, size: size, kinds: kinds).findings
    }

    /// `scan`, and the text it read, so the editor's Text sheet (#441) needn't run OCR on the same image again. The
    /// index is nil when no text kind was asked for.
    public static func scanReadingText(_ cg: CGImage, size: CGSize, kinds: Set<Kind> = Set(Kind.allCases)) async
        -> (findings: [Finding], index: TextRecognizer.TextIndex?) {
        var out: [Finding] = []
        var read: TextRecognizer.TextIndex?
        if kinds.contains(where: { $0 != .face }) {
            let index = await TextRecognizer.index(of: cg, size: size)
            read = index
            for m in matches(inLines: index.lines) where kinds.contains(m.kind) {
                if let box = index.box(line: m.line, range: m.range) { out.append(Finding(kind: m.kind, box: box)) }
            }
        }
        if kinds.contains(.face) {
            for box in await faceBoxes(in: cg, size: size) { out.append(Finding(kind: .face, box: box)) }
        }
        return (out, read)
    }

    private static func faceBoxes(in cg: CGImage, size: CGSize) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("Face detection failed: \(error)"); return [] }
            return (request.results ?? []).map { TextRecognizer.points($0.boundingBox, in: size) }
        }.value
    }
}
