import Photos
import PhotosUI
import SkreenerEditor
import SwiftUI
import SK1Tokens
import SK1UI

/// The app's home: an inbox of the screenshots taken since Skreener was last left (a contact sheet; the LCD reads
/// `N NEW`), and keys to open the latest screenshot or choose any image. Opening one shows the editor full screen.
@MainActor
struct HomeView: View {
    @ObservedObject var library: ScreenshotLibrary
    /// Screenshots the Shortcuts actions ask to open (#439).
    @ObservedObject var router: AppRouter
    /// The editor on screen, if any.
    @State private var session: EditorSession?
    /// An image is being read (from iCloud, maybe).
    @State private var opening = false
    /// What went wrong last, shown on the LCD until the next action.
    @State private var failure: String?
    @State private var picked: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 12) {
            SKPlate {
                HStack {
                    SKCaption("Skreener")
                    Spacer()
                }
                .padding(8)
            }
            SKReadout(readout)
            if let hint {
                Text(hint)
                    .sk1Hint()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SKWell { inbox.padding(10) }
                .frame(maxHeight: .infinity)
            keys
            Text("Skreener is in the share sheet too: tap Share on a screenshot and choose Skreener.")
                .sk1Hint()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .sk1Chassis()
        .disabled(opening)
        .fullScreenCover(item: $session) { session in
            ShareView(model: session.model,
                      onClose: { self.session = nil },
                      onShare: { url in Presenter.share(url) })
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await open(item) }
        }
        // Initial too: an intent may have asked before this screen existed.
        .onChange(of: router.request?.id, initial: true) {
            guard let asset = router.take() else { return }
            Task { await open(asset) }
        }
    }

    // MARK: Readout

    private var readout: String {
        if opening { return "OPENING…" }
        if let failure { return failure }
        switch library.access {
        case .notAsked:
            return "TAP SHOW MY SCREENSHOTS"
        case .denied:
            return "PHOTOS ACCESS IS OFF"
        case .limited:
            return library.inbox.isEmpty ? "NO SCREENSHOTS SELECTED" : "\(library.inbox.count) SELECTED"
        case .full:
            return library.inbox.isEmpty ? "NO NEW SCREENSHOTS" : "\(library.inbox.count) NEW"
        }
    }

    private var hint: String? {
        switch library.access {
        case .notAsked, .full:
            return nil
        case .denied:
            return "To see your screenshots here, allow Skreener in Settings > Privacy & Security > Photos. "
                + "Choose screenshot works without it."
        case .limited:
            return library.inbox.isEmpty
                ? "Skreener sees only the photos you selected. Tap Select more, or Choose screenshot."
                : "Skreener sees only the screenshots you selected."
        }
    }

    // MARK: Inbox

    @ViewBuilder private var inbox: some View {
        if library.canRead && !library.inbox.isEmpty {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(library.inbox, id: \.localIdentifier) { asset in
                        Button { Task { await open(asset) } } label: {
                            Thumbnail(asset: asset, manager: library.thumbnails)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: emptyIcon)
                    .font(.system(size: 40, weight: .light))
                    .accessibilityHidden(true)
                Text(emptyText)
                    .sk1Hint()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyIcon: String {
        switch library.access {
        case .notAsked, .full: return "camera.viewfinder"
        case .limited, .denied: return "photo.badge.exclamationmark"
        }
    }

    private var emptyText: String {
        switch library.access {
        case .notAsked: return "Your new screenshots show here."
        case .full: return "Screenshots you take show here."
        case .limited: return "No screenshots selected."
        case .denied: return "Photos access is off."
        }
    }

    // MARK: Keys

    @ViewBuilder private var keys: some View {
        VStack(spacing: 10) {
            if library.access == .notAsked {
                Button("Show my screenshots") { Task { await showScreenshots() } }
                    .buttonStyle(.sk1Key(.orange, size: .large))
            }
            if library.access == .limited {
                Button("Select more") { Presenter.selectMorePhotos() }
                    .buttonStyle(.sk1Key())
            }
            SKKeyTray {
                Button("Latest screenshot") { Task { await openLatest() } }
                    .buttonStyle(.sk1Key())
                PhotosPicker(selection: $picked, matching: .images) {
                    Text("Choose screenshot")
                }
                .buttonStyle(.sk1Key())
            }
        }
    }

    // MARK: Opening

    private func showScreenshots() async {
        failure = nil
        await library.requestAccess()
    }

    private func openLatest() async {
        failure = nil
        await library.requestAccess()
        // Denied: the LCD says so.
        guard library.canRead else { return }
        guard let asset = library.newest() else {
            failure = library.access == .limited ? "NO SCREENSHOTS SELECTED" : "NO SCREENSHOTS YET"
            return
        }
        await open(asset)
    }

    private func open(_ asset: PHAsset) async {
        await openImage { try await ScreenshotLibrary.imageData(for: asset) }
    }

    private func open(_ item: PhotosPickerItem) async {
        await openImage {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ScreenshotLibrary.OpenError.noData
            }
            return data
        }
    }

    /// Reads the image bytes, then shows them in a fresh editor. A failure shows on the LCD.
    private func openImage(reading read: () async throws -> Data) async {
        guard !opening else { return }
        failure = nil
        opening = true
        let data = try? await read()
        opening = false
        guard let data else {
            failure = "COULD NOT OPEN THE IMAGE"
            return
        }
        let model = ShareModel()
        model.load(source: .data(data))
        session = EditorSession(model: model)
    }
}

/// One editor on screen, with its own model.
struct EditorSession: Identifiable {
    let id = UUID()
    let model: ShareModel
}

/// A screenshot in the inbox, cropped to a phone-shaped cell.
private struct Thumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?

    var body: some View {
        Color(sk1Hex: SK1.lcdInk)
            .opacity(0.08)
            .aspectRatio(0.5, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
    }

    private var label: String {
        guard let date = asset.creationDate else { return "Screenshot" }
        return "Screenshot, " + date.formatted(date: .abbreviated, time: .shortened)
    }

    private func load() {
        guard image == nil, request == nil else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        request = manager.requestImage(for: asset, targetSize: ScreenshotLibrary.thumbnailSize,
                                       contentMode: .aspectFill, options: options) { result, _ in
            // Asynchronous requests answer on the main thread: first a quick, blurry image, then the sharp one.
            if let result { image = result }
        }
    }

    private func cancel() {
        if let request { manager.cancelImageRequest(request) }
        request = nil
    }
}
