import XCTest
@testable import SkreenerCore

final class PixelBudgetTests: XCTestCase {
    func testSmallImagesAreNeverUpscaled() {
        XCTAssertEqual(PixelBudget.app.longSide(width: 1320, height: 2868), 2868)
        XCTAssertEqual(PixelBudget.shareExtension.longSide(width: 1320, height: 2868), 2868)
    }

    func testExtensionKeepsTheOldFourThousandNinetySixLimit() {
        XCTAssertEqual(PixelBudget.shareExtension.longSide(width: 8064, height: 6048), 4096)
        XCTAssertEqual(PixelBudget.shareExtension.longSide(width: 1179, height: 30_000), 4096)
    }

    func testAppCapsTheLongSide() {
        XCTAssertEqual(PixelBudget.app.longSide(width: 1179, height: 30_000), 8192)
    }

    func testAppCapsTheArea() {
        let side = PixelBudget.app.longSide(width: 8064, height: 6048)
        XCTAssertLessThan(side, 8064)
        let w = Double(side), h = Double(side) * 6048 / 8064
        XCTAssertLessThanOrEqual(w * h, 40_000_000)
        XCTAssertGreaterThan(w * h, 38_000_000)
    }

    func testBoundedNeverLoosensTheBudget() {
        XCTAssertEqual(PixelBudget.app.bounded(toSide: 4096).longSide(width: 8064, height: 6048), 4096)
        XCTAssertEqual(PixelBudget.shareExtension.bounded(toSide: 9000), .shareExtension)
    }
}
