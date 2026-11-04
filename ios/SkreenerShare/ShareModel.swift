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

    /// Background presets on offer, as indexes into `Background.presets`; nil is no background.
    static let backgroundChoices: [Int?] = [nil, 0, 1, 4, 3, 5]

    @Published private(set) var phase = Phase.loading
    @Published private(set) var preview: UIImage?
    @Published var frameChoice = FrameChoice.iPhone { didSet { redraw() } }
    @Published var backgroundChoice: Int? = 0 { didSet { redraw() } }

    /// The screenshot at preview size. The decoded one (up to 4096 px) is dropped: holding both would cost memory the extension may not have. [verify] the save step reloads it.
    private var source: CGImage?

    func show(_ image: CGImage) {
        source = ImageLoader.preview(of: image)
        phase = .ready
        redraw()
    }

    func fail() {
        phase = .failed
    }

    private func redraw() {
        guard let source else { return }
        var frame = DeviceFrame()
        frame.kind = frameChoice.kind
        var background: Background?
        if let fill = backgroundChoice {
            var b = Background()
            b.fill = fill
            background = b
        }
        preview = Renderer.render(image: source, frame: frame, background: background)
    }
}
