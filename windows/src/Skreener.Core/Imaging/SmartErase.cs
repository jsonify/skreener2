using Skreener.Core.Colors;
using Skreener.Core.Geometry;

namespace Skreener.Core.Imaging;

/// <summary>Smart Erase: fills a box with the background around it, so the content looks as if it was never there.</summary>
public static class SmartErase
{
    private sealed class Bucket
    {
        public int Count;
        public long R, G, B, A;
    }

    /// <summary>
    /// The most common color in the one-pixel ring just outside <paramref name="rect"/> (pixels, top-left origin),
    /// averaged over the pixels of that color. Colors are grouped at 5 bits per channel, so anti-aliasing and compression
    /// noise still count as the same color. Parts of the ring outside the image are skipped; null when none of it is
    /// inside. Ported from SmartErase.fillColor, which takes a CGImage and returns a CGColor: this reads a
    /// <see cref="PixelBuffer"/> and returns straight-alpha sRGB. Equally common colors resolve to the one that appears
    /// first around the ring (the Swift version leaves that to dictionary order).
    /// </summary>
    public static RgbColor? FillColor(RectD rect, PixelBuffer image)
    {
        var ring = rect.Integral.InsetBy(-1, -1);
        var bounds = new RectD(0, 0, image.Width, image.Height);
        // Top and bottom rows, then the left and right columns between them.
        RectD[] strips =
        {
            new(ring.MinX, ring.MinY, ring.Width, 1),
            new(ring.MinX, ring.MaxY - 1, ring.Width, 1),
            new(ring.MinX, ring.MinY + 1, 1, ring.Height - 2),
            new(ring.MaxX - 1, ring.MinY + 1, 1, ring.Height - 2),
        };
        var buckets = new Dictionary<int, Bucket>();
        foreach (var strip in strips)
        {
            var area = strip.Intersection(bounds);
            if (area.IsEmpty) continue;
            for (int y = (int)area.MinY; y < (int)area.MaxY; y++)
            {
                for (int x = (int)area.MinX; x < (int)area.MaxX; x++)
                {
                    var px = image.Rgba(x, y);
                    int key = ((px.R >> 3) << 15) | ((px.G >> 3) << 10) | ((px.B >> 3) << 5) | (px.A >> 3);
                    if (!buckets.TryGetValue(key, out var s)) buckets[key] = s = new Bucket();
                    s.Count++; s.R += px.R; s.G += px.G; s.B += px.B; s.A += px.A;
                }
            }
        }
        Bucket? best = null;
        foreach (var s in buckets.Values) if (best is null || best.Count < s.Count) best = s;
        if (best is null) return null;
        double n = best.Count;
        double alpha = best.A / n / 255;
        // The samples are premultiplied.
        double Channel(long sum) => alpha > 0 ? Math.Min(sum / n / 255 / alpha, 1) : 0;
        return new RgbColor(Channel(best.R), Channel(best.G), Channel(best.B), alpha);
    }
}
