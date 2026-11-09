import SkreenerCore
import SK1UI
import SwiftUI

/// Redact mode's controls: how areas are covered, Undo and Clear, and finding text to cover (emails, phone numbers,
/// links or typed terms). Erase is left out: it needs the Mac's guess of the color around the text.
struct RedactControls: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                SKSegmented(selection: $model.redactStyle, options: [
                    .init(.pixelate, "Pixelate"),
                    .init(.blur, "Blur"),
                    .init(.solid, "Solid"),
                ], caption: "Cover")
                Text("Only Solid really removes the text.").sk1Hint()
            }
            SKKeyTray(caption: "Areas") {
                Button("Undo") { model.undoRedaction() }
                    .buttonStyle(.sk1Key())
                    .disabled(!model.canUndoRedaction)
                Button("Clear") { model.clearRedactions() }
                    .buttonStyle(.sk1Key())
                    .disabled(model.redactions.isEmpty)
            }
            Text("Drag on the picture to cover an area. Pinch to zoom.").sk1Hint()
            findText
        }
    }

    @ViewBuilder private var findText: some View {
        SKKeyTray(caption: "Find") {
            ForEach(TextFinder.Kind.allCases, id: \.self) { kind in
                Button(kind.title) { finder.find(kind) }
                    .buttonStyle(.sk1Key(isOn: finder.kind == kind))
            }
        }
        SKGroup(caption: "Find text") {
            SKRow(title: "Text") {
                SKTextField("Text to find", text: $finder.query, prompt: "Name, number…")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .frame(width: 190)
            }
        }
        let status = finder.status
        if !status.isEmpty {
            SKReadout(status)
            if !finder.hits.isEmpty {
                Text("Tap a match to leave it out. Separate several terms with commas.").sk1Hint()
            }
        }
        let n = finder.selectedCount
        SKKeyTray {
            Button("Redact \(n)") { model.redactFound() }
            .buttonStyle(.sk1Key(.orange))
            .disabled(n == 0)
        }
    }
}
