import Photos
import UIKit

/// The screenshots the home screen shows, from the Photos Screenshots album. Photos read access is asked for only
/// when the user taps Show my screenshots or Latest screenshot (`requestAccess`), never at launch.
///
/// With full access the inbox is the screenshots taken since the app was last sent to the background (the newest
/// `firstUseCount` the first time). With limited access it is every screenshot the user selected for Skreener, so a
/// screenshot added with Select more shows up however old it is.
@MainActor
final class ScreenshotLibrary: NSObject, ObservableObject {
    enum Access {
        case notAsked, full, limited, denied
    }

    /// How many screenshots the inbox shows before the app has ever been sent to the background.
    static let firstUseCount = 12
    /// The thumbnails' size in pixels: three columns on an iPhone, at 3x, cropped to fill.
    static let thumbnailSize = CGSize(width: 360, height: 720)
    private static let lastBackgroundKey = "lastBackground"

    @Published private(set) var access: Access
    /// Newest first.
    @Published private(set) var inbox: [PHAsset] = []

    /// Makes the inbox's thumbnails, and has them ready before they scroll into view.
    let thumbnails = PHCachingImageManager()
    private var observing = false

    override init() {
        access = Self.currentAccess
        super.init()
        refresh()
    }

    /// The read access now, without asking. Nonisolated, so the Shortcuts actions can read it too (#439).
    nonisolated static var currentAccess: Access {
        access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private nonisolated static func access(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .notAsked
        case .authorized: return .full
        case .limited: return .limited
        default: return .denied
        }
    }

    var canRead: Bool { access == .full || access == .limited }

    /// Asks for read access the first time; later calls do nothing (iOS would not ask again).
    func requestAccess() async {
        guard access == .notAsked else { return }
        access = Self.access(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        refresh()
    }

    /// When the app was last sent to the background; nil before the first time.
    private var lastBackground: Date? {
        UserDefaults.standard.object(forKey: Self.lastBackgroundKey) as? Date
    }

    /// Called when the app goes to the background: screenshots taken after now are new.
    func markBackground() {
        UserDefaults.standard.set(Date(), forKey: Self.lastBackgroundKey)
    }

    /// Reads the access (it may have changed in Settings) and the inbox again.
    func refresh() {
        access = Self.currentAccess
        guard canRead else {
            inbox = []
            return
        }
        startObserving()
        var since: Date?
        var limit = 0
        if access == .full {
            since = lastBackground
            if since == nil { limit = Self.firstUseCount }
        }
        let assets = Self.fetch(since: since, limit: limit)
        inbox = assets
        thumbnails.stopCachingImagesForAllAssets()
        thumbnails.startCachingImages(for: Array(assets.prefix(60)), targetSize: Self.thumbnailSize,
                                      contentMode: .aspectFill, options: nil)
    }

    /// The newest screenshot Skreener can see, whatever its date.
    func newest() -> PHAsset? {
        Self.newestScreenshot()
    }

    /// The newest screenshot Skreener can see, for callers without the home screen (the Shortcuts actions, #439). It
    /// never asks for access: nil without it.
    nonisolated static func newestScreenshot() -> PHAsset? {
        fetch(since: nil, limit: 1).first
    }

    /// Screenshots in the Screenshots album, newest first, taken after `since` (if any); `limit` 0 is all of them.
    private nonisolated static func fetch(since: Date?, limit: Int) -> [PHAsset] {
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots,
                                                             options: nil)
        guard let album = albums.firstObject else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let since {
            predicates.append(NSPredicate(format: "creationDate > %@", since as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(in: album, options: options)
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    /// Watches the library, so a screenshot taken (or selected) while the app is open shows up.
    private func startObserving() {
        guard !observing else { return }
        observing = true
        PHPhotoLibrary.shared().register(self)
    }

    enum OpenError: Error {
        case noData
    }

    /// The asset's image bytes, downloaded from iCloud if need be, in their current (edited) version.
    static func imageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: info?[PHImageErrorKey] as? Error ?? OpenError.noData)
                }
            }
        }
    }
}

extension ScreenshotLibrary: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}
