import CoreGraphics
import Foundation

/// Step Recorder (#242): naming a step from what was clicked. Step text is Markdown-lite: `**bold**` and `\` escapes.
enum StepText {
    /// A piece of step text, bold or not.
    struct Segment: Equatable {
        var text: String
        var bold: Bool
    }

    /// AX roles of fields one types into: "Click the **Name** field".
    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXSecureTextField"]
    /// AX roles of menu items: "Choose **Save**".
    private static let menuRoles: Set<String> = ["AXMenuItem", "AXMenuBarItem", "AXMenuButton", "AXPopUpButton"]

    /// The step's text: the clicked element's accessibility name if it has one, else the OCR line nearest the click,
    /// else "Click in <app>".
    static func make(axName: String?, axRole: String?, ocrLine: String?, app: String?) -> String {
        guard let name = (axName.flatMap { clean($0) }) ?? (ocrLine.flatMap { clean($0) }) else { return fallback(app: app) }
        let bold = "**" + escape(name) + "**"
        let role = axName.flatMap { clean($0) } == nil ? nil : axRole
        if let role, fieldRoles.contains(role) { return "Click the \(bold) field" }
        if let role, menuRoles.contains(role) { return "Choose \(bold)" }
        return "Click \(bold)"
    }

    static func fallback(app: String?) -> String {
        guard let app = app.flatMap({ clean($0) }) else { return "Click here" }
        return "Click in " + escape(app)
    }

    /// One line: whitespace collapsed, at most `limit` characters (cut at a word with "…"). Nil when nothing readable
    /// is left (no letters or digits).
    static func clean(_ s: String, limit: Int = 60) -> String? {
        let words = s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var out = words.joined(separator: " ")
        guard out.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        if out.count > limit {
            let cut = String(out.prefix(limit))
            let word = cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? cut
            out = (word.isEmpty ? cut : word) + "…"
        }
        return out
    }

    /// The recognized line to name the step by: the one under the click, else the nearest. `lines` are in the same
    /// coordinates as `point`. Lines with nothing readable are skipped.
    static func bestLine(_ lines: [(text: String, box: CGRect)], near point: CGPoint) -> String? {
        func distance(_ r: CGRect) -> CGFloat {
            let dx = max(r.minX - point.x, 0, point.x - r.maxX), dy = max(r.minY - point.y, 0, point.y - r.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }
        return lines.filter { clean($0.text) != nil }.min { distance($0.box) < distance($1.box) }?.text
    }

    /// Backslash-escapes the characters Markdown would read as formatting.
    static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            if "\\`*_[]<>#|".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// The text split into plain and bold runs: `**` starts and ends bold, `\x` is a literal `x`. An unmatched `**` is
    /// kept as text.
    static func segments(_ text: String) -> [Segment] {
        enum Token { case text(String), marker }
        var tokens: [Token] = []
        var run = ""
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if c == "\\", let next = chars.popFirst() {
                run.append(next)
            } else if c == "*", chars.first == "*" {
                chars.removeFirst()
                if !run.isEmpty { tokens.append(.text(run)); run = "" }
                tokens.append(.marker)
            } else {
                run.append(c)
            }
        }
        if !run.isEmpty { tokens.append(.text(run)) }
        // An odd marker count leaves the last one unmatched: it is plain text.
        let markers = tokens.indices.filter { if case .marker = tokens[$0] { return true } else { return false } }
        let unmatched = markers.count % 2 == 1 ? markers.last : nil
        var out: [Segment] = []
        var bold = false
        func add(_ s: String) {
            if let last = out.last, last.bold == bold { out[out.count - 1].text += s } else { out.append(Segment(text: s, bold: bold)) }
        }
        for (i, token) in tokens.enumerated() {
            switch token {
            case .text(let s): add(s)
            case .marker: if i == unmatched { add("**") } else { bold.toggle() }
            }
        }
        return out
    }

    /// The text without its formatting.
    static func plain(_ text: String) -> String { segments(text).map(\.text).joined() }
}

/// Step Recorder's click handling that needs no screen (#242).
enum StepClicks {
    /// Clicks this soon after the last step (a double-click, say) don't make a new one.
    static let debounce: TimeInterval = 0.4

    static func accepts(_ time: TimeInterval, after last: TimeInterval?, interval: TimeInterval = debounce) -> Bool {
        guard let last else { return true }
        return time - last >= interval
    }

    /// The click (global, bottom-left origin) in a capture of `captureRect`: image points, bottom-left origin.
    static func imagePoint(_ click: CGPoint, in captureRect: CGRect) -> CGPoint {
        CGPoint(x: min(max(click.x - captureRect.minX, 0), captureRect.width),
                y: min(max(click.y - captureRect.minY, 0), captureRect.height))
    }

    /// The box around the click that OCR reads to name the step (image points), kept inside the image.
    static func ocrArea(around p: CGPoint, imageSize: CGSize, size: CGSize = CGSize(width: 280, height: 56)) -> CGRect {
        CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height)
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// `items` with the one at `index` moved `delta` places (clamped to the ends).
    static func moved<T>(_ items: [T], from index: Int, by delta: Int) -> [T] {
        guard items.indices.contains(index) else { return items }
        var out = items
        let item = out.remove(at: index)
        out.insert(item, at: min(max(index + delta, 0), out.count))
        return out
    }
}

/// The guide as Markdown and as one HTML file (#242).
enum StepGuideExport {
    struct Step: Equatable {
        /// Markdown-lite step text (see `StepText`).
        var text: String
        /// The image's address: a relative path for Markdown, a data: URI or path for HTML.
        var image: String
    }

    /// "step-01.png": numbered with enough digits for `count` steps (at least two), so the files sort in order.
    static func imageName(_ number: Int, of count: Int) -> String {
        let digits = max(2, String(count).count)
        let n = String(number)
        return "step-" + String(repeating: "0", count: max(0, digits - n.count)) + n + ".png"
    }

    /// A path for a Markdown link: each component percent-encoded (spaces and all), slashes kept.
    static func linkPath(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
    }

    static func markdown(title: String, steps: [Step]) -> String {
        var out = "# \(StepText.escape(title))\n"
        for (i, step) in steps.enumerated() {
            out += "\n## Step \(i + 1)\n\n\(step.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            out += "![Step \(i + 1)](\(linkPath(step.image)))\n"
        }
        return out
    }

    static func escapeHTML(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Step text as HTML: escaped, `**bold**` as `<strong>`, line breaks as `<br>`.
    static func inlineHTML(_ text: String) -> String {
        StepText.segments(text.trimmingCharacters(in: .whitespacesAndNewlines)).map { seg in
            let s = escapeHTML(seg.text).replacingOccurrences(of: "\n", with: "<br>")
            return seg.bold ? "<strong>\(s)</strong>" : s
        }.joined()
    }

    static func html(title: String, steps: [Step]) -> String {
        let t = escapeHTML(title)
        var out = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(t)</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 16px/1.5 -apple-system, system-ui, sans-serif; margin: 0; padding: 32px 16px; }
        main { max-width: 960px; margin: 0 auto; }
        ol { list-style: none; padding: 0; counter-reset: step; }
        li { counter-increment: step; margin: 0 0 40px; }
        li p::before { content: counter(step); display: inline-block; min-width: 1.6em; margin-right: .5em;
          border-radius: 1em; background: #e5484d; color: #fff; font-weight: 700; text-align: center; }
        li p { font-size: 18px; margin: 0 0 12px; }
        img { max-width: 100%; height: auto; border-radius: 8px; box-shadow: 0 2px 12px rgba(0,0,0,.2); }
        </style>
        </head>
        <body>
        <main>
        <h1>\(t)</h1>
        <ol>

        """
        for (i, step) in steps.enumerated() {
            out += "<li><p>\(inlineHTML(step.text))</p><img src=\"\(escapeHTML(step.image))\" alt=\"Step \(i + 1)\"></li>\n"
        }
        out += "</ol>\n</main>\n</body>\n</html>\n"
        return out
    }

    /// Where a PDF page draws an image of `size` inside `box` (bottom-left origin): scaled down to fit, never up,
    /// centered across and at the top of the box.
    static func fit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let k = min(1, box.width / size.width, box.height / size.height)
        let w = size.width * k, h = size.height * k
        return CGRect(x: box.midX - w / 2, y: box.maxY - h, width: w, height: h)
    }
}
