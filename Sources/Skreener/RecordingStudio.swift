import AppKit
import CoreGraphics
import VideoToolbox
import SkreenerCore

// Studio Mode (#24): the recording editor's look for a Record for editing recording — a background with padding,
// rounded corners and a shadow around the video, and the effects from the event track switched on/off and restyled.

/// The recording editor's settings for one recording, saved as `studio.json` in its project folder so reopening the
/// editor shows them again. Versioned like the project and events files (`RecordingFile.check`).
struct StudioSettings: Codable, Equatable {
    /// 2 added auto-zoom (#24); a version 1 file reads with no zoom sections, made from the clicks on first open.
    static let currentVersion = 2
    static let file = "studio.json"

    var version = StudioSettings.currentVersion
    /// Off: the finished video is the recording itself with the effects drawn in, as without the editor.
    var backgroundOn = false
    var background = StudioBackground()
    /// How the effects are drawn; starts as the style the recording was made with.
    var effects: EffectsStyle
    /// Whether the spotlight is drawn where it was switched on while recording.
    var spotlight = true
    /// Off: no zoom is drawn, but the sections are kept.
    var autoZoom = true
    /// In time order, never overlapping.
    var zoomSections: [ZoomSection] = []
    /// Whether the sections have been made from the clicks yet: once, the first time the editor opens the recording;
    /// after that they are the user's.
    var zoomGenerated = false

    /// The defaults for `project`: no background, the effects as recorded.
    init(project: RecordingProject) {
        effects = project.style
    }

    func encoded() throws -> Data { try RecordingFile.encoder.encode(self) }

    /// Reads a settings file; refuses one written by a newer Skreener. Missing values keep their defaults.
    static func decode(_ data: Data, project: RecordingProject) throws -> StudioSettings {
        try RecordingFile.check(data, supported: currentVersion)
        let saved = try RecordingFile.decoder.decode(Saved.self, from: data)
        var s = StudioSettings(project: project)
        if let v = saved.backgroundOn { s.backgroundOn = v }
        if let v = saved.background { s.background = v }
        if let v = saved.effects { s.effects = v }
        if let v = saved.spotlight { s.spotlight = v }
        if let v = saved.autoZoom { s.autoZoom = v }
        if let v = saved.zoomSections { s.zoomSections = AutoZoom.tidy(v) }
        if let v = saved.zoomGenerated { s.zoomGenerated = v }
        return s
    }

    /// The settings saved in `folder`, or the defaults when there are none (or they can't be read).
    static func load(folder: URL, project: RecordingProject) -> StudioSettings {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(file)) else { return StudioSettings(project: project) }
        do { return try decode(data, project: project) } catch {
            NSLog("Couldn't read the recording's editor settings, using the defaults: \(error)")
            return StudioSettings(project: project)
        }
    }

    func save(folder: URL) throws {
        try encoded().write(to: folder.appendingPathComponent(Self.file), options: .atomic)
    }

    /// Every field optional, so a file missing some (from an earlier build of the same version) still reads.
    private struct Saved: Decodable {
        var backgroundOn: Bool?
        var background: StudioBackground?
        var effects: EffectsStyle?
        var spotlight: Bool?
        var autoZoom: Bool?
        var zoomSections: [ZoomSection]?
        var zoomGenerated: Bool?
    }

    /// These settings without the zoom ones: what changes the background and effects (`StudioCompositor.zoomed`).
    var withoutZoom: StudioSettings {
        var s = self
        s.autoZoom = true
        s.zoomSections = []
        s.zoomGenerated = false
        return s
    }

    /// Whether a zoom is drawn anywhere.
    var zooms: Bool { autoZoom && !zoomSections.isEmpty }
}

/// The screenshot editor's `Background` as saved in `studio.json`: fill, gradient, picture, padding, corner radius,
/// shadow and aspect ratio (no inset or outer corners: a video has no transparency). Sizes are in screen points.
struct StudioBackground: Codable, Equatable {
    var fill = 0
    /// The custom gradient's two colors, sRGB components with alpha.
    var colors: [[Double]] = Background().colors.map(\.components)
    var direction = Background.GradientDirection.diagonal.rawValue
    var imagePath: String?
    var imageBlur: Double = 0
    /// Width and height; nil keeps the padding the same on every side.
    var aspect: [Int]?
    var padding: Double = 48
    var cornerRadius: Double = 10
    /// 0 (none) to 1.
    var shadow: Double = 0.5

    init() {}

    init(_ b: Background) {
        fill = b.fill
        colors = b.colors.map(\.components)
        direction = b.direction.rawValue
        imagePath = b.imageURL?.path
        imageBlur = Double(b.imageBlur)
        aspect = b.aspect.map { [$0.width, $0.height] }
        padding = Double(b.padding)
        cornerRadius = Double(b.cornerRadius)
        shadow = Double(b.shadow)
    }

    /// As a `Background` for drawing and the fill menu.
    var background: Background {
        var b = Background()
        if fill >= 0, fill <= Background.imageFill { b.fill = fill }
        let parsed = colors.compactMap(RGBColor.init(components:))
        if parsed.count == 2 { b.colors = parsed }
        b.direction = Background.GradientDirection(rawValue: direction) ?? .diagonal
        b.imageURL = imagePath.map { URL(fileURLWithPath: $0) }
        b.imageBlur = CGFloat(max(imageBlur, 0))
        if let a = aspect, a.count == 2, a[0] > 0, a[1] > 0 { b.aspect = Background.Aspect(width: a[0], height: a[1]) }
        b.padding = CGFloat(max(padding, 0))
        b.inset = 0
        b.cornerRadius = CGFloat(max(cornerRadius, 0))
        b.outerRadius = 0
        b.shadow = CGFloat(min(max(shadow, 0), 1))
        return b
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = try c.decodeIfPresent(Int.self, forKey: .fill) ?? fill
        colors = try c.decodeIfPresent([[Double]].self, forKey: .colors) ?? colors
        direction = try c.decodeIfPresent(Int.self, forKey: .direction) ?? direction
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        imageBlur = try c.decodeIfPresent(Double.self, forKey: .imageBlur) ?? imageBlur
        aspect = try c.decodeIfPresent([Int].self, forKey: .aspect)
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? padding
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? shadow
    }
}

/// Where things go in a Studio frame. Canvas coordinates are output pixels with a bottom-left origin; the video's
/// are its own pixels (`videoSize`).
struct StudioLayout: Equatable {
    /// The output video's size in pixels: even, and within `maxPixels`.
    var canvas: CGSize
    /// Where the recording sits on the canvas.
    var content: CGRect
    /// Output pixels per screen point, for the padding, corner radius, shadow and effect sizes.
    var pointScale: CGFloat
    var videoSize: CGSize

    /// The layout for a video of `videoSize` pixels recorded at `pixelsPerPoint`: without a background the canvas is
    /// the video; with one, the video plus `padding` points on every side, grown to the aspect ratio (as the screenshot
    /// editor does, `Background.canvas`), then scaled down to fit `maxPixels` and rounded to even numbers like a
    /// recording (`RecordingGeometry.videoSize`).
    static func make(videoSize: CGSize, pixelsPerPoint: CGFloat, background: StudioBackground?,
                     maxPixels: Int = ScreenRecorder.maxPixels) -> StudioLayout {
        let video = CGRect(origin: .zero, size: videoSize)
        guard let background else {
            return StudioLayout(canvas: videoSize, content: video, pointScale: pixelsPerPoint, videoSize: videoSize)
        }
        let margin = CGFloat(max(background.padding, 0)) * pixelsPerPoint
        let b = background.background
        let full = Background.canvas(around: video, margin: margin, aspect: b.aspect)
        let canvas = RecordingGeometry.videoSize(area: full.size, backingScale: 1, maxPixels: maxPixels)
        // One scale for both axes, so the video isn't stretched; rounding to even numbers leaves under a pixel over.
        let k = min(canvas.width / max(full.width, 1), canvas.height / max(full.height, 1))
        let content = CGRect(x: (video.minX - full.minX) * k, y: (video.minY - full.minY) * k,
                             width: video.width * k, height: video.height * k)
        return StudioLayout(canvas: canvas, content: content, pointScale: pixelsPerPoint * k, videoSize: videoSize)
    }

    /// How much smaller than the canvas the preview is drawn: to fit `fitting`, never larger than the canvas.
    static func previewScale(canvas: CGSize, fitting box: CGSize) -> CGFloat {
        guard canvas.width > 0, canvas.height > 0 else { return 1 }
        return max(0.05, min(1, box.width / canvas.width, box.height / canvas.height))
    }

    /// A time in the editor's transport: minutes, seconds and tenths ("1:05.3"), or hours too ("1:02:03.4").
    static func timecode(_ seconds: Double) -> String {
        let tenths = Int((max(seconds.isFinite ? seconds : 0, 0) * 10).rounded(.down))
        let h = tenths / 36_000, m = tenths / 600 % 60, s = tenths / 10 % 60, f = tenths % 10
        let rest = String(format: "%02d.%d", s, f)
        return h > 0 ? String(format: "%d:%02d:", h, m) + rest : "\(m):" + rest
    }

    /// The whole video, as a crop rect.
    var fullCrop: CGRect { CGRect(origin: .zero, size: videoSize) }

    /// Maps the video's pixels (bottom-left origin) onto the canvas, showing `crop` of the video (in its pixels,
    /// top-left origin, as the event track has positions) in `content`. The whole video by default; a zoom (#24's
    /// auto-zoom) passes a smaller crop.
    func transform(crop: CGRect? = nil) -> CGAffineTransform {
        let c = crop ?? fullCrop
        guard c.width > 0, c.height > 0 else { return .identity }
        let sx = content.width / c.width, sy = content.height / c.height
        // The crop's bottom edge in the video's bottom-left-origin pixels.
        let bottom = videoSize.height - c.maxY
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: content.minX - c.minX * sx, ty: content.minY - bottom * sy)
    }

    /// A video point (pixels, top-left origin, as in the event track) on the canvas.
    func canvasPoint(video p: CGPoint, crop: CGRect? = nil) -> CGPoint {
        CGPoint(x: p.x, y: videoSize.height - p.y).applying(transform(crop: crop))
    }

    /// The video point (pixels, top-left origin) shown at a canvas point: `canvasPoint` the other way round.
    func videoPoint(canvas p: CGPoint, crop: CGRect? = nil) -> CGPoint {
        let v = p.applying(transform(crop: crop).inverted())
        return CGPoint(x: v.x, y: videoSize.height - v.y)
    }
}

/// Draws one Studio frame: the background (made once, at init), then the recording's frame in its rounded rect with
/// the shadow under it, then the effects over it, clipped to the same rounded rect. With auto-zoom, the frame and the
/// effects (but not the keystroke pill) show the camera's crop of the video (`ZoomCamera`). The export
/// (`RecordingRenderer`) and the editor's preview both draw with this, so the preview is what Export makes. Make it on
/// the main thread (the background is drawn with AppKit); after that it is fixed and safe to use from any thread.
final class StudioCompositor: @unchecked Sendable {
    let layout: StudioLayout
    let settings: StudioSettings
    let overlay: EffectsOverlay
    /// Output size: the canvas times `scale` (below 1 for the preview).
    let size: CGSize
    let scale: CGFloat
    let camera: ZoomCamera
    /// The background and the shadow, at `size`; nil without a background.
    private let backdrop: CGImage?

    /// `scale` shrinks everything for the preview; Export uses 1.
    @MainActor init(project: RecordingProject, events: RecordingEvents, folder: URL?, settings: StudioSettings,
                    scale: CGFloat = 1) {
        self.settings = settings
        self.scale = scale
        layout = StudioLayout.make(videoSize: project.videoSize, pixelsPerPoint: project.pixelScale,
                                   background: settings.backgroundOn ? settings.background : nil)
        overlay = EffectsOverlay(style: settings.effects, spotlight: settings.spotlight, videoSize: project.videoSize,
                                 scale: project.pixelScale, events: events, folder: folder)
        size = CGSize(width: max(1, (layout.canvas.width * scale).rounded()), height: max(1, (layout.canvas.height * scale).rounded()))
        backdrop = settings.backgroundOn ? Self.makeBackdrop(layout: layout, background: settings.background, size: size) : nil
        camera = ZoomCamera(sections: settings.zoomSections, events: events, videoSize: project.videoSize)
    }

    private init(_ other: StudioCompositor, settings: StudioSettings) {
        self.settings = settings
        layout = other.layout
        overlay = other.overlay
        size = other.size
        scale = other.scale
        backdrop = other.backdrop
        camera = ZoomCamera(sections: settings.zoomSections, events: other.overlay.events, videoSize: other.layout.videoSize)
    }

    /// This compositor with `settings`' zoom (the rest of `settings` must be the same as this one's): keeps the
    /// background and the effects, so it is quick to make while a zoom section is dragged.
    func zoomed(_ settings: StudioSettings) -> StudioCompositor {
        StudioCompositor(self, settings: settings)
    }

    /// Whether frames are composed (on a canvas, or zoomed) rather than drawn over the recording.
    var composes: Bool { settings.backgroundOn || settings.zooms }

    /// Whether this draws anything but the recording itself (a background, a zoom, or effects).
    var changesTheVideo: Bool { composes || overlay.drawsAnything }

    /// The part of the video showing at `t`; nil for all of it.
    func crop(at t: Double) -> CGRect? {
        guard settings.zooms else { return nil }
        let c = camera.crop(at: t)
        return c == camera.fullCrop ? nil : c
    }

    /// The content's corner radius in canvas pixels.
    private var cornerRadius: CGFloat {
        guard settings.backgroundOn else { return 0 }
        let r = CGFloat(max(settings.background.cornerRadius, 0)) * layout.pointScale
        return min(r, layout.content.width / 2, layout.content.height / 2)
    }

    /// Draws the frame at video time `t` into `ctx`, which covers `size` (bottom-left origin). `source` is the
    /// recording's frame showing at `t`; nil draws the background and effects only.
    func draw(in ctx: CGContext, source: CGImage?, at t: Double) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let backdrop {
            ctx.draw(backdrop, in: CGRect(origin: .zero, size: size))
        } else {
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        ctx.scaleBy(x: scale, y: scale)
        let clip = CGPath(roundedRect: layout.content, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(clip)
        ctx.clip()
        let shown = crop(at: t)
        ctx.saveGState()
        ctx.concatenate(layout.transform(crop: shown))
        if let source {
            ctx.interpolationQuality = .high
            ctx.draw(source, in: CGRect(origin: .zero, size: layout.videoSize))
        }
        // Zoomed, the effects stay on the content they belong to, but the keystroke pill stays put in the frame.
        overlay.draw(in: ctx, at: t, keystrokes: shown == nil)
        ctx.restoreGState()
        if shown != nil {
            ctx.concatenate(layout.transform())
            overlay.drawKeystrokes(in: ctx, at: t)
        }
    }

    /// The background filling the canvas, with the shadow the content casts on it, drawn with AppKit like the
    /// screenshot editor's (`AnnotationEditor.draw`).
    @MainActor private static func makeBackdrop(layout: StudioLayout, background: StudioBackground, size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let k = size.width / max(layout.canvas.width, 1)
        let b = background.background
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        b.drawFill(in: NSRect(origin: .zero, size: size))
        if b.shadow > 0 {
            // As in the screenshot editor: 8 pt down, 28 pt blur, in screen points of the recording.
            let pt = layout.pointScale * k
            let rect = CGRect(x: layout.content.minX * k, y: layout.content.minY * k,
                              width: layout.content.width * k, height: layout.content.height * k)
            let r = min(b.cornerRadius * pt, rect.width / 2, rect.height / 2)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8 * pt), blur: 28 * pt,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.8 * b.shadow))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// A frame of the recording as an image to draw.
    static func image(of buffer: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        return image
    }
}

/// Finding the recording project a finished MP4 was made from, so its preview can open the recording editor.
extension RecordingProject {
    /// Whether a project whose finished MP4 was saved at `exported` made `file`: the same path, or where filing moved it
    /// to (`follow`, e.g. `AutoFiling.current`).
    static func made(_ file: URL, exported: String?, follow: (URL) -> URL = { $0 }) -> Bool {
        guard let exported, !exported.isEmpty else { return false }
        let saved = URL(fileURLWithPath: exported).standardizedFileURL
        let wanted = file.standardizedFileURL.path
        return saved.path == wanted || follow(saved).standardizedFileURL.path == wanted
    }

    /// The project folder among `projects` (folder and its `exported` path) that made `file`; the newest match wins
    /// (the folders are in no particular order, so the caller passes them newest first).
    static func projectFolder(for file: URL, in projects: [(folder: URL, exported: String?)],
                       follow: (URL) -> URL = { $0 }) -> URL? {
        projects.first { made(file, exported: $0.exported, follow: follow) }?.folder
    }
}

/// Looks up recording projects by their finished MP4 (main thread). Each `project.json` is read once and again only
/// when it changes.
@MainActor enum RecordingProjectLookup {
    private struct Entry { var modified: Date; var exported: String?; var created: Date }
    private static var cache: [String: Entry] = [:]

    /// The project folder that made `file`, if it still has its clean video.
    static func folder(for file: URL, in parent: URL = RecordingProject.folder) -> URL? {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == RecordingProject.fileExtension } ?? []
        var seen = Set<String>()
        var projects: [(folder: URL, exported: String?, created: Date)] = []
        for folder in folders {
            let json = folder.appendingPathComponent(RecordingProject.projectFile)
            guard let modified = (try? json.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            else { continue }
            seen.insert(folder.path)
            if let e = cache[folder.path], e.modified == modified {
                projects.append((folder: folder, exported: e.exported, created: e.created))
                continue
            }
            guard let data = try? Data(contentsOf: json), let p = try? RecordingProject.decode(data) else { continue }
            cache[folder.path] = Entry(modified: modified, exported: p.exported, created: p.created)
            projects.append((folder: folder, exported: p.exported, created: p.created))
        }
        cache = cache.filter { seen.contains($0.key) }
        projects.sort { $0.created > $1.created }
        guard let found = RecordingProject.projectFolder(for: file, in: projects.map { (folder: $0.folder, exported: $0.exported) },
                                                  follow: AutoFiling.current) else { return nil }
        return fm.fileExists(atPath: found.appendingPathComponent(RecordingProject.videoFile).path) ? found : nil
    }
}
