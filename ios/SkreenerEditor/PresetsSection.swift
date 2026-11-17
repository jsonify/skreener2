import SK1Tokens
import SK1UI
import SwiftUI

/// Frame options' PRESETS section (#441): a Save key and a chip per saved look. Tap a chip to apply it; touch and
/// hold for Rename, Update to current look and Delete.
struct PresetsSection: View {
    @ObservedObject var model: ShareModel
    @State private var saving = false
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renamed = ""
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SKCaption("Presets")
            FlowLayout(spacing: 6) {
                SymbolKey(symbol: "plus", label: "Save current look as a preset") {
                    if model.presets.isFull {
                        notice = "You can keep \(LookPresets.limit) presets. Touch and hold one and choose Delete, "
                            + "then save this look."
                    } else {
                        newName = model.suggestedPresetName
                        saving = true
                    }
                }
                ForEach(model.presets.items) { preset in
                    Button { model.apply(preset) } label: {
                        Text(preset.name).lineLimit(1)
                    }
                    .buttonStyle(.skPhoneKey(isOn: model.isCurrent(preset)))
                    .accessibilityLabel(Text(preset.name))
                    .accessibilityHint(Text("Applies this look. Touch and hold for Rename, Update and Delete."))
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            renamed = preset.name
                            renaming = preset.name
                        }
                        Button("Update to current look", systemImage: "arrow.triangle.2.circlepath") {
                            model.updatePreset(preset.name)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.deletePreset(preset.name)
                        }
                    }
                }
            }
            if model.presets.items.isEmpty {
                Text("Save the frame, background and sliders as a preset to use again, here or in the share sheet.")
                    .sk1Hint()
            }
            SKGroove()
        }
        .onAppear { model.reloadPresets() }
        .alert("Save look as a preset", isPresented: $saving) {
            TextField("Name", text: $newName)
            Button("Save") { notice = model.savePreset(named: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A preset with the same name is replaced.")
        }
        .alert("Rename preset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renamed)
            Button("Rename") {
                if let old = renaming { notice = model.renamePreset(old, to: renamed) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Presets", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }
}

/// Lays its children out in rows, wrapping to the next row when one does not fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(width: bounds.width, subviews: subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}
