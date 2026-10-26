using Skreener.Core.Colors;
using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Skreener.Core.Imaging;
using Xunit;

namespace Skreener.Core.Tests.Editor;

/// <summary>Hit testing, handles, the arrow's shape and the pixelate mosaic.</summary>
public class AnnotationGeometryTests
{
    private static PointD P(double x, double y) => new(x, y);

    private static Annotation Make(AnnotationKind kind, PointD start, PointD end, double width = 4, params PointD[] points) =>
        new(1, kind, start, end, points, AnnotationStyle.Default with { LineWidth = width });

    [Fact]
    public void ARectangleIsHitNearItsEdgesOnly()
    {
        var r = Make(AnnotationKind.Rectangle, P(0, 0), P(100, 50));
        Assert.True(AnnotationGeometry.Hits(r, P(50, 0), 5));
        Assert.True(AnnotationGeometry.Hits(r, P(50, 56), 5)); // 6 px below the edge: half the 4 px line + 5 slop reach 7
        Assert.True(AnnotationGeometry.Hits(r, P(102, 25), 5));
        Assert.False(AnnotationGeometry.Hits(r, P(50, 25), 5));
        Assert.False(AnnotationGeometry.Hits(r, P(50, 60), 5));
    }

    [Fact]
    public void AnEllipseIsHitOnItsCurveNotOnTheBoxCorner()
    {
        var e = Make(AnnotationKind.Ellipse, P(0, 0), P(100, 100));
        Assert.True(AnnotationGeometry.Hits(e, P(50, 1), 5));
        Assert.True(AnnotationGeometry.Hits(e, P(99, 50), 5));
        Assert.False(AnnotationGeometry.Hits(e, P(2, 2), 5));
        Assert.False(AnnotationGeometry.Hits(e, P(50, 50), 5));
    }

    [Fact]
    public void ALineIsHitAlongItsLengthButNotPastItsEnds()
    {
        var l = Make(AnnotationKind.Line, P(0, 0), P(100, 0));
        Assert.True(AnnotationGeometry.Hits(l, P(30, 6), 5));
        Assert.False(AnnotationGeometry.Hits(l, P(30, 8), 5));
        Assert.False(AnnotationGeometry.Hits(l, P(110, 0), 5));
    }

    [Fact]
    public void AnArrowIsHitAcrossItsHead()
    {
        var a = Make(AnnotationKind.Arrow, P(0, 0), P(100, 0));
        // The head of a 4 px arrow is 20 px long and about 8.7 px to each side.
        Assert.True(AnnotationGeometry.Hits(a, P(95, 12), 5));
        Assert.False(AnnotationGeometry.Hits(Make(AnnotationKind.Line, P(0, 0), P(100, 0)), P(95, 12), 5));
    }

    [Fact]
    public void APenStrokeIsHitAlongEverySegment()
    {
        var pen = Make(AnnotationKind.Pen, P(0, 0), P(20, 20), 4, P(0, 0), P(20, 0), P(20, 20));
        Assert.True(AnnotationGeometry.Hits(pen, P(10, 1), 2));
        Assert.True(AnnotationGeometry.Hits(pen, P(21, 10), 2));
        Assert.False(AnnotationGeometry.Hits(pen, P(5, 15), 2));
        Assert.Equal(new RectD(0, 0, 20, 20), pen.Bounds);
    }

    [Fact]
    public void BoxHandlesAreTheCornersAndOppositeIsThreeMinus()
    {
        var r = Make(AnnotationKind.Pixelate, P(50, 40), P(10, 0)); // drawn up and to the left
        var h = AnnotationGeometry.Handles(r);
        Assert.Equal(new[] { P(10, 0), P(50, 0), P(10, 40), P(50, 40) }, h);
        var resized = AnnotationGeometry.Resized(r, 1, P(70, -10)); // top-right; bottom-left stays
        Assert.Equal(new RectD(10, -10, 60, 50), resized.Rect);
    }

    [Fact]
    public void LinesHaveTwoEndHandlesAndPenNone()
    {
        Assert.Equal(2, AnnotationGeometry.Handles(Make(AnnotationKind.Arrow, P(0, 0), P(9, 9))).Count);
        Assert.Empty(AnnotationGeometry.Handles(Make(AnnotationKind.Pen, P(0, 0), P(9, 9), 4, P(0, 0), P(9, 9))));
    }

    [Fact]
    public void TheNearestHandleWinsOnASmallBox()
    {
        var r = Make(AnnotationKind.Rectangle, P(0, 0), P(6, 6));
        Assert.Equal(3, AnnotationGeometry.HandleAt(r, P(5, 5), 8));
        Assert.Equal(0, AnnotationGeometry.HandleAt(r, P(1, 1), 8));
        Assert.Null(AnnotationGeometry.HandleAt(r, P(30, 30), 8));
    }

    [Fact]
    public void TheArrowHeadPointsAtTheTipAndHidesTheShaftEnd()
    {
        var shape = AnnotationGeometry.ArrowShape(P(0, 0), P(100, 0), 4)!.Value;
        Assert.Equal(P(100, 0), shape.Head[0]);
        // Head 20 px long at ±π/7: its back corners sit about 18 px behind the tip.
        Assert.Equal(100 - 20 * Math.Cos(Math.PI / 7), shape.Head[1].X, 6);
        Assert.Equal(20 * Math.Sin(Math.PI / 7), shape.Head[1].Y, 6);
        Assert.Equal(-shape.Head[1].Y, shape.Head[2].Y, 6);
        Assert.Equal(88, shape.ShaftEnd.X, 6);
        Assert.Null(AnnotationGeometry.ArrowShape(P(0, 0), P(1, 1), 4));
    }

    [Fact]
    public void TheHeadGrowsWithThickLines()
    {
        Assert.Equal(12, AnnotationGeometry.HeadSize(1));
        Assert.Equal(40, AnnotationGeometry.HeadSize(8));
    }

    [Fact]
    public void PixelateAveragesEachBlockOnAGridFromTheOrigin()
    {
        // 4 x 2: left half black, right half white; blocks of 2 keep them apart, blocks of 4 average them.
        var pixels = new byte[4 * 2 * 4];
        for (int y = 0; y < 2; y++)
            for (int x = 2; x < 4; x++)
                for (int c = 0; c < 4; c++) pixels[(y * 4 + x) * 4 + c] = 255;
        for (int y = 0; y < 2; y++)
            for (int x = 0; x < 2; x++) pixels[(y * 4 + x) * 4 + 3] = 255;

        var two = Pixelate.Apply(pixels, 4, 2, 2);
        Assert.Equal(pixels, two);

        var four = Pixelate.Apply(pixels, 4, 2, 4);
        for (int i = 0; i < four.Length; i += 4)
        {
            Assert.Equal(128, four[i]);
            Assert.Equal(255, four[i + 3]);
        }
    }

    [Fact]
    public void PixelateHandlesPartialBlocksAtTheEdges()
    {
        var buffer = new Canvas(5, 1, (0, 0, 0)).Fill(4, 0, 1, 1, (200, 200, 200));
        var bytes = RgbaBytes(buffer.ToBuffer(), 5, 1);
        var result = Pixelate.Apply(bytes, 5, 1, 4);
        Assert.Equal(0, result[0]);
        Assert.Equal(200, result[4 * 4]); // the last column is a block of its own
    }

    [Fact]
    public void DraftsNeedARealDrag()
    {
        Assert.False(Make(AnnotationKind.Rectangle, P(0, 0), P(10, 1)).IsDrawable);
        Assert.True(Make(AnnotationKind.Rectangle, P(0, 0), P(10, 3)).IsDrawable);
        Assert.False(Make(AnnotationKind.Line, P(0, 0), P(1, 1)).IsDrawable);
        Assert.False(Make(AnnotationKind.Pen, P(0, 0), P(0, 0), 4, P(0, 0)).IsDrawable);
    }

    [Fact]
    public void TextAndCountersAreAlwaysDrawable()
    {
        Assert.True(Make(AnnotationKind.Text, P(0, 0), P(0, 0)).IsDrawable);
        Assert.True(Make(AnnotationKind.Counter, P(5, 5), P(5, 5)).IsDrawable);
        Assert.False(Make(AnnotationKind.Highlighter, P(0, 0), P(0, 0), 4, P(0, 0)).IsDrawable);
    }

    [Theory]
    [InlineData(AnnotationKind.FilledRectangle)]
    [InlineData(AnnotationKind.Blur)]
    [InlineData(AnnotationKind.Text)]
    public void SolidKindsAreHitAnywhereInside(AnnotationKind kind)
    {
        var a = Make(kind, P(0, 0), P(100, 50));
        Assert.True(AnnotationGeometry.Hits(a, P(50, 25), 5));
        Assert.True(AnnotationGeometry.Hits(a, P(103, 25), 5)); // within the slop
        Assert.False(AnnotationGeometry.Hits(a, P(110, 25), 5));
        Assert.Equal(0, AnnotationGeometry.InkOutset(a));
    }

    [Fact]
    public void ACounterIsACircleAroundItsCenterSizedByTheFont()
    {
        var c = new Annotation(1, AnnotationKind.Counter, P(50, 50), P(50, 50), Array.Empty<PointD>(),
            AnnotationStyle.Default with { FontSize = 20 });
        Assert.Equal(15, c.Style.CounterRadius);
        Assert.Equal(new RectD(35, 35, 30, 30), c.Bounds);
        Assert.True(AnnotationGeometry.Hits(c, P(60, 60), 0));
        Assert.False(AnnotationGeometry.Hits(c, P(70, 50), 2));
        Assert.Empty(AnnotationGeometry.Handles(c));
        // Small fonts keep a counter big enough to read.
        Assert.Equal(10, (AnnotationStyle.Default with { FontSize = 8 }).CounterRadius);
    }

    [Fact]
    public void TheHighlighterIsHitAcrossItsWideStroke()
    {
        var h = Make(AnnotationKind.Highlighter, P(0, 0), P(100, 0), 4, P(0, 0), P(100, 0));
        Assert.Equal(20, h.Style.HighlighterWidth); // max(12, 4 x 5)
        Assert.True(AnnotationGeometry.Hits(h, P(50, 14), 5)); // 10 + 5 reach
        Assert.False(AnnotationGeometry.Hits(h, P(50, 16), 5));
        Assert.Equal(new RectD(0, 0, 100, 0), h.Bounds);
        Assert.Equal(10, AnnotationGeometry.InkOutset(h));
        Assert.Empty(AnnotationGeometry.Handles(h));
        Assert.Equal(12, (AnnotationStyle.Default with { LineWidth = 1 }).HighlighterWidth);
    }

    [Fact]
    public void CounterNumbersFollowIdsAmongCountersOnly()
    {
        Annotation C(int id) => new(id, AnnotationKind.Counter, P(id, id), P(id, id), Array.Empty<PointD>(), AnnotationStyle.Default);
        var items = new[] { C(5), Make(AnnotationKind.Rectangle, P(0, 0), P(9, 9)) with { Id = 2 }, C(3), C(9) };
        Assert.Equal(2, AnnotationGeometry.CounterNumber(items, items[0]));
        Assert.Equal(1, AnnotationGeometry.CounterNumber(items, items[2]));
        Assert.Equal(3, AnnotationGeometry.CounterNumber(items, items[3]));
        Assert.Equal(0, AnnotationGeometry.CounterNumber(items, items[1]));
    }

    [Fact]
    public void LightCountersGetDarkNumbers()
    {
        Assert.True(AnnotationGeometry.CounterUsesDarkText(RgbColor.FromBytes(255, 255, 255)));
        Assert.False(AnnotationGeometry.CounterUsesDarkText(RgbColor.FromBytes(255, 204, 0))); // saturated yellow: white
        Assert.False(AnnotationGeometry.CounterUsesDarkText(RgbColor.FromBytes(255, 59, 48)));
        Assert.False(AnnotationGeometry.CounterUsesDarkText(RgbColor.FromBytes(0, 0, 0)));
    }

    [Fact]
    public void TheTextEstimateCountsTheLongestLineAndEveryLine()
    {
        var style = AnnotationStyle.Default with { FontSize = 10 };
        Assert.Equal(new SizeD(18, 25), AnnotationGeometry.EstimateTextSize("abc\nde", style));
        Assert.Equal(new SizeD(5, 12.5), AnnotationGeometry.EstimateTextSize("", style));
    }

    private static byte[] RgbaBytes(PixelBuffer buffer, int width, int height)
    {
        var bytes = new byte[width * height * 4];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                RgbColor c = buffer.Color(x, y)!.Value;
                var i = (y * width + x) * 4;
                bytes[i] = (byte)RgbColor.Byte(c.R);
                bytes[i + 1] = (byte)RgbColor.Byte(c.G);
                bytes[i + 2] = (byte)RgbColor.Byte(c.B);
                bytes[i + 3] = (byte)RgbColor.Byte(c.A);
            }
        }
        return bytes;
    }
}
