import SkreenerCore
import SwiftUI
import UIKit

/// Finds text to redact with on-device OCR, like the Mac's Redact and Redact Text: emails, phone numbers and links,
/// or the terms typed in the search box (comma-separated). Matches are boxes in full-image pixels (bottom-left
/// origin, as Vision's own boxes are), shown on the preview; tapping one takes it out or back in.
@MainActor
final class TextFinder: ObservableObject {
    enum Kind: Hashable, CaseIterable, Sendable {
        case emails, phones, links

        var title: String {
            switch self {
            case .emails: return "Emails"
            case .phones: return "Phones"
            case .links: return "Links"
            }
        }

        var sensitive: TextRecognizer.Sensitive {
            switch self {
            case .emails: return .emails
            case .phones: return .phoneNumbers
            case .links: return .links
            }
        }
    }

    /// The search box. Typing replaces the matches of a kind key.
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            if !terms.isEmpty { kind = nil }
            refresh()
        }
    }
    @Published private(set) var hits: [RedactText.Hit] = []
    /// The kind key whose matches are shown, if any.
    @Published private(set) var kind: Kind?
    /// OCR is running.
    @Published private(set) var reading = false

    private var source: ImageSource?
    private var size = CGSize.zero
    /// All the text, read the first time the search box is used. Only this is kept, never the image.
    private var index: TextRecognizer.TextIndex?
    /// Each kind's boxes, read the first time its key is tapped.
    private var found: [Kind: [CGRect]] = [:]

    /// Where to read from; `size` is the full image's size in pixels.
    func prepare(source: ImageSource, size: CGSize) {
        self.source = source
        self.size = size
    }

    var status: String {
        RedactText.status(hits, reading: reading, invalidPattern: false, searching: kind != nil || !terms.isEmpty)
    }

    var selectedCount: Int { hits.filter(\.selected).count }

    /// The selected matches' boxes, in full-image pixels.
    var selectedBoxes: [CGRect] { hits.filter(\.selected).flatMap(\.boxes) }

    /// Shows the matches of a kind key, reading the image first if need be.
    func find(_ kind: Kind) {
        self.kind = kind
        query = ""
        refresh()
    }

    /// Takes the match under `p` (full-image pixels) out, or back in. False when `p` is on none.
    @discardableResult
    func toggle(at p: CGPoint) -> Bool {
        guard let toggled = RedactText.toggling(hits, at: p) else { return false }
        hits = toggled
        return true
    }

    func clear() {
        kind = nil
        query = ""
        hits = []
    }

    private var terms: [String] {
        query.components(separatedBy: ",").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func refresh() {
        if let kind {
            guard let boxes = found[kind] else { read(.kind(kind)); return }
            // Padded like the Mac's Redact.
            hits = RedactText.hits(boxes.map { [$0.insetBy(dx: -3, dy: -2)] }, keeping: hits)
            return
        }
        let terms = self.terms
        guard !terms.isEmpty else { hits = []; return }
        guard let index else { read(.index); return }
        let matches = TextMatcher.matches(of: terms, in: index.lines, options: TextMatcher.Options())
        let boxes = matches.map { match in
            RedactText.boxes(for: match) { span in index.box(line: span.line, range: span.range) }
        }
        hits = RedactText.hits(boxes, keeping: hits)
    }

    private enum Request: Sendable {
        case index
        case kind(Kind)
    }

    private enum Reading: Sendable {
        case index(TextRecognizer.TextIndex)
        case boxes(Kind, [CGRect])
    }

    /// One OCR pass at a time; `refresh` afterwards starts the next if the search moved on meanwhile.
    private func read(_ request: Request) {
        guard !reading, let source else { return }
        reading = true
        let size = self.size
        Task { [weak self] in
            let result = await Self.recognize(request, source: source, size: size)
            guard let self else { return }
            switch result {
            case .index(let index): self.index = index
            case .boxes(let kind, let boxes): self.found[kind] = boxes
            }
            self.reading = false
            self.refresh()
        }
    }

    /// Reloads the full image, reads it and lets it go, so only the text or boxes stay in memory. Vision's boxes
    /// come back bottom-left origin, scaled to `size`: full-image pixels, as Redaction takes them. An image that
    /// can't be loaded reads as no text, so it isn't retried over and over.
    private nonisolated static func recognize(_ request: Request, source: ImageSource, size: CGSize) async -> Reading {
        let image = try? await source.load()
        let full = image.map { CGSize(width: $0.width, height: $0.height) } ?? size
        switch request {
        case .index:
            guard let image else { return .index(TextRecognizer.TextIndex(size: full)) }
            return .index(await TextRecognizer.index(of: image, size: full))
        case .kind(let kind):
            guard let image else { return .boxes(kind, []) }
            return .boxes(kind, await TextRecognizer.boxes(in: image, size: full, matching: kind.sensitive))
        }
    }
}
