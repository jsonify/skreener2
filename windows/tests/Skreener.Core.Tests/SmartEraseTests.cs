using Skreener.Core.Colors;
using Skreener.Core.Geometry;
using Skreener.Core.Imaging;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>Smart Erase's fill: the background color around a box.</summary>
public class SmartEraseTests
{
    /// <summary>100 x 100 px: white, with a black square from (30, 30) to (70, 70) (top-left origin) and a red dot in it.</summary>
    private static PixelBuffer Image() =>
        new Canvas(100, 100, Canvas.White)
            .Fill(30, 30, 40, 40, Canvas.Black)
            // Drawn at y 45 bottom-left in Swift, which is 100 - 45 - 4 = 51 from the top.
            .Fill(45, 51, 4, 4, Canvas.Red)
            .ToBuffer();

    private static void AssertColor(RgbColor? c, double[] expected)
    {
        Assert.NotNull(c);
        double[] got = { c!.Value.R, c.Value.G, c.Value.B, c.Value.A };
        for (int i = 0; i < 4; i++) Assert.Equal(expected[i], got[i], 0.03);
    }

    [Fact]
    public void BoxOnTheBlackSquareTakesBlack()
    {
        // Around the red dot, inside the black square.
        AssertColor(SmartErase.FillColor(new RectD(40, 40, 15, 15), Image()), new double[] { 0, 0, 0, 1 });
    }

    [Fact]
    public void BoxCoveringTheSquareTakesWhite()
    {
        AssertColor(SmartErase.FillColor(new RectD(20, 20, 60, 60), Image()), new double[] { 1, 1, 1, 1 });
    }

    [Fact]
    public void MostCommonColorWins()
    {
        // The ring runs mostly over white, partly over the square's edge.
        AssertColor(SmartErase.FillColor(new RectD(10, 10, 30, 30), Image()), new double[] { 1, 1, 1, 1 });
    }

    [Fact]
    public void BoxPastTheEdgeUsesTheRingInsideTheImage()
    {
        AssertColor(SmartErase.FillColor(new RectD(-20, -20, 40, 40), Image()), new double[] { 1, 1, 1, 1 });
    }

    [Fact]
    public void BoxCoveringEverythingHasNoColor()
    {
        Assert.Null(SmartErase.FillColor(new RectD(-5, -5, 110, 110), Image()));
    }
}
