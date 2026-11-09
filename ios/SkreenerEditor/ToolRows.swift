import SkreenerCore
import SK1Tokens
import SK1UI
import SwiftUI

/// The editor's bottom row with the tools showing (#440): Undo, the tray of tool keys (it scrolls sideways when it
/// does not fit; a fade at its right edge hints at more), and the round colour key. Tapping the lit tool again opens
/// its options (`onOptions`).
struct ToolRow: View {
    @ObservedObject var model: ShareModel
    let onOptions: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SymbolKey(symbol: "arrow.uturn.backward", label: "Undo", hint: "Takes back the last redaction or drawing") {
                model.undo()
            }
            .disabled(!model.canUndo)
            ToolTray(model: model, onOptions: onOptions)
            ColorKey(model: model)
        }
    }
}

/// The joined, sideways-scrolling tray of square tool keys, the selected one lit.
struct ToolTray: View {
    @ObservedObject var model: ShareModel
    let onOptions: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let selected = model.editorTool
        SKWell(radius: SK1.Metrics.trayRadius) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(EditorTool.allCases, id: \.self) { tool in
                            SymbolKey(symbol: tool.symbol, label: tool.title, isOn: tool == selected,
                                      hint: tool == selected ? "Shows the \(tool.title) options" : nil) {
                                if tool == selected {
                                    onOptions()
                                } else {
                                    model.editorTool = tool
                                }
                            }
                            .id(tool)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
                    .padding(.bottom, 3)
                }
                .onAppear { proxy.scrollTo(selected) }
                .onChange(of: selected) { withAnimation { proxy.scrollTo(selected) } }
            }
        }
        .overlay(alignment: .trailing) {
            // The fade over the tray's end: there are more keys past it.
            LinearGradient(colors: [Color(sk1Hex: SK1.palette(for: scheme).wellBottom).opacity(0),
                                    Color(sk1Hex: SK1.palette(for: scheme).wellBottom)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 18)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: SK1.Metrics.trayRadius,
                                                  topTrailingRadius: SK1.Metrics.trayRadius))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
    }
}

/// The round key showing the markup colour; it opens the colour choices.
struct ColorKey: View {
    @ObservedObject var model: ShareModel
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: { ColorDot(colors: [model.markupColor.swiftUI]) }
            .buttonStyle(.skPhoneKey(shape: .round))
            .accessibilityLabel(Text("Colour: \(model.markupColorName)"))
            .accessibilityHint(Text("Shows the colours for arrows, rectangles, text and highlights"))
            .popover(isPresented: $choosing) {
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
                .padding(12)
                .presentationCompactAdaptation(.popover)
                .presentationBackground { Color.clear.sk1Chassis() }
            }
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

/// Arrow, Rectangle, Text and Highlight's options: the lit tool key (it closes the options too), the colour key,
/// Clear for the drawings, and ✕.
struct DrawOptionsRow: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void

    var body: some View {
        let tool = model.editorTool
        HStack(spacing: 8) {
            SymbolKey(symbol: tool.symbol, label: tool.title, isOn: true, hint: "Shows the tools again", action: onClose)
            ColorKey(model: model)
            // TODO(#440 step 3): the size slider goes here once Markup has a stroke width (step 2, SkreenerCore).
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
