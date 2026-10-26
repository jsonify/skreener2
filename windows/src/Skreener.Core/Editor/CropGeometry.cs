using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>Which sides of the crop a drag moves: one for a side handle, two for a corner (CropEdges on the Mac).</summary>
[Flags]
public enum CropEdges
{
    None = 0,
    Left = 1,
    Top = 2,
    Right = 4,
    Bottom = 8,
}

/// <summary>What a press in crop mode does (cropDrag on the Mac).</summary>
public enum CropDragKind
{
    /// <summary>Moves the sides in <see cref="CropDrag.Edges"/>.</summary>
    Edges,
    /// <summary>Moves the whole crop.</summary>
    Move,
    /// <summary>Draws a new crop from the press (outside the current one).</summary>
    NewArea,
}

/// <summary>A press in crop mode: what it drags, and for <see cref="CropDragKind.Edges"/> which sides.</summary>
public readonly record struct CropDrag(CropDragKind Kind, CropEdges Edges = CropEdges.None);

/// <summary>
/// The crop's rect math (the crop half of AnnotationEditor.swift: cropHandles, cropDrag and the crop cases of
/// mouseDragged). Image pixels, top-left origin, so "top" is the smaller y. Every result stays inside
/// <c>bounds</c> (the image) and, when a side is dragged, at least <see cref="MinSize"/> wide and high.
/// </summary>
public static class CropGeometry
{
    /// <summary>The smallest crop a side or corner drag leaves (4 pixels, as on the Mac).</summary>
    public const double MinSize = 4;

    /// <summary>On-screen grab distances, in view points: a handle's radius and the slop around a side (Mac values).</summary>
    public const double HandleRadiusPoints = 12, SideSlopPoints = 6;

    /// <summary>The eight handles: the four corners (top-left, top-right, bottom-left, bottom-right), then the middle of each side (left, right, top, bottom).</summary>
    public static IReadOnlyList<(PointD Point, CropEdges Edges)> Handles(RectD r) => new[]
    {
        (new PointD(r.MinX, r.MinY), CropEdges.Left | CropEdges.Top),
        (new PointD(r.MaxX, r.MinY), CropEdges.Right | CropEdges.Top),
        (new PointD(r.MinX, r.MaxY), CropEdges.Left | CropEdges.Bottom),
        (new PointD(r.MaxX, r.MaxY), CropEdges.Right | CropEdges.Bottom),
        (new PointD(r.MinX, r.MidY()), CropEdges.Left),
        (new PointD(r.MaxX, r.MidY()), CropEdges.Right),
        (new PointD(r.MidX(), r.MinY), CropEdges.Top),
        (new PointD(r.MidX(), r.MaxY), CropEdges.Bottom),
    };

    /// <summary>
    /// What a press at <paramref name="p"/> drags: the nearest handle within <paramref name="handleRadius"/>, else any
    /// side within <paramref name="slop"/> (two near a corner), else the inside moves the crop and the outside draws a
    /// new one.
    /// </summary>
    public static CropDrag HitTest(RectD r, PointD p, double handleRadius, double slop)
    {
        (PointD Point, CropEdges Edges)? best = null;
        double bestDistance = double.MaxValue;
        foreach (var h in Handles(r))
        {
            var d = AnnotationGeometry.Distance(h.Point, p);
            if (d <= handleRadius && d < bestDistance) { best = h; bestDistance = d; }
        }
        if (best is { } handle) return new CropDrag(CropDragKind.Edges, handle.Edges);

        bool inX = p.X >= r.MinX - slop && p.X <= r.MaxX + slop, inY = p.Y >= r.MinY - slop && p.Y <= r.MaxY + slop;
        var edges = CropEdges.None;
        if (inY && Math.Abs(p.X - r.MinX) <= slop) edges |= CropEdges.Left;
        if (inY && Math.Abs(p.X - r.MaxX) <= slop) edges |= CropEdges.Right;
        if (inX && Math.Abs(p.Y - r.MinY) <= slop) edges |= CropEdges.Top;
        if (inX && Math.Abs(p.Y - r.MaxY) <= slop) edges |= CropEdges.Bottom;
        // A crop thinner than twice the slop is near both opposite sides: keep the nearer one.
        if (edges.HasFlag(CropEdges.Left | CropEdges.Right))
            edges &= Math.Abs(p.X - r.MinX) <= Math.Abs(p.X - r.MaxX) ? ~CropEdges.Right : ~CropEdges.Left;
        if (edges.HasFlag(CropEdges.Top | CropEdges.Bottom))
            edges &= Math.Abs(p.Y - r.MinY) <= Math.Abs(p.Y - r.MaxY) ? ~CropEdges.Bottom : ~CropEdges.Top;
        if (edges != CropEdges.None) return new CropDrag(CropDragKind.Edges, edges);
        return r.Contains(p) ? new CropDrag(CropDragKind.Move) : new CropDrag(CropDragKind.NewArea);
    }

    /// <summary><paramref name="p"/> moved inside <paramref name="bounds"/>.</summary>
    public static PointD Clamp(PointD p, RectD bounds) =>
        new(Math.Clamp(p.X, bounds.MinX, bounds.MaxX), Math.Clamp(p.Y, bounds.MinY, bounds.MaxY));

    /// <summary>
    /// <paramref name="r"/> with the sides in <paramref name="edges"/> dragged to <paramref name="p"/> (clamped to
    /// <paramref name="bounds"/>). A side stops <see cref="MinSize"/> short of the opposite one instead of flipping.
    /// </summary>
    public static RectD DragEdges(RectD r, CropEdges edges, PointD p, RectD bounds)
    {
        var q = Clamp(p, bounds);
        double x0 = r.MinX, x1 = r.MaxX, y0 = r.MinY, y1 = r.MaxY;
        if (edges.HasFlag(CropEdges.Left)) x0 = Math.Min(q.X, x1 - MinSize);
        if (edges.HasFlag(CropEdges.Right)) x1 = Math.Max(q.X, x0 + MinSize);
        if (edges.HasFlag(CropEdges.Top)) y0 = Math.Min(q.Y, y1 - MinSize);
        if (edges.HasFlag(CropEdges.Bottom)) y1 = Math.Max(q.Y, y0 + MinSize);
        return new RectD(x0, y0, x1 - x0, y1 - y0);
    }

    /// <summary><paramref name="r"/> moved by (<paramref name="dx"/>, <paramref name="dy"/>), stopping at the sides of <paramref name="bounds"/>.</summary>
    public static RectD Moved(RectD r, double dx, double dy, RectD bounds)
    {
        var x = Math.Clamp(r.MinX + dx, bounds.MinX, Math.Max(bounds.MinX, bounds.MaxX - r.Width));
        var y = Math.Clamp(r.MinY + dy, bounds.MinY, Math.Max(bounds.MinY, bounds.MaxY - r.Height));
        return new RectD(x, y, r.Width, r.Height);
    }

    /// <summary>A new crop drawn from <paramref name="anchor"/> to <paramref name="p"/>, both clamped to <paramref name="bounds"/>.</summary>
    public static RectD NewArea(PointD anchor, PointD p, RectD bounds)
    {
        PointD a = Clamp(anchor, bounds), q = Clamp(p, bounds);
        return new RectD(Math.Min(a.X, q.X), Math.Min(a.Y, q.Y), Math.Abs(q.X - a.X), Math.Abs(q.Y - a.Y));
    }

    /// <summary>
    /// The crop to keep when crop mode is applied (applyCrop on the Mac): <paramref name="draft"/> rounded outwards to
    /// whole pixels inside <paramref name="bounds"/>. Null (no crop) when it covers all of <paramref name="bounds"/>;
    /// <paramref name="previous"/> (unchanged) when it is smaller than <see cref="MinSize"/> either way.
    /// </summary>
    public static RectD? Applied(RectD draft, RectD bounds, RectD? previous)
    {
        var r = draft.Integral.Intersection(bounds);
        if (r.IsNull) return previous;
        if (r.MinX <= bounds.MinX && r.MinY <= bounds.MinY && r.MaxX >= bounds.MaxX && r.MaxY >= bounds.MaxY) return null;
        return r.Width >= MinSize && r.Height >= MinSize ? r : previous;
    }

    private static double MidX(this RectD r) => r.MinX + r.Width / 2;
    private static double MidY(this RectD r) => r.MinY + r.Height / 2;
}
