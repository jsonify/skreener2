import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Gets the one shared image out of the extension's items, already small enough for the extension's memory limit
/// (about 120 MB).
enum ImageLoader {
    /// The longest side, in pixels, that any drawing starts from.
    static let maxPixels = 4096

    enum LoadError: Error {
        case noImage
    }

    /// A CGImage handed from the item provider's queue to the main actor. It is immutable once made.
    struct Loaded: @unchecked Sendable {
        let image: CGImage
    }

    /// The first image in `items`. Not main-actor: it waits on the provider's callback.
    static func load(from items: [NSExtensionItem]) async throws -> CGImage {
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            throw LoadError.noImage
        }
        let loaded: Loaded = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let image = item.flatMap(decode) {
                    continuation.resume(returning: Loaded(image: image))
                } else {
                    continuation.resume(throwing: error ?? LoadError.noImage)
                }
            }
        }
        return loaded.image
    }

    /// Photos hands over a file URL, other apps a UIImage or the bytes.
    private static func decode(_ item: NSSecureCoding) -> CGImage? {
        if let url = item as? URL {
            return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(thumbnail)
        }
        if let data = item as? Data {
            return CGImageSourceCreateWithData(data as CFData, nil).flatMap(thumbnail)
        }
        if let image = item as? UIImage {
            return downscale(image)
        }
        return nil
    }

    /// Decodes at most `maxPixels` on the long side straight from the file, with the EXIF orientation applied, so the
    /// full-size bitmap never exists. `maxPixel` never upscales a smaller image.
    private static func thumbnail(_ source: CGImageSource) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? maxPixels
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? maxPixels
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), maxPixels),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func downscale(_ image: UIImage) -> CGImage? {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > 0 else { return nil }
        let factor = min(1, CGFloat(maxPixels) / longest)
        let size = CGSize(width: (image.size.width * image.scale * factor).rounded(),
                          height: (image.size.height * image.scale * factor).rounded())
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
