namespace Skreener.Core.Geometry;

/// <summary>
/// Where the label typed after drawing an arrow goes (#174), ported from ArrowLabel.swift. Points are in image
/// coordinates of the macOS editor: bottom-left origin, y grows up.
/// </summary>
public static class ArrowLabel
{
    /// <summary>
    /// The frame for a label box of <paramref name="size"/> just past <paramref name="tail"/> (the arrow's end without a
    /// head), on the side away from <paramref name="head"/>, <paramref name="gap"/> points from it. The side of the box
    /// nearest the arrow faces the tail, so the box never covers it.
    /// y-direction: a label "above" the tail (dy &gt; 0) extends towards larger y. With a top-left origin that is below
    /// the tail on screen, so a Windows caller has to negate the y values of both points (or mirror the result).
    /// </summary>
    public static RectD Frame(SizeD size, PointD tail, PointD head, double gap)
    {
        double dx = tail.X - head.X, dy = tail.Y - head.Y;
        double length = Math.Sqrt(dx * dx + dy * dy);
        if (length > 0) { dx /= length; dy /= length; } else { dx = -1; dy = 0; }
        var c = new PointD(tail.X + dx * gap, tail.Y + dy * gap);
        // Within about 22° of straight up or down the box is centered across the arrow; likewise sideways.
        const double lean = 0.38;
        double x = dx > lean ? c.X : dx < -lean ? c.X - size.Width : c.X - size.Width / 2;
        double y = dy > lean ? c.Y : dy < -lean ? c.Y - size.Height : c.Y - size.Height / 2;
        return new RectD(x, y, size.Width, size.Height);
    }
}
