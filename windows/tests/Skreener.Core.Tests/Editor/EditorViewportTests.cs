using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests.Editor;

/// <summary>Fit, zoom around a point, zoom steps, scrolling and panning of the editor canvas.</summary>
public class EditorViewportTests
{
    private static PointD P(double x, double y) => new(x, y);

    private static EditorViewport Make(double imageW = 1000, double imageH = 500, double viewW = 616, double viewH = 432, double raster = 1)
    {
        var v = new EditorViewport();
        v.Update(new RectD(0, 0, imageW, imageH), new SizeD(viewW, viewH), raster, 16);
        return v;
    }

    private static void AssertNear(PointD expected, PointD actual)
    {
        Assert.Equal(expected.X, actual.X, 6);
        Assert.Equal(expected.Y, actual.Y, 6);
    }

    [Fact]
    public void FitShowsEverythingInsideThePaddingCentered()
    {
        var v = Make(); // 584 x 400 inside the padding: the width limits, 0.584
        Assert.True(v.IsFit);
        Assert.Equal(0.584, v.Scale, 6);
        Assert.False(v.CanScroll);
        AssertNear(P(16, Math.Round((432 - 500 * 0.584) / 2)), v.Origin);
    }

    [Fact]
    public void FitNeverGoesAbove100PercentAndCountsTheDisplayScaling()
    {
        var v = Make(100, 50, 800, 600, raster: 1.5);
        Assert.Equal(1, v.Scale);
        Assert.Equal(1 / 1.5, v.Zoom, 6); // DIPs per image pixel: one image pixel per screen pixel
    }

    [Fact]
    public void ImageAndViewPointsRoundTrip()
    {
        var v = Make();
        v.ZoomTo(2, P(100, 100));
        var image = P(321, 123);
        AssertNear(image, v.ToImage(v.ToView(image)));
    }

    [Fact]
    public void ZoomingKeepsThePointUnderThePointer()
    {
        var v = Make();
        var anchor = P(300, 200);
        var under = v.ToImage(anchor);
        v.ZoomTo(2, anchor);
        Assert.False(v.IsFit);
        Assert.Equal(2, v.Scale);
        Assert.True(v.CanScroll);
        AssertNear(anchor, v.ToView(under));

        v.ZoomBy(1.5, anchor);
        Assert.Equal(3, v.Scale, 6);
        AssertNear(anchor, v.ToView(under));
    }

    [Fact]
    public void TheScrollStopsAtThePaddingAroundTheEnds()
    {
        var v = Make();
        v.ZoomTo(1, P(0, 0)); // anchored at the top-left corner: scrolled as far up and left as it goes
        AssertNear(P(16, 16), v.Origin);
        v.ScrollBy(1e6, 1e6);
        // The image's bottom-right corner ends up the padding away from the view's.
        AssertNear(P(616 - 16, 432 - 16), v.ToView(P(1000, 500)));
        v.ScrollBy(-1e6, 0);
        Assert.Equal(16, v.Origin.X, 6);
    }

    [Fact]
    public void PanningMovesTheContentWithThePointer()
    {
        var v = Make();
        v.ZoomTo(2);
        var before = v.Origin;
        v.Pan(30, -20);
        AssertNear(P(before.X + 30, before.Y - 20), v.Origin);
    }

    [Fact]
    public void ScrollingDoesNothingWhenEverythingFits()
    {
        var v = Make();
        var before = v.Origin;
        v.ScrollBy(100, 100);
        Assert.Equal(before, v.Origin);
    }

    [Fact]
    public void StepsGoToTheNextPresetAndClamp()
    {
        var v = Make();
        Assert.Equal(0.67, v.NextStep(up: true));
        Assert.Equal(0.5, v.NextStep(up: false));
        v.ZoomTo(8);
        Assert.Equal(EditorViewport.MaxScale, v.NextStep(up: true));
        v.ZoomTo(100);
        Assert.Equal(EditorViewport.MaxScale, v.Scale);
        v.ZoomTo(0);
        Assert.Equal(EditorViewport.MinScale, v.Scale);
        v.Step(up: true);
        Assert.Equal(0.25, v.Scale);
    }

    [Fact]
    public void FitComesBackAndFollowsResizes()
    {
        var v = Make();
        v.ZoomTo(4);
        v.Fit();
        Assert.True(v.IsFit);
        v.Update(new RectD(0, 0, 1000, 500), new SizeD(1032, 532), 1, 16);
        Assert.Equal(1, v.Scale);
    }

    [Fact]
    public void AZoomStaysWhenTheViewIsResized()
    {
        var v = Make();
        v.ZoomTo(2);
        v.Update(new RectD(0, 0, 1000, 500), new SizeD(900, 700), 1, 16);
        Assert.Equal(2, v.Scale);
    }

    [Fact]
    public void ACropIsShownFromItsOwnCorner()
    {
        var v = new EditorViewport();
        v.Update(new RectD(100, 50, 200, 100), new SizeD(232, 132), 1, 16);
        Assert.Equal(1, v.Scale);
        AssertNear(P(16, 16), v.ToView(P(100, 50)));
        AssertNear(P(100, 50), v.ToImage(P(16, 16)));
    }

    [Fact]
    public void TheWheelZoomsInAwayFromTheUser()
    {
        Assert.True(EditorViewport.WheelFactor(120) > 1);
        Assert.True(EditorViewport.WheelFactor(-120) < 1);
        Assert.Equal(1, EditorViewport.WheelFactor(120) * EditorViewport.WheelFactor(-120), 9);
    }
}
