using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>
/// Hit testing, resize handles and the arrow's outline (from AnnotationEditor.swift: hits, handles, drawArrow).
/// Image pixels, top-left origin. Distances the user aims with (slop, handle radius) are passed in image pixels, so
/// callers divide their on-screen sizes by the zoom.
/// </summary>
public static class AnnotationGeometry
{
    /// <summary>
    /// Whether a click at <paramref name="p"/> picks <paramref name="a"/>: the solid kinds (pixelate, blur, filled
    /// rectangle, text, counter) anywhere inside their bounds, the outlined shapes (rectangle, ellipse, line, arrow,
    /// pen, highlighter) only on their line, widened by <paramref name="slop"/>. Hitting outlines only keeps whatever
    /// is inside a rectangle clickable, as on the Mac.
    /// </summary>
    public static bool Hits(Annotation a, PointD p, double slop)
    {
        if (a.IsSolid) return a.Bounds.InsetBy(-slop, -slop).Contains(p);
        var reach = (a.Kind == AnnotationKind.Highlighter ? a.Style.HighlighterWidth : a.Style.LineWidth) / 2 + slop;
        switch (a.Kind)
        {
            case AnnotationKind.Rectangle:
                return DistanceToRectOutline(a.Rect, p) <= reach;
            case AnnotationKind.Ellipse:
                return DistanceToEllipseOutline(a.Rect, p) <= reach;
            case AnnotationKind.Pen:
            case AnnotationKind.Highlighter:
                if (a.Points.Count == 1) return Distance(a.Points[0], p) <= reach;
                for (int i = 1; i < a.Points.Count; i++)
                    if (DistanceToSegment(a.Points[i - 1], a.Points[i], p) <= reach) return true;
                return false;
            default:
                // An arrow's head is wider than its shaft, so it counts the head's half-width too.
                if (a.Kind == AnnotationKind.Arrow) reach = Math.Max(reach, HeadSize(a.Style.LineWidth) * 0.45 + slop);
                return DistanceToSegment(a.Start, a.End, p) <= reach;
        }
    }

    /// <summary>The topmost annotation hit at <paramref name="p"/> (the last drawn wins), or null.</summary>
    public static Annotation? TopmostHit(IReadOnlyList<Annotation> items, PointD p, double slop)
    {
        for (int i = items.Count - 1; i >= 0; i--)
            if (Hits(items[i], p, slop)) return items[i];
        return null;
    }

    /// <summary>
    /// Where the resize handles sit: a box's four corners (top-left, top-right, bottom-left, bottom-right, so the
    /// opposite of handle <c>i</c> is <c>3 - i</c>), a line's or arrow's two ends (start, end), none for a stroke, a
    /// text label or a counter (they only move).
    /// </summary>
    public static IReadOnlyList<PointD> Handles(Annotation a)
    {
        if (a.IsBox)
        {
            var r = a.Rect;
            return new[] { new PointD(r.MinX, r.MinY), new PointD(r.MaxX, r.MinY), new PointD(r.MinX, r.MaxY), new PointD(r.MaxX, r.MaxY) };
        }
        return a.Kind is AnnotationKind.Arrow or AnnotationKind.Line ? new[] { a.Start, a.End } : Array.Empty<PointD>();
    }

    /// <summary>
    /// The handle within <paramref name="radius"/> of <paramref name="p"/>, the nearest if several are (handles of a
    /// small box sit close together), or null.
    /// </summary>
    public static int? HandleAt(Annotation a, PointD p, double radius)
    {
        var handles = Handles(a);
        int? best = null;
        double bestDistance = double.MaxValue;
        for (int i = 0; i < handles.Count; i++)
        {
            var d = Distance(handles[i], p);
            if (d <= radius && d < bestDistance) { best = i; bestDistance = d; }
        }
        return best;
    }

    /// <summary>
    /// <paramref name="a"/> with handle <paramref name="handle"/> dragged to <paramref name="p"/>: a line's end moves
    /// alone; a box's diagonally opposite corner stays put (dragging past it flips the box, which stays standardized).
    /// </summary>
    public static Annotation Resized(Annotation a, int handle, PointD p)
    {
        if (!a.IsBox) return handle == 0 ? a with { Start = p } : a with { End = p };
        var anchor = Handles(a)[3 - handle];
        return a with
        {
            Start = new PointD(Math.Min(anchor.X, p.X), Math.Min(anchor.Y, p.Y)),
            End = new PointD(Math.Max(anchor.X, p.X), Math.Max(anchor.Y, p.Y)),
        };
    }

    /// <summary>The arrowhead's length for a stroke width (max(12, width x 5) on the Mac).</summary>
    public static double HeadSize(double lineWidth) => Math.Max(12, lineWidth * 5);

    /// <summary>
    /// The pieces of a filled arrow (the Mac's default style): the shaft from the tail to <c>ShaftEnd</c>, stroked
    /// with round caps, and the head as a filled triangle (tip first). The shaft stops short of the tip so its round
    /// cap stays hidden under the head. Null when the arrow is too short to draw (2 px or less, like the Mac).
    /// </summary>
    public static (PointD ShaftEnd, PointD[] Head)? ArrowShape(PointD start, PointD end, double lineWidth)
    {
        double dx = end.X - start.X, dy = end.Y - start.Y;
        if (Math.Sqrt(dx * dx + dy * dy) <= 2) return null;
        var angle = Math.Atan2(dy, dx);
        var head = HeadSize(lineWidth);
        var spread = Math.PI / 7;
        var left = new PointD(end.X - head * Math.Cos(angle - spread), end.Y - head * Math.Sin(angle - spread));
        var right = new PointD(end.X - head * Math.Cos(angle + spread), end.Y - head * Math.Sin(angle + spread));
        var inset = head * 0.6;
        var shaftEnd = new PointD(end.X - Math.Cos(angle) * inset, end.Y - Math.Sin(angle) * inset);
        return (shaftEnd, new[] { end, left, right });
    }

    /// <summary>How far ink reaches past <see cref="Annotation.Bounds"/>: half the stroke, or an arrowhead's spread.</summary>
    public static double InkOutset(Annotation a) => a.Kind switch
    {
        _ when a.IsSolid => 0,
        AnnotationKind.Highlighter => a.Style.HighlighterWidth / 2,
        AnnotationKind.Arrow => Math.Max(a.Style.LineWidth / 2, HeadSize(a.Style.LineWidth) * 0.45),
        _ => a.Style.LineWidth / 2,
    };

    /// <summary>
    /// A counter's number: its place among the counters in creation order (lowest <see cref="Annotation.Id"/> first),
    /// so deleting one renumbers the ones after it (drawCounter on the Mac). 0 for anything that is not a counter.
    /// </summary>
    public static int CounterNumber(IEnumerable<Annotation> items, Annotation counter)
    {
        if (counter.Kind != AnnotationKind.Counter) return 0;
        return items.Count(a => a.Kind == AnnotationKind.Counter && a.Id < counter.Id) + 1;
    }

    /// <summary>
    /// Whether a counter's number is black rather than white: on very light, unsaturated fills such as white or pale
    /// yellow-grey (HSB brightness above 0.85 and saturation below 0.5, as on the Mac).
    /// </summary>
    public static bool CounterUsesDarkText(Colors.RgbColor c)
    {
        double max = Math.Max(c.R, Math.Max(c.G, c.B)), min = Math.Min(c.R, Math.Min(c.G, c.B));
        var saturation = max <= 0 ? 0 : (max - min) / max;
        return max > 0.85 && saturation < 0.5;
    }

    /// <summary>
    /// A rough size for <paramref name="text"/> in <paramref name="style"/> when no real text measurer is at hand
    /// (tests, or before the window supplies one): 0.6 em per character of the longest line, 1.25 em per line. At
    /// least one line high and half an em wide, so an empty label being typed still has a box.
    /// </summary>
    public static SizeD EstimateTextSize(string text, AnnotationStyle style)
    {
        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var longest = lines.Max(l => l.Length);
        return new SizeD(Math.Max(longest * style.FontSize * 0.6, style.FontSize * 0.5), lines.Length * style.FontSize * 1.25);
    }

    public static double Distance(PointD a, PointD b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));

    public static double DistanceToSegment(PointD a, PointD b, PointD p)
    {
        double dx = b.X - a.X, dy = b.Y - a.Y, lengthSquared = dx * dx + dy * dy;
        if (lengthSquared == 0) return Distance(a, p);
        var t = Math.Clamp(((p.X - a.X) * dx + (p.Y - a.Y) * dy) / lengthSquared, 0, 1);
        return Distance(new PointD(a.X + t * dx, a.Y + t * dy), p);
    }

    /// <summary>Distance from <paramref name="p"/> to the nearest edge of <paramref name="r"/>, inside or outside.</summary>
    public static double DistanceToRectOutline(RectD r, PointD p)
    {
        var tl = new PointD(r.MinX, r.MinY);
        var tr = new PointD(r.MaxX, r.MinY);
        var bl = new PointD(r.MinX, r.MaxY);
        var br = new PointD(r.MaxX, r.MaxY);
        return Math.Min(Math.Min(DistanceToSegment(tl, tr, p), DistanceToSegment(tr, br, p)),
            Math.Min(DistanceToSegment(br, bl, p), DistanceToSegment(bl, tl, p)));
    }

    /// <summary>
    /// Roughly how far <paramref name="p"/> is from the outline of the ellipse inscribed in <paramref name="r"/>: the
    /// radial gap, scaled by the shorter radius. Exact on a circle, close enough to aim at on an ellipse.
    /// </summary>
    public static double DistanceToEllipseOutline(RectD r, PointD p)
    {
        double rx = r.Width / 2, ry = r.Height / 2;
        if (rx < 0.5 || ry < 0.5) return DistanceToRectOutline(r, p);
        double nx = (p.X - (r.MinX + rx)) / rx, ny = (p.Y - (r.MinY + ry)) / ry;
        return Math.Abs(Math.Sqrt(nx * nx + ny * ny) - 1) * Math.Min(rx, ry);
    }
}
