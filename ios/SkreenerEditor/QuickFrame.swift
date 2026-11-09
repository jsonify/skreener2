import CoreGraphics
import Foundation
import SkreenerCore

/// Frames a screenshot with the last look and checks it with Safe Check, without the editor on screen (#439). The
/// app's Shortcuts actions use it; they decide what to do with the findings and the PNG.
public enum QuickFrame {
    /// How many things Safe Check finds in the image, with the same on-device scan the editor runs as it opens. An
    /// image that can't be loaded finds nothing (rendering it then fails on its own).
    public static func findings(in source: ImageSource) async -> Int {
        guard let image = try? await source.load() else { return 0 }
        let size = CGSize(width: image.width, height: image.height)
        return await TextFinder.scanLeaks(image, size: size).count
    }

    /// The image at full size in the last look (frame, background, sliders and Clean bar), as PNG bytes.
    public static func png(_ source: ImageSource) async throws -> Data {
        let look = Look.load(offered: ShareModel.backgroundChoices)
        let job = Exporter.Job(source: source, frame: look.makeFrame(), background: look.makeBackground(scale: 1),
                               redactions: [], markups: [], cleanBar: look.cleanBar)
        return try await Exporter.png(job)
    }

    /// Puts the PNG on the pasteboard.
    @MainActor public static func copy(_ png: Data) {
        Exporter.copy(png)
    }

    /// Adds the PNG to Photos, asking only for "Add Photos Only" access, as the editor's Save does.
    public static func save(_ png: Data) async throws {
        try await Exporter.save(png)
    }

    /// Writes the PNG to a temporary `Skreener.png` for the share sheet; remove its folder when the sheet is done.
    public static func shareFile(_ png: Data) throws -> URL {
        try Exporter.shareFile(png)
    }
}

extension Look {
    /// The device frame this look draws, with the browser's address.
    func makeFrame(url: String = DeviceFrame.defaultURL) -> DeviceFrame {
        var frame = DeviceFrame()
        switch self.frame {
        case "plain": frame.kind = .none
        case "browser": frame.kind = .browser
        case "macWindow": frame.kind = .macWindow
        default: frame.kind = .iPhone
        }
        frame.dark = dark
        frame.url = url
        return frame
    }

    /// The background, with padding and corners in full-image pixels times `scale` (the preview is smaller); nil for
    /// no background.
    func makeBackground(scale: CGFloat) -> Background? {
        guard let fill = background else { return nil }
        var background = Background()
        background.fill = fill
        background.padding = CGFloat(padding) * scale
        background.cornerRadius = CGFloat(cornerRadius) * scale
        background.shadow = CGFloat(shadow)
        return background
    }
}
