import AppKit

/// How Capture Text ends, the same whether it was started from the menu bar or from the editor's Copy Text: the text
/// is read (as Markdown when formatting is kept), then opened in the scratch pad when that is on
/// (`Preferences.textScratchPad`, also switched from the editor's Copy Text strip), or else copied straight away.
enum CaptureText {
    enum Outcome: Equatable {
        case noText
        case openedPad
        case copied(lines: Int)
    }

    /// Reads `image` and opens or copies its text; the pad opens centered on `screen`.
    @MainActor static func deliver(_ image: NSImage, on screen: NSScreen?) async -> Outcome {
        let formatted = Preferences.keepTextFormatting
        var result = FormattedText.Result()
        if formatted { result = await TextRecognizer.formatted(image) } else { result.text = await TextRecognizer.recognize(image) }
        let text = result.text
        guard !text.isEmpty else { return .noText }
        if Preferences.textScratchPad {
            TextScratchPad.show(text, blocks: formatted ? result.blocks : nil, on: screen)
            return .openedPad
        }
        if formatted { TextRecognizer.copyFormatted(.init(markdown: text, colors: result.colors), as: .standard) } else { TextRecognizer.copyText(text) }
        return .copied(lines: text.split(separator: "\n").count)
    }

    /// The part of `image` inside `region` (normalized, bottom-left origin, like Vision's), at full resolution; nil
    /// when nothing of it is left.
    static func cropped(_ image: NSImage, to region: CGRect) -> NSImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let part = cg.cropping(to: pixelRect(of: region, width: cg.width, height: cg.height)), part.width > 0, part.height > 0
        else { return nil }
        return NSImage(cgImage: part, size: NSSize(width: image.size.width * CGFloat(part.width) / CGFloat(cg.width),
                                                   height: image.size.height * CGFloat(part.height) / CGFloat(cg.height)))
    }

    /// `region` (normalized, bottom-left origin) in the pixels of a `width` × `height` image (top-left origin), widened
    /// to whole pixels and kept inside the image.
    static func pixelRect(of region: CGRect, width: Int, height: Int) -> CGRect {
        let w = CGFloat(width), h = CGFloat(height)
        let minX = max(0, (region.minX * w).rounded(.down)), maxX = min(w, (region.maxX * w).rounded(.up))
        let minY = max(0, ((1 - region.maxY) * h).rounded(.down)), maxY = min(h, ((1 - region.minY) * h).rounded(.up))
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
