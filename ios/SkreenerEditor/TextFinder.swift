import SkreenerCore
import SwiftUI
import UIKit

/// Finds text to redact with on-device OCR, like the Mac's Redact and Redact Text: emails, phone numbers and links,
/// or the terms typed in the search box (comma-separated). Matches are boxes in full-image pixels (bottom-left
/// origin, as Vision's own boxes are), shown on the preview; tapping one takes it out or back in. It also runs Safe
/// Check's scan (#408) and shows its findings the same way (`SafeCheck.swift`). One OCR pass at a time, so the full
/// image is loaded only once at a time.
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
            if !terms.isEmpty { kind = nil; reviewing = false }
            refresh()
        }
    }
    @Published private(set) var hits: [RedactText.Hit] = []
    /// The kind key whose matches are shown, if any.
    @Published private(set) var kind: Kind?
    /// OCR is running.
    @Published private(set) var reading = false
    /// Safe Check: what the scan on open found (boxes padded), in reading order; nil until it has read the image.
    @Published private(set) var leaks: [LeakScan.Finding]?
    /// Safe Check's findings are the matches shown (its Review key), in `reviewed`'s order.
    @Published private(set) var reviewing = false
    /// Each Redact N of Safe Check's findings, oldest first.
    @Published private(set) var leakCovers: [SafeCheck.Cover] = []
    /// The findings `hits` stand for while reviewing.
    private var reviewed: [LeakScan.Finding] = []
    /// The scan was asked for while another OCR pass was running.
    private var scanPending = false

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
        // The Safe Check scan reads too, but says so on its own line.
        let searching = kind != nil || reviewing || !terms.isEmpty
        return RedactText.status(hits, reading: reading && searching, invalidPattern: false, searching: searching)
    }

    var selectedCount: Int { hits.filter(\.selected).count }

    /// The selected matches' boxes, in full-image pixels.
    var selectedBoxes: [CGRect] { hits.filter(\.selected).flatMap(\.boxes) }

    /// Shows the matches of a kind key, reading the image first if need be.
    func find(_ kind: Kind) {
        self.kind = kind
        reviewing = false
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
        reviewing = false
        query = ""
        hits = []
    }

    private var terms: [String] {
        query.components(separatedBy: ",").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func refresh() {
        // Safe Check's findings stay as reviewed (and ticked) until another search replaces them.
        if reviewing { return }
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
        case leaks
    }

    private enum Reading: Sendable {
        case index(TextRecognizer.TextIndex)
        case boxes(Kind, [CGRect])
        case leaks([LeakScan.Finding])
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
            case .leaks(let findings): self.leaks = findings
            }
            self.reading = false
            self.refresh()
            if self.scanPending { self.scanForLeaks() }
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
        case .leaks:
            guard let image else { return .leaks([]) }
            let findings = await LeakScan.scan(image, size: full)
            // Padded like the Mac's Redact.
            return .leaks(findings.map { LeakScan.Finding(kind: $0.kind, box: $0.box.insetBy(dx: -3, dy: -2)) })
        }
    }

    // MARK: Safe Check

    /// Starts Safe Check's scan, once: after the OCR pass running now, if any.
    func scanForLeaks() {
        guard leaks == nil else { scanPending = false; return }
        guard source != nil else { leaks = []; return }
        guard !reading else { scanPending = true; return }
        scanPending = false
        read(.leaks)
    }

    /// Shows `findings` as the matches, all ticked, for Redact N or a tap to leave one out.
    func review(_ findings: [LeakScan.Finding]) {
        kind = nil
        reviewing = true
        query = ""
        reviewed = findings
        hits = findings.map { RedactText.Hit(boxes: [$0.box]) }
    }

    /// While reviewing: the findings left unticked.
    var unticked: [LeakScan.Finding] {
        guard reviewing else { return [] }
        return zip(reviewed, hits).filter { !$0.1.selected }.map { $0.0 }
    }

    /// Notes that Redact N covered the ticked findings with `redactions`.
    func noteLeaksCovered(by redactions: [Redaction]) {
        guard reviewing, !redactions.isEmpty else { return }
        leakCovers.append(SafeCheck.Cover(redactions: redactions, left: unticked))
    }
}
