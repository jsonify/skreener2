import SkreenerCore
import SK1Tokens
import SK1UI
import SwiftUI

/// The sheet's heading: a caption and a key that closes it.
private struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            SKCaption(title, tone: .soft)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            SymbolKey(symbol: "xmark", label: "Close \(title)", action: onClose)
        }
    }
}

/// Frame's More sheet (#440), on the chassis: the backgrounds, the Padding, Corners and Shadow sliders (with a
/// background), Clean bar (when the screenshot has a status bar Skreener knows) and Dark (for every frame but None),
/// and the address for Browser. The preview stays usable above it.
struct FrameSheet: View {
    @ObservedObject var model: ShareModel
    @Environment(\.dismiss) private var dismiss

    private static let detents: Set<PresentationDetent> = [.medium, .large]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(title: "Frame options") { dismiss() }
                SKCaption("Background")
                // Wraps onto more lines rather than scrolling sideways.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: SKPhoneMetrics.face, maximum: SKPhoneMetrics.face),
                                             spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(ShareModel.backgroundChoices, id: \.self) { fill in
                        Button { model.backgroundChoice = fill } label: {
                            ColorDot(colors: ShareModel.swatchColors(fill), empty: fill == nil)
                        }
                        .buttonStyle(.skPhoneKey(isOn: model.backgroundChoice == fill, shape: .round))
                        .accessibilityLabel(Text(ShareModel.backgroundName(fill)))
                    }
                }
                .padding(.vertical, 4)
                if model.backgroundChoice != nil {
                    sliderRow("Padding", value: $model.padding, range: 0...160, step: 1, text: "\(Int(model.padding))")
                    sliderRow("Corners", value: $model.cornerRadius, range: 0...40, step: 1,
                              text: "\(Int(model.cornerRadius))")
                    sliderRow("Shadow", value: $model.shadow, range: 0...1, step: 0.05,
                              text: "\(Int((model.shadow * 100).rounded()))%")
                } else {
                    Text("Pick a background for padding, corners and shadow.").sk1Hint()
                }
                if model.canCleanBar || model.frameChoice != .plain {
                    SKGroove()
                    HStack(spacing: 24) {
                        if model.canCleanBar {
                            Toggle("Clean bar", isOn: $model.cleanBar)
                                .toggleStyle(.sk1Square)
                        }
                        if model.frameChoice != .plain {
                            Toggle("Dark", isOn: $model.dark)
                                .toggleStyle(.sk1Square)
                        }
                    }
                    .frame(minHeight: 44)
                    if model.canCleanBar {
                        Text("Clean bar repaints the status bar: 9:41, full signal, Wi-Fi and battery.").sk1Hint()
                    }
                }
                if model.frameChoice == .browser {
                    SKCaption("Address")
                    SKTextField("Address", text: $model.browserURL, prompt: DeviceFrame.defaultURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .presentationDetents(Self.detents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .sk1Sheet()
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                           text: String) -> some View {
        HStack(spacing: 12) {
            SKCaption(title)
                .frame(width: 70, alignment: .leading)
                .accessibilityHidden(true)
            SKSlider(title: title, value: value, range: range, step: step, valueText: text)
            SKChip(text, minWidth: 52)
                .accessibilityHidden(true)
        }
    }
}

/// Redact's Find sheet (#440): the Emails, Phones and Links keys and the text search (several terms separated by
/// commas) find text to cover with on-device OCR; matches are outlined on the picture, which stays usable above the
/// sheet, so a tap there leaves one out. Redact N covers the ticked matches; Undo and Clear take back covered areas.
struct FindSheet: View {
    @ObservedObject var model: ShareModel
    @ObservedObject var finder: TextFinder
    @Environment(\.dismiss) private var dismiss

    private static let small = PresentationDetent.height(340)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(title: "Find") { dismiss() }
                PhoneKeyTray(label: "Find") {
                    ForEach(TextFinder.Kind.allCases, id: \.self) { kind in
                        Button(kind.title) { finder.find(kind) }
                            .buttonStyle(.skPhoneKey(isOn: finder.kind == kind, fill: true))
                    }
                }
                SKTextField("Text to find", text: $finder.query, prompt: "Name, number…", height: 44)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                let status = finder.status
                if !status.isEmpty {
                    SKReadout(status)
                }
                HStack(spacing: 8) {
                    let n = finder.selectedCount
                    Button("Redact \(n)") { model.redactFound() }
                        .buttonStyle(.skPhoneKey(.orange))
                        .disabled(n == 0)
                    Spacer(minLength: 0)
                    Button("Undo") { model.undoRedaction() }
                        .buttonStyle(.skPhoneKey())
                        .disabled(!model.canUndoRedaction)
                        .accessibilityLabel(Text("Undo area"))
                    Button("Clear") { model.clearRedactions() }
                        .buttonStyle(.skPhoneKey())
                        .disabled(model.redactions.isEmpty)
                        .accessibilityLabel(Text("Clear areas"))
                }
                Text(finder.hits.isEmpty
                     ? "Drag on the picture to cover an area. Pinch to zoom. Only Solid really removes the text."
                     : "Tap a match to leave it out. Separate several terms with commas.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .presentationDetents([Self.small, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: Self.small))
        .sk1Sheet()
    }
}
