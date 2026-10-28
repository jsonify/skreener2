import AppKit
import Vision

extension TextRecognizer {
    /// Capture Text with formatting: the text in `image` as Markdown (headings, lists, bold, `code`), with its colored
    /// words for the rich-text copy. Each word's box is read from the pixels, since Vision reports no styles.
    static func formatted(_ image: NSImage) async -> FormattedText.Result {
        FormattedText.format(await formattedLines(image))
    }

    /// Each recognized line of `image` with its words' boxes (pixels, bottom-left origin) and how they are drawn.
    static func formattedLines(_ image: NSImage) async -> [FormattedText.Line] {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            let bitmap = FormattedText.Bitmap(cg)
            let size = CGSize(width: cg.width, height: cg.height)
            // Pixels rather than points, so the measurements see every pixel; Vision's boxes are normalized with a
            // bottom-left origin, like the bitmap's coordinates.
            func pixels(_ b: CGRect) -> CGRect {
                CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
            }
            return (request.results ?? []).compactMap { obs -> FormattedText.Line? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                let line = pixels(obs.boundingBox)
                let words = FormattedText.wordRanges(candidate.string).map { range in
                    let box = (try? candidate.boundingBox(for: range)).map { pixels($0.boundingBox) }
                    return FormattedText.Word(text: String(candidate.string[range]), rect: box ?? line,
                                              look: box.flatMap { bitmap?.look($0) } ?? .init())
                }
                return FormattedText.Line(rect: line, words: words, bullet: bitmap?.hasBullet(leftOf: line) ?? false)
            }
        }.value
    }

    /// What a formatted copy puts on the clipboard.
    enum CopyKind {
        /// Rich text (HTML and RTF) with clean plain text beside it, for fields that don't read Markdown.
        case standard
        /// Rich text with the Markdown as the plain text, for GitHub and code editors.
        case markdown
        /// Clean plain text and nothing else.
        case plainOnly
    }

    /// Copies Capture Text's `markdown` as `kind`. The rich flavors (HTML, RTF) let apps that take rich text (Notes,
    /// Mail, Pages, Google Docs) get the headings, lists, bold, code and colors.
    @MainActor static func copyFormatted(_ markdown: String, colors: [FormattedText.Painted], as kind: CopyKind = .standard) {
        let item = NSPasteboardItem()
        item.setString(kind == .markdown ? markdown : FormattedText.plain(markdown: markdown), forType: .string)
        if kind != .plainOnly {
            let body = FormattedText.html(markdown: markdown, colors: colors)
            item.setString("<meta charset=\"utf-8\">" + body, forType: .html)
            // RTF in the system font rather than the HTML default (Times).
            let styled = "<meta charset=\"utf-8\"><style>body { font-family: -apple-system, 'Helvetica Neue'; font-size: 13px }</style>" + body
            if let rich = NSAttributedString(html: Data(styled.utf8), documentAttributes: nil),
               let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
                item.setData(rtf, forType: .rtf)
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
    }
}
