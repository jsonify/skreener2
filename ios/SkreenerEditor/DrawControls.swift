import SkreenerCore
import SK1UI
import SwiftUI

/// Draw mode's controls: the label being typed (on top, so the keyboard doesn't hide it), the tool, the color, and
/// Undo and Clear for the drawings.
struct DrawControls: View {
    @ObservedObject var model: ShareModel
    @FocusState private var typing: Bool

    /// The text entry's scroll target.
    static let textID = "drawText"

    var body: some View {
        VStack(spacing: 12) {
            if model.textSpot != nil {
                textEntry.id(Self.textID)
            }
            SKSegmented(selection: $model.tool, options: [
                .init(.arrow, "Arrow"),
                .init(.rect, "Rect", help: "Rectangle"),
                .init(.text, "Text"),
                .init(.highlight, "Highlight"),
            ], caption: "Tool")
            SKKeyTray(caption: "Color") {
                ForEach(ShareModel.markupColors.indices, id: \.self) { i in
                    let choice = ShareModel.markupColors[i]
                    Button { model.markupColor = choice.color } label: { swatch(choice.color) }
                        .buttonStyle(.sk1Key(isOn: model.markupColor == choice.color))
                        .accessibilityLabel(Text(choice.name))
                }
            }
            SKKeyTray(caption: "Drawings") {
                Button("Undo") { model.undoMarkup() }
                    .buttonStyle(.sk1Key())
                    .disabled(model.markups.isEmpty)
                Button("Clear") { model.clearMarkups() }
                    .buttonStyle(.sk1Key())
                    .disabled(model.markups.isEmpty)
            }
            Text(model.tool == .text ? "Tap the picture where the text goes. Pinch to zoom."
                 : "Drag on the picture to draw. Pinch to zoom.")
                .sk1Hint()
        }
    }

    private var textEntry: some View {
        VStack(spacing: 12) {
            entryField
            SKKeyTray {
                Button("Done") { model.commitText() }
                    .buttonStyle(.sk1Key(.orange))
                Button("Cancel") { model.cancelText() }
                    .buttonStyle(.sk1Key())
            }
        }
    }

    private var entryField: some View {
        SKGroup(caption: "Text") {
            SKRow(title: "Text") {
                SKTextField("Text", text: $model.draftText, prompt: "Type a label")
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { model.commitText() }
                    .frame(width: 190)
            }
        }
        .onAppear { typing = true }
        // A tap elsewhere on the picture moves the label; keep typing.
        .onChange(of: model.textSpot) { typing = model.textSpot != nil }
    }

    private func swatch(_ c: RGBColor) -> some View {
        Circle()
            .fill(Color(red: c.r, green: c.g, blue: c.b))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .frame(width: 18, height: 18)
    }
}
