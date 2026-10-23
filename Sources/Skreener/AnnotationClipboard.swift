import AppKit

/// Copied annotations (#125). They stay editable objects, so they are kept here in memory; the pasteboard gets a token
/// of a private type, so anything copied after them (in Skreener or another app) takes precedence, as usual.
enum AnnotationClipboard {
    static let type = NSPasteboard.PasteboardType("com.skreener.annotation")

    private static var token = ""
    private static var copied: [Annotation] = []

    /// Puts `items` on `pasteboard`, replacing what was there.
    static func write(_ items: [Annotation], to pasteboard: NSPasteboard = .general) {
        guard !items.isEmpty else { return }
        token = UUID().uuidString
        copied = items
        pasteboard.clearContents()
        pasteboard.setString(token, forType: type)
    }

    /// The annotations last copied, while they are still what's on `pasteboard`; nil otherwise.
    static func read(from pasteboard: NSPasteboard = .general) -> [Annotation]? {
        guard !copied.isEmpty, pasteboard.string(forType: type) == token else { return nil }
        return copied
    }

    /// Copies to paste into a canvas that already holds `existing`: new identities (pasted counters take the next
    /// numbers), moved 10 pt down and right as many times as needed so a copy never lands exactly on an annotation
    /// that is already there (pasting into another screenshot keeps the same place).
    static func pasted(_ items: [Annotation], into existing: [Annotation]) -> [Annotation] {
        guard !items.isEmpty else { return [] }
        let taken = Set(existing.map { PointKey($0.start) })
        var shift: CGFloat = 0
        while items.contains(where: { taken.contains(PointKey(NSPoint(x: $0.start.x + shift, y: $0.start.y - shift))) }) {
            shift += 10
        }
        return items.map { a in
            var b = a.duplicate()
            b.translate(dx: shift, dy: -shift)
            return b
        }
    }

    private struct PointKey: Hashable {
        let x: CGFloat, y: CGFloat
        init(_ p: NSPoint) { x = p.x; y = p.y }
    }
}
