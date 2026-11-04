import SkreenerCore
import SwiftUI
import UIKit

/// What the share sheet shows and the choices made in it.
@MainActor
final class ShareModel: ObservableObject {
    enum FrameChoice: Hashable {
        case plain, iPhone, browser, macWindow

        var kind: DeviceFrame.Kind {
            switch self {
            case .plain: return .none
            case .iPhone: return .iPhone
            case .browser: return .browser
            case .macWindow: return .macWindow
            }
        }
    }

    enum Phase {
        case loading, ready, failed
    }

    enum Output {
        case save, copy, share
    }

    /// A line for the readout, and, when the user has to do something, what.
    struct Status: Equatable {
        var text: String
        var detail: String?
    }

    /// Background presets on offer, as indexes into `Background.presets`; nil is no background.
    static let backgroundChoices: [Int?] = [nil, 0, 1, 4, 3, 5]

    @Published private(set) var phase = Phase.loading
    @Published private(set) var preview: UIImage?
    @Published private(set) var status: Status?
    @Published private(set) var busy = false
    @Published var frameChoice = FrameChoice.iPhone { didSet { scheduleRedraw() } }
    @Published var backgroundChoice: Int? = 0 { didSet { scheduleRedraw() } }
    @Published var browserURL = DeviceFrame.defaultURL { didSet { scheduleRedraw() } }
    @Published var dark = false { didSet { scheduleRedraw() } }
    @Published var padding = 48.0 { didSet { scheduleRedraw() } }
    @Published var cornerRadius = 10.0 { didSet { scheduleRedraw() } }
    @Published var shadow = 0.5 { didSet { scheduleRedraw() } }

    var canExport: Bool { phase == .ready && !busy }

    /// The extension's input items. Kept so an export can reload the full image: the decoded one (up to 4096 px) is
    /// dropped after the preview is made, since holding both would cost memory the extension may not have.
    private var items: [NSExtensionItem] = []
    /// The screenshot at preview size.
    private var source: CGImage?
    /// The width of the full image, to scale padding and corners down for the preview.
    private var fullWidth: CGFloat = 1
    private var redrawPending = false

    /// Loads the image from `items` and shows it.
    func load(items: [NSExtensionItem]) {
        self.items = items
        Task { [weak self] in
            do {
                let image = try await ImageLoader.load(from: items)
                self?.show(image)
            } catch {
                self?.fail()
            }
        }
    }

    private func show(_ image: CGImage) {
        fullWidth = CGFloat(max(image.width, 1))
        source = ImageLoader.preview(of: image)
        phase = .ready
        redraw()
    }

    private func fail() {
        phase = .failed
    }

    // MARK: Preview

    /// Redraws once for a burst of changes, so dragging a slider stays smooth.
    private func scheduleRedraw() {
        guard source != nil, !redrawPending else { return }
        redrawPending = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            self?.redrawPending = false
            self?.redraw()
        }
    }

    private func redraw() {
        guard let source else { return }
        // Padding and corners are in full-image pixels; the preview is smaller by this much.
        let scale = CGFloat(source.width) / fullWidth
        preview = Renderer.render(image: source, frame: makeFrame(), background: makeBackground(scale: scale))
    }

    private func makeFrame() -> DeviceFrame {
        var frame = DeviceFrame()
        frame.kind = frameChoice.kind
        frame.dark = dark
        frame.url = browserURL
        return frame
    }

    private func makeBackground(scale: CGFloat) -> Background? {
        guard let fill = backgroundChoice else { return nil }
        var background = Background()
        background.fill = fill
        background.padding = CGFloat(padding) * scale
        background.cornerRadius = CGFloat(cornerRadius) * scale
        background.shadow = CGFloat(shadow)
        return background
    }

    // MARK: Output

    /// Renders at full size, then saves, copies or hands the file to `share`. The output keys are off meanwhile.
    func export(_ output: Output, share: @escaping (URL) -> Void) {
        guard canExport else { return }
        busy = true
        status = Status(text: output == .save ? "Saving…" : "Rendering…")
        let job = Exporter.Job(items: items, frame: makeFrame(), background: makeBackground(scale: 1))
        Task { [weak self] in
            await self?.perform(output, job: job, share: share)
        }
    }

    private func perform(_ output: Output, job: Exporter.Job, share: (URL) -> Void) async {
        defer { busy = false }
        do {
            let png = try await Exporter.png(job)
            switch output {
            case .save:
                try await Exporter.save(png)
                status = Status(text: "Saved to Photos")
            case .copy:
                Exporter.copy(png)
                status = Status(text: "Copied")
            case .share:
                let url = try Exporter.shareFile(png)
                status = nil
                share(url)
            }
        } catch Exporter.ExportError.photosDenied {
            status = Status(text: "No access to Photos",
                            detail: "In Settings > Privacy & Security > Photos, allow “Add Photos Only” for Skreener.")
        } catch {
            status = Status(text: "Could not export")
        }
    }
}
