using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>Keyboard and drag math for the area selection (#102, #103). Bottom-left origin, like the overlay's views.</summary>
public class SelectionGeometryTests
{
    private static readonly RectD Bounds = new(0, 0, 1000, 800);
    private static readonly RectD Rect = new(100, 100, 200, 150);

    private static RectD Apply(SelectionGeometry.Key key, bool command = false, bool shift = false, RectD? to = null) =>
        SelectionGeometry.Apply(key, command, shift, to ?? Rect, Bounds);

    [Fact]
    public void KeyMapping()
    {
        Assert.Equal(SelectionGeometry.Key.Left, SelectionGeometry.KeyFor(123));
        Assert.Equal(SelectionGeometry.Key.Right, SelectionGeometry.KeyFor(124));
        Assert.Equal(SelectionGeometry.Key.Down, SelectionGeometry.KeyFor(125));
        Assert.Equal(SelectionGeometry.Key.Up, SelectionGeometry.KeyFor(126));
        Assert.Null(SelectionGeometry.KeyFor(30));   // ] no longer resizes: the scroll wheel does
        Assert.Null(SelectionGeometry.KeyFor(0));
    }

    [Fact]
    public void ArrowsMoveOneOrTenPoints()
    {
        Assert.Equal(Rect.OffsetBy(1, 0), Apply(SelectionGeometry.Key.Right));
        Assert.Equal(Rect.OffsetBy(-10, 0), Apply(SelectionGeometry.Key.Left, shift: true));
        Assert.Equal(Rect.OffsetBy(0, 1), Apply(SelectionGeometry.Key.Up));
        Assert.Equal(Rect.OffsetBy(0, -10), Apply(SelectionGeometry.Key.Down, shift: true));
    }

    [Fact]
    public void MovesStopAtTheScreenEdge()
    {
        var corner = new RectD(0, 0, 50, 50);
        Assert.Equal(corner, Apply(SelectionGeometry.Key.Left, to: corner));
        Assert.Equal(corner, Apply(SelectionGeometry.Key.Down, shift: true, to: corner));
        var topRight = new RectD(945, 745, 50, 50);
        Assert.Equal(new RectD(950, 745, 50, 50), Apply(SelectionGeometry.Key.Right, shift: true, to: topRight));
        Assert.Equal(new RectD(945, 750, 50, 50), Apply(SelectionGeometry.Key.Up, shift: true, to: topRight));
    }

    [Fact]
    public void CommandArrowsResizeTheRightAndBottomEdges()
    {
        Assert.Equal(new RectD(100, 100, 201, 150), Apply(SelectionGeometry.Key.Right, command: true));
        Assert.Equal(new RectD(100, 100, 190, 150), Apply(SelectionGeometry.Key.Left, command: true, shift: true));
        // Down moves the bottom edge down: the top (maxY = 250) stays.
        Assert.Equal(new RectD(100, 99, 200, 151), Apply(SelectionGeometry.Key.Down, command: true));
        Assert.Equal(new RectD(100, 110, 200, 140), Apply(SelectionGeometry.Key.Up, command: true, shift: true));
    }

    [Fact]
    public void CommandArrowsStayOnScreenAndKeepAPoint()
    {
        var edge = new RectD(900, 5, 95, 20);
        Assert.Equal(1000, Apply(SelectionGeometry.Key.Right, command: true, shift: true, to: edge).MaxX);
        Assert.Equal(new RectD(900, 0, 95, 25), Apply(SelectionGeometry.Key.Down, command: true, shift: true, to: edge));
        var tiny = new RectD(10, 10, 3, 3);
        Assert.Equal(SelectionGeometry.MinSide, Apply(SelectionGeometry.Key.Left, command: true, shift: true, to: tiny).Width);
        Assert.Equal(new RectD(10, 12, 3, 1), Apply(SelectionGeometry.Key.Up, command: true, shift: true, to: tiny));
    }

    [Fact]
    public void ScrollGrowsAndShrinksEverySide()
    {
        Assert.Equal(new RectD(99, 99, 202, 152), SelectionGeometry.ResizeAllSides(Rect, 1, Bounds));
        Assert.Equal(new RectD(90, 90, 220, 170), SelectionGeometry.ResizeAllSides(Rect, 10, Bounds));
        Assert.Equal(new RectD(101, 101, 198, 148), SelectionGeometry.ResizeAllSides(Rect, -1, Bounds));
        Assert.Equal(new RectD(110, 110, 180, 130), SelectionGeometry.ResizeAllSides(Rect, -10, Bounds));
    }

    [Fact]
    public void GrowStopsAtTheScreenAndShrinkKeepsAPoint()
    {
        Assert.Equal(new RectD(0, 0, 62, 50), SelectionGeometry.ResizeAllSides(new RectD(2, 0, 50, 40), 10, Bounds));
        Assert.Equal(Bounds, SelectionGeometry.ResizeAllSides(Bounds, 1, Bounds));
        var small = new RectD(10, 10, 5, 1);
        Assert.Equal(new RectD(12, 10, 1, 1), SelectionGeometry.ResizeAllSides(small, -10, Bounds));
    }

    [Fact]
    public void RoundingKeepsTheSizeOfAFractionalPosition()
    {
        // `Integral` would make this 201 x 151; dragging repeated that on every move and grew the selection.
        var r = new RectD(100.5, 99.5, 200, 150);
        Assert.Equal(r.Size, SelectionGeometry.Rounded(r).Size);
        Assert.Equal(new RectD(10, 21, 31, 40), SelectionGeometry.Rounded(new RectD(10.2, 20.7, 30.6, 40.1)));
    }

    [Fact]
    public void PlainDragSpansStartAndCurrent()
    {
        var r = SelectionGeometry.DragRect(new PointD(300, 300), new PointD(200, 450), square: false, fromCenter: false, Bounds);
        Assert.Equal(new RectD(200, 300, 100, 150), r);
    }

    [Fact]
    public void ShiftDragMakesASquareOnTheLongerSide()
    {
        var r = SelectionGeometry.DragRect(new PointD(300, 300), new PointD(200, 450), square: true, fromCenter: false, Bounds);
        Assert.Equal(new RectD(150, 300, 150, 150), r);
    }

    [Fact]
    public void ShiftDragStaysSquareAtTheScreenEdge()
    {
        // 200 points to the right, but only 50 down to the bottom edge.
        var r = SelectionGeometry.DragRect(new PointD(500, 50), new PointD(700, 0), square: true, fromCenter: false, Bounds);
        Assert.Equal(new RectD(500, 0, 50, 50), r);
    }

    [Fact]
    public void OptionDragGrowsAroundTheStart()
    {
        var r = SelectionGeometry.DragRect(new PointD(500, 400), new PointD(560, 380), square: false, fromCenter: true, Bounds);
        Assert.Equal(new RectD(440, 380, 120, 40), r);
        var sq = SelectionGeometry.DragRect(new PointD(500, 400), new PointD(560, 380), square: true, fromCenter: true, Bounds);
        Assert.Equal(new RectD(440, 340, 120, 120), sq);
    }

    [Fact]
    public void ResizeByHandles()
    {
        // Top-right corner (index 4) to (350, 300).
        Assert.Equal(new RectD(100, 100, 250, 200), SelectionGeometry.Resize(Rect, 4, new PointD(350, 300), Bounds));
        // Left edge (index 7) only moves x, and stops at the screen edge.
        Assert.Equal(new RectD(0, 100, 300, 150), SelectionGeometry.Resize(Rect, 7, new PointD(-40, 700), Bounds));
        // Bottom edge (index 1) dragged above the top flips the rect.
        Assert.Equal(new RectD(100, 250, 200, 50), SelectionGeometry.Resize(Rect, 1, new PointD(0, 300), Bounds));
    }

    [Fact]
    public void MoveStaysOnScreen()
    {
        Assert.Equal(new RectD(800, 0, 200, 150), SelectionGeometry.Move(Rect, new PointD(900, -20), Bounds));
    }
}
