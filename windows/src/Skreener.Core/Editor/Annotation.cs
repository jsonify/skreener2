using Skreener.Core.Colors;
using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>
/// What an annotation draws (the drawing half of Tool in AnnotationEditor.swift; more kinds come with the later
/// editor milestones).
/// </summary>
public enum AnnotationKind
{
    Arrow,
    Rectangle,
    Ellipse,
    Line,
    Pen,
    Pixelate,
}

/// <summary>How an annotation looks (Style in AnnotationEditor.swift, the parts these kinds use).</summary>
/// <param name="Color">Stroke color.</param>
/// <param name="LineWidth">Stroke width in image pixels.</param>
/// <param name="PixelSize">Pixelate block size in image pixels.</param>
public sealed record AnnotationStyle(RgbColor Color, double LineWidth, int PixelSize)
{
    /// <summary>The Mac defaults: system red; 3 pt on a Retina Mac is about 4 px on a 125-150 % Windows display.</summary>
    public static AnnotationStyle Default { get; } = new(RgbColor.FromBytes(255, 59, 48), 4, 10);
}

/// <summary>
/// One shape on the screenshot (Annotation in AnnotationEditor.swift). Immutable: edits make a new one with the same
/// <see cref="Id"/>, so the undo history can keep whole lists of them. Coordinates are image pixels, top-left origin,
/// y down (unlike the Mac's y-up view points).
/// </summary>
/// <param name="Id">Stays the same across edits; what the selection refers to.</param>
/// <param name="Kind">What it draws.</param>
/// <param name="Start">Where the drag began: an arrow's tail, a box's first corner, a pen stroke's first point.</param>
/// <param name="End">Where the drag ended: an arrow's tip, a box's opposite corner, a pen stroke's last point.</param>
/// <param name="Points">A pen stroke's points, first to last; empty for every other kind.</param>
/// <param name="Style">Color, width, pixel size.</param>
public sealed record Annotation(int Id, AnnotationKind Kind, PointD Start, PointD End, IReadOnlyList<PointD> Points, AnnotationStyle Style)
{
    /// <summary>Box kinds are drawn in the rect between <see cref="Start"/> and <see cref="End"/> and resized by its corners.</summary>
    public bool IsBox => Kind is AnnotationKind.Rectangle or AnnotationKind.Ellipse or AnnotationKind.Pixelate;

    /// <summary>The rect between <see cref="Start"/> and <see cref="End"/>, standardized.</summary>
    public RectD Rect => new(Math.Min(Start.X, End.X), Math.Min(Start.Y, End.Y), Math.Abs(End.X - Start.X), Math.Abs(End.Y - Start.Y));

    /// <summary>The geometric bounds, without the stroke: the points' bounds for a pen stroke, else <see cref="Rect"/>.</summary>
    public RectD Bounds
    {
        get
        {
            if (Kind != AnnotationKind.Pen || Points.Count == 0) return Rect;
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
    /// </summary>
    public bool IsDrawable
    {
        get
        {
            const double min = 2;
            if (Kind == AnnotationKind.Pen) return Points.Count >= 2 && (Bounds.Width >= min || Bounds.Height >= min);
            if (IsBox) return Rect.Width >= min && Rect.Height >= min;
            return Math.Sqrt(Square(End.X - Start.X) + Square(End.Y - Start.Y)) > min;
        }
    }

    private static double Square(double v) => v * v;
}
