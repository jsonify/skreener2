import XCTest
@testable import Skreener

/// Watch This Area (#240): frame comparison, sensitivity and the text trigger.
final class WatchAreaTests: XCTestCase {
    /// A `width` × `height` white image with a black rectangle `black` (pixels, bottom-left origin) on it.
    private func image(width: Int = 200, height: Int = 100, black: CGRect? = nil, gray: CGFloat = 0) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let black {
            ctx.setFillColor(CGColor(gray: gray, alpha: 1))
            ctx.fill(black)
        }
        return ctx.makeImage()!
    }

    func testGrayscaleIsAFixedSizeThumbnail() {
        let white = WatchMath.grayscale(image())
        XCTAssertEqual(white.count, WatchMath.side * WatchMath.side)
        XCTAssertTrue(white.allSatisfy { $0 > 250 })
        let black = WatchMath.grayscale(image(black: CGRect(x: 0, y: 0, width: 200, height: 100)))
        XCTAssertTrue(black.allSatisfy { $0 < 5 })
    }

    func testTransparentPixelsCountAsWhite() {
        let ctx = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let clear = WatchMath.grayscale(ctx.makeImage()!)
        XCTAssertTrue(clear.allSatisfy { $0 > 250 })
    }

    func testMeanDifference() {
        XCTAssertEqual(WatchMath.meanDifference([0, 0, 0, 0], [0, 0, 0, 0]), 0)
        XCTAssertEqual(WatchMath.meanDifference([0, 0, 0, 0], [255, 255, 255, 255]), 1)
        XCTAssertEqual(WatchMath.meanDifference([0, 0, 0, 0], [255, 0, 0, 0]), 0.25, accuracy: 1e-9)
        XCTAssertEqual(WatchMath.meanDifference([10, 20], [20, 10]), 10.0 / 255, accuracy: 1e-9)
        // Thumbnails that don't match count as completely different.
        XCTAssertEqual(WatchMath.meanDifference([0, 0], [0]), 1)
        XCTAssertEqual(WatchMath.meanDifference([], []), 1)
    }

    func testSameFramesDoNotChange() {
        let a = WatchMath.grayscale(image(black: CGRect(x: 20, y: 20, width: 40, height: 30)))
        let b = WatchMath.grayscale(image(black: CGRect(x: 20, y: 20, width: 40, height: 30)))
        let d = WatchMath.meanDifference(a, b)
        XCTAssertEqual(d, 0, accuracy: 1e-9)
        for s in WatchSettings.Sensitivity.allCases { XCTAssertFalse(WatchMath.changed(d, sensitivity: s)) }
    }

    func testSensitivityDecidesWhatCountsAsAChange() {
        let base = WatchMath.grayscale(image())
        // A tenth of the area turns black: every sensitivity notices.
        let big = WatchMath.meanDifference(base, WatchMath.grayscale(image(black: CGRect(x: 0, y: 0, width: 20, height: 100))))
        XCTAssertEqual(big, 0.1, accuracy: 0.02)
        for s in WatchSettings.Sensitivity.allCases { XCTAssertTrue(WatchMath.changed(big, sensitivity: s), "\(s)") }
        // A small mid-gray mark (about 1.5% of the area, half as dark as black): only High notices.
        let small = WatchMath.meanDifference(base, WatchMath.grayscale(image(black: CGRect(x: 100, y: 40, width: 30, height: 10),
                                                                             gray: 0.5)))
        XCTAssertTrue(WatchMath.changed(small, sensitivity: .high))
        XCTAssertFalse(WatchMath.changed(small, sensitivity: .medium))
        XCTAssertFalse(WatchMath.changed(small, sensitivity: .low))
    }

    func testThresholdsGoFromLowToHigh() {
        XCTAssertGreaterThan(WatchSettings.Sensitivity.low.threshold, WatchSettings.Sensitivity.medium.threshold)
        XCTAssertGreaterThan(WatchSettings.Sensitivity.medium.threshold, WatchSettings.Sensitivity.high.threshold)
        XCTAssertTrue(WatchMath.changed(WatchSettings.Sensitivity.medium.threshold, sensitivity: .medium))
        XCTAssertFalse(WatchMath.changed(WatchSettings.Sensitivity.medium.threshold * 0.99, sensitivity: .medium))
    }

    func testTextFound() {
        XCTAssertTrue(WatchMath.textFound("Passed", in: "Tests: 12\nPASSED in 3.2 s"))
        XCTAssertTrue(WatchMath.textFound("Build succeeded", in: "Build\nsucceeded"))
        XCTAssertTrue(WatchMath.textFound("  Done ", in: "All done."))
        XCTAssertFalse(WatchMath.textFound("Pass", in: "Password"))
        XCTAssertFalse(WatchMath.textFound("Passed", in: "Failed"))
        XCTAssertFalse(WatchMath.textFound("", in: "anything"))
        XCTAssertFalse(WatchMath.textFound("Passed", in: ""))
    }

    func testTextTriggerFiresOnTheChangeOnly() {
        // The first check only sets the starting point.
        XCTAssertFalse(WatchMath.textFires(.textAppears, wasPresent: nil, isPresent: true))
        XCTAssertFalse(WatchMath.textFires(.textDisappears, wasPresent: nil, isPresent: false))
        XCTAssertTrue(WatchMath.textFires(.textAppears, wasPresent: false, isPresent: true))
        XCTAssertFalse(WatchMath.textFires(.textAppears, wasPresent: true, isPresent: true))
        XCTAssertFalse(WatchMath.textFires(.textAppears, wasPresent: true, isPresent: false))
        XCTAssertTrue(WatchMath.textFires(.textDisappears, wasPresent: true, isPresent: false))
        XCTAssertFalse(WatchMath.textFires(.textDisappears, wasPresent: false, isPresent: false))
        XCTAssertFalse(WatchMath.textFires(.textDisappears, wasPresent: false, isPresent: true))
        XCTAssertFalse(WatchMath.textFires(.change, wasPresent: false, isPresent: true))
    }

    func testSideBySide() {
        let both = WatchMath.sideBySide(image(width: 200, height: 100), image(width: 100, height: 100), height: 50, gap: 10)
        XCTAssertEqual(both?.height, 50)
        XCTAssertEqual(both?.width, 100 + 10 + 50)
    }

    func testSettingsRoundTripAndValidity() {
        let defaults = UserDefaults(suiteName: "WatchAreaTests")!
        defaults.removePersistentDomain(forName: "WatchAreaTests")
        defer { defaults.removePersistentDomain(forName: "WatchAreaTests") }
        XCTAssertEqual(WatchSettings.load(from: defaults), WatchSettings())
        var s = WatchSettings()
        s.interval = .fiveSeconds
        s.trigger = .textAppears
        s.sensitivity = .high
        s.text = " Passed "
        s.keepWatching = true
        s.save(to: defaults)
        XCTAssertEqual(WatchSettings.load(from: defaults), s)
        XCTAssertTrue(s.isValid)
        XCTAssertEqual(s.notificationTitle(watching: "window"), "“Passed” appeared in the watched window")
        s.text = "  "
        XCTAssertFalse(s.isValid)
        s.trigger = .change
        XCTAssertTrue(s.isValid)
        XCTAssertEqual(s.notificationTitle(watching: "area"), "The watched area changed")
    }
}
