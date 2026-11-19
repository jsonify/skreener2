import AppKit
import CoreImage
import CoreText

// Timed callouts in the recording editor (#383): the screenshot editor's arrow, box, text, counter, highlight and blur,
// drawn over the video from a start to an end time, fading in and out. Positions are in the recording's own pixels
// (top-left origin, like the event track), so a callout stays on the content it points at inside a zoom section; one
// that doesn't follow the zoom stays where it is in the frame. Times are in the recording's own time (source time),
// like the edits, so cuts never move a callout.

/// One callout over the video.
struct Callout: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case arrow, box, text, counter, highlight, blur

        var name: String {
            switch self {
            case .arrow: return "Arrow"
            case .box: return "Box"
            case .text: return "Text"
            case .counter: return "Counter"
            case .highlight: return "Highlight"
            case .blur: return "Blur"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var start: Double
    var end: Double
    /// Video pixels, top-left origin. A box, highlight or blur covers `x`, `y`, `width`, `height`; an arrow goes from
    /// `x`, `y` (its tail) to `x + width`, `y + height` (its tip); text starts at its top-left corner `x`, `y`; a
    /// counter is centered on `x`, `y`.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// What a text callout says.
    var text = ""
    /// sRGB red, green, blue and alpha, 0…1.
    var color = Callout.red
    /// Moves and scales with a zoom section (the content it points at); off, it stays put in the frame. A blur always
    /// follows, since it hides what is under it.
    var followsZoom = true

    static let red = [1.0, 0.231, 0.188, 1.0]

    init(kind: Kind, start: Double, end: Double, x: Double, y: Double, width: Double, height: Double, text: String = "") {
        self.kind = kind
        self.start = start
        self.end = end
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
    }

    /// Missing values keep their defaults; an unknown kind (from a newer Skreener) reads as a box.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .box
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? start + Callouts.defaultLength
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        let saved = try c.decodeIfPresent([Double].self, forKey: .color) ?? Callout.red
        color = saved.count == 4 ? saved.map { min(max($0.isFinite ? $0 : 1, 0), 1) } : Callout.red
        followsZoom = try c.decodeIfPresent(Bool.self, forKey: .followsZoom) ?? true
    }

    var duration: Double { end - start }

    /// Whether it moves with a zoom section.
    var follows: Bool { followsZoom || kind == .blur }

    var cgColor: CGColor { CGColor(srgbRed: color[0], green: color[1], blue: color[2], alpha: color[3]) }

    /// The arrow's tail and tip.
    var from: CGPoint { CGPoint(x: x, y: y) }
    var to: CGPoint { CGPoint(x: x + width, y: y + height) }
}

/// Making, timing, placing and drawing callouts. Pure apart from `draw`, so the preview and the export show the same.
enum Callouts {
    /// How long a new callout shows.
    static let defaultLength = 3.0
    /// The shortest a callout can be.
    static let minLength = 0.3
    /// How long it takes to fade in, and out (less for a short callout).
    static let fade = 0.25
    /// Sizes in screen points of the recording (as the screenshot editor's defaults).
    static let lineWidth = 4.0
    static let fontSize = 28.0
    static let blurRadius = 12.0

    // MARK: Time

    /// How visible `c` is at `t`: 0 outside its time, fading up to 1 at the start and back down at the end.
    static func opacity(_ c: Callout, at t: Double) -> Double {
        guard t >= c.start, t < c.end, c.end > c.start else { return 0 }
        let f = min(fade, c.duration / 3)
        guard f > 0 else { return 1 }
        return min(1, (t - c.start) / f, (c.end - t) / f)
    }

    /// The indexes of the callouts showing at `t`, in drawing order (the order they were added).
    static func showing(_ callouts: [Callout], at t: Double) -> [Int] {
        callouts.indices.filter { t >= callouts[$0].start && t < callouts[$0].end }
    }

    /// Times inside the recording, each at least `minLength` long; the order (which is drawn on top) is kept.
    static func tidy(_ callouts: [Callout], duration: Double? = nil) -> [Callout] {
        callouts.compactMap { c in
            var c = c
            guard c.start.isFinite, c.end.isFinite, c.x.isFinite, c.y.isFinite, c.width.isFinite, c.height.isFinite
            else { return nil }
            c.start = max(0, c.start)
            if let d = duration, d > 0 { c.start = min(c.start, max(0, d - minLength)) }
            c.end = max(c.end, c.start + minLength)
            if let d = duration, d > 0 { c.end = min(c.end, max(d, c.start + minLength)) }
            return c
        }
    }

    /// `c` moved to start at `t`, keeping its length, inside `0…duration`.
    static func moved(_ c: Callout, to t: Double, duration: Double) -> Callout {
        var c = c
        let length = c.duration
        c.start = min(max(t, 0), max(0, duration - length))
        c.end = c.start + length
        return c
    }

    /// `c` with its start or end edge at `t`, at least `minLength` long and inside `0…duration`.
    static func resized(_ c: Callout, start isStart: Bool, to t: Double, duration: Double) -> Callout {
        var c = c
        if isStart {
            c.start = min(max(t, 0), c.end - minLength)
        } else {
            c.end = max(min(t, duration), c.start + minLength)
        }
        return c
    }

    /// The counter's number: its place among the counters, by when they start (then by the order they were added).
    static func number(of index: Int, in callouts: [Callout]) -> Int {
        let c = callouts[index]
        return callouts.indices.filter { i in
            callouts[i].kind == .counter && (callouts[i].start < c.start || (callouts[i].start == c.start && i < index))
        }.count + 1
    }

    // MARK: Making

    /// A new callout of `kind` at `t`, around `point` (video pixels, top-left origin; the middle of the video when nil),
    /// sized for a video of `videoSize` recorded at `pixelsPerPoint`.
    static func make(_ kind: Callout.Kind, at t: Double, duration: Double, videoSize: CGSize, pixelsPerPoint: CGFloat,
                     around point: CGPoint? = nil) -> Callout {
        let k = Double(max(pixelsPerPoint, 0.1))
        let p = point ?? CGPoint(x: videoSize.width / 2, y: videoSize.height / 2)
        let end = duration > 0 ? min(t + defaultLength, duration) : t + defaultLength
        var c: Callout
        switch kind {
        case .arrow:
            // Pointing at `point` from the lower left.
            let dx = 120 * k, dy = 80 * k
            c = Callout(kind: kind, start: t, end: end, x: Double(p.x) - dx, y: Double(p.y) + dy, width: dx, height: -dy)
        case .box, .highlight, .blur:
            let w = 200 * k, h = (kind == .highlight ? 40 : 100) * k
            c = Callout(kind: kind, start: t, end: end, x: Double(p.x) - w / 2, y: Double(p.y) - h / 2, width: w, height: h)
        case .text:
            c = Callout(kind: kind, start: t, end: end, x: Double(p.x), y: Double(p.y), width: 0, height: 0, text: "Text")
        case .counter:
            c = Callout(kind: kind, start: t, end: end, x: Double(p.x), y: Double(p.y), width: 0, height: 0)
        }
        if kind == .highlight { c.color = [1, 0.84, 0.04, 1] }
        return clamped(c, videoSize: videoSize)
    }

    /// `c` moved so its anchor (`x`, `y`) is inside the video.
    static func clamped(_ c: Callout, videoSize: CGSize) -> Callout {
        var c = c
        c.x = min(max(c.x, 0), Double(videoSize.width))
        c.y = min(max(c.y, 0), Double(videoSize.height))
        return c
    }

    // MARK: Place

    /// The size of a text callout's box, in video pixels, at `pixelsPerPoint`.
    static func textBoxSize(_ text: String, pixelsPerPoint: CGFloat) -> CGSize {
        let size = textSize(text.isEmpty ? " " : text, fontSize: CGFloat(fontSize) * pixelsPerPoint)
        let pad = CGFloat(fontSize) * pixelsPerPoint * 0.4
        return CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
    }

    /// One line of text in the callouts' font: its width, and the font's line height.
    private static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: max(fontSize, 1), weight: .semibold),
        ]))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGSize(width: ceil(width) + 2, height: ceil(ascent + descent) + 1)
    }

    /// The area `c` covers, in video pixels with a top-left origin.
    static func bounds(_ c: Callout, pixelsPerPoint: CGFloat) -> CGRect {
        switch c.kind {
        case .arrow:
            let pad = CGFloat(lineWidth * 4) * pixelsPerPoint
            return CGRect(x: min(c.from.x, c.to.x), y: min(c.from.y, c.to.y), width: abs(c.width), height: abs(c.height))
                .insetBy(dx: -pad, dy: -pad)
        case .box, .highlight, .blur:
            return CGRect(x: c.x, y: c.y, width: c.width, height: c.height).standardized
        case .text:
            return CGRect(origin: c.from, size: textBoxSize(c.text, pixelsPerPoint: pixelsPerPoint))
        case .counter:
            let r = counterRadius(pixelsPerPoint)
            return CGRect(x: CGFloat(c.x) - r, y: CGFloat(c.y) - r, width: 2 * r, height: 2 * r)
        }
    }

    static func counterRadius(_ pixelsPerPoint: CGFloat) -> CGFloat { CGFloat(fontSize) * 0.75 * pixelsPerPoint }

    /// The point in video pixels (top-left origin) shown at canvas point `p` for `c`: through the zoom at `crop` when it
    /// follows the zoom, through the whole video when it doesn't.
    static func videoPoint(_ p: CGPoint, for c: Callout, layout: StudioLayout, crop: CGRect?) -> CGPoint {
        layout.videoPoint(canvas: p, crop: c.follows ? crop : nil)
    }

    /// The topmost callout showing at `t` under canvas point `p`, and whether `p` is on its handle (an arrow's tip, or a
    /// box's lower-right corner) rather than its body. `slop` is how far off (in canvas pixels) still counts.
    static func hit(_ callouts: [Callout], at p: CGPoint, time t: Double, layout: StudioLayout, crop: CGRect?,
                    pixelsPerPoint: CGFloat, slop: CGFloat) -> (index: Int, handle: Bool)? {
        for i in showing(callouts, at: t).reversed() {
            let c = callouts[i]
            let shownCrop = c.follows ? crop : nil
            // Canvas pixels per video pixel here.
            let k = max(layout.transform(crop: shownCrop).a, 0.0001)
            let v = layout.videoPoint(canvas: p, crop: shownCrop)
            let tolerance = slop / k
            if let h = handle(c), hypot(v.x - h.x, v.y - h.y) <= tolerance * 1.5 { return (i, true) }
            if c.kind == .arrow {
                if distance(from: v, toSegment: c.from, c.to) <= tolerance + CGFloat(lineWidth) * pixelsPerPoint * 2 {
                    return (i, false)
                }
            } else if bounds(c, pixelsPerPoint: pixelsPerPoint).insetBy(dx: -tolerance, dy: -tolerance).contains(v) {
                return (i, false)
            }
        }
        return nil
    }

    /// Where a callout's size is dragged from, in video pixels (top-left origin); nil for text and counters.
    static func handle(_ c: Callout) -> CGPoint? {
        switch c.kind {
        case .arrow, .box, .highlight, .blur: return c.to
        case .text, .counter: return nil
        }
    }

    /// `c` with its handle dragged to `p` (video pixels); a box never gets smaller than `minSize` either way.
    static func resizing(_ c: Callout, handleTo p: CGPoint, minSize: CGFloat) -> Callout {
        var c = c
        switch c.kind {
        case .arrow:
            c.width = Double(p.x) - c.x
            c.height = Double(p.y) - c.y
        case .box, .highlight, .blur:
            c.width = max(Double(p.x) - c.x, Double(minSize))
            c.height = max(Double(p.y) - c.y, Double(minSize))
        case .text, .counter:
            break
        }
        return c
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let u = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length2, 0), 1)
        return hypot(p.x - (a.x + u * dx), p.y - (a.y + u * dy))
    }

    // MARK: Drawing

    private static let ciContext = CIContext()

    /// Draws `callouts[index]` at `opacity` into `ctx`, whose coordinates are the video's pixels with a bottom-left
    /// origin (`StudioLayout.transform`). `pixelsPerPoint` sizes the lines and text; `source` (the frame, at any size)
    /// is what a blur blurs.
    static func draw(_ callouts: [Callout], index: Int, opacity: Double, in ctx: CGContext, videoSize: CGSize,
                     pixelsPerPoint: CGFloat, source: CGImage?) {
        let c = callouts[index]
        guard opacity > 0 else { return }
        // Top-left video pixels to the context's bottom-left ones.
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: videoSize.height - p.y) }
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: videoSize.height - r.maxY, width: r.width, height: r.height) }
        let pt = pixelsPerPoint
        let lw = CGFloat(lineWidth) * pt
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setAlpha(CGFloat(opacity))
        let box = flip(bounds(c, pixelsPerPoint: pt))
        let shadowed = c.kind != .blur && c.kind != .highlight
        if shadowed {
            // One shadow for the whole callout (an arrow's shaft and head), as the screenshot editor draws them.
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5 * pt), blur: 4 * pt,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
            ctx.beginTransparencyLayer(in: box.insetBy(dx: -12 * pt, dy: -12 * pt), auxiliaryInfo: nil)
        }
        ctx.setStrokeColor(c.cgColor)
        ctx.setFillColor(c.cgColor)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch c.kind {
        case .arrow:
            drawArrow(from: flip(c.from), to: flip(c.to), lineWidth: lw, in: ctx)
        case .box:
            let r = box.insetBy(dx: lw / 2, dy: lw / 2)
            let radius = min(4 * pt, r.width / 2, r.height / 2)
            if r.width > 0, r.height > 0 {
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.strokePath()
            }
        case .highlight:
            // Multiply, like a marker: the text under it stays readable.
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(c.cgColor.copy(alpha: 0.45 * c.color[3]) ?? c.cgColor)
            let radius = min(3 * pt, box.width / 2, box.height / 2)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        case .blur:
            drawBlur(box, source: source, videoSize: videoSize, radius: CGFloat(blurRadius) * pt, in: ctx)
        case .text:
            drawText(c, box: box, pixelsPerPoint: pt, in: ctx)
        case .counter:
            ctx.fillEllipse(in: box)
            let n = "\(number(of: index, in: callouts))"
            drawLabel(n, centeredIn: box, fontSize: counterRadius(pt) * 1.1, color: labelColor(on: c.color), in: ctx)
        }
        if shadowed { ctx.endTransparencyLayer() }
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, lineWidth lw: CGFloat, in ctx: CGContext) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 2 else { return }
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = min(max(12, lw * 4), length * 0.6)
        // A filled head covers the end of the shaft, so stop the shaft short of the tip.
        let shaftEnd = CGPoint(x: b.x - cos(angle) * head * 0.6, y: b.y - sin(angle) * head * 0.6)
        ctx.move(to: a)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()
        let left = CGPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7))
        let right = CGPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7))
        ctx.move(to: b)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    /// The part of `source` under `rect` (video pixels, bottom-left origin), blurred.
    private static func drawBlur(_ rect: CGRect, source: CGImage?, videoSize: CGSize, radius: CGFloat, in ctx: CGContext) {
        guard let source, videoSize.width > 0, videoSize.height > 0, rect.width >= 1, rect.height >= 1 else { return }
        let video = CGRect(origin: .zero, size: videoSize)
        let r = rect.intersection(video)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return }
        // The source may be smaller than the video (the preview's frames are).
        let sx = CGFloat(source.width) / videoSize.width, sy = CGFloat(source.height) / videoSize.height
        let image = CIImage(cgImage: source)
        // Some room around the area, so its edges blur with what is next to them.
        let margin = radius * 3
        let area = CGRect(x: (r.minX - margin) * sx, y: (r.minY - margin) * sy,
                          width: (r.width + 2 * margin) * sx, height: (r.height + 2 * margin) * sy).intersection(image.extent)
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return }
        let blurred = image.cropped(to: area).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius * sx)).cropped(to: area)
        guard let out = ciContext.createCGImage(blurred, from: area) else { return }
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.interpolationQuality = .high
        ctx.draw(out, in: CGRect(x: area.minX / sx, y: area.minY / sy, width: area.width / sx, height: area.height / sy))
        ctx.restoreGState()
    }

    /// A label on a solid box in the callout's color, the text black or white, whichever reads better on it.
    private static func drawText(_ c: Callout, box: CGRect, pixelsPerPoint pt: CGFloat, in ctx: CGContext) {
        let radius = min(CGFloat(fontSize) * pt * 0.3, box.width / 2, box.height / 2)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        drawLabel(c.text, centeredIn: box, fontSize: CGFloat(fontSize) * pt, color: labelColor(on: c.color), in: ctx)
    }

    private static func drawLabel(_ text: String, centeredIn box: CGRect, fontSize: CGFloat, color: CGColor, in ctx: CGContext) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: max(fontSize, 1), weight: .semibold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: box.midX - width / 2, y: box.midY - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Black or white, whichever reads better on `color`.
    static func labelColor(on color: [Double]) -> CGColor {
        let luminance = 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2]
        return luminance > 0.6 ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }
}
