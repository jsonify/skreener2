import CoreGraphics
import Foundation

/// Capture Table (#248): rebuilds a table from OCR word boxes and writes it as CSV, TSV, Markdown or HTML. Rows come
/// from words that share a line; columns from the vertical gutters that run down the table, so a cell that is empty in
/// one row still lines up. All of it is pure, so it runs without a screen.
enum TableText {
    /// One recognized word (or run of words Vision kept together): its text and box (any consistent units, bottom-left
    /// origin, so higher y is higher up).
    struct Word: Equatable, Sendable {
        var text: String
        var rect: CGRect
    }

    /// What a table is copied as.
    enum Format: String, CaseIterable, Sendable {
        case csv, tsv, markdown

        var title: String {
            switch self {
            case .csv: return "CSV"
            case .tsv: return "TSV"
            case .markdown: return "Markdown"
            }
        }
    }

    /// Rows of cells, top to bottom and left to right; every row has the same number of cells.
    typealias Grid = [[String]]

    // MARK: Layout

    /// The table in `words`: rows by line, columns by the gutters between them, with empty rows and columns dropped.
    static func grid(_ words: [Word]) -> Grid {
        let words = words.compactMap { w -> Word? in
            let text = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || w.rect.width <= 0 || w.rect.height <= 0 ? nil : Word(text: text, rect: w.rect)
        }
        guard !words.isEmpty else { return [] }
        let rows = groupRows(words)
        let bounds = columns(rows, height: median(words.map(\.rect.height).sorted()))
        var grid: Grid = rows.map { row in
            var cells = Array(repeating: [Word](), count: bounds.count)
            for word in row {
                let mid = word.rect.midX
                // The column the word's centre is in; one in a gutter (a word that spans it) goes to the nearer side.
                let i = bounds.firstIndex { mid < $0.upperBound } ?? bounds.count - 1
                cells[i].append(word)
            }
            return cells.map { $0.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: " ") }
        }
        grid = grid.filter { $0.contains { !$0.isEmpty } }
        return dropEmptyColumns(grid)
    }

    /// Top-to-bottom rows: a word joins the row whose centre line it sits on (within half the shorter height).
    private static func groupRows(_ words: [Word]) -> [[Word]] {
        var rows: [[Word]] = []
        var centres: [CGFloat] = []
        var heights: [CGFloat] = []
        for word in words.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let last = rows.indices.last,
               abs(centres[last] - word.rect.midY) < 0.5 * min(heights[last], word.rect.height) {
                rows[last].append(word)
                let n = CGFloat(rows[last].count)
                centres[last] += (word.rect.midY - centres[last]) / n
                heights[last] = min(heights[last], word.rect.height)
            } else {
                rows.append([word])
                centres.append(word.rect.midY)
                heights.append(word.rect.height)
            }
        }
        return rows
    }

    /// Where each column ends: the x of the middle of each gutter, the last one open-ended. A gutter is a gap at
    /// least `minimumGutter(height)` wide that almost no row has a word across: none with up to 4 rows, and at most
    /// one in 8 beyond that, so a title or a wide cell spanning columns doesn't merge them.
    static func columns(_ rows: [[Word]], height: CGFloat) -> [Range<CGFloat>] {
        let all = rows.flatMap { $0 }
        guard let left = all.map(\.rect.minX).min(), let right = all.map(\.rect.maxX).max() else { return [] }
        let allowed = rows.count <= 4 ? 0 : rows.count / 8
        // Every word edge is a place the count of rows covering x can change.
        let edges = Set(all.flatMap { [$0.rect.minX, $0.rect.maxX] }).sorted()
        var cuts: [CGFloat] = []
        var gapStart: CGFloat?
        for (a, b) in zip(edges, edges.dropFirst()) where b > a {
            let mid = (a + b) / 2
            let covering = rows.filter { row in row.contains { $0.rect.minX < mid && mid < $0.rect.maxX } }.count
            if covering <= allowed {
                if gapStart == nil { gapStart = a }
            } else if let start = gapStart {
                if a - start >= minimumGutter(height) { cuts.append((start + a) / 2) }
                gapStart = nil
            }
        }
        var out: [Range<CGFloat>] = []
        var lower = left
        for cut in cuts { out.append(lower..<cut); lower = cut }
        out.append(lower..<Swift.max(right, lower) + 1)
        return out
    }

    /// The narrowest gap between columns: wider than the space between words of one cell.
    static func minimumGutter(_ height: CGFloat) -> CGFloat { height * 0.8 }

    private static func dropEmptyColumns(_ grid: Grid) -> Grid {
        guard let width = grid.map(\.count).max() else { return [] }
        let keep = (0..<width).filter { c in grid.contains { c < $0.count && !$0[c].isEmpty } }
        return grid.map { row in keep.map { $0 < row.count ? row[$0] : "" } }
    }

    /// `rows` as a grid: cells trimmed, short rows padded, empty rows and columns dropped. For tables Vision reads
    /// itself, which may give rows of different lengths.
    static func normalized(_ rows: [[String]]) -> Grid {
        let trimmed = rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { $0.contains { !$0.isEmpty } }
        let width = trimmed.map(\.count).max() ?? 0
        return dropEmptyColumns(trimmed.map { $0 + Array(repeating: "", count: width - $0.count) })
    }

    private static func median(_ sorted: [CGFloat]) -> CGFloat {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    // MARK: Writing

    /// `grid` as `format`.
    static func text(_ grid: Grid, as format: Format) -> String {
        switch format {
        case .csv: return csv(grid)
        case .tsv: return tsv(grid)
        case .markdown: return markdown(grid)
        }
    }

    /// RFC 4180 CSV: a field with a comma, quote, line break or edge space is quoted, its quotes doubled.
    static func csv(_ grid: Grid) -> String {
        grid.map { row in
            row.map { cell in
                let quote = cell.contains { ",\"\n\r".contains($0) } || cell.first == " " || cell.last == " "
                return quote ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    /// Tab-separated, as Numbers and Excel paste it: tabs and line breaks inside a cell become spaces.
    static func tsv(_ grid: Grid) -> String {
        grid.map { row in row.map(flat).joined(separator: "\t") }.joined(separator: "\n")
    }

    /// A GitHub-flavoured Markdown table with the first row as its header, columns padded to line up, and columns of
    /// numbers right-aligned.
    static func markdown(_ grid: Grid) -> String {
        guard let header = grid.first, !header.isEmpty else { return "" }
        let rows = grid.map { $0.map { flat($0).replacingOccurrences(of: "|", with: "\\|") } }
        let right = (0..<header.count).map { c in
            let body = grid.dropFirst().map { $0[c] }.filter { !$0.isEmpty }
            return !body.isEmpty && body.allSatisfy(isNumber)
        }
        let widths = (0..<header.count).map { c in max(3, rows.map { $0[c].count }.max() ?? 0) }
        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { c, cell in
                let pad = String(repeating: " ", count: widths[c] - cell.count)
                return right[c] ? pad + cell : cell + pad
            }.joined(separator: " | ") + " |"
        }
        let rule = "| " + widths.enumerated().map { c, w in
            right[c] ? String(repeating: "-", count: w - 1) + ":" : String(repeating: "-", count: w)
        }.joined(separator: " | ") + " |"
        return ([line(rows[0]), rule] + rows.dropFirst().map(line)).joined(separator: "\n")
    }

    /// An HTML table (the first row as headers) for the clipboard, so Numbers, Excel and Google Sheets paste cells.
    static func html(_ grid: Grid) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var out = "<table>"
        for (i, row) in grid.enumerated() {
            let tag = i == 0 ? "th" : "td"
            out += "<tr>" + row.map { "<\(tag)>\(esc($0))</\(tag)>" }.joined() + "</tr>"
        }
        return out + "</table>"
    }

    /// A number as tables show one: digits with optional sign, currency, thousands separators, decimals and percent.
    static func isNumber(_ text: String) -> Bool {
        text.range(of: #"^[-+−]?[$€£¥]?\(?[-+−]?\d[\d,.'\x{00A0}\x{202F}]*\)?%?$"#, options: .regularExpression) != nil
    }

    private static func flat(_ cell: String) -> String {
        cell.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
