import CoreGraphics

/// How many pixels an image may keep when it is loaded: a cap on the long side and on the area. The iOS Share
/// Extension (about 120 MB of memory) and the app (no such limit) use different budgets (#441).
public struct PixelBudget: Equatable, Sendable {
    /// The longest side, in pixels.
    public let maxSide: Int
    /// Width times height, in pixels.
    public let maxArea: Int

    public init(maxSide: Int, maxArea: Int) {
        self.maxSide = max(maxSide, 1)
        self.maxArea = max(maxArea, 1)
    }

    /// The Share Extension's: 4096 px on the long side (16.8 MP at most).
    public static let shareExtension = PixelBudget(maxSide: 4096, maxArea: 4096 * 4096)

    /// The app's: 8192 px on the long side and 40 MP. A 48 MP camera photo (8064 x 6048) is kept at about 7300 x 5480.
    public static let app = PixelBudget(maxSide: 8192, maxArea: 40_000_000)

    /// The longest side to decode a `width` x `height` image at: its own, unless that is over the budget. Never
    /// upscales, and keeps the aspect ratio within rounding down (so the area stays inside the budget).
    public func longSide(width: Int, height: Int) -> Int {
        let long = max(width, height)
        guard width > 0, height > 0 else { return min(long, maxSide) }
        var scale = min(1, Double(maxSide) / Double(long))
        let area = Double(width) * Double(height) * scale * scale
        if area > Double(maxArea) { scale *= (Double(maxArea) / area).squareRoot() }
        return max(Int((Double(long) * scale).rounded(.down)), 1)
    }

    /// This budget tightened to at most `side` on the long side (for work that doesn't need the full image, like OCR).
    public func bounded(toSide side: Int) -> PixelBudget {
        PixelBudget(maxSide: min(maxSide, side), maxArea: min(maxArea, side * side))
    }
}
