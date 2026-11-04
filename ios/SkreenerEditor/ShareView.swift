import SkreenerCore
import SK1UI
import SwiftUI

/// The share sheet: a Close key on top, the preview, a status readout, the Style / Redact / Draw switch, that mode's
/// controls (which scroll when they do not fit) and the Save, Copy and Share keys at the bottom. While a text label is
/// typed, the switch and the output keys step aside and the preview shrinks, so the field stays above the keyboard.
public struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void
    /// Shows the system share sheet for the PNG file; the hosting view controller does it.
    let onShare: (URL) -> Void

    public init(model: ShareModel, onClose: @escaping () -> Void, onShare: @escaping (URL) -> Void) {
        self.model = model
        self.onClose = onClose
        self.onShare = onShare
    }

    public var body: some View {
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
                .frame(minHeight: typing ? 120 : 200, maxHeight: .infinity)
                .layoutPriority(1)
            statusArea
            if !typing {
                SKSegmented(selection: $model.mode, options: [
                    .init(.style, "Style"),
                    .init(.redact, "Redact"),
                    .init(.draw, "Draw"),
                ], caption: "Mode")
            }
            ScrollViewReader { proxy in
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
                        case .draw:
                            DrawControls(model: model)
                        }
                    }
                }
                .onChange(of: typing) {
                    if typing { withAnimation { proxy.scrollTo(DrawControls.textID, anchor: .top) } }
                }
            }
            // A floor, or the preview (which has layout priority) takes every point and a tall screenshot leaves the
            // controls at zero height.
            .frame(minHeight: 140, maxHeight: 300)
            if !typing {
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
        }
        .padding(16)
        .sk1Chassis()
    }

    /// A text label is being typed in Draw.
    private var typing: Bool { model.mode == .draw && model.textSpot != nil }

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
            } else if let preview = model.preview, model.mode == .draw {
                DrawCanvas(model: model, preview: preview)
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
