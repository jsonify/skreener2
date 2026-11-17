import ImageIO
import SkreenerCore
import UIKit
import UniformTypeIdentifiers

/// Where the editor's image comes from: the Share Extension's items, or image bytes (a Photos asset or a picked
/// image in the app). The editor keeps the source, not the decoded image, and loads it again for each export and OCR
/// pass, so the full image is only in memory while it is used. Every load is downscaled to the source's
/// `PixelBudget` with the EXIF orientation applied. The budget is chosen by how the editor is hosted (#441): the
/// Share Extension's items get `.shareExtension` (it has about 120 MB), image bytes opened in the app get `.app`.
public struct ImageSource: Sendable {
    private let loader: @Sendable (PixelBudget?) async throws -> CGImage

    /// A source that loads with `load`, at whatever size it decides. It may be called several times and must give
    /// the same image each time. It is read as it is, also by `load(within:)`: a long screenshot is far taller than
    /// wide, and shrinking it to a long-side cap would leave its text unreadable.
    public init(_ load: @escaping @Sendable () async throws -> CGImage) {
        loader = { _ in try await load() }
    }

    /// A source that decodes straight to the budget it is asked for, so a smaller copy never costs a full decode.
    init(budgeted load: @escaping @Sendable (PixelBudget?) async throws -> CGImage) {
        loader = load
    }

    /// Loads the image. Not main-actor: it decodes on the caller's task.
    public func load() async throws -> CGImage {
        try await loader(nil)
    }

    /// Loads the image no bigger than `budget` allows, decoded straight to that size when the source can. For work
    /// that doesn't need every pixel (OCR, face detection).
    func load(within budget: PixelBudget) async throws -> CGImage {
        try await loader(budget)
    }

    /// The first image in the extension's input items, within `budget` (the extension's 4096 px by default).
    public static func items(_ items: [NSExtensionItem], budget: PixelBudget = .shareExtension) -> ImageSource {
        let items = ImageLoader.Items(items: items)
        return ImageSource(budgeted: { smaller in
            try await ImageLoader.load(from: items.items, budget: budget.tightened(by: smaller))
        })
    }

    /// An encoded image (PNG, JPEG, HEIC...), within `budget` (the app's by default: it has the memory the extension
    /// lacks). The bytes stay in memory for as long as the source does.
    public static func data(_ data: Data, budget: PixelBudget = .app) -> ImageSource {
        ImageSource(budgeted: { smaller in try ImageLoader.load(data: data, budget: budget.tightened(by: smaller)) })
    }
}

private extension PixelBudget {
    /// Whichever of the two budgets is smaller on each count.
    func tightened(by other: PixelBudget?) -> PixelBudget {
        guard let other else { return self }
        return PixelBudget(maxSide: min(maxSide, other.maxSide), maxArea: min(maxArea, other.maxArea))
    }
}

/// Decodes the image within a `PixelBudget`.
enum ImageLoader {
    /// The size of the bounded copy that OCR and face detection read: Vision scales its input down itself, so more
    /// pixels only cost memory and time. It is what the extension has always read.
    static let recognitionBudget = PixelBudget.shareExtension

    enum LoadError: Error {
        case noImage
    }

    /// A CGImage handed from the item provider's queue to the main actor. It is immutable once made.
    struct Loaded: @unchecked Sendable {
        let image: CGImage
    }

    /// The extension's items, handed to a loading task. They are only read, by `load(from:)`.
    struct Items: @unchecked Sendable {
        let items: [NSExtensionItem]
    }

    /// Decodes encoded image bytes. Not main-actor work: call it off the main actor.
    static func load(data: Data, budget: PixelBudget) throws -> CGImage {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ thumbnail($0, budget: budget) }) else {
            throw LoadError.noImage
        }
        return image
    }

    /// The first image in `items`. Not main-actor: it waits on the provider's callback.
    static func load(from items: [NSExtensionItem], budget: PixelBudget) async throws -> CGImage {
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            throw LoadError.noImage
        }
        let loaded: Loaded = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let image = item.flatMap { decode($0, budget: budget) } {
                    continuation.resume(returning: Loaded(image: image))
                } else {
                    continuation.resume(throwing: error ?? LoadError.noImage)
                }
            }
        }
        return loaded.image
    }

    /// Photos hands over a file URL, other apps a UIImage or the bytes.
    private static func decode(_ item: NSSecureCoding, budget: PixelBudget) -> CGImage? {
        if let url = item as? URL {
            return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { thumbnail($0, budget: budget) }
        }
        if let data = item as? Data {
            return CGImageSourceCreateWithData(data as CFData, nil).flatMap { thumbnail($0, budget: budget) }
        }
        if let image = item as? UIImage {
            return downscale(image, budget: budget)
        }
        return nil
    }

    /// Decodes within `budget` straight from the file, with the EXIF orientation applied, so the full-size bitmap
    /// never exists. It never upscales a smaller image. The budget is applied to the stored size; a 90-degree
    /// orientation only swaps width and height, which a long-side cap and an area cap don't care about.
    private static func thumbnail(_ source: CGImageSource, budget: PixelBudget) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? budget.maxSide
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? budget.maxSide
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: budget.longSide(width: w, height: h),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func downscale(_ image: UIImage, budget: PixelBudget) -> CGImage? {
        let width = Int((image.size.width * image.scale).rounded())
        let height = Int((image.size.height * image.scale).rounded())
        let longest = max(width, height)
        guard longest > 0 else { return nil }
        let factor = min(1, CGFloat(budget.longSide(width: width, height: height)) / CGFloat(longest))
        let size = CGSize(width: (CGFloat(width) * factor).rounded(), height: (CGFloat(height) * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing a UIImage applies its orientation.
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// A smaller copy for the live preview, so each change redraws quickly and the extension stays well under its limit.
    static func preview(of image: CGImage, maxPixels: Int = 1600) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixels else { return image }
        let factor = CGFloat(maxPixels) / CGFloat(longest)
        let w = max(Int((CGFloat(image.width) * factor).rounded()), 1)
        let h = max(Int((CGFloat(image.height) * factor).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
