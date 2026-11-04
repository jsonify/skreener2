import AppKit
import Vision
import SkreenerCore

extension TextRecognizer {
    /// The table in `image` for Capture Table (#248). Where Vision reads documents (macOS 26) and finds a table, its
    /// rows and cells are used; otherwise the words are laid out into rows and columns by where they sit
    /// (`TableText.grid`).
    static func table(in image: NSImage) async -> TableText.Grid {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let found = await documentTable(cg), found.count > 1, (found.first?.count ?? 0) > 1 {
            return found
        }
        #endif
        return TableText.grid(await tableWords(cg))
    }

    #if compiler(>=6.2)
    /// The largest table Vision's document reader finds in `cg`, or nil when it finds none.
    @available(macOS 26.0, *)
    private static func documentTable(_ cg: CGImage) async -> TableText.Grid? {
        do {
            let observations = try await RecognizeDocumentsRequest().perform(on: cg)
            let tables = observations.flatMap { $0.document.tables }
            let grids = tables.map { table in
                TableText.normalized(table.rows.map { row in row.map { $0.content.text.transcript } })
            }
            return grids.max { $0.count * ($0.first?.count ?? 0) < $1.count * ($1.first?.count ?? 0) }
        } catch {
            NSLog("Table recognition failed: \(error)")
            return nil
        }
    }
    #endif

    /// Each recognized word of `cg` with its box (pixels, bottom-left origin). Language correction is off so numbers
    /// and codes stay as shown.
    static func tableWords(_ cg: CGImage) async -> [TableText.Word] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { NSLog("OCR failed: \(error)"); return [] }
            let size = CGSize(width: cg.width, height: cg.height)
            func pixels(_ b: CGRect) -> CGRect {
                CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
            }
            var out: [TableText.Word] = []
            for obs in request.results ?? [] {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let line = pixels(obs.boundingBox)
                let text = candidate.string
                var start: String.Index?
                // Word by word, so cells Vision read as one line still split at the gutters.
                for i in Array(text.indices) + [text.endIndex] {
                    let space = i == text.endIndex || text[i].isWhitespace
                    if !space, start == nil { start = i }
                    guard space, let s = start else { continue }
                    start = nil
                    let range = s..<i
                    let box = (try? candidate.boundingBox(for: range)).map { pixels($0.boundingBox) }
                    // A word Vision can't place is cut from the line's box in proportion to where it sits.
                    let n = CGFloat(text.count)
                    let fallback = CGRect(x: line.minX + line.width * CGFloat(text.distance(from: text.startIndex, to: s)) / n,
                                          y: line.minY,
                                          width: line.width * CGFloat(text.distance(from: s, to: i)) / n, height: line.height)
                    out.append(TableText.Word(text: String(text[range]), rect: box ?? fallback))
                }
            }
            return out
        }.value
    }
}

extension TextRecognizer {
    /// Copies `grid` as `format`. CSV and TSV also go on the clipboard as an HTML table, so Numbers, Excel and Google
    /// Sheets paste cells rather than one column of text; Markdown is text only, for GitHub and editors.
    @MainActor static func copyTable(_ grid: TableText.Grid, as format: TableText.Format) {
        let item = NSPasteboardItem()
        item.setString(TableText.text(grid, as: format), forType: .string)
        if format != .markdown {
            item.setString("<meta charset=\"utf-8\">" + TableText.html(grid), forType: .html)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
        PasteWatcher.shared.disarm()
    }
}
