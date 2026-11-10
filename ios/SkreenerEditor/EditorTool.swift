import SkreenerCore
import SwiftUI

/// The editor's tools (#440). Frame is the Style mode, Redact the Redact mode, and the rest are Draw with that tool, so
/// picking one sets the model's mode (and tool). The bottom row's keys are `ToolKey`s: the shapes share the Draw key.
enum EditorTool: CaseIterable, Hashable {
    case frame, arrow, line, rect, ellipse, pen, text, highlight, redact

    /// The Draw key's shapes, in its flyout's order, top to bottom. Six 44 pt keys in one column take about 310 pt,
    /// which fits above the Draw key with room to spare even on a 667 pt iPhone SE (about 530 pt between the top bar
    /// and the key there).
    static let shapes: [EditorTool] = [.arrow, .line, .rect, .ellipse, .pen, .highlight]

    /// One of the Draw key's shapes.
    var isShape: Bool { Self.shapes.contains(self) }

    var title: String {
        switch self {
        case .frame: return "Frame"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .text: return "Text"
        case .highlight: return "Highlight"
        case .redact: return "Redact"
        }
    }

    /// Its key's SF Symbol.
    var symbol: String {
        switch self {
        case .frame: return "photo.artframe"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "scribble"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .redact: return "checkerboard.rectangle"
        }
    }

    /// The Draw tool it stands for; nil for Frame and Redact.
    var drawTool: ShareModel.Tool? {
        switch self {
        case .arrow: return .arrow
        case .line: return .line
        case .rect: return .rect
        case .ellipse: return .ellipse
        case .pen: return .pen
        case .text: return .text
        case .highlight: return .highlight
        case .frame, .redact: return nil
        }
    }
}

extension ShareModel {
    /// The tool tray's lit key, from the mode and the Draw tool; setting it sets them. Safe Check's Review, which
    /// switches to Redact, lights Redact.
    var editorTool: EditorTool {
        get {
            switch mode {
            case .style: return .frame
            case .redact: return .redact
            case .draw:
                switch tool {
                case .arrow: return .arrow
                case .line: return .line
                case .rect: return .rect
                case .ellipse: return .ellipse
                case .pen: return .pen
                case .text: return .text
                case .highlight: return .highlight
                }
            }
        }
        set {
            if let drawTool = newValue.drawTool {
                tool = drawTool
                mode = .draw
            } else {
                mode = newValue == .frame ? .style : .redact
            }
        }
    }

    /// The markup colour's name ("Red"...).
    var markupColorName: String {
        Self.markupColors.first { $0.color == markupColor }?.name ?? "Custom"
    }

    /// The LCD strip's short line after the lit tool's name: Frame's look ("iPhone · Sky · Padding 48"), Redact's
    /// cover ("Pixelate · drag to cover"), or what to do with a shape or Text ("drag to draw"; the strip reads
    /// "ARROW · DRAG TO DRAW"), or, with a drawing or area selected, that it can be dragged.
    var toolHint: String {
        if selectedMarkup != nil { return "selected · drag to move" }
        if selectedRedaction != nil { return "area selected · drag to move" }
        switch editorTool {
        case .frame:
            var parts = [frameChoice.title]
            if let fill = backgroundChoice {
                parts.append(Background.presets[fill].name)
                parts.append("Padding \(Int(padding))")
            }
            return parts.joined(separator: " · ")
        case .arrow, .line, .rect, .ellipse:
            return "drag to draw"
        case .pen:
            return "draw freely"
        case .highlight:
            return "drag across text"
        case .text:
            return "tap where it goes"
        case .redact:
            return "\(redactStyle.title) · drag to cover"
        }
    }
}

/// The bottom row's tool keys (#440), left to right: they always fit a 375 pt phone, so the row never scrolls.
/// Draw stands for the shapes (`EditorTool.shapes`), showing the last one used.
enum ToolKey: CaseIterable, Hashable {
    case frame, draw, text, redact

    /// Lit for `tool`.
    func isLit(for tool: EditorTool) -> Bool {
        switch self {
        case .frame: return tool == .frame
        case .draw: return tool.isShape
        case .text: return tool == .text
        case .redact: return tool == .redact
        }
    }

    /// The tool it picks when it is not lit; Draw picks the last shape used.
    func tool(lastShape: EditorTool) -> EditorTool {
        switch self {
        case .frame: return .frame
        case .draw: return lastShape
        case .text: return .text
        case .redact: return .redact
        }
    }
}

extension ShareModel.FrameChoice {
    /// The frame's name on its key and in the LCD.
    var title: String {
        switch self {
        case .plain: return "None"
        case .iPhone: return "iPhone"
        case .browser: return "Browser"
        case .macWindow: return "macOS Window"
        }
    }

    /// Its key's SF Symbol.
    var symbol: String {
        switch self {
        case .plain: return "square.dashed"
        case .iPhone: return "iphone"
        case .browser: return "globe"
        case .macWindow: return "macwindow"
        }
    }

    static let all: [Self] = [.plain, .iPhone, .browser, .macWindow]
}

/// Colours for SwiftUI from SkreenerCore's.
extension RGBColor {
    var swiftUI: Color { Color(red: r, green: g, blue: b, opacity: a) }
}

extension ShareModel {
    /// A background choice's colours for its swatch; empty for no background.
    static func swatchColors(_ fill: Int?) -> [Color] {
        guard let fill else { return [] }
        return Background.presets[fill].colors.map(\.swiftUI)
    }

    static func backgroundName(_ fill: Int?) -> String {
        fill.map { Background.presets[$0].name } ?? "No background"
    }
}
