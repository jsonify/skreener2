import SkreenerCore
import SK1UI
import SwiftUI

/// The share sheet: a Close key on top, the preview, a status readout, the Style / Redact switch, that mode's
/// controls (which scroll when they do not fit) and the Save, Copy and Share keys at the bottom.
struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void
    /// Shows the system share sheet for the PNG file; the hosting view controller does it.
    let onShare: (URL) -> Void

    var body: some View {
        VStack(spacing: 12) {
            SKPlate {
                HStack {
                    Button("Close", action: onClose)
                        .buttonStyle(.sk1Key())
                    Spacer()
                    SKCaption("Skreener")
                }
                .padding(8)
            }
            SKWell { previewArea.padding(10) }
                .frame(minHeight: 200, maxHeight: .infinity)
                .layoutPriority(1)
            statusArea
            SKSegmented(selection: $model.mode, options: [
                .init(.style, "Style"),
                .init(.redact, "Redact"),
            ], caption: "Mode")
            ScrollView {
                VStack(spacing: 12) {
                    switch model.mode {
                    case .style:
                        frameAndBackground
                        FrameOptions(model: model)
                        if model.backgroundChoice != nil {
                            BackgroundControls(model: model)
                        }
                    case .redact:
                        RedactControls(model: model, finder: model.finder)
                    }
                }
            }
            .frame(maxHeight: 300)
            SKKeyTray {
                Button("Save") { model.export(.save, share: onShare) }
                    .buttonStyle(.sk1Key(.orange))
                Button("Copy") { model.export(.copy, share: onShare) }
                    .buttonStyle(.sk1Key())
                Button("Share") { model.export(.share, share: onShare) }
                    .buttonStyle(.sk1Key())
            }
            .disabled(!model.canExport)
        }
        .padding(16)
        .sk1Chassis()
    }

    @ViewBuilder private var statusArea: some View {
        let status = model.status
        VStack(spacing: 4) {
            SKReadout(status?.text ?? "Ready")
            if let detail = status?.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var frameAndBackground: some View {
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

    @ViewBuilder private var previewArea: some View {
        switch model.phase {
        case .loading:
            SKReadout("Loading…").frame(maxHeight: .infinity, alignment: .center)
        case .failed:
            SKReadout("Could not read the image.").frame(maxHeight: .infinity, alignment: .center)
        case .ready:
            if let preview = model.preview, model.mode == .redact {
                RedactCanvas(model: model, finder: model.finder, preview: preview)
            } else if let preview = model.preview {
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
