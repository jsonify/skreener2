import AppKit
import UniformTypeIdentifiers

enum Output {
    /// The image as a file in the format chosen in Settings (PNG or JPEG), downscaled to 1× when that is on.
    /// JPEG has no alpha, so transparent areas (window captures) become white.
    static func fileData(_ image: NSImage, format: ImageFormat = Preferences.imageFormat) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let jpeg = format == .jpeg
        var w = rep.pixelsWide, h = rep.pixelsHigh
        if Preferences.downscaleRetina, image.size.width >= 1, image.size.height >= 1 {
            w = min(w, Int(image.size.width.rounded()))
            h = min(h, Int(image.size.height.rounded()))
        }
        var out = rep
        if jpeg || w != rep.pixelsWide || h != rep.pixelsHigh, let cg = rep.cgImage,
           let redrawn = redraw(cg, width: w, height: h, onWhite: jpeg) {
            out = NSBitmapImageRep(cgImage: redrawn)
        }
        return jpeg ? out.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    : out.representation(using: .png, properties: [:])
    }

    private static func redraw(_ cg: CGImage, width: Int, height: Int, onWhite: Bool) -> CGImage? {
        let space = cg.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if onWhite { ctx.setFillColor(.white); ctx.fill(rect) }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: rect)
        return ctx.makeImage()
    }

    /// File name (without extension) from the template in Settings. Tokens: %Y %y %m %d %H %M %S, %% for a percent sign.
    static func filename(for date: Date = Date(), template: String = Preferences.filenameTemplate) -> String {
        let patterns: [Character: String] = ["Y": "yyyy", "y": "yy", "m": "MM", "d": "dd", "H": "HH", "M": "mm", "S": "ss"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var out = ""
        var chars = template.makeIterator()
        while let c = chars.next() {
            guard c == "%", let token = chars.next() else { out.append(c); continue }
            if let p = patterns[token] {
                f.dateFormat = p
                out += f.string(from: date)
            } else if token == "%" {
                out.append("%")
            } else {
                out.append(c); out.append(token)
            }
        }
        // "/" separates folders and ":" shows as "/" in Finder.
        out = out.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return "Skreener" }
        return out.hasPrefix(".") ? "Skreener " + out : out   // a leading dot would hide the file
    }

    /// `dir/name.ext`, or `name 2.ext`, `name 3.ext`… when that file already exists (a template without seconds).
    static func uniqueURL(in dir: URL, name: String, ext: String,
                          exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        var url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while exists(url) {
            url = dir.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    static func copy(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    /// `fileData` for a file the user keeps: a PNG is also compressed when Settings says so (#279). Screenshots shared
    /// through a temporary file and the capture history's PNGs (the editor's base) stay as they are.
    private static func savedData(_ image: NSImage, format: ImageFormat = Preferences.imageFormat) -> Data? {
        guard let data = fileData(image, format: format) else { return nil }
        guard format == .png, Preferences.compressScreenshots else { return data }
        return PNGQuantizer.compressed(png: data) ?? data
    }

    @discardableResult
    static func save(_ image: NSImage, to dir: URL = Preferences.saveDirectory) -> URL? {
        let url = uniqueURL(in: dir, name: filename(), ext: Preferences.imageFormat.fileExtension)
        guard let data = savedData(image) else { return nil }
        do { try data.write(to: url); return url } catch { NSLog("Save failed: \(error)"); return nil }
    }

    /// Writes the image over `url` (an earlier save of the same screenshot, #118), in that file's format. Fails for
    /// a file that isn't a PNG or JPEG.
    static func overwrite(_ image: NSImage, at url: URL) -> Bool {
        guard let format = ImageFormat(fileExtension: url.pathExtension), let data = savedData(image, format: format) else {
            return false
        }
        // An atomic write makes a new file, which would lose the page the capture came from (#269), its tags and
        // Spotlight comment (#277).
        let page = SourcePage.readWhereFroms(of: url), kept = AutoFiling.Kept(of: url)
        do { try data.write(to: url, options: .atomic) } catch { NSLog("Save failed: \(error)"); return false }
        if let page { SourcePage.writeWhereFroms(page, to: url) }
        kept.restore(to: url)
        return true
    }

    /// The save panel; returns where the image went (nil when cancelled or the write failed).
    @discardableResult
    static func saveAs(_ image: NSImage, name: String? = nil) -> URL? {
        let format = Preferences.imageFormat
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = (name ?? filename()) + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url, let data = savedData(image) else { return nil }
        do { try data.write(to: url, options: .atomic); return url } catch { NSLog("Save failed: \(error)"); return nil }
    }

    /// Writes the image to a temporary file named like a saved screenshot, for Drag Me and the share sheet.
    static func temporaryFile(_ image: NSImage) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Skreener Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = uniqueURL(in: dir, name: filename(), ext: Preferences.imageFormat.fileExtension)
        guard let data = fileData(image) else { return nil }
        do { try data.write(to: url); return url } catch { NSLog("Export failed: \(error)"); return nil }
    }

    /// The share sheet (AirDrop, Mail, Messages…) under `view`. Shares a file rather than the bare image, so the
    /// sheet's header shows its thumbnail and name and receivers get a properly named PNG/JPEG.
    /// `delegate` hears which service was picked (Quick Access closes once one is).
    static func share(_ image: NSImage, from view: NSView, delegate: NSSharingServicePickerDelegate? = nil) {
        guard let url = temporaryFile(image) else { NSSound.beep(); return }
        share(url, from: view, delegate: delegate)
    }

    static func share(_ file: URL, from view: NSView, delegate: NSSharingServicePickerDelegate? = nil) {
        let picker = NSSharingServicePicker(items: [file])
        picker.delegate = delegate
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
