import CoreGraphics
import XCTest
@testable import Skreener

final class CombineLayoutTests: XCTestCase {
    private func options(_ a: CombineLayout.Arrangement, gutter: CGFloat = 0, margin: CGFloat = 0,
                         _ alignment: CombineLayout.Alignment = .start) -> CombineLayout.Options {
        CombineLayout.Options(arrangement: a, gutter: gutter, margin: margin, alignment: alignment)
    }

    func testGridColumnsAreTheCeilingOfTheSquareRoot() {
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 9].map(CombineLayout.gridColumns(for:)), [1, 2, 2, 2, 3, 3, 3, 3])
        XCTAssertEqual(CombineLayout.gridColumns(for: 0), 0)
    }

    func testRowPlacesCapturesSideBySideWithGutterAndMargin() {
        let r = CombineLayout.layout(sizes: [CGSize(width: 100, height: 50), CGSize(width: 40, height: 80)],
                                     options: options(.row, gutter: 10, margin: 5))
        XCTAssertEqual(r.frames, [CGRect(x: 5, y: 5, width: 100, height: 50), CGRect(x: 115, y: 5, width: 40, height: 80)])
        XCTAssertEqual(r.size, CGSize(width: 160, height: 90))
    }

    func testColumnStacksCapturesAndAlignsThem() {
        let sizes = [CGSize(width: 100, height: 20), CGSize(width: 40, height: 30)]
        let start = CombineLayout.layout(sizes: sizes, options: options(.column, gutter: 8, .start))
        XCTAssertEqual(start.frames[1], CGRect(x: 0, y: 28, width: 40, height: 30))
        XCTAssertEqual(start.size, CGSize(width: 100, height: 58))
        let center = CombineLayout.layout(sizes: sizes, options: options(.column, gutter: 8, .center))
        XCTAssertEqual(center.frames[1].minX, 30)
        let end = CombineLayout.layout(sizes: sizes, options: options(.column, gutter: 8, .end))
        XCTAssertEqual(end.frames[1].minX, 60)
    }

    func testRowAlignsVertically() {
        let sizes = [CGSize(width: 10, height: 100), CGSize(width: 10, height: 40)]
        XCTAssertEqual(CombineLayout.layout(sizes: sizes, options: options(.row, .start)).frames[1].minY, 0)
        XCTAssertEqual(CombineLayout.layout(sizes: sizes, options: options(.row, .center)).frames[1].minY, 30)
        XCTAssertEqual(CombineLayout.layout(sizes: sizes, options: options(.row, .end)).frames[1].minY, 60)
    }

    func testGridSizesColumnsAndRowsByTheirBiggestCapture() {
        let sizes = [CGSize(width: 100, height: 50), CGSize(width: 60, height: 80), CGSize(width: 30, height: 30)]
        let r = CombineLayout.layout(sizes: sizes, options: options(.grid, gutter: 10, margin: 20))
        // Three captures make two columns and two rows.
        XCTAssertEqual(r.frames[0], CGRect(x: 20, y: 20, width: 100, height: 50))
        XCTAssertEqual(r.frames[1], CGRect(x: 130, y: 20, width: 60, height: 80))
        XCTAssertEqual(r.frames[2], CGRect(x: 20, y: 110, width: 30, height: 30))
        XCTAssertEqual(r.size, CGSize(width: 100 + 10 + 60 + 40, height: 80 + 10 + 30 + 40))
    }

    func testFramesStayInsideTheCanvasAndNeverOverlap() {
        let sizes = (1...9).map { CGSize(width: CGFloat($0 * 17), height: CGFloat(200 - $0 * 11)) }
        for arrangement in CombineLayout.Arrangement.allCases {
            for alignment in CombineLayout.Alignment.allCases {
                let r = CombineLayout.layout(sizes: sizes, options: options(arrangement, gutter: 12, margin: 7, alignment))
                let canvas = CGRect(origin: .zero, size: r.size)
                for (i, f) in r.frames.enumerated() {
                    XCTAssertTrue(canvas.contains(f))
                    XCTAssertEqual(f.size, sizes[i])
                    for g in r.frames.dropFirst(i + 1) { XCTAssertFalse(f.intersects(g)) }
                }
            }
        }
    }

    func testNegativeSpacingIsTreatedAsZeroAndNoCapturesGiveAnEmptyCanvas() {
        let r = CombineLayout.layout(sizes: [CGSize(width: 10, height: 10), CGSize(width: 10, height: 10)],
                                     options: options(.row, gutter: -5, margin: -5))
        XCTAssertEqual(r.size, CGSize(width: 20, height: 10))
        XCTAssertEqual(CombineLayout.layout(sizes: [], options: options(.grid)), CombineLayout.Result(size: .zero, frames: []))
    }
}
