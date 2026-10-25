namespace Skreener.Core.Geometry;

/// <summary>A point with double coordinates (CGPoint). Whether y grows up or down is up to the caller.</summary>
public readonly record struct PointD(double X, double Y);

/// <summary>A size with double extents (CGSize).</summary>
public readonly record struct SizeD(double Width, double Height);

/// <summary>
/// A rectangle with CGRect's semantics, for the code ported from Swift: origin plus size, where the size may be negative
/// (see <see cref="Standardized"/>) and <see cref="Width"/>, <see cref="MinX"/> and friends read as CoreGraphics reads
/// them. Equality compares origin and size exactly, like CGRect's. A rect that does not intersect another has the
/// <see cref="Null"/> rect as its intersection. The y axis is not interpreted here: "min" is the smaller y, whether
/// that is the bottom (macOS views) or the top (pixels, Windows).
/// </summary>
public readonly record struct RectD
{
    public RectD(double x, double y, double width, double height)
    {
        Origin = new PointD(x, y);
        Size = new SizeD(width, height);
    }

    public RectD(PointD origin, SizeD size)
    {
        Origin = origin;
        Size = size;
    }

    public PointD Origin { get; init; }
    public SizeD Size { get; init; }

    /// <summary>CGRectNull: what an empty intersection and an over-inset rect come out as.</summary>
    public static RectD Null { get; } = new(double.PositiveInfinity, double.PositiveInfinity, 0, 0);

    public bool IsNull => double.IsPositiveInfinity(Origin.X) || double.IsPositiveInfinity(Origin.Y);

    /// <summary>Null, or no width or no height.</summary>
    public bool IsEmpty => IsNull || Size.Width == 0 || Size.Height == 0;

    public double MinX => Math.Min(Origin.X, Origin.X + Size.Width);
    public double MaxX => Math.Max(Origin.X, Origin.X + Size.Width);
    public double MinY => Math.Min(Origin.Y, Origin.Y + Size.Height);
    public double MaxY => Math.Max(Origin.Y, Origin.Y + Size.Height);

    /// <summary>The extent, never negative (CGRect.width, unlike <c>Size.Width</c>).</summary>
    public double Width => Math.Abs(Size.Width);
    public double Height => Math.Abs(Size.Height);

    public RectD Standardized => IsNull ? this : new RectD(MinX, MinY, Width, Height);

    public RectD OffsetBy(double dx, double dy) => new(Origin.X + dx, Origin.Y + dy, Size.Width, Size.Height);

    /// <summary>
    /// Shrinks each side by <paramref name="dx"/>/<paramref name="dy"/> (grows for negative values), around the same
    /// center. Null when it would end up with a negative width or height.
    /// </summary>
    public RectD InsetBy(double dx, double dy)
    {
        if (IsNull) return this;
        var r = Standardized;
        double w = r.Size.Width - 2 * dx, h = r.Size.Height - 2 * dy;
        return w < 0 || h < 0 ? Null : new RectD(r.Origin.X + dx, r.Origin.Y + dy, w, h);
    }

    /// <summary>The smallest whole-number rect that contains this one: it rounds outwards (CGRect.integral).</summary>
    public RectD Integral
    {
        get
        {
            if (IsNull) return this;
            double x = Math.Floor(MinX), y = Math.Floor(MinY);
            return new RectD(x, y, Math.Ceiling(MaxX) - x, Math.Ceiling(MaxY) - y);
        }
    }

    /// <summary>The overlap of two rects: <see cref="Null"/> when they are apart. Rects that only touch give an empty rect.</summary>
    public RectD Intersection(RectD other)
    {
        if (IsNull || other.IsNull) return Null;
        double x0 = Math.Max(MinX, other.MinX), x1 = Math.Min(MaxX, other.MaxX);
        double y0 = Math.Max(MinY, other.MinY), y1 = Math.Min(MaxY, other.MaxY);
        return x0 > x1 || y0 > y1 ? Null : new RectD(x0, y0, x1 - x0, y1 - y0);
    }

    /// <summary>Whether the two share area; rects that only touch along an edge do not.</summary>
    public bool Intersects(RectD other) =>
        !IsNull && !other.IsNull && MinX < other.MaxX && MaxX > other.MinX && MinY < other.MaxY && MaxY > other.MinY;

    /// <summary>The min edges are inside, the max edges are not (CGRect.contains).</summary>
    public bool Contains(PointD p) => p.X >= MinX && p.X < MaxX && p.Y >= MinY && p.Y < MaxY;
}
