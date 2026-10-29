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

    /// Every form of a formatted Capture Text copy. Whatever the editor holds (#326) turns into one of these, and the
    /// clipboard gets the forms its `CopyKind` (or, for `.standard`, the paste destination, #327) calls for.
    struct TextCopy: Equatable, Sendable {
        /// For GitHub and code editors.
        var markdown: String
        /// For fields that don't read Markdown: • bullets, no symbols.
        var clean: String
        /// The HTML body (no `<html>` or `<meta>`) for apps that take rich text.
        var html: String

        init(markdown: String, clean: String, html: String) {
            self.markdown = markdown
            self.clean = clean
            self.html = html
        }

        /// From Capture Text's Markdown, with `colors` painting their words in the HTML.
        init(markdown: String, colors: [FormattedText.Painted]) {
            self.init(markdown: markdown, clean: FormattedText.plain(markdown: markdown),
                      html: FormattedText.html(markdown: markdown, colors: colors))
        }
    }

    /// Copies `copy` as `kind`. The rich flavors (HTML, RTF) let apps that take rich text (Notes, Mail, Pages, Google
    /// Docs) get the headings, lists, bold, code and colors.
    @MainActor static func copyFormatted(_ copy: TextCopy, as kind: CopyKind = .standard) {
        let item = NSPasteboardItem()
        item.setString(kind == .markdown ? copy.markdown : copy.clean, forType: .string)
        if kind != .plainOnly {
            let body = copy.html
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
