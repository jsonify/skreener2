import Photos
import PhotosUI
import SkreenerEditor
import SwiftUI
import SK1Tokens
import SK1UI

/// The app's home: an inbox of the screenshots taken since Skreener was last left (a contact sheet; the LCD reads
/// `N NEW`), and keys to open the latest screenshot or choose any image. Opening one shows the editor full screen,
/// presented through UIKit by `EditorPresenter` (as the Share Extension hosts it), not SwiftUI's `fullScreenCover`.
@MainActor
struct HomeView: View {
    @ObservedObject var library: ScreenshotLibrary
    /// Screenshots the Shortcuts actions ask to open (#439).
    @ObservedObject var router: AppRouter
    /// The editor on screen, if any. Setting it shows a fresh editor (replacing one on screen); clearing it dismisses
    /// the editor (`EditorPresenter`).
    @State private var session: EditorSession?
    /// An image is being read (from iCloud, maybe).
    @State private var opening = false
    /// What went wrong last, or what the Frame Latest control did (#439), shown on the LCD until the next action.
    @State private var failure: String?
    @State private var picked: PhotosPickerItem?
    /// More about the failure, shown as the hint under the LCD.
    @State private var failureDetail: String?
    /// A long screenshot being made (#456), with its panel over the screen.
    @State private var longShot: LongShotRun?
    @State private var pickingRecording = false
    @State private var pickingScreenshots = false
    @State private var pickedRecording: PhotosPickerItem?
    @State private var pickedScreenshots: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 10) {
            header
            lcd
            if let hint {
                Text(hint)
                    .sk1Hint()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SKWell(radius: SK1.Metrics.trayRadius) { inbox.padding(10) }
                .frame(maxHeight: .infinity)
            keys
            Text("Skreener is in the share sheet too: tap Share on a screenshot and choose Skreener.")
                .sk1Hint()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // The chassis fills the screen; the content stays inside the safe area.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SKChassisFill() }
        .disabled(opening || longShot != nil)
        .overlay {
            if let longShot { LongShotProgressView(run: longShot) }
        }
        .onChange(of: session?.id) { showEditor() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await open(item) }
        }
        .onChange(of: pickedRecording) { _, item in
            guard let item else { return }
            pickedRecording = nil
            makeLongShot(fromRecording: item)
        }
        .onChange(of: pickedScreenshots) { _, items in
            guard !items.isEmpty else { return }
            pickedScreenshots = []
            makeLongShot(fromScreenshots: items)
        }
        // Initial too: an intent may have asked before this screen existed.
        .onChange(of: router.request?.id, initial: true) {
            guard let asset = router.take() else { return }
            Task { await open(asset) }
        }
        // The Frame Latest control's result (#439), also from before this screen existed.
        .onChange(of: router.reportCount, initial: true) {
            guard router.reportCount > 0 else { return }
            failure = router.lastReport?.title
            failureDetail = router.lastReport?.detail
        }
        // A finished live scrolling capture (#456, LiveScrollCapture.swift) opens like a picked image, once no editor is up.
        .onLiveScrollCapture(when: session == nil) { capture in await openImage { try await capture.joinedPNG() } }
#if DEBUG
        // -SKDemoEditor (DemoLaunch.swift): the editor on a sample picture, for the Simulator screenshots.
        .task { await openDemo() }
#endif
    }

    /// Presents the session's editor, or dismisses the editor when the session ended. Close ends the session only if it
    /// is still the one on screen (a Shortcut may have replaced it).
    private func showEditor() {
        guard let session else {
            EditorPresenter.dismiss()
            return
        }
        let id = session.id
        EditorPresenter.show(session.model, notice: session.notice, onClose: {
            if self.session?.id == id { self.session = nil }
        })
    }

#if DEBUG
    /// Opens the demo editor through the same `EditorPresenter` as a real pick, once the home screen is on screen.
    private func openDemo() async {
        guard DemoLaunch.opensEditor, session == nil, let model = DemoLaunch.editorModel() else { return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        session = EditorSession(model: model)
    }
#endif

    // MARK: Header and LCD

    /// "SK-1 Skreener" and a speaker grille, as on the Mac's panels; the editor shows the same header.
    private var header: some View {
        SKAppHeader()
    }

    /// The LCD: the count in seven-segment digits and what it counts ("12" "NEW"), or the state in words, a short
    /// line under it, and the inbox lamp. VoiceOver reads the readout ("12 NEW").
    private var lcd: some View {
        let (number, title) = lcdParts
        return SKLCD {
            HStack(spacing: 14) {
                if let number {
                    SKSevenSegment(SK1.SevenSegment.cells(number, count: 2), digitHeight: 38, spacing: 4)
                        .shadow(color: Color(sk1Hex: SK1.lcdInk, opacity: 0.15), radius: 0, x: 1, y: 1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(1.2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let line = lcdLine {
                        Text(line)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    SKLamp(color: .orange, lit: library.canRead && !library.inbox.isEmpty, glow: 0, size: 6)
                    Text("INBOX")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 14)
            }
            .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
            .padding(.horizontal, 16)
        }
        .frame(height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(readout))
    }

    /// The readout as a number in digits and words, when it is a count ("12 NEW", "3 SELECTED").
    private var lcdParts: (Int?, String) {
        if !opening, failure == nil, library.canRead, !library.inbox.isEmpty {
            return (library.inbox.count, library.access == .limited ? "SELECTED" : "NEW")
        }
        return (nil, readout)
    }

    /// The short line under the LCD's words, with screenshots to show.
    private var lcdLine: String? {
        lcdParts.0 == nil ? nil : "Tap one to edit it"
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
        if let failureDetail { return failureDetail }
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

    /// The main action is orange: Show my screenshots until Photos access is asked, then Latest screenshot.
    @ViewBuilder private var keys: some View {
        VStack(spacing: 8) {
            if library.access == .notAsked {
                Button("Show my screenshots") { Task { await showScreenshots() } }
                    .buttonStyle(.skPhoneKey(.orange, fill: true))
            }
            if library.access == .limited {
                Button("Select more") { Presenter.selectMorePhotos() }
                    .buttonStyle(.skPhoneKey(fill: true))
            }
            ScrollCaptureKey()
            VStack(spacing: 5) {
                SKWell(radius: SK1.Metrics.trayRadius) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Button("Latest screenshot") { Task { await openLatest() } }
                                .buttonStyle(.skPhoneKey(library.access == .notAsked ? .cream : .orange, fill: true))
                            PhotosPicker(selection: $picked, matching: .images) {
                                Text("Choose screenshot")
                            }
                            .buttonStyle(.skPhoneKey(fill: true))
                        }
                        longShotKey
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 5)
                    .padding(.bottom, 4)
                }
                SKCaption("Open").accessibilityHidden(true)
            }
        }
    }

    /// Long screenshot (#456): a menu of where the frames come from, each opening the system photo picker (no Photos
    /// access needed). A recording is handed over as it is (`.current`), not converted first; screenshots keep the
    /// order they were picked in, and `photoLibrary` gives their identifiers for sorting them by date.
    private var longShotKey: some View {
        Menu {
            Button { pickingRecording = true } label: {
                Label("From a screen recording", systemImage: "record.circle")
            }
            Button { pickingScreenshots = true } label: {
                Label("From screenshots", systemImage: "square.stack")
            }
        } label: {
            Text("Long screenshot")
        }
        .menuStyle(.button)
        .buttonStyle(.skPhoneKey(fill: true))
        .accessibilityHint(Text("Stitches a screen recording or overlapping screenshots into one tall image."))
        .photosPicker(isPresented: $pickingRecording, selection: $pickedRecording, matching: .videos,
                      preferredItemEncoding: .current)
        .photosPicker(isPresented: $pickingScreenshots, selection: $pickedScreenshots, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current,
                      photoLibrary: .shared())
    }

    // MARK: Opening

    private func showScreenshots() async {
        failure = nil
        failureDetail = nil
        await library.requestAccess()
    }

    private func openLatest() async {
        failure = nil
        failureDetail = nil
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
        failureDetail = nil
        opening = true
        let data = try? await read()
        opening = false
        guard let data else {
            failure = "COULD NOT OPEN THE IMAGE"
            return
        }
        await openEditor(on: .data(data))
    }

    /// Shows `source` in a fresh editor, with `notice` over it for a few seconds.
    private func openEditor(on source: ImageSource, notice: String? = nil) async {
        // The system photo picker may still be going away (it runs out of process); the editor is presented once it
        // is gone, as presenting during its dismissal left the editor's keys outside the safe area (#440).
        await Presenter.waitUntilSettled()
        let model = ShareModel()
        model.load(source: source)
        session = EditorSession(model: model, notice: notice)
    }

    // MARK: Long screenshot

    private func makeLongShot(fromRecording item: PhotosPickerItem) {
        makeLongShot("READING THE RECORDING…") { run in
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw LongShotError.unreadableRecording
            }
            defer { movie.remove() }
            try Task.checkCancellation()
            run.title = "STITCHING THE RECORDING…"
            return try await LongShotMaker.fromRecording(at: movie.url, progress: run.reporter(from: 0))
        }
    }

    private func makeLongShot(fromScreenshots items: [PhotosPickerItem]) {
        let ordered = Self.inShootingOrder(items)
        makeLongShot("READING SCREENSHOTS…") { run in
            guard ordered.count >= 2 else { throw LongShotError.tooFewScreenshots }
            var files: [Data] = []
            for (index, item) in ordered.enumerated() {
                try Task.checkCancellation()
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    throw LongShotError.unreadableScreenshot(index + 1)
                }
                files.append(data)
                run.progress = 0.3 * Double(index + 1) / Double(ordered.count)
            }
            run.title = "STITCHING SCREENSHOTS…"
            return try await LongShotMaker.fromScreenshots(files, progress: run.reporter(from: 0.3))
        }
    }

    /// Runs `work` with the progress panel up, then opens the long screenshot in the editor, or shows on the LCD why
    /// there is none. Cancel stops it and shows nothing.
    private func makeLongShot(_ title: String, _ work: @escaping @MainActor (LongShotRun) async throws -> LongShot) {
        guard longShot == nil, !opening else { return }
        failure = nil
        failureDetail = nil
        let run = LongShotRun(title: title)
        longShot = run
        run.task = Task {
            do {
                let shot = try await work(run)
                try Task.checkCancellation()
                longShot = nil
                await openEditor(on: LongShotMaker.source(shot.png), notice: shot.notice)
            } catch is CancellationError {
                longShot = nil
            } catch let error as LongShotError {
                longShot = nil
                failure = error.title
                failureDetail = error.detail
            } catch {
                longShot = nil
                failure = Task.isCancelled ? nil : LongShotError.couldNotEncode.title
            }
        }
    }

    /// Screenshots sorted by when they were taken, which is top to bottom when taken while scrolling. Their dates are
    /// only readable with Photos access (never asked for here); without it, or for any item without one, they stay in
    /// the order they were picked.
    private static func inShootingOrder(_ items: [PhotosPickerItem]) -> [PhotosPickerItem] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return items }
        let ids = items.compactMap(\.itemIdentifier)
        guard ids.count == items.count else { return items }
        var dates: [String: Date] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            if let date = asset.creationDate { dates[asset.localIdentifier] = date }
        }
        guard dates.count == Set(ids).count else { return items }
        return items.enumerated().sorted { a, b in
            let da = dates[a.element.itemIdentifier ?? ""] ?? .distantPast
            let db = dates[b.element.itemIdentifier ?? ""] ?? .distantPast
            return da == db ? a.offset < b.offset : da < db
        }.map(\.element)
    }
}

/// One editor on screen, with its own model.
struct EditorSession: Identifiable {
    let id = UUID()
    let model: ShareModel
    /// Shown over the editor for a few seconds (a long screenshot that only partly stitched).
    var notice: String? = nil
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
