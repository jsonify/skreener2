namespace Skreener.Core.Imaging;

/// <summary>An inclusive run of pixel indexes along a row or column (Swift's ClosedRange).</summary>
public readonly record struct PixelSpan(int Start, int End)
{
    public int Length => End - Start + 1;
}

/// <summary>
/// The editor's pixel ruler (#107): from a pixel, how far the same color runs left and right (or up and down), so
/// holding the ruler over a button measures the button and over a gap measures the gap. Top-left origin, like the pixels.
/// </summary>
public static class RulerScanner
{
    public enum Axis { Horizontal, Vertical }

    /// <summary>Largest channel difference (0 to 255) still counted as the same color.</summary>
    public const int DefaultTolerance = 10;

    /// <summary>
    /// With <c>outer</c>, a run of another color past an edge counts as that element's border only up to this many pixels;
    /// a longer one is the background.
    /// </summary>
    public const int MaxBorder = 16;

    /// <summary>
    /// The pixels (inclusive, along <paramref name="axis"/>) that share the color at (x, y) (top-left origin), or null
    /// outside the image. <paramref name="outer"/> also takes in a border on each side: the run of the next color, when
    /// it is at most <see cref="MaxBorder"/> long.
    /// </summary>
    public static PixelSpan? Span(PixelBuffer buf, int x, int y, Axis axis, int tolerance = DefaultTolerance, bool outer = false)
    {
        if (!buf.Contains(x, y)) return null;
        int count = axis == Axis.Horizontal ? buf.Width : buf.Height;
        int start = axis == Axis.Horizontal ? x : y;
        Pixel At(int i) => axis == Axis.Horizontal ? buf.Rgba(i, y) : buf.Rgba(x, i);
        bool Same(Pixel p, Pixel q) =>
            Math.Max(Math.Max(Math.Abs(p.R - q.R), Math.Abs(p.G - q.G)), Math.Max(Math.Abs(p.B - q.B), Math.Abs(p.A - q.A))) <= tolerance;
        var origin = At(start);
        // The last index of the run of `color` from `i` (exclusive) in direction `step`, at most `limit` pixels on.
        int RunEnd(int i, int step, Pixel color, int limit = int.MaxValue)
        {
            int j = i, n = 0;
            while (j + step >= 0 && j + step < count && n < limit && Same(At(j + step), color)) { j += step; n++; }
            return j;
        }
        // Past the edge at `edge`: the end of the next color's run, when that run is a border (short enough).
        int BorderEnd(int edge, int step)
        {
            int first = edge + step;
            if (first < 0 || first >= count) return edge;
            int end = RunEnd(first, step, At(first), MaxBorder);
            // Longer than a border: it's the background around the element.
            return Math.Abs(end - first) + 1 > MaxBorder ? edge : end;
        }
        int lo = RunEnd(start, -1, origin);
        int hi = RunEnd(start, 1, origin);
        if (outer)
        {
            lo = BorderEnd(lo, -1);
            hi = BorderEnd(hi, 1);
        }
        return new PixelSpan(lo, hi);
    }
}
