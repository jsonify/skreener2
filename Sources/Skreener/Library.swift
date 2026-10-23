import AppKit
import Vision

extension Notification.Name {
    /// Posted when the save folder's index changes (files added, removed, or their text read).
    static let skreenerLibraryChanged = Notification.Name("SkreenerLibraryChanged")
}

/// An index of the export location (#117): every screenshot, GIF and recording in it, including ones that were there
/// before Skreener, kept up to date while files are added or deleted (in Finder too). For search it keeps, per file,
/// the app in front when Skreener saved it, whether it was edited, and the text OCR finds in it (read in the
/// background), in a small JSON file in Application Support.
final class SavedLibrary {
    static let shared = SavedLibrary()

    enum Kind: String, CaseIterable, Codable {
        case image, gif, video

        var title: String {
            switch self {
            case .image: return "Screenshots"
            case .gif: return "GIFs"
            case .video: return "Recordings"
            }
        }

        init?(fileExtension ext: String) {
            switch ext.lowercased() {
            case "png", "jpg", "jpeg", "heic", "tiff", "tif": self = .image
            case "gif": self = .gif
            case "mp4", "mov", "m4v": self = .video
            default: return nil
            }
        }
    }

    /// What Skreener knows about a file beyond the file system.
    struct Meta: Codable, Equatable {
        var app: String?
        var edited = false
        /// The text OCR found; nil until it has been read.
        var text: String?
    }

    struct Entry: Equatable {
        let url: URL
        let date: Date
        let kind: Kind
        var meta: Meta

        var name: String { url.deletingPathExtension().lastPathComponent }
        /// "2026-03" for March 2026: what the Month filter groups by.
        var month: String { Self.monthKey.string(from: date) }

        static let monthKey: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM"
            return f
        }()
    }

    /// What the library panel's search field and filters ask for; nil or empty means any.
    struct Query: Equatable {
        var text = ""
        var month: String?
        var app: String?
        var kind: Kind?
        var editedOnly = false
    }

    /// Newest first. Main thread.
    private(set) var entries: [Entry] = []
    private(set) var isIndexing = false
    private var meta: [String: Meta] = [:]
    private var loadedMeta = false
    private var watched: URL?
    private var watcher: DispatchSourceFileSystemObject?
    private var reindexPending = false
    private var ocrRunning = false
    private let ocrQueue = DispatchQueue(label: "Skreener.library.ocr", qos: .utility)
    private let saveQueue = DispatchQueue(label: "Skreener.library.save", qos: .utility)

    private static var metaFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Skreener", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Library.json")
    }

    // MARK: Indexing

    /// Indexes the export location and watches it, moving to the new one when Settings changed it. Main thread.
    func refresh() {
        if !loadedMeta {
            loadedMeta = true
            if let data = try? Data(contentsOf: Self.metaFile),
               let saved = try? JSONDecoder().decode([String: Meta].self, from: data) { meta = saved }
        }
        let dir = Preferences.saveDirectory.standardizedFileURL
        if dir != watched { watch(dir) }
        reindex()
    }

    private func watch(_ dir: URL) {
        watcher?.cancel()
        watcher = nil
        watched = dir
        entries = []
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReindex() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Several changes in a row (a recording being written, a batch moved in Finder) index once.
    private func scheduleReindex() {
        guard !reindexPending else { return }
        reindexPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.reindexPending = false
            self?.reindex()
        }
    }

    private func reindex() {
        guard let dir = watched else { return }
        isIndexing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = Self.list(dir)
            DispatchQueue.main.async {
                guard let self, self.watched == dir else { return }
                self.entries = files.map { Entry(url: $0.url, date: $0.date, kind: $0.kind, meta: self.meta[$0.url.lastPathComponent] ?? Meta()) }
                self.isIndexing = false
                NotificationCenter.default.post(name: .skreenerLibraryChanged, object: nil)
                self.readTextInBackground()
            }
        }
    }

    /// The screenshots, GIFs and recordings in `dir` (not in subfolders), newest first.
    static func list(_ dir: URL) -> [(url: URL, date: Date, kind: Kind)] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> (url: URL, date: Date, kind: Kind)? in
            guard let kind = Kind(fileExtension: url.pathExtension),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return (url, values.creationDate ?? .distantPast, kind)
        }.sorted { $0.date > $1.date }
    }

    // MARK: Metadata

    /// Records what Skreener knows about a file it just saved: the app in front when it was captured, and whether it
    /// was edited. Leaves out what isn't given. Main thread.
    func note(_ url: URL, app: String? = nil, edited: Bool? = nil) {
        if !loadedMeta { refresh() }
        let key = url.lastPathComponent
        var m = meta[key] ?? Meta()
        if let app { m.app = app }
        if let edited { m.edited = m.edited || edited }
        // A file saved over is a new picture: its text is read again.
        m.text = nil
        meta[key] = m
        if let i = entries.firstIndex(where: { $0.url.lastPathComponent == key }) { entries[i].meta = m }
        saveMeta()
    }

    private func saveMeta() {
        let snapshot = meta
        let url = Self.metaFile
        saveQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Reads the text in screenshots that haven't been read yet, one at a time, at low priority.
    private func readTextInBackground() {
        guard !ocrRunning, let next = entries.first(where: { $0.kind == .image && $0.meta.text == nil }) else { return }
        ocrRunning = true
        let url = next.url
        ocrQueue.async { [weak self] in
            let text = Self.recognizeText(at: url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.ocrRunning = false
                let key = url.lastPathComponent
                var m = self.meta[key] ?? Meta()
                m.text = text
                self.meta[key] = m
                if let i = self.entries.firstIndex(where: { $0.url == url }) { self.entries[i].meta = m }
                // Save every so often rather than after every file.
                if self.entries.filter({ $0.kind == .image && $0.meta.text == nil }).count % 20 == 0 { self.saveMeta() }
                self.readTextInBackground()
            }
        }
    }

    private static func recognizeText(at url: URL) -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return "" }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: Search and filters

    /// The entries matching `q`: every word of the search text in the file name, the app's name or the text in it.
    static func filter(_ entries: [Entry], _ q: Query) -> [Entry] {
        let words = q.text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { e in
            if let m = q.month, e.month != m { return false }
            if let a = q.app, e.meta.app != a { return false }
            if let k = q.kind, e.kind != k { return false }
            if q.editedOnly, !e.meta.edited { return false }
            guard !words.isEmpty else { return true }
            let hay = [e.name, e.meta.app ?? "", e.meta.text ?? ""].joined(separator: "\n").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    /// Each value of `key` among `entries` and how many entries have it, most common first.
    static func counts(_ entries: [Entry], by key: (Entry) -> String?) -> [(value: String, count: Int)] {
        var c: [String: Int] = [:]
        for e in entries { if let v = key(e) { c[v, default: 0] += 1 } }
        return c.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.value < $1.value }
    }
}
