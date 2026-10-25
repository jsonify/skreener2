using Skreener.App.Overlay;
using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests.Overlay;

/// <summary>
/// The overlay's adapter (<see cref="ScreenSelection"/>, top-left screen pixels) over Core's y-up
/// <see cref="SelectionGeometry"/>. Each operation is compared, over a grid of inputs, with the top-left implementation
/// the overlay used before (<see cref="TopLeftSelection"/>): on screen nothing may change, except the one case documented
/// in <see cref="ShiftSquareWithNoVerticalMovementGrowsUpLikeTheMac"/>.
/// </summary>
public class ScreenSelectionTests
{
    private const ushort VkLeft = 0x25, VkUp = 0x26, VkRight = 0x27, VkDown = 0x28;

    // The overlay's bounds are its client area at (0, 0); an offset one checks the mirror axis is taken from the bounds.
    public static TheoryData<double, double, double, double> AllBounds => new()
    {
        { 0, 0, 1000, 800 },
        { -300, 120, 640, 481 },
    };

    private static RectD ToCore(SelRect r) => new(r.X, r.Y, r.Width, r.Height);

    private static void Same(SelRect expected, RectD actual)
    {
        Assert.Equal(expected.MinX, actual.MinX);
        Assert.Equal(expected.MinY, actual.MinY);
        Assert.Equal(expected.Width, actual.Width);
        Assert.Equal(expected.Height, actual.Height);
    }

    /// <summary>Rects inside the bounds: middle, touching each edge, thin, and the whole bounds.</summary>
    private static IEnumerable<SelRect> Rects(SelRect b)
    {
        yield return new(b.X + 100, b.Y + 100, 200, 150);
        yield return new(b.X, b.Y, 50, 40);
        yield return new(b.MaxX - 50, b.MaxY - 40, 50, 40);
        yield return new(b.X + 3, b.MaxY - 1, 1, 1);
        yield return new(b.X + 10.5, b.Y + 20.5, 30, 7);
        yield return b;
    }

    private static IEnumerable<(double X, double Y)> Points(SelRect b)
    {
        double[] xs = [b.X - 50, b.X, b.X + 1, b.MidX, b.MidX + 0.5, b.MaxX - 1, b.MaxX, b.MaxX + 70];
        double[] ys = [b.Y - 50, b.Y, b.Y + 1, b.MidY, b.MidY + 0.5, b.MaxY - 1, b.MaxY, b.MaxY + 70];
        foreach (var x in xs)
            foreach (var y in ys)
                yield return (x, y);
    }

    [Fact]
    public void ArrowKeysMapToCoreKeys()
    {
        Assert.Equal(SelectionGeometry.Key.Left, ScreenSelection.KeyFor(VkLeft));
        Assert.Equal(SelectionGeometry.Key.Right, ScreenSelection.KeyFor(VkRight));
        // No swap: the mirror turns Core's "up" (more y-up y) into "up" on screen (less screen y).
        Assert.Equal(SelectionGeometry.Key.Up, ScreenSelection.KeyFor(VkUp));
        Assert.Equal(SelectionGeometry.Key.Down, ScreenSelection.KeyFor(VkDown));
        Assert.Null(ScreenSelection.KeyFor(0x20));   // Space
        Assert.Null(ScreenSelection.KeyFor(0x0D));   // Return
    }

    [Fact]
    public void UpMovesTheSelectionUpOnScreen()
    {
        var bounds = new RectD(0, 0, 1000, 800);
        var rect = new RectD(100, 100, 200, 150);
        Assert.Equal(new RectD(100, 99, 200, 150), ScreenSelection.Apply(ScreenSelection.KeyFor(VkUp)!.Value, false, false, rect, bounds));
        Assert.Equal(new RectD(100, 110, 200, 150), ScreenSelection.Apply(ScreenSelection.KeyFor(VkDown)!.Value, false, true, rect, bounds));
        // Ctrl: the top edge stays, the bottom one moves.
        Assert.Equal(new RectD(100, 100, 200, 151), ScreenSelection.Apply(ScreenSelection.KeyFor(VkDown)!.Value, true, false, rect, bounds));
        Assert.Equal(new RectD(100, 100, 200, 149), ScreenSelection.Apply(ScreenSelection.KeyFor(VkUp)!.Value, true, false, rect, bounds));
    }

    [Fact]
    public void HandleIndexesMapScreenOrderToCoreOrder()
    {
        // Screen top-left (0) is Core's top-left (6), screen bottom-left (6) is Core's bottom-left (0), etc.
        int[] expected = [6, 5, 4, 3, 2, 1, 0, 7];
        for (int i = 0; i < 8; i++)
        {
            Assert.Equal(expected[i], ScreenSelection.CoreHandle(i));
            Assert.Equal(i, ScreenSelection.CoreHandle(ScreenSelection.CoreHandle(i)));
        }
    }

    [Fact]
    public void HandlesAreWhereTheyWere()
    {
        var r = new SelRect(10, 20, 300, 200);
        var expected = TopLeftSelection.Handles(r);
        var actual = ScreenSelection.Handles(ToCore(r));
        Assert.Equal(expected.Length, actual.Length);
        for (int i = 0; i < expected.Length; i++) Assert.Equal(new PointD(expected[i].X, expected[i].Y), actual[i]);
    }

    [Theory]
    [MemberData(nameof(AllBounds))]
    public void KeysMatchTheTopLeftImplementation(double bx, double by, double bw, double bh)
    {
        var b = new SelRect(bx, by, bw, bh);
        (RefKey Ref, ushort Vk)[] keys = [(RefKey.Left, VkLeft), (RefKey.Right, VkRight), (RefKey.Up, VkUp), (RefKey.Down, VkDown)];
        foreach (var r in Rects(b))
            foreach (var (refKey, vk) in keys)
                foreach (var control in new[] { false, true })
                    foreach (var shift in new[] { false, true })
                    {
                        Same(TopLeftSelection.Apply(refKey, control, shift, r, b),
                            ScreenSelection.Apply(ScreenSelection.KeyFor(vk)!.Value, control, shift, ToCore(r), ToCore(b)));
                    }
    }

    [Theory]
    [MemberData(nameof(AllBounds))]
    public void WheelMatchesTheTopLeftImplementation(double bx, double by, double bw, double bh)
    {
        var b = new SelRect(bx, by, bw, bh);
        foreach (var r in Rects(b))
            foreach (var pixels in new double[] { -400, -7, -1, 1, 7, 400 })
                Same(TopLeftSelection.ResizeAllSides(r, pixels, b), ScreenSelection.ResizeAllSides(ToCore(r), pixels, ToCore(b)));
    }

    [Fact]
    public void RoundingMatchesTheTopLeftImplementation()
    {
        foreach (var v in new[] { 0.0, 0.4, 0.5, 0.6, 1.5, 2.5, 10.49, 10.51 })
        {
            var r = new SelRect(v, v + 0.5, 20 + v, 30 - v);
            Same(TopLeftSelection.Rounded(r), ScreenSelection.Rounded(ToCore(r)));
        }
    }

    [Theory]
    [MemberData(nameof(AllBounds))]
    public void DragMatchesTheTopLeftImplementation(double bx, double by, double bw, double bh)
    {
        var b = new SelRect(bx, by, bw, bh);
        foreach (var start in Points(b))
        {
            if (!b.Contains(start.X, start.Y)) continue;   // a drag starts on the overlay
            foreach (var current in Points(b))
                foreach (var square in new[] { false, true })
                    foreach (var fromCenter in new[] { false, true })
                    {
                        // The one intended difference, covered below.
                        if (square && !fromCenter && current.Y == start.Y && current.X != start.X) continue;
                        Same(TopLeftSelection.DragRect(start, current, square, fromCenter, b),
                            ScreenSelection.DragRect(new(start.X, start.Y), new(current.X, current.Y), square, fromCenter, ToCore(b)));
                    }
        }
    }

    /// <summary>
    /// Shift-drag exactly along the start row: there is no vertical direction, and Core (like the Mac) takes "no
    /// movement" as positive y-up, so the square grows up on screen. The old top-left code grew it down.
    /// </summary>
    [Fact]
    public void ShiftSquareWithNoVerticalMovementGrowsUpLikeTheMac()
    {
        var bounds = new RectD(0, 0, 1000, 800);
        var square = ScreenSelection.DragRect(new(500, 400), new(560, 400), square: true, fromCenter: false, bounds);
        Assert.Equal(new RectD(500, 340, 60, 60), square);
        var old = TopLeftSelection.DragRect((500, 400), (560, 400), square: true, fromCenter: false, new SelRect(0, 0, 1000, 800));
        Assert.Equal(new SelRect(500, 400, 60, 60), old);
    }

    [Theory]
    [MemberData(nameof(AllBounds))]
    public void HandleDragsMatchTheTopLeftImplementation(double bx, double by, double bw, double bh)
    {
        var b = new SelRect(bx, by, bw, bh);
        foreach (var r in Rects(b))
            for (int handle = 0; handle < 8; handle++)
                foreach (var p in Points(b))
                    Same(TopLeftSelection.Resize(r, handle, p, b), ScreenSelection.Resize(ToCore(r), handle, new(p.X, p.Y), ToCore(b)));
    }

    [Theory]
    [MemberData(nameof(AllBounds))]
    public void MovesMatchTheTopLeftImplementation(double bx, double by, double bw, double bh)
    {
        var b = new SelRect(bx, by, bw, bh);
        foreach (var r in Rects(b))
            foreach (var p in Points(b))
                Same(TopLeftSelection.Move(r, p, b), ScreenSelection.Move(ToCore(r), new(p.X, p.Y), ToCore(b)));
    }

    [Fact]
    public void ContainsIncludesTheFarEdges()
    {
        var r = new RectD(10, 20, 30, 40);
        Assert.True(ScreenSelection.Contains(r, new(40, 60)));
        Assert.True(ScreenSelection.Contains(r, new(10, 20)));
        Assert.False(ScreenSelection.Contains(r, new(40.5, 60)));
    }
}
