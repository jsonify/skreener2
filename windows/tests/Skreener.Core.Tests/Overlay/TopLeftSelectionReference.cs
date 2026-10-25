namespace Skreener.Core.Tests.Overlay;

// The overlay's temporary top-left selection geometry from the capture branch (before Skreener.Core's port landed), kept
// verbatim apart from names as the reference for ScreenSelectionTests: the overlay's adapter over Core must behave the
// same on screen. Coordinates: top-left origin, y grows down.

/// A rect in overlay client pixels (double so drags and wheel steps can be fractional before rounding).
internal readonly record struct SelRect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public double MidX => X + Width / 2;
    public double MidY => Y + Height / 2;

    public bool Contains(double px, double py) => px >= MinX && px <= MaxX && py >= MinY && py <= MaxY;

    public static SelRect FromEdges(double minX, double minY, double maxX, double maxY) =>
        new(Math.Min(minX, maxX), Math.Min(minY, maxY), Math.Abs(maxX - minX), Math.Abs(maxY - minY));

    public SelRect Inset(double dx, double dy) => new(X + dx, Y + dy, Width - 2 * dx, Height - 2 * dy);

    /// <summary>The overlap of two rects (empty at the origin when they do not overlap, like CGRect.intersection).</summary>
    public SelRect Intersect(SelRect o)
    {
        double minX = Math.Max(MinX, o.MinX), minY = Math.Max(MinY, o.MinY);
        double maxX = Math.Min(MaxX, o.MaxX), maxY = Math.Min(MaxY, o.MaxY);
        return maxX < minX || maxY < minY ? default : new SelRect(minX, minY, maxX - minX, maxY - minY);
    }
}

internal enum RefKey { Left, Right, Up, Down }

internal static class TopLeftSelection
{
    /// <summary>Smallest selection the keys and the scroll wheel shrink to.</summary>
    public const double MinSide = 1;

    /// <summary>
    /// Arrows move the selection; Ctrl + arrows move its right or bottom edge (Right / Down grow, Left / Up shrink).
    /// One pixel per press, ten with Shift. The result stays inside <paramref name="bounds"/>. (Cmd on the Mac.)
    /// </summary>
    public static SelRect Apply(RefKey key, bool control, bool shift, SelRect rect, SelRect bounds)
    {
        double step = shift ? 10 : 1;
        double x = rect.X, y = rect.Y, w = rect.Width, h = rect.Height;
        switch (key, control)
        {
            case (RefKey.Left, false): x -= step; break;
            case (RefKey.Right, false): x += step; break;
            case (RefKey.Up, false): y -= step; break;
            case (RefKey.Down, false): y += step; break;
            case (RefKey.Right, true): w = Math.Min(w + step, bounds.MaxX - x); break;
            case (RefKey.Left, true): w = Math.Max(w - step, MinSide); break;
            // The top edge stays put; the bottom one moves.
            case (RefKey.Down, true): h = Math.Min(h + step, bounds.MaxY - y); break;
            case (RefKey.Up, true): h = Math.Max(h - step, MinSide); break;
        }
        // A move slides the whole rect back inside the bounds.
        x = Math.Min(Math.Max(x, bounds.MinX), bounds.MaxX - w);
        y = Math.Min(Math.Max(y, bounds.MinY), bounds.MaxY - h);
        return new SelRect(x, y, w, h);
    }

    /// <summary>
    /// Grows (positive <paramref name="pixels"/>) or shrinks every side of <paramref name="rect"/>, for the scroll wheel.
    /// A grown rect stays inside <paramref name="bounds"/>; a shrunk one keeps at least <see cref="MinSide"/> each way.
    /// </summary>
    public static SelRect ResizeAllSides(SelRect rect, double pixels, SelRect bounds)
    {
        if (pixels >= 0) return rect.Inset(-pixels, -pixels).Intersect(bounds);
        double dx = Math.Min(-pixels, Math.Max((rect.Width - MinSide) / 2, 0));
        double dy = Math.Min(-pixels, Math.Max((rect.Height - MinSide) / 2, 0));
        return rect.Inset(dx, dy);
    }

    /// <summary>
    /// <paramref name="rect"/> with each edge on the nearest whole pixel. Unlike rounding outwards, this keeps the size
    /// when only the position is fractional, so moving a selection never grows it.
    /// </summary>
    public static SelRect Rounded(SelRect rect)
    {
        double minX = Math.Round(rect.MinX, MidpointRounding.AwayFromZero), minY = Math.Round(rect.MinY, MidpointRounding.AwayFromZero);
        return new SelRect(minX, minY,
            Math.Round(rect.MaxX, MidpointRounding.AwayFromZero) - minX, Math.Round(rect.MaxY, MidpointRounding.AwayFromZero) - minY);
    }

    /// <summary>
    /// The rect being dragged from <paramref name="start"/> to <paramref name="current"/>. <paramref name="square"/> (Shift)
    /// makes it a square on the longer side; <paramref name="fromCenter"/> (Alt) grows it around the start. It stays
    /// inside <paramref name="bounds"/> (a square stays square).
    /// </summary>
    public static SelRect DragRect((double X, double Y) start, (double X, double Y) current, bool square, bool fromCenter, SelRect bounds)
    {
        double dx = current.X - start.X, dy = current.Y - start.Y;
        // Room from the start to the bounds in the direction of the drag (on both sides from the center).
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
        var a = fromCenter ? (X: start.X - dx, Y: start.Y - dy) : start;
        var b = (X: start.X + dx, Y: start.Y + dy);
        return SelRect.FromEdges(a.X, a.Y, b.X, b.Y);
    }

    /// <summary>
    /// Handle positions, clockwise from the top-left: corners at even indexes, edge midpoints at odd ones. (The Mac
    /// lists them counter-clockwise from the bottom-left in y-up space, which is the same sequence of edges.)
    /// </summary>
    public static (double X, double Y)[] Handles(SelRect r) =>
    [
        (r.MinX, r.MinY), (r.MidX, r.MinY), (r.MaxX, r.MinY), (r.MaxX, r.MidY),
        (r.MaxX, r.MaxY), (r.MidX, r.MaxY), (r.MinX, r.MaxY), (r.MinX, r.MidY),
    ];

    /// <summary>
    /// Resizes <paramref name="rect"/> by dragging handle <paramref name="index"/> (see <see cref="Handles"/>) to the
    /// point, clamped to <paramref name="bounds"/>. Dragging past the opposite side flips the rect.
    /// </summary>
    public static SelRect Resize(SelRect rect, int index, (double X, double Y) point, SelRect bounds)
    {
        double qx = Math.Min(Math.Max(point.X, bounds.MinX), bounds.MaxX);
        double qy = Math.Min(Math.Max(point.Y, bounds.MinY), bounds.MaxY);
        double minX = rect.MinX, maxX = rect.MaxX, minY = rect.MinY, maxY = rect.MaxY;
        if (index is 0 or 6 or 7) minX = qx;
        if (index is 2 or 3 or 4) maxX = qx;
        if (index is 0 or 1 or 2) minY = qy;
        if (index is 4 or 5 or 6) maxY = qy;
        return SelRect.FromEdges(minX, minY, maxX, maxY);
    }

    /// <summary>Moves <paramref name="rect"/> so its origin is at the given point, kept inside <paramref name="bounds"/>.</summary>
    public static SelRect Move(SelRect rect, (double X, double Y) origin, SelRect bounds) =>
        new(Math.Min(Math.Max(origin.X, bounds.MinX), bounds.MaxX - rect.Width),
            Math.Min(Math.Max(origin.Y, bounds.MinY), bounds.MaxY - rect.Height),
            rect.Width, rect.Height);
}
