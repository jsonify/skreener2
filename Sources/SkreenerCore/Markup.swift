import CoreGraphics
import CoreText
import Foundation

/// An arrow, line, freehand pen stroke, rectangle, ellipse, text label or highlight drawn over a screenshot, for the iOS Share Extension (#396). Points
/// and rects are in image pixels (bottom-left origin, like `Redaction`). Named `Markup`, not `Annotation`: the Mac
/// editor has its own `Annotation`, and tests import both modules.
///
/// It looks like the Mac editor's defaults: a 3 pt line, a filled arrowhead 5 line widths long, bold 22 pt system
/// text with no box (the Mac's is semibold), a 45% multiply highlight, and the soft drop shadow under everything but
/// the highlight. One "point" here is 1/393 of the image's width (an iPhone screen's width in points), so a 3x
/// screenshot gets the Mac's sizes at 3x, and the preview looks like the export. `width` scales the strokes and the
/// text size from those defaults.
public struct Markup: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        /// A straight stroke with round caps and no head.
        case line(from: CGPoint, to: CGPoint)
        /// A freehand stroke through the points, smoothed, with round caps and joins. One point is a dot, none draws
        /// nothing.
        case pen([CGPoint])
        case rectangle(CGRect)
        /// An outlined ellipse inscribed in the rect.
        case ellipse(CGRect)
        /// `at` is the left end of the line of text, halfway up its glyphs.
        case text(String, at: CGPoint)
        case highlight(CGRect)
    }

    public var kind: Kind
    public var color: RGBColor

    /// The allowed range of `width`.
    public static let widthRange: ClosedRange<CGFloat> = 0.5...4

    /// A multiplier of the default size, kept within `widthRange`: 1 is today's 3 pt line. It scales the stroke of
    /// arrows (their head follows), lines, pens, rectangles and ellipses, and the font size of text. A highlight
    /// ignores it. It is relative, so `scaled(by:)` leaves it alone.
    public var width: CGFloat {
        didSet { width = Markup.clampedWidth(width) }
    }

    private static func clampedWidth(_ w: CGFloat) -> CGFloat {
        w.isNaN ? 1 : min(max(w, widthRange.lowerBound), widthRange.upperBound)
    }

    /// The Mac editor's default color (systemRed).
    public static let defaultColor = RGBColor.hex(0xFF3B30)

    public init(_ kind: Kind, color: RGBColor = Markup.defaultColor, width: CGFloat = 1) {
        self.kind = kind
        self.color = color
        self.width = Markup.clampedWidth(width)
    }

    /// The same markup on an image `k` times as wide (the preview is smaller than the export).
    public func scaled(by k: CGFloat) -> Markup {
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * k, y: q.y * k) }
        func r(_ q: CGRect) -> CGRect { CGRect(x: q.minX * k, y: q.minY * k, width: q.width * k, height: q.height * k) }
        let scaledKind: Kind
        switch kind {
        case .arrow(let a, let b): scaledKind = .arrow(from: p(a), to: p(b))
        case .line(let a, let b): scaledKind = .line(from: p(a), to: p(b))
        case .pen(let points): scaledKind = .pen(points.map(p))
        case .rectangle(let rect): scaledKind = .rectangle(r(rect))
        case .ellipse(let rect): scaledKind = .ellipse(r(rect))
        case .text(let s, let at): scaledKind = .text(s, at: p(at))
        case .highlight(let rect): scaledKind = .highlight(r(rect))
        }
        return Markup(scaledKind, color: color, width: width)
    }

    // MARK: Sizes

    /// One point on an image `width` pixels wide: 1/393 of it (3 px on a 1179 px screenshot), at least 1 px.
    public static func unit(imageWidth width: Int) -> CGFloat { max(1, CGFloat(width) / 393) }

    /// Arrows' and rectangles' line width: the Mac's 3 pt.
    public static func lineWidth(imageWidth width: Int) -> CGFloat { 3 * unit(imageWidth: width) }

    /// The line width of a markup with this `width` multiplier.
    public static func lineWidth(imageWidth: Int, scale: CGFloat) -> CGFloat {
        lineWidth(imageWidth: imageWidth) * clampedWidth(scale)
    }

    /// An arrowhead's length: the Mac's max(12, 5 × line width). `scale` is the markup's `width`.
    public static func headLength(imageWidth width: Int, scale: CGFloat = 1) -> CGFloat {
        max(12 * unit(imageWidth: width), 5 * lineWidth(imageWidth: width, scale: scale))
    }

    /// Text size: the Mac's 22 pt. `scale` is the markup's `width`.
    public static func fontSize(imageWidth width: Int, scale: CGFloat = 1) -> CGFloat {
        22 * unit(imageWidth: width) * clampedWidth(scale)
    }

    /// The highlight's opacity, multiplied over the picture so the text under it stays readable, like a marker.
    public static let highlightAlpha: CGFloat = 0.45

    /// The rect a text label's glyphs take up (its typographic bounds), in image pixels.
    public static func textBounds(_ text: String, at p: CGPoint, imageWidth width: Int, scale: CGFloat = 1) -> CGRect {
        let line = makeLine(text, color: CGColor(gray: 0, alpha: 1), imageWidth: width, scale: scale)
        let m = metrics(line)
        return CGRect(x: p.x, y: baseline(at: p, metrics: m) - m.descent, width: m.width, height: m.ascent + m.descent)
    }

    // MARK: Drawing

    /// Draws `markups` in order into `ctx`, which shows the image in `CGRect(0, 0, width, height)` (y-up, one unit per
    /// image pixel). Sizes follow `imageWidth`. Safe off the main actor: nothing is cached between calls.
    public static func draw(_ markups: [Markup], imageWidth: Int, in ctx: CGContext) {
        let u = unit(imageWidth: imageWidth)
        for markup in markups {
            let lw = lineWidth(imageWidth: imageWidth, scale: markup.width)
            let head = headLength(imageWidth: imageWidth, scale: markup.width)
            if case .pen(let points) = markup.kind, points.isEmpty { continue }
            let color = markup.color.cgColor
            ctx.saveGState()
            if case .highlight(let rect) = markup.kind {
                ctx.setBlendMode(.multiply)
                ctx.setFillColor(color.copy(alpha: highlightAlpha * CGFloat(markup.color.a)) ?? color)
                ctx.fill(rect.standardized)
                ctx.restoreGState()
                continue
            }
            // The Mac's drop shadow, on one layer so an arrow's shaft and head cast a single shadow. Without the
            // Mac's small downward offset: UIKit and bitmap contexts disagree on which way is down for shadows.
            let pad = head + lw + 12 * u
            ctx.setShadow(offset: .zero, blur: 4 * u, color: CGColor(gray: 0, alpha: 0.35))
            ctx.beginTransparencyLayer(in: bounds(of: markup, imageWidth: imageWidth).insetBy(dx: -pad, dy: -pad),
                                       auxiliaryInfo: nil)
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            switch markup.kind {
            case .arrow(let from, let to):
                drawArrow(from: from, to: to, lineWidth: lw, head: head, in: ctx)
            case .line(let from, let to):
                ctx.setLineWidth(lw)
                ctx.setLineCap(.round)
                ctx.move(to: from)
                ctx.addLine(to: to)
                ctx.strokePath()
            case .pen(let points):
                drawPen(points, lineWidth: lw, in: ctx)
            case .ellipse(let rect):
                ctx.setLineWidth(lw)
                ctx.strokeEllipse(in: rect.standardized)
            case .rectangle(let rect):
                // The Mac's rectangles have 2 pt corners and round joins.
                ctx.setLineJoin(.round)
                Draw.stroke(Draw.roundedRect(rect.standardized, radius: 2 * u), color, width: lw, in: ctx)
            case .text(let text, let at):
                drawText(text, at: at, color: color, imageWidth: imageWidth, scale: markup.width, in: ctx)
            case .highlight:
                break
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    /// Roughly where a markup draws, to bound its shadow layer.
    private static func bounds(of markup: Markup, imageWidth: Int) -> CGRect {
        switch markup.kind {
        case .arrow(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .line(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .pen(let points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        case .rectangle(let r), .ellipse(let r), .highlight(let r):
            return r.standardized
        case .text(let s, let at):
            return textBounds(s, at: at, imageWidth: imageWidth, scale: markup.width)
        }
    }

    /// The Mac's filled arrow: a round-capped shaft that stops inside the head, and a triangle with sides at ±π/7.
    private static func drawArrow(from a: CGPoint, to b: CGPoint, lineWidth lw: CGFloat, head: CGFloat,
                                  in ctx: CGContext) {
        guard hypot(b.x - a.x, b.y - a.y) > 2 else { return }
        let angle = atan2(b.y - a.y, b.x - a.x)
        let inset = head * 0.6
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: b.x - cos(angle) * inset, y: b.y - sin(angle) * inset))
        ctx.strokePath()
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
        ctx.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
        ctx.closePath()
        ctx.fillPath()
    }

    /// A freehand stroke: quadratic curves that use each point as a control point and pass through the midpoints
    /// between neighbours, so it is smooth and starts and ends exactly on the first and last point. One point is a
    /// dot as wide as the line.
    private static func drawPen(_ points: [CGPoint], lineWidth lw: CGFloat, in ctx: CGContext) {
        guard let first = points.first else { return }
        if points.count == 1 {
            ctx.fillEllipse(in: CGRect(x: first.x - lw / 2, y: first.y - lw / 2, width: lw, height: lw))
            return
        }
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: first)
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            ctx.addQuadCurve(to: mid, control: points[i])
        }
        ctx.addLine(to: points[points.count - 1])
        ctx.strokePath()
    }

    private static func drawText(_ text: String, at p: CGPoint, color: CGColor, imageWidth: Int, scale: CGFloat,
                                 in ctx: CGContext) {
        guard !text.isEmpty else { return }
        let line = makeLine(text, color: color, imageWidth: imageWidth, scale: scale)
        // Glyphs upright in a y-up context: an identity text matrix, whatever the caller left set.
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: p.x, y: baseline(at: p, metrics: metrics(line)))
        CTLineDraw(line, ctx)
    }

    /// One line of bold system text (line breaks become spaces).
    private static func makeLine(_ text: String, color: CGColor, imageWidth: Int, scale: CGFloat) -> CTLine {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ")
        let size = fontSize(imageWidth: imageWidth, scale: scale)
        // The emphasized (bold) system font; the Mac's is semibold, which CoreText has no plain way to ask for.
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let string = CFAttributedStringCreate(nil, flat as CFString, attrs as CFDictionary)
            ?? (NSAttributedString(string: "") as CFAttributedString)
        return CTLineCreateWithAttributedString(string)
    }

    private struct Metrics {
        var ascent: CGFloat, descent: CGFloat, width: CGFloat
    }

    private static func metrics(_ line: CTLine) -> Metrics {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return Metrics(ascent: ascent, descent: descent, width: width)
    }

    /// The baseline that puts `p` halfway up the line's glyph box.
    private static func baseline(at p: CGPoint, metrics m: Metrics) -> CGFloat { p.y - (m.ascent - m.descent) / 2 }
}
