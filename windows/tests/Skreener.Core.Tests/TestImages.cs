using Skreener.Core.Imaging;

namespace Skreener.Core.Tests;

/// <summary>
/// Images made in code for the tests. Unlike TestImages.swift, which draws with AppKit in bottom-left coordinates, this
/// paints opaque rects straight into top-left pixel coordinates, so the y values of the Swift drawing code are flipped
/// here (height - y - rectHeight).
/// </summary>
public sealed class Canvas
{
    public int Width { get; }
    public int Height { get; }
    private readonly byte[] _bytes;

    /// <summary>An opaque canvas filled with <paramref name="fill"/>.</summary>
    public Canvas(int width, int height, (int R, int G, int B) fill)
    {
        Width = width;
        Height = height;
        _bytes = new byte[width * height * 4];
        Fill(0, 0, width, height, fill);
    }

    /// <summary>Paints the pixels from (x, y), top-left origin, <paramref name="w"/> x <paramref name="h"/> in <paramref name="color"/>.</summary>
    public Canvas Fill(int x, int y, int w, int h, (int R, int G, int B) color)
    {
        for (int yy = y; yy < y + h; yy++)
        {
            for (int xx = x; xx < x + w; xx++)
            {
                int i = (yy * Width + xx) * 4;
                _bytes[i] = (byte)color.R; _bytes[i + 1] = (byte)color.G; _bytes[i + 2] = (byte)color.B; _bytes[i + 3] = 255;
            }
        }
        return this;
    }

    public PixelBuffer ToBuffer() => new(Width, Height, _bytes);

    /// <summary>A <paramref name="width"/> x <paramref name="height"/> image whose pixel (x, y), top-left origin, is <c>color(x, y)</c> as 0 to 255 RGB.</summary>
    public static PixelBuffer Image(int width, int height, Func<int, int, (int R, int G, int B)> color)
    {
        var c = new Canvas(width, height, (255, 255, 255));
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) c.Fill(x, y, 1, 1, color(x, y));
        return c.ToBuffer();
    }

    public static readonly (int, int, int) White = (255, 255, 255);
    public static readonly (int, int, int) Black = (0, 0, 0);
    public static readonly (int, int, int) Red = (255, 0, 0);
    /// <summary>NSColor.systemBlue (light appearance).</summary>
    public static readonly (int, int, int) SystemBlue = (0, 122, 255);
    /// <summary>NSColor.systemOrange (light appearance).</summary>
    public static readonly (int, int, int) SystemOrange = (255, 149, 0);
}
