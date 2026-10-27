import CoreGraphics

/// Where Combine Screenshots (#273) puts each capture on the new canvas. Pure geometry, so it is unit tested. Frames
/// have a top-left origin and are in whatever unit the sizes are in.
enum CombineLayout {
    enum Arrangement: Int, CaseIterable {
        case row, column, grid

        var title: String {
            switch self {
            case .row: return "Row"
            case .column: return "Column"
            case .grid: return "Grid"
            }
        }
    }

    /// How a capture sits in its cell when it is smaller than the biggest one in its row or column.
    enum Alignment: Int, CaseIterable {
        case start, center, end

        var title: String {
            switch self {
            case .start: return "Start"
            case .center: return "Center"
            case .end: return "End"
            }
        }
    }

    struct Options: Equatable {
        var arrangement = Arrangement.row
        var gutter: CGFloat = 16
        var margin: CGFloat = 16
        var alignment = Alignment.center
    }

    struct Result: Equatable {
        var size: CGSize
        var frames: [CGRect]
    }

    /// How many captures can be combined.
    static let countRange = 2...9
    /// The largest canvas side in pixels, like Resize Image's limit.
    static let maxSide = 16_384

    /// A grid's default width: the squarest arrangement, so 5 captures make 3 columns and 2 rows.
    static func gridColumns(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(Double(count).squareRoot().rounded(.up))
    }

    /// The canvas size and one frame per entry of `sizes`, in order. A row is one line of cells, a column one cell
    /// wide; in a grid each column is as wide as its widest capture and each row as tall as its tallest.
    static func layout(sizes: [CGSize], options: Options) -> Result {
        guard !sizes.isEmpty else { return Result(size: .zero, frames: []) }
        let gutter = max(0, options.gutter), margin = max(0, options.margin)
        let columns: Int
        switch options.arrangement {
        case .row: columns = sizes.count
        case .column: columns = 1
        case .grid: columns = gridColumns(for: sizes.count)
        }
        let rows = (sizes.count + columns - 1) / columns

        var columnWidths = [CGFloat](repeating: 0, count: columns)
        var rowHeights = [CGFloat](repeating: 0, count: rows)
        for (i, s) in sizes.enumerated() {
            columnWidths[i % columns] = max(columnWidths[i % columns], s.width)
            rowHeights[i / columns] = max(rowHeights[i / columns], s.height)
        }

        func origins(_ lengths: [CGFloat]) -> [CGFloat] {
            var out: [CGFloat] = [], at = margin
            for l in lengths { out.append(at); at += l + gutter }
            return out
        }
        let xs = origins(columnWidths), ys = origins(rowHeights)

        func offset(_ free: CGFloat) -> CGFloat {
            switch options.alignment {
            case .start: return 0
            case .center: return free / 2
            case .end: return free
            }
        }
        let frames = sizes.enumerated().map { i, s in
            let c = i % columns, r = i / columns
            return CGRect(x: xs[c] + offset(columnWidths[c] - s.width), y: ys[r] + offset(rowHeights[r] - s.height),
                          width: s.width, height: s.height)
        }
        let width = columnWidths.reduce(0, +) + gutter * CGFloat(columns - 1) + margin * 2
        let height = rowHeights.reduce(0, +) + gutter * CGFloat(rows - 1) + margin * 2
        return Result(size: CGSize(width: width, height: height), frames: frames)
    }
}
