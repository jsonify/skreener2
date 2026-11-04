import AppKit
import SkreenerCore

/// The NSImage side of `TextRecognizer` (SkreenerCore): the same calls, taking the image's CGImage and its size in
/// points, and the clipboard.
extension TextRecognizer {
    /// `image` as a CGImage at its full pixel size, nil if it has none.
    static func cgImage(of image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func recognize(_ image: NSImage, region: CGRect? = nil) async -> String {
        guard let cg = cgImage(of: image) else { return "" }
        return await recognize(cg, region: region)
    }

    static func boxes(in image: NSImage, matching kind: Sensitive) async -> [CGRect] {
        guard let cg = cgImage(of: image) else { return [] }
        return await boxes(in: cg, size: image.size, matching: kind)
    }

    static func lineBoxes(in image: NSImage, area: CGRect) async -> [CGRect] {
        guard let cg = cgImage(of: image) else { return [] }
        return await lineBoxes(in: cg, size: image.size, area: area)
    }

    static func index(of image: NSImage) async -> TextIndex {
        guard let cg = cgImage(of: image) else { return TextIndex(size: image.size) }
        return await index(of: cg, size: image.size)
    }

    static func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
