using Skreener.Core.Colors;
using Skreener.Core.Geometry;

namespace Skreener.Core.Imaging;

/// <summary>The raw bytes of a pixel (0 to 255 each, premultiplied by alpha), for quick comparisons.</summary>
public readonly record struct Pixel(int R, int G, int B, int A);

/// <summary>
/// A screenshot's pixels as 8-bit sRGB RGBA, row 0 at the top, read once so the editor can look at single pixels as
/// the pointer moves (the color picker, the ruler) or at an area (average color, contrast). Ported from PixelBuffer.swift;
/// the Swift one is built from a CGImage, this one from bytes the caller has already converted (Windows captures come as
/// BGRA, so swap the channels first). Treat the array as read-only after handing it over.
/// </summary>
public sealed class PixelBuffer
{
    public int Width { get; }
    public int Height { get; }
    private readonly byte[] _data;
    private readonly int _stride;

    /// <param name="width">Pixels per row.</param>
    /// <param name="height">Rows.</param>
    /// <param name="data">Premultiplied RGBA, four bytes per pixel, rows top to bottom.</param>
    /// <param name="stride">Bytes from one row to the next; 0 means <c>width * 4</c> (no padding).</param>
    public PixelBuffer(int width, int height, byte[] data, int stride = 0)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width), "An image has at least one pixel.");
        if (stride == 0) stride = width * 4;
        if (stride < width * 4) throw new ArgumentOutOfRangeException(nameof(stride));
        if (data.Length < (height - 1) * stride + width * 4) throw new ArgumentException("Not enough bytes for the image.", nameof(data));
        Width = width;
        Height = height;
        _data = data;
        _stride = stride;
    }

    public bool Contains(int x, int y) => x >= 0 && y >= 0 && x < Width && y < Height;

    /// <summary>The raw (premultiplied) bytes of a pixel, for quick comparisons.</summary>
    public Pixel Rgba(int x, int y)
    {
        int i = y * _stride + x * 4;
        return new Pixel(_data[i], _data[i + 1], _data[i + 2], _data[i + 3]);
    }

    /// <summary>The color of one pixel (top-left origin), or null outside the image.</summary>
    public RgbColor? Color(int x, int y)
    {
        if (!Contains(x, y)) return null;
        var p = Rgba(x, y);
        return Unpremultiplied(p.R, p.G, p.B, p.A);
    }

    /// <summary>
    /// The darkest pixel (lowest luminance) within <paramref name="radius"/> pixels of (x, y) each way, e.g. the text color
    /// under the pointer even when it sits between two strokes.
    /// </summary>
    public RgbColor? Darkest(int x, int y, int radius = 10)
    {
        if (!Contains(x, y) || radius < 0) return null;
        RgbColor? best = null;
        double bestLum = double.PositiveInfinity;
        for (int yy = Math.Max(y - radius, 0); yy <= Math.Min(y + radius, Height - 1); yy++)
        {
            for (int xx = Math.Max(x - radius, 0); xx <= Math.Min(x + radius, Width - 1); xx++)
            {
                var c = Color(xx, yy);
                if (c is not { } color || !(color.A > 0)) continue;
                double lum = color.Luminance;
                if (lum < bestLum) { bestLum = lum; best = color; }
            }
        }
        return best;
    }

    /// <summary>The pixel rect (top-left origin) clipped to the image; null when nothing is left.</summary>
    private (int X0, int Y0, int X1, int Y1)? Clipped(RectD rect)
    {
        var r = rect.Integral.Intersection(new RectD(0, 0, Width, Height));
        if (r.IsNull || !(r.Width >= 1) || !(r.Height >= 1)) return null;
        return ((int)r.MinX, (int)r.MinY, (int)r.MaxX, (int)r.MaxY);
    }

    /// <summary>The mean of the sRGB values in <paramref name="rect"/> (pixels, top-left origin): half black, half white gives #808080.</summary>
    public RgbColor? Average(RectD rect)
    {
        if (Clipped(rect) is not { } c) return null;
        long r = 0, g = 0, b = 0, a = 0;
        for (int y = c.Y0; y < c.Y1; y++)
        {
            for (int x = c.X0; x < c.X1; x++)
            {
                var p = Rgba(x, y);
                r += p.R; g += p.G; b += p.B; a += p.A;
            }
        }
        return Unpremultiplied(r, g, b, a, (c.X1 - c.X0) * (c.Y1 - c.Y0));
    }

    private sealed class Group
    {
        public int Count;
        public long R, G, B, A;
    }

    /// <summary>
    /// The two colors that make up <paramref name="rect"/> (pixels, top-left origin): the most common one, taken as the
    /// background, and the one that stands out most against it among the others that cover a fair share of the area
    /// (text, an icon). Colors are grouped at 4 bits per channel, so anti-aliasing counts as its color; each is the mean
    /// of its group. With a single color, both are that color. Equally common groups are ordered by first appearance
    /// (the Swift version leaves that to dictionary order).
    /// </summary>
    public (RgbColor Background, RgbColor Foreground)? DominantColors(RectD rect)
    {
        if (Clipped(rect) is not { } c) return null;
        var groups = new Dictionary<int, Group>();
        for (int y = c.Y0; y < c.Y1; y++)
        {
            for (int x = c.X0; x < c.X1; x++)
            {
                var p = Rgba(x, y);
                int key = ((p.R >> 4) << 8) | ((p.G >> 4) << 4) | (p.B >> 4);
                if (!groups.TryGetValue(key, out var s)) groups[key] = s = new Group();
                s.Count++; s.R += p.R; s.G += p.G; s.B += p.B; s.A += p.A;
            }
        }
        int total = (c.X1 - c.X0) * (c.Y1 - c.Y0);
        var colors = groups.Values.OrderByDescending(s => s.Count)
            .Select(s => (s.Count, Color: Unpremultiplied(s.R, s.G, s.B, s.A, s.Count))).ToList();
        if (colors.Count == 0) return null;
        var bg = colors[0];
        // Thin text covers only a few percent of a box around it.
        int minShare = Math.Max(1, total / 200);
        RgbColor? fg = null;
        double fgContrast = 0;
        foreach (var candidate in colors.Skip(1).Where(k => k.Count >= minShare))
        {
            double contrast = Contrast.Wcag(candidate.Color, bg.Color);
            // The first of equally contrasting colors wins, like Swift's max(by:).
            if (fg is null || fgContrast < contrast) { fg = candidate.Color; fgContrast = contrast; }
        }
        return (bg.Color, fg ?? bg.Color);
    }

    /// <summary>Sums of the premultiplied channels of <paramref name="count"/> pixels, as their mean straight-alpha color.</summary>
    internal static RgbColor Unpremultiplied(double r, double g, double b, double a, int count = 1)
    {
        if (!(a > 0) || count <= 0) return new RgbColor(0, 0, 0, 0);
        // Dividing by the alpha sum undoes the premultiplication and the averaging at once.
        return new RgbColor(Math.Min(r / a, 1), Math.Min(g / a, 1), Math.Min(b / a, 1), a / 255 / count);
    }
}
