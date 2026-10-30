import AppKit
import Vision

/// Names saved screenshots after what they show: %t in the file name template (the default) becomes the web page's title
/// for a browser capture, else the capture's biggest line of text, read on this Mac with Vision. Nothing leaves the Mac.
/// The file is saved straight away as "Skreener …" and renamed once the page or the text is known; previews, editors
/// and Saved Files follow it like a file a filing rule moved (#277).
enum ContentNaming {
    /// A line of text Vision found, in fractions of the image: `height` of its box, `top` from the top edge.
    struct Line: Equatable {
        let text: String
        let height: CGFloat
        let top: CGFloat
    }

    /// Longest title kept in a file name, in characters; cut at a word.
    static let maxLength = 60

    /// Whether `template` names files after what they show.
    static func usesTitle(_ template: String) -> Bool {
        var chars = template.makeIterator()
        while let c = chars.next() {
            guard c == "%", let token = chars.next() else { continue }
            if token == "t" { return true }
        }
        return false
    }

    // MARK: Picking the title

    /// The capture's most prominent line: of the lines that read as words, the tallest (within 10%), the highest of
    /// those on a tie. Nil when no line reads as words.
    static func title(from lines: [Line]) -> String? {
        let wordy = lines.compactMap { line -> (line: Line, text: String)? in
            let text = clean(line.text)
            return readsAsWords(text) ? (line, text) : nil
        }
        guard let tallest = wordy.map(\.line.height).max() else { return nil }
        let best = wordy.filter { $0.line.height >= tallest * 0.9 }.min { $0.line.top < $1.line.top }
        return best.map { shorten($0.text) }
    }

    /// At least three letters, and mostly letters: not a time, a price or a row of symbols.
    static func readsAsWords(_ text: String) -> Bool {
        let visible = text.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) }
        let letters = visible.filter { CharacterSet.letters.contains($0) }.count
        return letters >= 3 && letters * 2 >= visible.count
    }

    /// One line with single spaces, without characters a file name can't have.
    static func clean(_ text: String) -> String {
        let flat = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return flat.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// At most `maxLength` characters, cut after a whole word, without a dangling separator or full stop.
    static func shorten(_ text: String) -> String {
        var out = text
        if out.count > maxLength {
            let cut = String(out.prefix(maxLength))
            out = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " -–—·|,;.…"))
    }

    /// After a token was left out: one space between words, one separator between parts ("Shot -  - 2026" →
    /// "Shot - 2026"), none at either end.
    static func tidySeparators(_ name: String) -> String {
        var out = name.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let separators = "-–—·|"
        if let run = try? NSRegularExpression(pattern: "( [\(separators)])( [\(separators)])+(?= )") {
            out = run.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1")
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " " + separators))
    }

    // MARK: Reading the capture

    /// The lines of text in `image`. Slow: off the main thread.
    static func lines(in image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox   // Vision's origin is the bottom left
            return Line(text: text, height: box.height, top: 1 - box.maxY)
        }
    }

    // MARK: Renaming

    /// Renames one saved capture once its title is known: the browser's page title as soon as it answers, else the
    /// text, once both the browser (or the lack of one) and Vision have answered. Main thread.
    final class Job {
        private let file: URL
        private let date: Date
        private let app: String?
        private var page: SourcePage.Page??
        private var lines: [Line]?
        private var done = false

        /// Nil when the file name template has no %t. Starts reading the text right away.
        init?(file: URL, image: NSImage, date: Date, app: String?,
              template: String = Preferences.filenameTemplate) {
            guard usesTitle(template), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            self.file = file
            self.date = date
            self.app = app
            DispatchQueue.global(qos: .utility).async {
                let lines = ContentNaming.lines(in: cg)
                DispatchQueue.main.async { self.textRead(lines) }
            }
        }

        /// The browser's front page, or nil for any other app or no answer.
        func pageAnswered(_ page: SourcePage.Page?) {
            self.page = .some(page)
            if let title = page?.title { finish(title) } else { finishFromText() }
        }

        private func textRead(_ lines: [Line]) {
            self.lines = lines
            finishFromText()
        }

        private func finishFromText() {
            guard case .some = page, let lines else { return }
            finish(ContentNaming.title(from: lines))
        }

        private func finish(_ title: String?) {
            guard !done else { return }
            done = true
            guard let title = title.map(ContentNaming.shorten), !title.isEmpty else { return }   // stays "Skreener …"
            ContentNaming.rename(file, to: Output.filename(for: date, app: app, title: title))
        }
    }

    /// Renames a saved capture (wherever a filing rule put it) in its folder, never over another file.
    static func rename(_ file: URL, to name: String) {
        let from = AutoFiling.current(file)
        guard FileManager.default.fileExists(atPath: from.path),
              name != from.deletingPathExtension().lastPathComponent else { return }
        let to = Output.uniqueURL(in: from.deletingLastPathComponent(), name: name, ext: from.pathExtension)
        do {
            // A rename keeps the file's tags, Spotlight comment and "Where from".
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            NSLog("Naming \(from.lastPathComponent) failed: \(error)")
            return
        }
        AutoFiling.remember(from, movedTo: to)
        SavedLibrary.shared.moved(from: from, to: to)
    }
}
