using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>Arrow labels (#174), from AnnotationStyleTests.swift. The test for the label being on by default belongs to Style, which is not ported.</summary>
public class ArrowLabelTests
{
    [Fact]
    public void ArrowLabelSitsPastTheTailAwayFromTheHead()
    {
        var size = new SizeD(80, 30);
        var tail = new PointD(100, 100);
        // Arrow pointing right: the label is to the left of the tail, centered on it.
        var left = ArrowLabel.Frame(size, tail, new PointD(200, 100), 6);
        Assert.Equal(new RectD(14, 85, 80, 30), left);
        // Arrow pointing down: the label is above the tail.
        var above = ArrowLabel.Frame(size, tail, new PointD(100, 0), 6);
        Assert.Equal(new RectD(60, 106, 80, 30), above);
        // Arrow pointing up and to the right: the label is below and to the left, its corner nearest the tail.
        var diagonal = ArrowLabel.Frame(size, tail, new PointD(200, 200), 0);
        Assert.Equal(100, diagonal.MaxX, 0.01);
        Assert.Equal(100, diagonal.MaxY, 0.01);
    }

    [Fact]
    public void ArrowLabelNeverCoversTheTail()
    {
        var size = new SizeD(60, 24);
        var tail = new PointD(50, 50);
        for (int degrees = 0; degrees < 360; degrees += 15)
        {
            double t = degrees * Math.PI / 180;
            var head = new PointD(tail.X + Math.Cos(t) * 100, tail.Y + Math.Sin(t) * 100);
            var box = ArrowLabel.Frame(size, tail, head, 6);
            Assert.False(box.InsetBy(-2, -2).Contains(tail), $"arrow at {degrees}°");
        }
    }
}
