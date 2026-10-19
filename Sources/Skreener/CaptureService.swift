import AppKit
import ScreenCaptureKit

enum CaptureError: Error { case noDisplay, cancelled }

enum CaptureService {
    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func makeConfig(width: CGFloat, height: CGFloat, scale: CGFloat, showsCursor: Bool = Preferences.showCursor) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        cfg.width = Int(width * scale)
        cfg.height = Int(height * scale)
        cfg.showsCursor = showsCursor
        cfg.captureResolution = .best
        return cfg
    }

    private static func image(_ cg: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }

    /// Capture a screen, or a sub-rect given in global (bottom-left origin) screen coordinates.
    static func captureScreen(_ screen: NSScreen, globalRect: CGRect? = nil, showsCursor: Bool = Preferences.showCursor) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = displayID(screen), let display = content.displays.first(where: { $0.displayID == id })
        else { throw CaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = screen.backingScaleFactor
        let cfg: SCStreamConfiguration
        if let r = globalRect {
            cfg = makeConfig(width: r.width, height: r.height, scale: scale, showsCursor: showsCursor)
            // convert to display-local, top-left origin
            cfg.sourceRect = CGRect(x: r.minX - screen.frame.minX,
                                    y: screen.frame.maxY - r.maxY,
                                    width: r.width, height: r.height)
        } else {
            cfg = makeConfig(width: screen.frame.width, height: screen.frame.height, scale: scale, showsCursor: showsCursor)
        }
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return image(cg, scale: scale)
    }

    static func captureWindow(_ window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
        let cfg = makeConfig(width: window.frame.width, height: window.frame.height, scale: scale)
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return image(cg, scale: scale)
    }

    static func onScreenWindows() async -> [SCWindow] {
        let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let me = Bundle.main.bundleIdentifier
        return (content?.windows ?? []).filter {
            $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40 &&
            $0.owningApplication?.bundleIdentifier != me
        }
    }
}
