import XCTest
@testable import Skreener

final class SpotlightTests: XCTestCase {
    func testSettingsAreClamped() {
        XCTAssertEqual(Spotlight.clampedRadius(0), Spotlight.radiusRange.lowerBound)
        XCTAssertEqual(Spotlight.clampedRadius(10_000), Spotlight.radiusRange.upperBound)
        XCTAssertEqual(Spotlight.clampedRadius(120), 120)
        XCTAssertEqual(Spotlight.clampedDim(-5), Spotlight.dimRange.lowerBound)
        XCTAssertEqual(Spotlight.clampedDim(100), Spotlight.dimRange.upperBound)
        XCTAssertEqual(Spotlight.clampedDim(50), 50)
    }

    func testPresetsAreInRange() {
        for (_, r) in Spotlight.radii { XCTAssertEqual(Spotlight.clampedRadius(r), r) }
        for (_, d) in Spotlight.dims { XCTAssertEqual(Spotlight.clampedDim(d), d) }
    }

    func testLocalPointSubtractsAreaOrigin() {
        let p = Spotlight.localPoint(global: CGPoint(x: 1500, y: 300), areaOrigin: CGPoint(x: 1440, y: 100))
        XCTAssertEqual(p, CGPoint(x: 60, y: 200))
        // Outside the area it goes negative rather than clamping.
        XCTAssertEqual(Spotlight.localPoint(global: CGPoint(x: 10, y: 10), areaOrigin: CGPoint(x: 50, y: 50)), CGPoint(x: -40, y: -40))
    }

    func testSquareIsCenteredOnPointer() {
        XCTAssertEqual(Spotlight.square(center: CGPoint(x: 100, y: 80), radius: 30), CGRect(x: 70, y: 50, width: 60, height: 60))
    }

    private func area(_ rects: [CGRect]) -> CGFloat { rects.reduce(0) { $0 + $1.width * $1.height } }

    func testSurroundCoversEverythingOutsideTheSquareOnce() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let square = CGRect(x: 100, y: 50, width: 80, height: 80)
        let rects = Spotlight.surround(of: square, in: bounds)
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(area(rects), bounds.width * bounds.height - 80 * 80)
        for (i, a) in rects.enumerated() {
            XCTAssertFalse(a.intersects(square))
            for b in rects[(i + 1)...] { XCTAssertTrue(a.intersection(b).isNull || a.intersection(b).isEmpty) }
        }
    }

    func testSurroundClipsASquareAtTheEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let square = CGRect(x: -40, y: 250, width: 100, height: 100)
        let rects = Spotlight.surround(of: square, in: bounds)
        XCTAssertEqual(area(rects), bounds.width * bounds.height - 60 * 50)
        XCTAssertTrue(rects.allSatisfy { bounds.contains($0) })
    }

    func testSurroundOfASquareOffTheAreaIsTheWholeArea() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(Spotlight.surround(of: CGRect(x: 900, y: 900, width: 50, height: 50), in: bounds), [bounds])
    }

    func testStopsGoFromClearToFullDim() {
        let stops = Spotlight.stops(dim: 0.6)
        XCTAssertEqual(stops.first?.alpha, 0)
        XCTAssertEqual(stops.last?.alpha ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertEqual(stops.last?.location, 1)
        XCTAssertEqual(stops.map(\.location), stops.map(\.location).sorted())
        XCTAssertEqual(stops.map(\.alpha), stops.map(\.alpha).sorted())
    }

    func testStopsClampTheDim() {
        XCTAssertEqual(Spotlight.stops(dim: 3).last?.alpha, 1)
        XCTAssertEqual(Spotlight.stops(dim: -1).last?.alpha, 0)
    }
}
