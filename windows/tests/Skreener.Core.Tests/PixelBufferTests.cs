using Skreener.Core.Colors;
using Skreener.Core.Geometry;
using Skreener.Core.Imaging;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>Pixel colors (#108) and the dominant colors behind the contrast checker (#109), from ColorToolsTests.swift.</summary>
public class PixelBufferTests
{
    private static string Hex(RgbColor? c) => ColorFormat.Hex.Format(c!.Value);

    [Fact]
    public void PixelColorIsReadTopLeft()
    {
        var buf = Canvas.Image(4, 4, (x, y) => x == 1 && y == 0 ? (255, 0, 0) : (255, 255, 255));
        Assert.Equal("#FF0000", Hex(buf.Color(1, 0)));
        Assert.Equal("#FFFFFF", Hex(buf.Color(1, 3)));
        Assert.Null(buf.Color(4, 0));
        Assert.Null(buf.Color(-1, 0));
    }

    [Fact]
    public void DarkestNearbyFindsTheTextColor()
    {
        // White, with a 1-px dark gray stroke 5 px to the right of the pointer.
        var buf = Canvas.Image(40, 40, (x, _) => x == 25 ? (30, 30, 30) : (255, 255, 255));
        Assert.Equal("#1E1E1E", Hex(buf.Darkest(20, 20)));
        // Out of reach: just white.
        Assert.Equal("#FFFFFF", Hex(buf.Darkest(5, 20, radius: 10)));
        Assert.Null(buf.Darkest(50, 20));
    }

    [Fact]
    public void AverageOfHalfBlackHalfWhiteIsMidGray()
    {
        var buf = Canvas.Image(10, 10, (x, _) => x < 5 ? (0, 0, 0) : (255, 255, 255));
        Assert.Equal("#808080", Hex(buf.Average(new RectD(0, 0, 10, 10))));
        // Clipped to the image.
        Assert.Equal("#FFFFFF", Hex(buf.Average(new RectD(5, -5, 20, 20))));
        Assert.Null(buf.Average(new RectD(20, 20, 5, 5)));
    }

    [Fact]
    public void DominantColorsOfTextOnABackground()
    {
        // White with 10 % of the pixels a dark blue "text" and a few stray red pixels.
        var buf = Canvas.Image(100, 20, (x, y) =>
        {
            if (x % 10 == 0) return (20, 30, 120);
            if (x == 55 && y == 5) return (255, 0, 0);
            return (255, 255, 255);
        });
        var found = buf.DominantColors(new RectD(0, 0, 100, 20))!.Value;
        Assert.Equal("#FFFFFF", Hex(found.Background));
        Assert.Equal("#141E78", Hex(found.Foreground));
    }

    [Fact]
    public void DominantColorsOfOneColor()
    {
        var buf = Canvas.Image(10, 10, (_, _) => (10, 200, 10));
        var found = buf.DominantColors(new RectD(0, 0, 10, 10))!.Value;
        Assert.Equal(found.Background, found.Foreground);
        Assert.Null(buf.DominantColors(new RectD(50, 50, 10, 10)));
    }

    [Fact]
    public void RowPaddingIsSkipped()
    {
        // No Swift counterpart: a stride wider than the row (as Windows bitmaps often have) reads the same pixels.
        var bytes = new byte[2 * 12];
        for (int i = 0; i < bytes.Length; i++) bytes[i] = 99;
        bytes[0] = 1; bytes[1] = 2; bytes[2] = 3; bytes[3] = 255;
        bytes[12] = 4; bytes[13] = 5; bytes[14] = 6; bytes[15] = 255;
        var buf = new PixelBuffer(2, 2, bytes, stride: 12);
        Assert.Equal(new Pixel(4, 5, 6, 255), buf.Rgba(0, 1));
    }
}
