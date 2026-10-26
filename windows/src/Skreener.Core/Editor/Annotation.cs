using Skreener.Core.Colors;
using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>
/// What an annotation draws (the drawing half of Tool in AnnotationEditor.swift; spotlight, erase, magnifier and the
/// rest come with later editor milestones).
/// </summary>
public enum AnnotationKind
{
    Arrow,
    Rectangle,
    Ellipse,
    Line,
    Pen,
    Pixelate,
    /// <summary>A box filled with the color (filledRect).</summary>
    FilledRectangle,
    /// <summary>A wide freehand stroke drawn with multiply, so text under it stays readable.</summary>
    Highlighter,
    /// <summary>A text label; <see cref="Annotation.Start"/> is its top-left corner.</summary>
    Text,
    /// <summary>A numbered filled circle centered on <see cref="Annotation.Start"/>.</summary>
    Counter,
    /// <summary>A box showing the screenshot blurred under it.</summary>
    Blur,
}

/// <summary>How an annotation looks (Style in AnnotationEditor.swift, the parts these kinds use).</summary>
/// <param name="Color">Stroke, fill or text color.</param>
/// <param name="LineWidth">Stroke width in image pixels.</param>
/// <param name="PixelSize">Pixelate block size in image pixels.</param>
public sealed record AnnotationStyle(RgbColor Color, double LineWidth, int PixelSize)
{
    /// <summary>The Mac defaults: system red; 3 pt on a Retina Mac is about 4 px on a 125-150 % Windows display.</summary>
    public static AnnotationStyle Default { get; } = new(RgbColor.FromBytes(255, 59, 48), 4, 10);

    /// <summary>Text size in image pixels; a counter's size follows it too (fontSize on the Mac, 22 by default).</summary>
    public double FontSize { get; init; } = 22;

    /// <summary>Bold text (on by default, as on the Mac).</summary>
    public bool Bold { get; init; } = true;

    /// <summary>
    /// The blur's strength: its Gaussian radius in image pixels. The Mac shares pixelSize between pixelate and blur;
    /// here each keeps its own, so switching between the two tools keeps both choices.
    /// </summary>
    public int BlurRadius { get; init; } = 10;

    /// <summary>A highlighter stroke's width (highlighterWidth on the Mac).</summary>
    public double HighlighterWidth => Math.Max(12, LineWidth * 5);

    /// <summary>A counter's radius (counterRadius on the Mac).</summary>
    public double CounterRadius => Math.Max(10, FontSize * 0.75);
}

/// <summary>
/// One shape on the screenshot (Annotation in AnnotationEditor.swift). Immutable: edits make a new one with the same
/// <see cref="Id"/>, so the undo history can keep whole lists of them. Coordinates are image pixels, top-left origin,
/// y down (unlike the Mac's y-up view points).
/// </summary>
/// <param name="Id">Stays the same across edits; what the selection refers to. Ids grow with creation order, which
/// is what numbers the counters (the Mac's seq).</param>
/// <param name="Kind">What it draws.</param>
/// <param name="Start">Where the drag began: an arrow's tail, a box's first corner, a stroke's first point, a text
/// label's top-left corner, a counter's center.</param>
/// <param name="End">Where the drag ended: an arrow's tip, a box's opposite corner, a stroke's last point, a text
/// label's bottom-right corner (kept in step with its measured size by <see cref="EditorSession"/>), a counter's
/// center again.</param>
/// <param name="Points">A pen or highlighter stroke's points, first to last; empty for every other kind.</param>
/// <param name="Style">Color, width, pixel size, font.</param>
public sealed record Annotation(int Id, AnnotationKind Kind, PointD Start, PointD End, IReadOnlyList<PointD> Points, AnnotationStyle Style)
{
    /// <summary>A text label's text (may hold line breaks); empty for every other kind.</summary>
    public string Text { get; init; } = "";

    /// <summary>Box kinds are drawn in the rect between <see cref="Start"/> and <see cref="End"/> and resized by its corners.</summary>
    public bool IsBox => Kind is AnnotationKind.Rectangle or AnnotationKind.Ellipse or AnnotationKind.Pixelate
        or AnnotationKind.FilledRectangle or AnnotationKind.Blur;

    /// <summary>Freehand kinds (pen, highlighter) keep every point of the stroke in <see cref="Points"/>.</summary>
    public bool IsFreehand => Kind is AnnotationKind.Pen or AnnotationKind.Highlighter;

    /// <summary>Kinds hit anywhere inside their bounds rather than on a line (the Mac's list in hits).</summary>
    public bool IsSolid => Kind is AnnotationKind.Pixelate or AnnotationKind.Blur or AnnotationKind.FilledRectangle
        or AnnotationKind.Text or AnnotationKind.Counter;

    /// <summary>The rect between <see cref="Start"/> and <see cref="End"/>, standardized.</summary>
    public RectD Rect => new(Math.Min(Start.X, End.X), Math.Min(Start.Y, End.Y), Math.Abs(End.X - Start.X), Math.Abs(End.Y - Start.Y));

    /// <summary>
    /// The geometric bounds, without the stroke: the points' bounds for a stroke, the circle's for a counter, else
    /// <see cref="Rect"/>.
    /// </summary>
    public RectD Bounds
    {
        get
        {
            if (Kind == AnnotationKind.Counter)
            {
                var r = Style.CounterRadius;
                return new RectD(Start.X - r, Start.Y - r, 2 * r, 2 * r);
            }
            if (!IsFreehand || Points.Count == 0) return Rect;
            double x0 = double.MaxValue, y0 = double.MaxValue, x1 = double.MinValue, y1 = double.MinValue;
            foreach (var p in Points)
            {
                x0 = Math.Min(x0, p.X); y0 = Math.Min(y0, p.Y);
                x1 = Math.Max(x1, p.X); y1 = Math.Max(y1, p.Y);
            }
            return new RectD(x0, y0, x1 - x0, y1 - y0);
        }
    }

    /// <summary>The same annotation moved by (<paramref name="dx"/>, <paramref name="dy"/>).</summary>
    public Annotation Translated(double dx, double dy) => dx == 0 && dy == 0 ? this : this with
    {
        Start = new PointD(Start.X + dx, Start.Y + dy),
        End = new PointD(End.X + dx, End.Y + dy),
        Points = Points.Count == 0 ? Points : Points.Select(p => new PointD(p.X + dx, p.Y + dy)).ToArray(),
    };

    /// <summary>
    /// Whether this was drawn by a real drag rather than a click: a click with a drawing tool adds nothing (the Mac
    /// drops drafts this small too). A box needs some width and height, a line some length, a stroke two points.
    /// Text and counters are placed by a click, so they always count.
    /// </summary>
    public bool IsDrawable
    {
        get
        {
            const double min = 2;
            if (Kind is AnnotationKind.Text or AnnotationKind.Counter) return true;
            if (IsFreehand) return Points.Count >= 2 && (Bounds.Width >= min || Bounds.Height >= min);
            if (IsBox) return Rect.Width >= min && Rect.Height >= min;
            return Math.Sqrt(Square(End.X - Start.X) + Square(End.Y - Start.Y)) > min;
        }
    }

    private static double Square(double v) => v * v;
}
