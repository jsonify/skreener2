import SkreenerCore
import SK1Tokens
import SK1UI
import SwiftUI

/// The editor (#440), the same in the app and the Share Extension: Close, the title, Share and the orange Save on top
/// (Copy is the share sheet's Copy Photo); a slim LCD strip with the tool and a hint, Safe Check or an export's status
/// (`EditorStrip`); the picture as big as it fits; and one bottom row: Undo, the tray of tool keys (Frame, Arrow,
/// Rectangle, Text, Highlight, Redact) and the colour key. Tapping the lit tool again swaps the row for that tool's
/// options and a ✕ back to the tools. While a text label is typed, the row is its text field, above the keyboard.
/// Redact and Draw share one zoom (#441), back to fit in Frame and for a new image.
public struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void
    /// Shows the system share sheet for the PNG file; the hosting view controller does it.
    let onShare: (URL) -> Void
    @State private var zoom = PreviewZoom()
    /// The bottom row shows the lit tool's options.
    @State private var showsOptions = false
    /// Frame's More sheet.
    @State private var showsMore = false
    /// Redact's Find sheet.
    @State private var showsFind = false

    public init(model: ShareModel, onClose: @escaping () -> Void, onShare: @escaping (URL) -> Void) {
        self.model = model
        self.onClose = onClose
        self.onShare = onShare
    }

    public var body: some View {
        VStack(spacing: 10) {
            topBar
            EditorStrip(model: model, finder: model.finder)
            previewArea
                .padding(10)
                .background(CanvasWell())
                .overlay(alignment: .topTrailing) { zoomReadout.padding(2) }
                .frame(minHeight: typing ? 120 : 200, maxHeight: .infinity)
                .layoutPriority(1)
            bottomRow
                .frame(minHeight: SKPhoneMetrics.key + 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sk1Chassis()
        .onChange(of: model.mode) {
            if model.mode == .style { zoom = PreviewZoom() }
        }
        .onChange(of: model.phase) { zoom = PreviewZoom() }
        // Picking another tool shows the tools; Safe Check's Review switches to Redact with the options as they were.
        .onChange(of: model.editorTool) {
            if model.editorTool != .redact { showsFind = false }
            if model.editorTool != .frame { showsMore = false }
        }
        .sheet(isPresented: $showsMore) { FrameSheet(model: model) }
        .sheet(isPresented: $showsFind) { FindSheet(model: model, finder: model.finder) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            Button("Close", action: onClose)
                .buttonStyle(.skPhoneKey())
            Spacer(minLength: 8)
            SymbolKey(symbol: "square.and.arrow.up", label: "Share",
                      hint: "Shows the share sheet, with Copy Photo to copy it") {
                model.export(.share, share: onShare)
            }
            .disabled(!model.canExport || typing)
            Button("Save") { model.export(.save, share: onShare) }
                .buttonStyle(.skPhoneKey(.orange))
                .disabled(!model.canExport || typing)
                .accessibilityHint(Text("Saves it to Photos"))
        }
        .overlay {
            SKCaption("Skreener", style: SK1.TextStyle(size: 12, weight: .bold, kern: 0.8, uppercase: true))
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Bottom row

    @ViewBuilder private var bottomRow: some View {
        if typing {
            TextEntryRow(model: model)
        } else if showsOptions {
            switch model.editorTool {
            case .frame:
                FrameOptionsRow(model: model, onMore: { showsMore = true }, onClose: closeOptions)
            case .redact:
                RedactOptionsRow(model: model, finding: showsFind, onFind: { showsFind = true },
                                 onClose: closeOptions)
            case .arrow, .rect, .text, .highlight:
                DrawOptionsRow(model: model, onClose: closeOptions)
            }
        } else {
            ToolRow(model: model) { showsOptions = true }
        }
    }

    private func closeOptions() {
        showsOptions = false
        showsMore = false
        showsFind = false
    }

    /// A text label is being typed in Draw.
    private var typing: Bool { model.mode == .draw && model.textSpot != nil }

    // MARK: Preview

    /// The zoom level while Redact or Draw is zoomed in; tapping it goes back to fit.
    @ViewBuilder private var zoomReadout: some View {
        if zoom.isZoomed, model.mode != .style {
            let percent = "\(Int((zoom.scale * 100).rounded()))%"
            Button { zoom = PreviewZoom() } label: { SKChip(percent).padding(12) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Zoom \(percent)"))
                .accessibilityHint(Text("Shows the whole picture"))
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
                RedactCanvas(model: model, finder: model.finder, preview: preview, zoom: $zoom)
            } else if let preview = model.preview, model.mode == .draw {
                DrawCanvas(model: model, preview: preview, zoom: $zoom)
            } else if let preview = model.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("Preview"))
            }
        }
    }
}
