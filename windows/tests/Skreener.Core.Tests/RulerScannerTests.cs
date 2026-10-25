using Skreener.Core.Imaging;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>The editor's pixel ruler (#107), from ColorToolsTests.swift.</summary>
public class RulerScannerTests
{
    /// <summary>
    /// 220 x 100 white, with a blue box from x 40 to 139 and y 20 to 69 (100 x 50 px) that has a 2-px black border, and a
    /// second blue box 40 px to its right.
    /// </summary>
    private static PixelBuffer Boxes() => Canvas.Image(220, 100, (x, y) =>
    {
        if (x is >= 180 and < 200 && y is >= 20 and < 70) return (0, 0, 255);
        if (!(x is >= 40 and < 140 && y is >= 20 and < 70)) return (255, 255, 255);
        if (x < 42 || x >= 138 || y < 22 || y >= 68) return (0, 0, 0);
        return (0, 0, 255);
    });

    [Fact]
    public void RulerMeasuresTheInsideOfABox()
    {
        var buf = Boxes();
        Assert.Equal(new PixelSpan(42, 137), RulerScanner.Span(buf, 90, 45, RulerScanner.Axis.Horizontal));   // 96 px inside the border
        Assert.Equal(new PixelSpan(22, 67), RulerScanner.Span(buf, 90, 45, RulerScanner.Axis.Vertical));      // 46 px
    }

    [Fact]
    public void RulerWithShiftIncludesTheBorder()
    {
        var buf = Boxes();
        Assert.Equal(new PixelSpan(40, 139), RulerScanner.Span(buf, 90, 45, RulerScanner.Axis.Horizontal, outer: true));   // 100 px
        Assert.Equal(new PixelSpan(20, 69), RulerScanner.Span(buf, 90, 45, RulerScanner.Axis.Vertical, outer: true));      // 50 px
    }

    [Fact]
    public void RulerOuterIgnoresTheBackgroundAroundABorderlessBox()
    {
        // The right box has no border: past its edge is the white background, far wider than a border.
        Assert.Equal(new PixelSpan(180, 199), RulerScanner.Span(Boxes(), 190, 45, RulerScanner.Axis.Horizontal, outer: true));
    }

    [Fact]
    public void RulerMeasuresTheGapBetweenBoxes()
    {
        Assert.Equal(new PixelSpan(140, 179), RulerScanner.Span(Boxes(), 160, 45, RulerScanner.Axis.Horizontal));   // 40 px
    }

    [Fact]
    public void RulerRunsToTheImageEdge()
    {
        var buf = Boxes();
        Assert.Equal(new PixelSpan(0, 219), RulerScanner.Span(buf, 5, 5, RulerScanner.Axis.Horizontal));
        Assert.Null(RulerScanner.Span(buf, 220, 5, RulerScanner.Axis.Horizontal));
    }

    [Fact]
    public void RulerToleratesSlightNoise()
    {
        // Alternating 250/255 is one color within the default tolerance, not within 2.
        var buf = Canvas.Image(30, 1, (x, _) => x % 2 == 0 ? (255, 255, 255) : (250, 250, 250));
        Assert.Equal(new PixelSpan(0, 29), RulerScanner.Span(buf, 10, 0, RulerScanner.Axis.Horizontal));
        Assert.Equal(new PixelSpan(10, 10), RulerScanner.Span(buf, 10, 0, RulerScanner.Axis.Horizontal, tolerance: 2));
    }
}
