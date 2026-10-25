using Skreener.Core.Geometry;
using Skreener.Core.Imaging;
using Xunit;

namespace Skreener.Core.Tests;

public class ObjectSnapTests
{
    /// <summary>
    /// A white 400 x 300 px image with a blue "button" from (100, 80) to (220, 120), top-left origin, and some darker
    /// "text" inside it.
    /// </summary>
    private static PixelBuffer Button() =>
        new Canvas(400, 300, Canvas.White)
            .Fill(100, 80, 120, 40, Canvas.SystemBlue)
            // Bottom-left origin in Swift: y 195..205 of 300 is 95..105 from the top.
            .Fill(130, 95, 60, 10, Canvas.Black)
            .ToBuffer();

    [Fact]
    public void ABoxDrawnRoughlyAroundAButtonGetsItsExactBounds()
    {
        var found = ObjectSnap.Snap(new RectD(94, 75, 132, 52), Button(), reach: 8);
        Assert.Equal(new RectD(100, 80, 120, 40), found.Rect);
        Assert.Equal(new ObjectSnap.Sides(Left: true, Right: true, Top: true, Bottom: true), found.Sides);
    }

    [Fact]
    public void ABoxDrawnJustInsideSnapsOutToTheEdges()
    {
        var found = ObjectSnap.Snap(new RectD(104, 84, 112, 33), Button(), reach: 8);
        Assert.Equal(new RectD(100, 80, 120, 40), found.Rect);
    }

    [Fact]
    public void NothingNearbyLeavesTheBoxAlone()
    {
        var box = new RectD(250, 150, 100, 100);
        var found = ObjectSnap.Snap(box, Button(), reach: 8);
        Assert.Equal(box, found.Rect);
        Assert.False(found.Sides.Any);
    }

    [Fact]
    public void SimilarObjectsAreFound()
    {
        // Four identical badges in a row, each 40 x 40 px with a mark inside.
        var canvas = new Canvas(400, 100, Canvas.White);
        for (int i = 0; i < 4; i++)
        {
            int x = 20 + i * 90;
            // Bottom-left y 30..70 and 40..60 of 100 are the same from the top.
            canvas.Fill(x, 30, 40, 40, Canvas.SystemOrange).Fill(x + 10, 40, 12, 20, Canvas.Black);
        }
        var buf = canvas.ToBuffer();
        // The first badge, top-left origin.
        var found = ObjectSnap.SimilarNow(new RectD(20, 30, 40, 40), buf);
        Assert.Equal(new HashSet<int> { 110, 200, 290 }, found.Select(r => (int)r.MinX).ToHashSet());
        Assert.All(found, r => { Assert.Equal(30, r.MinY); Assert.Equal(40, r.Width); Assert.Equal(40, r.Height); });
    }

    [Fact]
    public void AFlatBoxMatchesNothing()
    {
        var found = ObjectSnap.SimilarNow(new RectD(300, 200, 40, 40), Button());
        Assert.Empty(found);
    }
}
