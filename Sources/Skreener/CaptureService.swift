import AppKit
import ScreenCaptureKit

enum CaptureError: Error { case noDisplay, cancelled, cropFailed }

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
        let cg = try await captureScreenImage(screen, globalRect: globalRect, showsCursor: showsCursor)
        return image(cg, scale: screen.backingScaleFactor)
    }

    /// Like `captureScreen`, as a CGImage at the screen's pixel scale. `excludingSelf` leaves Skreener's own windows
    /// out (e.g. the scrolling capture's frame and controls).
    static func captureScreenImage(_ screen: NSScreen, globalRect: CGRect? = nil, showsCursor: Bool = Preferences.showCursor,
                                   excludingSelf: Bool = false) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = displayID(screen), let display = content.displays.first(where: { $0.displayID == id })
        else { throw CaptureError.noDisplay }
        let me = Bundle.main.bundleIdentifier
        let filter = excludingSelf
            ? SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.bundleIdentifier == me },
                              exceptingWindows: [])
            : SCContentFilter(display: display, excludingWindows: [])
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
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Grabs the same area over and over (scrolling capture), without the cursor or Skreener's own windows. The display
    /// lookup and filter are set up once: fetching the shareable content for every frame took longer than the grab.
    final class AreaGrabber: @unchecked Sendable {
        private let filter: SCContentFilter
        private let config: SCStreamConfiguration

        init(screen: NSScreen, globalRect r: CGRect) async throws {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let id = CaptureService.displayID(screen), let display = content.displays.first(where: { $0.displayID == id })
            else { throw CaptureError.noDisplay }
            let me = getpid()
            filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == me },
                                     exceptingWindows: [])
            config = CaptureService.makeConfig(width: r.width, height: r.height, scale: screen.backingScaleFactor, showsCursor: false)
            config.sourceRect = CGRect(x: r.minX - screen.frame.minX, y: screen.frame.maxY - r.maxY, width: r.width, height: r.height)
        }

        func grab() async throws -> CGImage {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
    }

    /// Cut a global (bottom-left origin) rect out of a full-display frame grabbed earlier, e.g. a frozen screen.
    static func crop(_ frame: CGImage, screen: NSScreen, globalRect r: CGRect) throws -> NSImage {
        let px = pixelRect(r, in: screen.frame, pixelSize: CGSize(width: frame.width, height: frame.height))
        guard let cg = frame.cropping(to: px) else { throw CaptureError.cropFailed }
        return image(cg, scale: CGFloat(frame.width) / screen.frame.width)
    }

    /// A global (bottom-left origin) rect as whole pixels (top-left origin) of a `pixelSize` frame showing `screenFrame`.
    static func pixelRect(_ r: CGRect, in screenFrame: CGRect, pixelSize: CGSize) -> CGRect {
        let sx = pixelSize.width / screenFrame.width, sy = pixelSize.height / screenFrame.height
        return CGRect(x: (r.minX - screenFrame.minX) * sx, y: (screenFrame.maxY - r.maxY) * sy,
                      width: r.width * sx, height: r.height * sy).integral
    }

    static func captureWindow(_ window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
        let cfg = makeConfig(width: window.frame.width, height: window.frame.height, scale: scale)
        cfg.ignoreShadowsSingleWindow = true   // we draw our own shadow so it fits inside the image
        // Keep the alpha channel: without these the window's rounded corners came out filled in (black), so the
        // "transparent background" option had nothing transparent to keep (#138). The white fill, when that option
        // is off, is ours in `decorateWindow`.
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.backgroundColor = .clear
        cfg.shouldBeOpaque = false
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return image(decorateWindow(cg, scale: scale), scale: scale)
    }

    /// Applies the window-capture options: drop shadow, padding, transparent or white background.
    static func decorateWindow(_ cg: CGImage, scale: CGFloat, shadow: Bool = Preferences.windowShadow,
                               transparent: Bool = Preferences.windowTransparentBackground,
                               padding: Int = Preferences.windowPadding) -> CGImage {
        let opaque = !transparent
        let margin = Int(((shadow ? 40 : 0) + CGFloat(max(padding, 0))) * scale)
        guard margin > 0 || opaque,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: cg.width + margin * 2, height: cg.height + margin * 2,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return cg }
        if opaque {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        }
        if shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 30 * scale,
                          color: NSColor.black.withAlphaComponent(0.45).cgColor)
        }
        ctx.draw(cg, in: CGRect(x: margin, y: margin, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    /// Normal app windows on screen, frontmost first, so a hit test picks the window you actually see under
    /// the pointer. (ScreenCaptureKit's own list is not in stacking order, so a window behind could win.)
    static func onScreenWindows() async -> [SCWindow] {
        let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let me = Bundle.main.bundleIdentifier
        let windows = (content?.windows ?? []).filter {
            $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40 &&
            $0.owningApplication?.bundleIdentifier != me
        }
        // Core Graphics lists on-screen windows front to back. Fully transparent windows are left out: they
        // can't be seen, but would still catch the click.
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var rank: [CGWindowID: Int] = [:]
        for (i, w) in info.enumerated() {
            guard let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if ((w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01 { rank[id] = i }
        }
        guard !rank.isEmpty else { return windows }
        return windows.filter { rank[$0.windowID] != nil }.sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
    }
}
