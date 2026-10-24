import AppKit

/// The editor's state apart from the screenshot itself: the annotations, the crop and the background. Capture history
/// keeps one next to each capture, so reopening it carries on editing instead of starting from the flattened image (#30).
///
/// On disk it is a folder: `document.json`, `base.png` (the screenshot as the editor holds it, which rotating or
/// flipping changes) and an `img-<id>.png` for each picture added to the capture.
struct EditorDocument {
    static let version = 1

    var items: [Annotation] = []
    var crop: NSRect?
    var background: Background?

    private static let documentFile = "document.json"
    private static let baseFile = "base.png"
    private static func imageFile(_ id: UUID) -> String { "img-\(id.uuidString).png" }

    /// Writes the document into `folder`. `base` is written only when given: it is the biggest file and rarely changes.
    func write(to folder: URL, base: NSImage?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let base { try Self.png(base).write(to: folder.appendingPathComponent(Self.baseFile)) }
        var kept = Set<String>()
        for a in items {
            guard let image = a.image else { continue }
            let name = Self.imageFile(a.id)
            kept.insert(name)
            let url = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) { try Self.png(image).write(to: url) }
        }
        // Pictures that have since been deleted from the capture.
        for file in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        where file.hasPrefix("img-") && !kept.contains(file) {
            try? fm.removeItem(at: folder.appendingPathComponent(file))
        }
        var root: [String: Any] = ["version": Self.version, "items": items.map(Self.encode)]
        if let crop { root["crop"] = [crop.minX, crop.minY, crop.width, crop.height].map(Double.init) }
        if let background { root["background"] = background.plist }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent(Self.documentFile))
    }

    /// The document in `folder` with its screenshot, or nil when there is none or it can't be read (a newer version,
    /// say): the caller then falls back to the flattened capture.
    static func read(from folder: URL) -> (base: NSImage, document: EditorDocument)? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(documentFile)),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["version"] as? Int).map({ $0 <= version }) == true,
              let base = NSImage(contentsOf: folder.appendingPathComponent(baseFile)) else { return nil }
        var doc = EditorDocument()
        for d in root["items"] as? [[String: Any]] ?? [] {
            guard var a = decode(d) else { continue }
            if d["image"] as? Bool == true { a.image = NSImage(contentsOf: folder.appendingPathComponent(imageFile(a.id))) }
            // A picture whose file went missing has nothing to show.
            if a.tool == .image, a.image == nil { continue }
            doc.items.append(a)
        }
        if let c = root["crop"] as? [Double], c.count == 4 { doc.crop = NSRect(x: c[0], y: c[1], width: c[2], height: c[3]) }
        if let b = root["background"] as? [String: Any] { doc.background = Background(plist: b) }
        Annotation.resumeNumbering(after: doc.items.map(\.seq).max() ?? 0)
        return (base, doc)
    }

    // MARK: Annotations

    private static func point(_ p: NSPoint) -> [Double] { [Double(p.x), Double(p.y)] }
    private static func point(_ v: Any?) -> NSPoint? {
        guard let a = v as? [Double], a.count == 2 else { return nil }
        return NSPoint(x: a[0], y: a[1])
    }

    static func encode(_ a: Annotation) -> [String: Any] {
        var d: [String: Any] = [
            "id": a.id.uuidString, "seq": a.seq, "tool": a.tool.rawValue, "start": point(a.start), "end": point(a.end),
            "bend": Double(a.bend), "seed": String(a.seed), "style": a.style.plist,
        ]
        if !a.points.isEmpty { d["points"] = a.points.map(point) }
        if !a.text.isEmpty { d["text"] = a.text }
        if a.image != nil { d["image"] = true }
        if let lens = a.lens { d["lens"] = point(lens) }
        if let tail = a.tail { d["tail"] = point(tail) }
        if let w = a.wrapWidth { d["wrapWidth"] = Double(w) }
        return d
    }

    static func decode(_ d: [String: Any]) -> Annotation? {
        guard let id = (d["id"] as? String).flatMap(UUID.init(uuidString:)),
              let tool = (d["tool"] as? Int).flatMap(Tool.init(rawValue:)),
              let start = point(d["start"]), let end = point(d["end"]) else { return nil }
        var a = Annotation(tool: tool, start: start, end: end, style: Style(plist: d["style"] as? [String: Any] ?? [:]))
        a.id = id
        a.seq = d["seq"] as? Int ?? a.seq
        a.points = (d["points"] as? [[Double]] ?? []).compactMap { point($0) }
        a.text = d["text"] as? String ?? ""
        a.lens = point(d["lens"])
        a.tail = point(d["tail"])
        a.wrapWidth = (d["wrapWidth"] as? Double).map { CGFloat($0) }
        a.bend = CGFloat(d["bend"] as? Double ?? 0)
        a.seed = (d["seed"] as? String).flatMap(UInt64.init) ?? a.seed
        return a
    }

    private static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
