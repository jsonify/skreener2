import Photos
import SkreenerCore
import UIKit
import UniformTypeIdentifiers

/// Renders the picture at full size and hands it on: to Photos, the pasteboard or a file for the share sheet.
enum Exporter {
    enum ExportError: Error {
        case photosDenied
        case renderFailed
    }

    /// What an export needs. Nothing in it changes once made, so this is safe to pass on.
    struct Job: @unchecked Sendable {
        let source: ImageSource
        let frame: DeviceFrame
        let background: Background?
        /// In full-image pixels.
        let redactions: [Redaction]
        /// In full-image pixels, drawn over the redactions.
        let markups: [Markup]
        /// Repaint the status bar clean (#408), if the full image's size has a layout.
        let cleanBar: Bool
    }

    /// Reloads the full image (up to `ImageLoader.maxPixels`), draws it and encodes a PNG. It runs off the main actor
    /// and lets go of the image when it returns, so only the PNG bytes stay in memory.
    static func png(_ job: Job) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { () -> Data in
            let image = try await job.source.load()
            let frame: DeviceFrame? = job.frame
            let bar = job.cleanBar ? StatusBar.layout(forPixelWidth: image.width, height: image.height) : nil
            guard let data = Renderer.render(image: image, frame: frame, background: job.background,
                                             redactions: job.redactions, markups: job.markups,
                                             statusBar: bar).pngData() else {
                throw ExportError.renderFailed
            }
            return data
        }.value
    }

    /// Adds the picture to Photos. Asks only for "Add Photos Only" access.
    static func save(_ png: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
        }
    }

    /// Puts the PNG on the pasteboard.
    @MainActor static func copy(_ png: Data) {
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
    }

    /// Writes the PNG to a temporary `Skreener.png`, so the app that receives it gets a named PNG. The caller removes
    /// the file's folder when the share sheet is done.
    static func shareFile(_ png: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Skreener.png")
        try png.write(to: url, options: .atomic)
        return url
    }
}
