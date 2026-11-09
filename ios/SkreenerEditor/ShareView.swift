import SkreenerCore
import SK1Tokens
import SK1UI
import SwiftUI

/// The editor (#440), the same in the app and the Share Extension: the home screen's header (`SKAppHeader`), then
/// Close and Undo on the left and Share and the orange Save on the right (Copy is the share sheet's Copy Photo); a slim
/// LCD strip with the tool and a hint, Safe Check or an export's status (`EditorStrip`); the picture as big as it fits;
/// and one bottom row of fixed keys: Frame, Draw, Text and Redact in a tray, and the colour key (`ToolRow`). Draw
/// stands for the shapes; tapping it lit fans them upward (`ShapeFlyout`). Tapping lit Frame, Text or Redact swaps the
/// row for that tool's options and a ✕ back to the tools; the colour key holds Draw's options. While a text label
/// is typed, the row is its text field, above the keyboard. Redact and Draw share one zoom (#441), back to fit in Frame
/// and for a new image.
///
/// The chassis fills the screen behind it, but every control stays inside the safe area, clear of the status bar, the
/// Dynamic Island and the home indicator; nothing at the bottom scrolls sideways, so the system's swipes along the
/// bottom edge (home, switch apps) work as usual.
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
    /// The Draw key's shapes are fanned out above it.
    @State private var showsShapes = false
    /// The shape the Draw key shows and picks: the last one used.
    @State private var lastShape = EditorTool.arrow

    public init(model: ShareModel, onClose: @escaping () -> Void, onShare: @escaping (URL) -> Void) {
        self.model = model
        self.onClose = onClose
        self.onShare = onShare
    }

    public var body: some View {
        VStack(spacing: 10) {
            topBar
            EditorStrip(model: model, finder: model.finder)
            // The picture fills the space it is given and never asks for more (a tall screenshot fitted to the width
            // would), so the column always fits between the safe area's edges.
            Color.clear
                .overlay { previewArea.padding(10) }
                .background(CanvasWell())
                .overlay(alignment: .topTrailing) { zoomReadout.padding(2) }
                .frame(minHeight: typing ? 120 : 200, maxHeight: .infinity)
                .layoutPriority(1)
            bottomRow
                .frame(height: SKPhoneMetrics.key + 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlayPreferenceValue(DrawKeyBounds.self) { anchor in shapes(anchor) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SKChassisFill() }
        .onAppear {
            if model.editorTool.isShape { lastShape = model.editorTool }
#if DEBUG
            applyDemoArguments()
#endif
        }
        .onChange(of: model.mode) {
            if model.mode == .style { zoom = PreviewZoom() }
        }
        .onChange(of: model.phase) { zoom = PreviewZoom() }
        // Picking another tool shows the tools; Safe Check's Review switches to Redact with the options as they were.
        .onChange(of: model.editorTool) {
            let tool = model.editorTool
            if tool != .redact { showsFind = false }
            if tool != .frame { showsMore = false }
            if tool.isShape {
                lastShape = tool
                showsOptions = false
            } else {
                showsShapes = false
            }
        }
        .onChange(of: typing) { if typing { showsShapes = false } }
        .sheet(isPresented: $showsMore) { FrameSheet(model: model) }
        .sheet(isPresented: $showsFind) { FindSheet(model: model, finder: model.finder) }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 8) {
            SKAppHeader()
            topKeys
        }
    }

    /// Close and Undo on the left, Share and the orange Save on the right.
    private var topKeys: some View {
        HStack(spacing: 6) {
            Button("Close", action: onClose)
                .buttonStyle(.skPhoneKey())
            SymbolKey(symbol: "arrow.uturn.backward", label: "Undo", hint: "Takes back the last redaction or drawing") {
                model.undo()
            }
            .disabled(!model.canUndo || typing)
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
    }

    // MARK: Bottom row

    @ViewBuilder private var bottomRow: some View {
        if typing {
            TextEntryRow(model: model)
        } else if showsOptions && !model.editorTool.isShape {
            switch model.editorTool {
            case .frame:
                FrameOptionsRow(model: model, onMore: { showsMore = true }, onClose: closeOptions)
            case .redact:
                RedactOptionsRow(model: model, finding: showsFind, onFind: { showsFind = true },
                                 onClose: closeOptions)
            case .text, .arrow, .line, .rect, .ellipse, .pen, .highlight:
                TextOptionsRow(model: model, onClose: closeOptions)
            }
        } else {
            ToolRow(model: model, lastShape: lastShape, onOptions: { showsOptions = true },
                    onShapes: { setShapes(!showsShapes) })
        }
    }

    private func closeOptions() {
        showsOptions = false
        showsMore = false
        showsFind = false
    }

    // MARK: Shapes flyout

    /// The Draw key's shapes, fanned upward above it, over a catcher that closes them on a tap anywhere else (the Draw
    /// key included).
    @ViewBuilder private func shapes(_ anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if showsShapes {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { setShapes(false) }
                        .accessibilityHidden(true)
                }
                if showsShapes, let anchor {
                    let key = geo[anchor]
                    ShapeFlyout(current: model.editorTool, onPick: { shape in
                        model.editorTool = shape
                        setShapes(false)
                    }, onClose: { setShapes(false) })
                    .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                    // Its bottom 6 pt above the key, centred on it.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .frame(width: geo.size.width, height: max(key.minY - 6, 0))
                    .offset(x: key.midX - geo.size.width / 2)
                }
            }
        }
        .allowsHitTesting(showsShapes)
    }

    private func setShapes(_ open: Bool) {
        guard open != showsShapes else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.2)) { showsShapes = open }
    }

#if DEBUG
    /// Debug builds only, for the Simulator screenshots (the app's DemoLaunch.swift): `-SKDemoTool <frame|draw|text|
    /// redact>` starts with that tool lit, `-SKDemoShapes` with the Draw key's shapes fanned out.
    private func applyDemoArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-SKDemoTool"), i + 1 < args.count {
            switch args[i + 1] {
            case "frame": model.editorTool = .frame
            case "draw": model.editorTool = lastShape
            case "text": model.editorTool = .text
            case "redact": model.editorTool = .redact
            default: break
            }
        }
        if args.contains("-SKDemoShapes") {
            if !model.editorTool.isShape { model.editorTool = lastShape }
            showsShapes = true
        }
    }
#endif

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
