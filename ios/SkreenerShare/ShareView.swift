import SkreenerCore
import SK1UI
import SwiftUI

/// The share sheet: the preview, a frame picker and background keys, with Cancel and Done.
struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            SKPlate {
                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.sk1Key())
                    Spacer()
                    SKCaption("Skreener")
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(.sk1Key(.orange))
                }
                .padding(8)
            }
            SKWell { previewArea.padding(10) }
            SKSegmented(selection: $model.frameChoice, options: [
                .init(.plain, "None"),
                .init(.iPhone, "iPhone"),
                .init(.browser, "Browser"),
                .init(.macWindow, "macOS Window", help: "macOS window"),
            ], caption: "Frame")
            SKKeyTray(caption: "Background") {
                ForEach(ShareModel.backgroundChoices, id: \.self) { fill in
                    Button { model.backgroundChoice = fill } label: { swatch(fill) }
                        .buttonStyle(.sk1Key(isOn: model.backgroundChoice == fill))
                        .accessibilityLabel(Text(fill.map { Background.presets[$0].name } ?? "No background"))
                }
            }
        }
        .padding(16)
        .sk1Chassis()
    }

    @ViewBuilder private var previewArea: some View {
        switch model.phase {
        case .loading:
            SKReadout("Loading…").frame(maxHeight: .infinity, alignment: .center)
        case .failed:
            SKReadout("Could not read the image.").frame(maxHeight: .infinity, alignment: .center)
        case .ready:
            if let preview = model.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("Preview"))
            }
        }
    }

    /// A small swatch of the preset's colors; an empty circle for no background.
    @ViewBuilder private func swatch(_ fill: Int?) -> some View {
        if let fill {
            let colors = Background.presets[fill].colors.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
            Circle()
                .fill(LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 18, height: 18)
        } else {
            Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 18, height: 18)
        }
    }
}
