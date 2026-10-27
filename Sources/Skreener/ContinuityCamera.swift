import AppKit

/// Pictures taken, scanned or sketched on a nearby iPhone or iPad (Continuity Camera). AppKit fills the menu item
/// with the devices; the picture comes back through `NSServicesMenuRequestor.readSelection(from:)`.
enum ContinuityCamera {
    /// What a device sends, best first: photos and sketches as PNG / TIFF / JPEG, scanned documents as PDF.
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), .pdf]

    /// True when the requestor is asked for a picture back (and nothing is sent).
    static func accepts(sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Bool {
        guard sendType == nil, let returnType else { return false }
        return imageTypes.contains(returnType)
    }

    /// The first picture on `pasteboard`; a PDF (a scan) gives its first page.
    static func image(from pasteboard: NSPasteboard) -> NSImage? {
        let available = pasteboard.types ?? []
        for type in imageTypes where available.contains(type) {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data),
               image.size.width > 0, image.size.height > 0 { return image }
        }
        return nil
    }

    /// Whether the picture opens in a new editor tab (the menu-bar menu) instead of becoming a layer (Add Image).
    /// Set when either menu opens, since both can be reached while an editor is the key window.
    @MainActor static var opensInNewTab = false

    /// AppKit's "Import from iPhone or iPad" item: Take Photo, Scan Documents and Add Sketch for each device.
    static func menuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = NSMenuItem.importFromDeviceIdentifier
        return item
    }
}
