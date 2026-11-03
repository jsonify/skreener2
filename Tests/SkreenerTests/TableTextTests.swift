import XCTest
@testable import Skreener

/// Capture Table's layout and writers (#248), on made-up OCR words: no screen needed, except the last test, which
/// reads a drawn table with Vision.
final class TableTextTests: XCTestCase {
    private let cw: CGFloat = 10   // character width of the made-up text
    private let height: CGFloat = 20
    private let pitch: CGFloat = 30

    /// A word `row` rows from the top (bottom-left origin) starting at `x`.
    private func word(_ text: String, row: Int, x: CGFloat) -> TableText.Word {
        TableText.Word(text: text, rect: CGRect(x: x, y: 800 - CGFloat(row) * pitch, width: CGFloat(text.count) * cw, height: height))
    }

    /// The words of `cells` in one row, each cell starting at its column's x and split into words a space apart.
    private func row(_ cells: [String?], row: Int, columns: [CGFloat]) -> [TableText.Word] {
        zip(cells, columns).flatMap { cell, x -> [TableText.Word] in
            guard let cell else { return [] }
            var out: [TableText.Word] = []
            var at = x
            for part in cell.split(separator: " ") {
                out.append(word(String(part), row: row, x: at))
                at += CGFloat(part.count + 1) * cw
            }
            return out
        }
    }

    private let columns: [CGFloat] = [100, 300, 500]

    // MARK: Layout

    func testEmptyInput() {
        XCTAssertEqual(TableText.grid([]), [])
        XCTAssertEqual(TableText.grid([word("  ", row: 0, x: 0)]), [])
    }

    func testSimpleTable() {
        let words = row(["Name", "Age", "City"], row: 0, columns: columns)
            + row(["Ann", "31", "Paris"], row: 1, columns: columns)
            + row(["Bob", "4", "Rome"], row: 2, columns: columns)
        XCTAssertEqual(TableText.grid(words), [["Name", "Age", "City"], ["Ann", "31", "Paris"], ["Bob", "4", "Rome"]])
    }

    func testInputOrderDoesNotMatter() {
        let words = row(["Name", "Age", "City"], row: 0, columns: columns)
            + row(["Ann", "31", "Paris"], row: 1, columns: columns)
        XCTAssertEqual(TableText.grid(words.reversed()), TableText.grid(words))
    }

    func testWordsOfOneCellStayTogether() {
        let words = row(["Product", "Price", "Notes"], row: 0, columns: columns)
            + row(["Blue Widget XL", "$1,200.00", "Back in stock"], row: 1, columns: columns)
        XCTAssertEqual(TableText.grid(words), [["Product", "Price", "Notes"], ["Blue Widget XL", "$1,200.00", "Back in stock"]])
    }

    func testEmptyCellKeepsItsColumn() {
        let words = row(["A", "B", "C"], row: 0, columns: columns)
            + row(["1", nil, "3"], row: 1, columns: columns)
            + row([nil, "5", "6"], row: 2, columns: columns)
        XCTAssertEqual(TableText.grid(words), [["A", "B", "C"], ["1", "", "3"], ["", "5", "6"]])
    }

    func testSlightlyUnevenBaselinesShareARow() {
        var words = row(["Name", "Age", "City"], row: 0, columns: columns)
        words[1].rect.origin.y += 4
        words[2].rect.origin.y -= 3
        XCTAssertEqual(TableText.grid(words), [["Name", "Age", "City"]])
    }

    func testRightAlignedNumbersStayInTheirColumn() {
        // Numbers of different lengths end at the same x.
        let words = [word("Item", row: 0, x: 100), word("Qty", row: 0, x: 370),
                     word("Pens", row: 1, x: 100), word("1200", row: 1, x: 360),
                     word("Ink", row: 2, x: 100), word("7", row: 2, x: 390)]
        XCTAssertEqual(TableText.grid(words), [["Item", "Qty"], ["Pens", "1200"], ["Ink", "7"]])
    }

    func testATitleSpanningTheColumnsDoesNotMergeThem() {
        // A title row over a long table sits across the gutters; with enough rows, the gutters still count.
        var words = [word("Quarterly results for every region", row: 0, x: 100)]
        for r in 1...9 { words += row(["R\(r)", "\(r * 10)", "ok"], row: r, columns: columns) }
        let grid = TableText.grid(words)
        XCTAssertEqual(grid.count, 10)
        XCTAssertEqual(grid[1], ["R1", "10", "ok"])
        XCTAssertEqual(grid[9], ["R9", "90", "ok"])
    }

    func testNarrowGapsBetweenWordsAreNotColumns() {
        // Two rows whose word gaps happen to line up: one space is not a gutter.
        let words = [word("New", row: 0, x: 100), word("York", row: 0, x: 140),
                     word("Old", row: 1, x: 100), word("Town", row: 1, x: 140)]
        XCTAssertEqual(TableText.grid(words), [["New York"], ["Old Town"]])
    }

    func testNormalizedPadsShortRowsAndDropsEmptyOnes() {
        XCTAssertEqual(TableText.normalized([[" a ", "b"], ["", " "], ["c"], ["d", "", ""]]),
                       [["a", "b"], ["c", ""], ["d", ""]])
    }

    // MARK: Writing

    private let sample: TableText.Grid = [["Name", "Amount"], ["Ann", "12.50"], ["Bob", "3"]]

    func testCSV() {
        XCTAssertEqual(TableText.csv(sample), "Name,Amount\nAnn,12.50\nBob,3")
    }

    func testCSVQuotesWhatNeedsIt() {
        XCTAssertEqual(TableText.csv([["a,b", "say \"hi\"", " pad", "plain"]]), "\"a,b\",\"say \"\"hi\"\"\",\" pad\",plain")
    }

    func testTSV() {
        XCTAssertEqual(TableText.tsv(sample), "Name\tAmount\nAnn\t12.50\nBob\t3")
        XCTAssertEqual(TableText.tsv([["a\tb", "c\nd"]]), "a b\tc d")
    }

    func testMarkdownAlignsAndRightAlignsNumbers() {
        XCTAssertEqual(TableText.markdown(sample), """
        | Name | Amount |
        | ---- | -----: |
        | Ann  |  12.50 |
        | Bob  |      3 |
        """)
    }

    func testMarkdownEscapesPipes() {
        XCTAssertEqual(TableText.markdown([["a|b"], ["c"]]), """
        | a\\|b |
        | ---- |
        | c    |
        """)
    }

    func testMarkdownOfNothing() {
        XCTAssertEqual(TableText.markdown([]), "")
    }

    func testHTMLEscapesAndHeadsTheFirstRow() {
        XCTAssertEqual(TableText.html([["A&B"], ["<1>"]]), "<table><tr><th>A&amp;B</th></tr><tr><td>&lt;1&gt;</td></tr></table>")
    }

    func testNumbers() {
        for yes in ["3", "-4", "12.50", "1,200", "$1,200.00", "45%", "(300)", "€9"] { XCTAssertTrue(TableText.isNumber(yes), yes) }
        for no in ["", "abc", "12 apples", "v1.2b", "-"] { XCTAssertFalse(TableText.isNumber(no), no) }
    }

    func testTextPicksTheFormat() {
        XCTAssertEqual(TableText.text(sample, as: .csv), TableText.csv(sample))
        XCTAssertEqual(TableText.text(sample, as: .tsv), TableText.tsv(sample))
        XCTAssertEqual(TableText.text(sample, as: .markdown), TableText.markdown(sample))
    }

    // MARK: Vision

    func testReadsADrawnTable() async {
        let cells = [["Fruit", "Count", "Color"], ["Apple", "12", "Red"], ["Banana", "7", "Yellow"]]
        let image = TestImages.image(width: 1200, height: 420) { r in
            NSColor.white.setFill()
            r.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black]
            for (i, row) in cells.enumerated() {
                for (j, cell) in row.enumerated() {
                    NSAttributedString(string: cell, attributes: attrs)
                        .draw(at: NSPoint(x: 40 + CGFloat(j) * 400, y: r.height - CGFloat(i + 1) * 130 + 30))
                }
            }
        }
        let grid = await TextRecognizer.table(in: image)
        XCTAssertEqual(grid, cells)
    }
}
