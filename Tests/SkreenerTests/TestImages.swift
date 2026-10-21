import AppKit

/// Images drawn in code for the tests.
enum TestImages {
    /// A `width` × `height` pixel RGBA bitmap shown at `points` (half the pixels each way for a Retina image), drawn
    /// by `draw` in point coordinates (bottom-left origin).
    static func image(width: Int, height: Int, points: NSSize? = nil, draw: (NSRect) -> Void) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let size = points ?? NSSize(width: width, height: height)
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Fully transparent.
    static func clear(width: Int, height: Int, points: NSSize? = nil) -> NSImage {
        image(width: width, height: height, points: points) { r in
            NSColor.clear.setFill()
            r.fill(using: .copy)
        }
    }

    /// Black 48 pt text on white, one line per 120 px band (the first line at the top).
    static func text(_ lines: [String]) -> NSImage {
        image(width: 1000, height: 120 * lines.count) { r in
            NSColor.white.setFill()
            r.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
            for (i, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: attrs)
                    .draw(at: NSPoint(x: 40, y: r.height - CGFloat(i + 1) * 120 + 30))
            }
        }
    }
}
