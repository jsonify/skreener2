import AppKit
import SkreenerCore

extension RedactText {
    /// One annotation per box, covering it as `cover` says, in `style` otherwise (strength, shadow). Solid is an
    /// opaque black filled rectangle with square corners; pixelate is never too fine to hide the text.
    static func annotations(_ boxes: [CGRect], cover: Cover, style: Style) -> [Annotation] {
        var s = style
        s.textOnly = false   // the whole box: it is already just the text
        let tool: Tool
        switch cover {
        case .solid:
            tool = .filledRect
            s.color = .black
            s.cornerRadius = 0
        case .pixelate:
            tool = .pixelate
            s.pixelSize = max(s.pixelSize, 8)
        case .blur: tool = .blur
        case .erase: tool = .erase
        }
        return boxes.map { Annotation(tool: tool, start: $0.origin, end: NSPoint(x: $0.maxX, y: $0.maxY), style: s) }
    }
}
