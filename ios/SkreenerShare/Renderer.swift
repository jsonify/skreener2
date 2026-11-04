import CoreGraphics
import SkreenerCore
import UIKit

/// Draws a screenshot with its device frame and background, the same way the Mac editor's canvas does, using
/// SkreenerCore. Kept apart from the view code so the save and copy steps can reuse it.
enum Renderer {
    /// The whole picture's rect: the frame around the screenshot, then the background's margin around that.
    /// `content` is the screenshot's own rect, at the origin.
    static func canvas(for content: CGRect, frame: DeviceFrame?, background: Background?) -> CGRect {
        let framed = frame.map { $0.layout(around: content).outer } ?? content
        guard let background else { return framed }
        return Background.canvas(around: framed, margin: background.padding + background.inset, aspect: background.aspect)
    }

    /// One image pixel is one point, and the renderer's scale is 1, so the result has the canvas's size in pixels.
    static func render(image: CGImage, frame: DeviceFrame?, background: Background?) -> UIImage {
        let content = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // A frame of kind .none means no frame.
        let frame = frame?.isNone == true ? nil : frame
        let bounds = canvas(for: content, frame: frame, background: background)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // SkreenerCore draws y-up like the Mac canvas. Flip UIKit's context, and move the canvas's origin (the
        // padding makes it negative) to the corner.
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { rendered in
            let ctx = rendered.cgContext
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            ctx.saveGState()
            let black = CGColor(gray: 0, alpha: 1)
            let layout = Framing.drawUnderlay(in: ctx, bounds: bounds, content: content,
                                              frame: frame, background: background,
                                              picture: nil, fallback: black, backdrop: black)
            // A device's screen is bigger than the screenshot when the shapes differ: black around it.
            if let screen = layout?.screen, screen != content {
                ctx.setFillColor(black)
                ctx.fill(screen)
            }
            ctx.draw(image, in: content)
            ctx.restoreGState()
        }
    }
}
