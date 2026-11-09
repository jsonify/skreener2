import SkreenerCore
import SwiftUI

/// The keys in the editor's tool tray (#440), in order. Frame is the Style mode, Redact the Redact mode, and the rest
/// are Draw with that tool, so picking one sets the model's mode (and tool).
enum EditorTool: CaseIterable, Hashable {
    case frame, arrow, rect, text, highlight, redact

    var title: String {
        switch self {
        case .frame: return "Frame"
        case .arrow: return "Arrow"
        case .rect: return "Rectangle"
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
        case .rect: return "rectangle"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .redact: return "checkerboard.rectangle"
        }
    }

    /// The Draw tool it stands for; nil for Frame and Redact.
    var drawTool: ShareModel.Tool? {
        switch self {
        case .arrow: return .arrow
        case .rect: return .rect
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
                case .rect: return .rect
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

    /// The LCD strip's short line for the lit tool, e.g. "Red · drag to draw".
    var toolHint: String {
        switch editorTool {
        case .frame:
            var parts = [frameChoice.title]
            if let fill = backgroundChoice {
                parts.append(Background.presets[fill].name)
                parts.append("Padding \(Int(padding))")
            }
            return parts.joined(separator: " · ")
        case .arrow, .rect:
            return "\(markupColorName) · drag to draw"
        case .highlight:
            return "\(markupColorName) · drag across text"
        case .text:
            return "\(markupColorName) · tap where the text goes"
        case .redact:
            return "\(redactStyle.title) · drag to cover"
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
