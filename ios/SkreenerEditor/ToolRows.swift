import SkreenerCore
import SK1Tokens
import SK1UI
import SwiftUI

/// The editor's bottom row with the tools showing (#440): the tray of tool keys (Frame, Draw, Text, Redact) and the
/// round colour key. It always fits a 375 pt phone, so nothing at the bottom of the screen scrolls sideways (a sideways
/// swipe there is the system's, to switch apps). Tapping the lit Frame, Text or Redact key opens its options
/// (`onOptions`); tapping the lit Draw key opens the shapes (`onShapes`).
struct ToolRow: View {
    @ObservedObject var model: ShareModel
    /// The shape the Draw key shows and picks.
    let lastShape: EditorTool
    let onOptions: () -> Void
    let onShapes: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PhoneKeyTray(label: "Tools") {
                ForEach(ToolKey.allCases, id: \.self) { key in
                    if key == .draw {
                        DrawKey(model: model, lastShape: lastShape, onShapes: onShapes)
                    } else {
                        toolKey(key)
                    }
                }
            }
            Spacer(minLength: 0)
            ColorKey(model: model)
        }
    }

    private func toolKey(_ key: ToolKey) -> some View {
        let tool = key.tool(lastShape: lastShape)
        let lit = key.isLit(for: model.editorTool)
        return SymbolKey(symbol: tool.symbol, label: tool.title, isOn: lit,
                         hint: lit ? "Shows the \(tool.title) options" : nil) {
            if lit {
                onOptions()
            } else {
                model.editorTool = tool
            }
        }
    }
}

/// Where the Draw key is, for the shapes' flyout above it (`ShareView` lays the flyout over the whole editor, so a tap
/// anywhere else closes it).
struct DrawKeyBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The Draw key: one key for the shapes, showing the last one used (Arrow at first) with a small ▴ for the flyout of
/// the others. Not lit, a tap draws with that shape; lit, a tap opens the flyout.
struct DrawKey: View {
    @ObservedObject var model: ShareModel
    let lastShape: EditorTool
    let onShapes: () -> Void

    var body: some View {
        let lit = model.editorTool.isShape
        Button {
            if lit {
                onShapes()
            } else {
                model.editorTool = lastShape
            }
        } label: {
            Image(systemName: lastShape.symbol)
                .font(.system(size: SKPhoneMetrics.symbol, weight: .semibold))
                .frame(width: SKPhoneMetrics.face, height: SKPhoneMetrics.face)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 6, weight: .bold))
                        .opacity(0.7)
                        .padding(5)
                }
        }
        .buttonStyle(.skPhoneKey(isOn: lit, shape: .square))
        .anchorPreference(key: DrawKeyBounds.self, value: .bounds) { $0 }
        .accessibilityLabel(Text("Draw, \(lastShape.title)"))
        .accessibilityHint(Text(lit ? "Shows the shapes" : "Draws with \(lastShape.title)"))
        .accessibilityAction(named: Text("Shapes")) {
            if !lit { model.editorTool = lastShape }
            onShapes()
        }
    }
}

/// The Draw key's shapes (`EditorTool.shapes`) as a column of keys on a chassis plate, the current one lit. Picking
/// one draws with it (`onPick`); `onClose` closes it (VoiceOver's escape).
struct ShapeFlyout: View {
    let current: EditorTool
    let onPick: (EditorTool) -> Void
    let onClose: () -> Void

    var body: some View {
        SKPlate {
            VStack(spacing: 4) {
                ForEach(EditorTool.shapes, id: \.self) { shape in
                    SymbolKey(symbol: shape.symbol, label: shape.title, isOn: shape == current) { onPick(shape) }
                }
            }
            .padding(6)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Shapes"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }
}

/// The round key showing the markup colour. It opens Draw's options, so they need no second tap: the colours, the
/// size slider (`WidthRow`) and Clear for the drawings.
struct ColorKey: View {
    @ObservedObject var model: ShareModel
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: { ColorDot(colors: [model.markupColor.swiftUI]) }
            .buttonStyle(.skPhoneKey(shape: .round))
            .accessibilityLabel(Text("Colour: \(model.markupColorName)"))
            .accessibilityHint(Text("Shows the colours and the size for drawings and text, and Clear"))
            .popover(isPresented: $choosing) {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(ShareModel.markupColors.indices, id: \.self) { i in
                            let choice = ShareModel.markupColors[i]
                            Button {
                                model.markupColor = choice.color
                                choosing = false
                            } label: { ColorDot(colors: [choice.color.swiftUI]) }
                                .buttonStyle(.skPhoneKey(isOn: model.markupColor == choice.color, shape: .round))
                                .accessibilityLabel(Text(choice.name))
                        }
                    }
                    WidthRow(model: model)
                    SKGroove()
                    Button("Clear drawings") {
                        model.clearMarkups()
                        choosing = false
                    }
                    .buttonStyle(.skPhoneKey(fill: true))
                    .disabled(model.markups.isEmpty)
                    .accessibilityHint(Text("Removes the drawings and text; the redactions stay"))
                }
                .padding(12)
                .fixedSize()
                .presentationCompactAdaptation(.popover)
                .presentationBackground { Color.clear.sk1Chassis() }
            }
    }
}

/// The size slider in the colour key's popover: a preview of the line in the current colour, the slider over
/// `ShareModel.markupWidths` (snapping to 0.5, 1, 2, 3 and 4) and the size in an LCD chip ("2×"). New drawings and
/// text take it; it is greyed out with Highlight, which has one size.
struct WidthRow: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        let widths = ShareModel.markupWidths
        let off = model.mode == .draw && !model.tool.hasWidth
        let text = Self.text(model.markupWidth)
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // The line as drawn at 1x: the default line is 3 pt.
                Capsule()
                    .fill(model.markupColor.swiftUI)
                    .frame(width: 28, height: 3 * model.markupWidth)
                    .frame(width: 32, height: 16)
                    .accessibilityHidden(true)
                SKSlider(title: "Size", value: Binding(
                    get: { Double(widths.firstIndex(of: ShareModel.nearestMarkupWidth(model.markupWidth)) ?? 1) },
                    set: { i in model.markupWidth = widths[min(max(Int(i.rounded()), 0), widths.count - 1)] }),
                         range: 0...Double(widths.count - 1), step: 1, valueText: text)
                    .frame(width: 140)
                    .allowsHitTesting(!off)
                    .accessibilityHint(Text("The size of new drawings and text"))
                SKChip(text, minWidth: 44)
                    .accessibilityHidden(true)
            }
            .opacity(off ? 0.6 : 1)
            .disabled(off)
            if off {
                Text("Highlights have one size.").sk1Hint()
            }
        }
    }

    /// "0.5×", "1×", "2×"...
    static func text(_ width: Double) -> String {
        width == width.rounded() ? "\(Int(width))×" : "\(width)×"
    }
}

/// The key that closes a tool's options and brings the tools back.
struct CloseOptionsKey: View {
    let action: () -> Void

    var body: some View {
        SymbolKey(symbol: "xmark", label: "Close options", hint: "Shows the tools again", action: action)
    }
}

/// Frame's options: the frame keys, the background key and More (both open the More sheet), and ✕.
struct FrameOptionsRow: View {
    @ObservedObject var model: ShareModel
    let onMore: () -> Void
    let onClose: () -> Void

    var body: some View {
        // On a narrow phone the background key steps aside; More opens the same sheet.
        ViewThatFits(in: .horizontal) {
            row(backgroundKey: true)
            row(backgroundKey: false)
        }
    }

    private func row(backgroundKey: Bool) -> some View {
        HStack(spacing: 8) {
            PhoneKeyTray(label: "Frame") {
                ForEach(ShareModel.FrameChoice.all, id: \.self) { frame in
                    SymbolKey(symbol: frame.symbol, label: frame.title, isOn: model.frameChoice == frame) {
                        model.frameChoice = frame
                    }
                }
            }
            Spacer(minLength: 0)
            if backgroundKey {
                Button(action: onMore) {
                    ColorDot(colors: ShareModel.swatchColors(model.backgroundChoice),
                             empty: model.backgroundChoice == nil)
                }
                .buttonStyle(.skPhoneKey(shape: .round))
                .accessibilityLabel(Text("Background: \(ShareModel.backgroundName(model.backgroundChoice))"))
                .accessibilityHint(Text("Shows the backgrounds and more frame options"))
            }
            SymbolKey(symbol: "slider.horizontal.3", label: "More frame options", action: onMore)
            CloseOptionsKey(action: onClose)
        }
    }
}

/// Text's options: the lit Text key (it closes the options too), the colour key, Clear for the drawings, and ✕.
struct TextOptionsRow: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SymbolKey(symbol: EditorTool.text.symbol, label: EditorTool.text.title, isOn: true,
                      hint: "Shows the tools again", action: onClose)
            ColorKey(model: model)
            Spacer(minLength: 0)
            Button("Clear") { model.clearMarkups() }
                .buttonStyle(.skPhoneKey())
                .disabled(model.markups.isEmpty)
                .accessibilityLabel(Text("Clear drawings"))
            CloseOptionsKey(action: onClose)
        }
    }
}

/// Redact's options: the lit Redact key, how areas are covered (Pixelate, Blur, Solid), Find (the Find sheet:
/// emails, phones, links, text, Redact N, Undo and Clear for areas), and ✕.
struct RedactOptionsRow: View {
    @ObservedObject var model: ShareModel
    let finding: Bool
    let onFind: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SymbolKey(symbol: EditorTool.redact.symbol, label: "Redact", isOn: true, hint: "Shows the tools again",
                      action: onClose)
            Spacer(minLength: 0)
            SKSegmented(selection: $model.redactStyle, options: [
                .init(.pixelate, "Pixelate"),
                .init(.blur, "Blur"),
                .init(.solid, "Solid"),
            ], height: 40)
            .accessibilityLabel(Text("Cover"))
            Spacer(minLength: 0)
            SymbolKey(symbol: "magnifyingglass", label: "Find", isOn: finding,
                      hint: "Finds emails, phone numbers, links or text to cover", action: onFind)
            CloseOptionsKey(action: onClose)
        }
    }
}

/// The label being typed with the Text tool: the field (focused, so the keyboard comes up and this row rides above
/// it), Done (or the keyboard's Done) and Cancel. Tapping elsewhere on the picture moves the label.
struct TextEntryRow: View {
    @ObservedObject var model: ShareModel
    @FocusState private var typing: Bool

    var body: some View {
        HStack(spacing: 8) {
            SKTextField("Text", text: $model.draftText, prompt: "Type a label", height: 44)
                .focused($typing)
                .submitLabel(.done)
                .onSubmit { model.commitText() }
            Button("Done") { model.commitText() }
                .buttonStyle(.skPhoneKey())
            SymbolKey(symbol: "xmark", label: "Cancel", hint: "Adds no text") { model.cancelText() }
        }
        .onAppear { typing = true }
        // A tap elsewhere on the picture moves the label; keep typing.
        .onChange(of: model.textSpot) { typing = model.textSpot != nil }
    }
}
