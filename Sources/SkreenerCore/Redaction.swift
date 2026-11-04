import CoreGraphics
import CoreImage
import Foundation

// A plain enum of cases; Redaction carries it across actors (iOS exports run off the main actor).
extension RedactText.Cover: @unchecked Sendable {}

/// A covered area of a screenshot, for the iOS Share Extension (#396): a rect in image pixels (bottom-left origin,
/// like the canvas) and how it is covered. The Mac editor still draws its own pixelate and blur annotations.
public struct Redaction: Equatable, Sendable {
    public var rect: CGRect
    /// `.solid`, `.pixelate` or `.blur`. `.erase` is drawn as `.solid` (it needs the editor's color guess).
    public var style: RedactText.Cover

    public init(rect: CGRect, style: RedactText.Cover) {
        self.rect = rect
        self.style = style
    }

    /// The same redaction on an image `k` times as wide (the preview is smaller than the export).
    public func scaled(by k: CGFloat) -> Redaction {
        Redaction(rect: CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k),
                  style: style)
    }

    /// Pixelate's cell size on an image `width` pixels wide: 1/40 of the width, at least 4 px. About the Mac's
    /// default (10 points) on a 3x iPhone screenshot (1179 px: 29 px), and the same share of the picture at any size,
    /// so the preview looks like the export.
    public static func blockSize(imageWidth width: Int) -> CGFloat { max(4, CGFloat(width) / 40) }

    /// Blur's sigma on an image `width` pixels wide: 1/50 of the width (24 px on a 1179 px screenshot), at least 2 px.
    public static func blurSigma(imageWidth width: Int) -> CGFloat { max(2, CGFloat(width) / 50) }

    /// Draws `redactions` over `image`, which `ctx` already shows in `CGRect(0, 0, width, height)` (y-up, one unit
    /// per image pixel). Each is clipped to the image. Safe off the main actor: nothing is cached between calls.
    public static func draw(_ redactions: [Redaction], over image: CGImage, in ctx: CGContext) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var ci: CIContext?
        for redaction in redactions {
            let rect = redaction.rect.standardized.intersection(bounds)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { continue }
            ctx.saveGState()
            ctx.clip(to: rect)
            switch redaction.style {
            case .solid, .erase:
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.fill(rect)
            case .pixelate:
                drawPixelated(rect, image: image, in: ctx)
            case .blur:
                let context = ci ?? CIContext(options: [.cacheIntermediates: false])
                ci = context
                drawBlurred(rect, image: image, in: ctx, context: context)
            }
            ctx.restoreGState()
        }
    }

    /// `rect` (inside the image) as whole pixels from the top-left, as `CGImage.cropping(to:)` takes it, and the same
    /// area y-up.
    private static func pixelArea(_ rect: CGRect, imageHeight h: Int) -> (topLeft: CGRect, yUp: CGRect) {
        let up = rect.integral
        return (CGRect(x: up.minX, y: CGFloat(h) - up.maxY, width: up.width, height: up.height), up)
    }

    /// Blocks like the Mac's: cells from the rect's corner, each filled with the image's color at the cell's center.
    private static func drawPixelated(_ rect: CGRect, image: CGImage, in ctx: CGContext) {
        let area = pixelArea(rect, imageHeight: image.height)
        // Only the covered part is read, so a large image doesn't need a second full copy.
        guard let crop = image.cropping(to: area.topLeft), let pixels = PixelBuffer(crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let block = blockSize(imageWidth: image.width)
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let cell = CGRect(x: x, y: y, width: min(block, rect.maxX - x), height: min(block, rect.maxY - y))
                // PixelBuffer's row 0 is the crop's top.
                let px = min(max(Int((cell.midX - area.yUp.minX).rounded(.down)), 0), pixels.width - 1)
                let py = min(max(Int((area.yUp.maxY - cell.midY).rounded(.down)), 0), pixels.height - 1)
                if let c = pixels.color(x: px, y: py),
                   let color = CGColor(colorSpace: space, components: [c.r, c.g, c.b, c.a].map { CGFloat($0) }) {
                    ctx.setFillColor(color)
                    ctx.fill(cell)
                }
                x += block
            }
            y += block
        }
    }

    /// A gaussian blur of the area around `rect` (edges clamped, so the image's border doesn't darken), drawn in it.
    private static func drawBlurred(_ rect: CGRect, image: CGImage, in ctx: CGContext, context: CIContext) {
        let sigma = blurSigma(imageWidth: image.width)
        let margin = (sigma * 3).rounded(.up)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let around = rect.insetBy(dx: -margin, dy: -margin).intersection(bounds)
        let area = pixelArea(around, imageHeight: image.height)
        guard let crop = image.cropping(to: area.topLeft) else { return }
        let input = CIImage(cgImage: crop)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: input.extent)
        guard let blurred = context.createCGImage(output, from: input.extent) else { return }
        ctx.draw(blurred, in: CGRect(x: area.yUp.minX, y: area.yUp.minY, width: CGFloat(crop.width),
                                     height: CGFloat(crop.height)))
    }
}
