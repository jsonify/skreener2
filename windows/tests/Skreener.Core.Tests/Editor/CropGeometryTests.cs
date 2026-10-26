using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests.Editor;

/// <summary>The crop's handles, hit testing and dragging (cropHandles, cropDrag and the crop drags on the Mac).</summary>
public class CropGeometryTests
{
    private static readonly RectD Image = new(0, 0, 400, 300);
    private static PointD P(double x, double y) => new(x, y);

    [Fact]
    public void ThereAreEightHandlesCornersFirst()
    {
        var h = CropGeometry.Handles(new RectD(10, 20, 100, 50));
        Assert.Equal(8, h.Count);
        Assert.Equal((P(10, 20), CropEdges.Left | CropEdges.Top), h[0]);
        Assert.Equal((P(110, 70), CropEdges.Right | CropEdges.Bottom), h[3]);
        Assert.Equal((P(10, 45), CropEdges.Left), h[4]);
        Assert.Equal((P(60, 70), CropEdges.Bottom), h[7]);
    }

    [Fact]
    public void APressPicksAHandleThenASideThenInsideOrOutside()
    {
        var r = new RectD(100, 100, 200, 100);
        Assert.Equal(new CropDrag(CropDragKind.Edges, CropEdges.Right | CropEdges.Bottom), CropGeometry.HitTest(r, P(305, 205), 12, 6));
        Assert.Equal(new CropDrag(CropDragKind.Edges, CropEdges.Top), CropGeometry.HitTest(r, P(200, 108), 12, 6));
        // Along a side, far from its handles.
        Assert.Equal(new CropDrag(CropDragKind.Edges, CropEdges.Left), CropGeometry.HitTest(r, P(104, 125), 12, 6));
        Assert.Equal(new CropDrag(CropDragKind.Move), CropGeometry.HitTest(r, P(150, 130), 12, 6));
        Assert.Equal(new CropDrag(CropDragKind.NewArea), CropGeometry.HitTest(r, P(20, 20), 12, 6));
        // Beside a side but past its end is outside.
        Assert.Equal(new CropDrag(CropDragKind.NewArea), CropGeometry.HitTest(r, P(100, 250), 12, 6));
    }

    [Fact]
    public void AThinCropPicksTheNearerSide()
    {
        var r = new RectD(100, 100, 6, 200); // both sides within the slop of its middle
        Assert.Equal(new CropDrag(CropDragKind.Edges, CropEdges.Right), CropGeometry.HitTest(r, P(105, 150), 1, 6));
        Assert.Equal(new CropDrag(CropDragKind.Edges, CropEdges.Left), CropGeometry.HitTest(r, P(101, 150), 1, 6));
    }

    [Fact]
    public void DraggingACornerMovesTwoSidesAndStaysInTheImage()
    {
        var r = new RectD(100, 100, 200, 100);
        Assert.Equal(new RectD(50, 80, 250, 120), CropGeometry.DragEdges(r, CropEdges.Left | CropEdges.Top, P(50, 80), Image));
        Assert.Equal(new RectD(100, 100, 300, 200), CropGeometry.DragEdges(r, CropEdges.Right | CropEdges.Bottom, P(900, 900), Image));
    }

    [Fact]
    public void ASideStopsShortOfTheOppositeOne()
    {
        var r = new RectD(100, 100, 200, 100);
        Assert.Equal(new RectD(100, 100, CropGeometry.MinSize, 100), CropGeometry.DragEdges(r, CropEdges.Right, P(20, 150), Image));
        Assert.Equal(new RectD(100, 196, 200, CropGeometry.MinSize), CropGeometry.DragEdges(r, CropEdges.Top, P(150, 290), Image));
    }

    [Fact]
    public void MovingStopsAtTheImageEdges()
    {
        var r = new RectD(100, 100, 200, 100);
        Assert.Equal(new RectD(200, 0, 200, 100), CropGeometry.Moved(r, 500, -500, Image));
        Assert.Equal(new RectD(90, 110, 200, 100), CropGeometry.Moved(r, -10, 10, Image));
    }

    [Fact]
    public void ANewAreaIsClampedAndStandardized()
    {
        Assert.Equal(new RectD(0, 50, 100, 250), CropGeometry.NewArea(P(100, 50), P(-30, 999), Image));
    }

    [Fact]
    public void ApplyingRoundsOutwardsAndDropsWholeOrTinyCrops()
    {
        Assert.Equal(new RectD(10, 20, 91, 81), CropGeometry.Applied(new RectD(10.5, 20.2, 90, 80), Image, null));
        Assert.Null(CropGeometry.Applied(Image, Image, new RectD(0, 0, 10, 10)));
        var previous = new RectD(5, 5, 50, 50);
        Assert.Equal(previous, CropGeometry.Applied(new RectD(10, 10, 2, 80), Image, previous));
    }
}
