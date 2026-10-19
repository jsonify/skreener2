import AppKit

enum Output {
    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func copy(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    @discardableResult
    static func save(_ image: NSImage, to dir: URL = Preferences.saveDirectory) -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("Skreener \(f.string(from: Date())).png")
        guard let data = pngData(image) else { return nil }
        do { try data.write(to: url); return url } catch { NSLog("Save failed: \(error)"); return nil }
    }

    static func saveAs(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot.png"
        if panel.runModal() == .OK, let url = panel.url, let data = pngData(image) { try? data.write(to: url) }
    }
}
