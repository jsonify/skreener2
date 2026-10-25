namespace Skreener.Core.Geometry;

/// <summary>
/// Rect math for the area selection (#102, #103), ported from SelectionGeometry.swift. Rects are in view coordinates
/// of the macOS overlay: bottom-left origin, y grows up. Nothing here flips y, so on Windows (top-left origin) "up"
/// arrows, "bottom" edges and the handle order are mirrored unless the caller works in a y-up space; see
/// <see cref="Key"/>, <see cref="Apply"/> and <see cref="Resize"/>.
/// </summary>
public static class SelectionGeometry
{
    public enum Key { Left, Right, Down, Up }

    /// <summary>Smallest selection the keys and the scroll wheel shrink to.</summary>
    public const double MinSide = 1;

    /// <summary>
    /// The selection key for an arrow key code. These are macOS virtual key codes (123 to 126); a Windows caller has to
    /// map VK_LEFT/RIGHT/DOWN/UP (0x25 to 0x28) itself.
    /// </summary>
    public static Key? KeyFor(ushort keyCode) => keyCode switch
    {
        123 => Key.Left,
        124 => Key.Right,
        125 => Key.Down,
        126 => Key.Up,
        _ => null,
    };

    /// <summary>
    /// Arrows move the selection; Command (Ctrl on Windows) + arrows move its right or bottom edge (right / down grow,
    /// left / up shrink). One point per press, ten with Shift. The result stays inside <paramref name="bounds"/>.
    /// y-direction: <see cref="Key.Up"/> adds to y and "bottom" is the min y, as with a bottom-left origin.
    /// </summary>
    public static RectD Apply(Key key, bool command, bool shift, RectD rect, RectD bounds)
    {
        double step = shift ? 10 : 1;
        var r = rect.Standardized;
        double x = r.Origin.X, y = r.Origin.Y, w = r.Width, h = r.Height;
        switch (key, command)
        {
            case (Key.Left, false): x -= step; break;
            case (Key.Right, false): x += step; break;
            case (Key.Down, false): y -= step; break;
            case (Key.Up, false): y += step; break;
            case (Key.Right, true):
                w = Math.Min(w + step, bounds.MaxX - r.MinX);
                break;
            case (Key.Left, true):
                w = Math.Max(w - step, MinSide);
                break;
            case (Key.Down, true):
            {
                // The top edge stays put; the bottom one moves down.
                double nh = Math.Min(h + step, r.MaxY - bounds.MinY);
                y = r.MaxY - nh;
                h = nh;
                break;
            }
            case (Key.Up, true):
            {
                double nh = Math.Max(h - step, MinSide);
                y = r.MaxY - nh;
                h = nh;
                break;
            }
        }
        // A move slides the whole rect back inside the bounds.
        x = Math.Min(Math.Max(x, bounds.MinX), bounds.MaxX - w);
        y = Math.Min(Math.Max(y, bounds.MinY), bounds.MaxY - h);
        return new RectD(x, y, w, h);
    }

    /// <summary>
    /// Grows (positive <paramref name="points"/>) or shrinks every side of <paramref name="rect"/> by <paramref name="points"/>,
    /// for the scroll wheel. A grown rect stays inside <paramref name="bounds"/>; a shrunk one keeps at least
    /// <see cref="MinSide"/> each way.
    /// </summary>
    public static RectD ResizeAllSides(RectD rect, double points, RectD bounds)
    {
        if (points >= 0) return rect.InsetBy(-points, -points).Intersection(bounds);
        double dx = Math.Min(-points, Math.Max((rect.Width - MinSide) / 2, 0));
        double dy = Math.Min(-points, Math.Max((rect.Height - MinSide) / 2, 0));
        return rect.InsetBy(dx, dy);
    }

    /// <summary>
    /// <paramref name="rect"/> with each edge on the nearest whole point. Unlike <see cref="RectD.Integral"/>, which rounds
    /// outwards, this keeps the size when only the position is fractional, so moving a selection never grows it.
    /// </summary>
    public static RectD Rounded(RectD rect)
    {
        double minX = Text.CMath.Round(rect.MinX), minY = Text.CMath.Round(rect.MinY);
        return new RectD(minX, minY, Text.CMath.Round(rect.MaxX) - minX, Text.CMath.Round(rect.MaxY) - minY);
    }

    /// <summary>
    /// The rect being dragged from <paramref name="start"/> to <paramref name="current"/>. <paramref name="square"/>
    /// (Shift) makes it a square on the longer side; <paramref name="fromCenter"/> (Alt) grows it around
    /// <paramref name="start"/>. It stays inside <paramref name="bounds"/> (a square stays square). Symmetric in y.
    /// </summary>
    public static RectD DragRect(PointD start, PointD current, bool square, bool fromCenter, RectD bounds)
    {
        double dx = current.X - start.X, dy = current.Y - start.Y;
        // Room from `start` to the bounds in the direction of the drag (on both sides from the center).
        double Room(double d, double lo, double hi, double s) => fromCenter ? Math.Min(s - lo, hi - s) : (d < 0 ? s - lo : hi - s);
        double roomX = Math.Max(Room(dx, bounds.MinX, bounds.MaxX, start.X), 0);
        double roomY = Math.Max(Room(dy, bounds.MinY, bounds.MaxY, start.Y), 0);
        if (square)
        {
            double side = Math.Min(Math.Min(Math.Max(Math.Abs(dx), Math.Abs(dy)), roomX), roomY);
            dx = dx < 0 ? -side : side;
            dy = dy < 0 ? -side : side;
        }
        else
        {
            dx = Math.Max(Math.Min(dx, roomX), -roomX);
            dy = Math.Max(Math.Min(dy, roomY), -roomY);
        }
        var a = fromCenter ? new PointD(start.X - dx, start.Y - dy) : start;
        var b = new PointD(start.X + dx, start.Y + dy);
        return new RectD(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Abs(b.X - a.X), Math.Abs(b.Y - a.Y));
    }

    /// <summary>
    /// Resizes <paramref name="rect"/> by dragging handle <paramref name="index"/> (counter-clockwise from bottom-left:
    /// corners at even indexes, edge midpoints at odd ones) to <paramref name="point"/>, clamped to <paramref name="bounds"/>.
    /// Dragging past the opposite side flips the rect. y-direction: "bottom-left" is the min x, min y corner, so with a
    /// top-left origin indexes 0 to 2 are the top handles and the order runs clockwise.
    /// </summary>
    public static RectD Resize(RectD rect, int index, PointD point, RectD bounds)
    {
        var q = new PointD(Math.Min(Math.Max(point.X, bounds.MinX), bounds.MaxX),
                           Math.Min(Math.Max(point.Y, bounds.MinY), bounds.MaxY));
        double minX = rect.MinX, maxX = rect.MaxX, minY = rect.MinY, maxY = rect.MaxY;
        if (index is 0 or 6 or 7) minX = q.X;
        if (index is 2 or 3 or 4) maxX = q.X;
        if (index is 0 or 1 or 2) minY = q.Y;
        if (index is 4 or 5 or 6) maxY = q.Y;
        return new RectD(Math.Min(minX, maxX), Math.Min(minY, maxY), Math.Abs(maxX - minX), Math.Abs(maxY - minY));
    }

    /// <summary>Moves <paramref name="rect"/> so its origin is at <paramref name="origin"/>, kept inside <paramref name="bounds"/>.</summary>
    public static RectD Move(RectD rect, PointD origin, RectD bounds) =>
        new(Math.Min(Math.Max(origin.X, bounds.MinX), bounds.MaxX - rect.Width),
            Math.Min(Math.Max(origin.Y, bounds.MinY), bounds.MaxY - rect.Height),
            rect.Width, rect.Height);
}
