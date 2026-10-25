using Skreener.Core.Geometry;

namespace Skreener.App.Overlay;

/// <summary>
/// The overlay's one adapter to <see cref="SelectionGeometry"/> (Skreener.Core), which is a faithful port of the Mac code
/// and so works y-up with a bottom-left origin. The overlay works in its window's client pixels: top-left origin, y down.
///
/// Every call mirrors its rects and points about the horizontal centre line of <c>bounds</c> (y -> MinY + MaxY - y),
/// asks Core, and mirrors the answer back. Why that gives the on-screen behaviour of the Mac:
/// <list type="bullet">
/// <item>The mirror maps <c>bounds</c> onto itself and is its own inverse, so clamping to the bounds is unchanged.</item>
/// <item>Core's <see cref="SelectionGeometry.Key.Up"/> adds to y-up y, which mirrored is a smaller screen y: the
/// selection moves up on screen. So VK_UP maps to Key.Up with no swap (and Down to Down).</item>
/// <item>Core's "bottom" edge is min y-up, i.e. the bottom on screen after the mirror: Ctrl+Down/Up keep the top edge and
/// move the bottom one, as on the Mac.</item>
/// <item>Core numbers handles counter-clockwise from the bottom-left in y-up space. Mirrored, that is the bottom-left on
/// screen too, so this class uses screen order (clockwise from the top-left, like the cursor table in
/// <c>OverlayWindow</c>) and converts with <see cref="CoreHandle"/>.</item>
/// </list>
/// <see cref="Rounded"/> rounds each edge on its own, which does not depend on the y direction, so it calls Core
/// without mirroring (mirroring would flip which way an exact half pixel rounds).
///
/// Pure (Core types only): tests compile this file into Skreener.Core.Tests (ScreenSelectionTests).
/// </summary>
internal static class ScreenSelection
{
    private const ushort VkLeft = 0x25, VkUp = 0x26, VkRight = 0x27, VkDown = 0x28;

    /// <summary>The selection key for a Windows virtual-key code (VK_LEFT..VK_DOWN), or null for any other key.</summary>
    public static SelectionGeometry.Key? KeyFor(ushort virtualKey) => virtualKey switch
    {
        VkLeft => SelectionGeometry.Key.Left,
        VkRight => SelectionGeometry.Key.Right,
        VkUp => SelectionGeometry.Key.Up,
        VkDown => SelectionGeometry.Key.Down,
        _ => null,
    };

    /// <summary>
    /// Core's handle index for a screen handle index. Screen: 0 top-left, 1 top, 2 top-right, 3 right, 4 bottom-right,
    /// 5 bottom, 6 bottom-left, 7 left. Core: 0 bottom-left, 1 bottom, 2 bottom-right, 3 right, 4 top-right, 5 top,
    /// 6 top-left, 7 left. The mapping is its own inverse.
    /// </summary>
    public static int CoreHandle(int screenIndex) => (6 - screenIndex) & 7;

    /// <summary>Handle positions in screen order (see <see cref="CoreHandle"/>): corners at even indexes, edge midpoints at odd ones.</summary>
    public static PointD[] Handles(RectD r)
    {
        double midX = (r.MinX + r.MaxX) / 2, midY = (r.MinY + r.MaxY) / 2;
        return
        [
            new(r.MinX, r.MinY), new(midX, r.MinY), new(r.MaxX, r.MinY), new(r.MaxX, midY),
            new(r.MaxX, r.MaxY), new(midX, r.MaxY), new(r.MinX, r.MaxY), new(r.MinX, midY),
        ];
    }

    /// <summary>Hit test with both edges inside (unlike <see cref="RectD.Contains"/>), so the last row and column count too.</summary>
    public static bool Contains(RectD r, PointD p) => p.X >= r.MinX && p.X <= r.MaxX && p.Y >= r.MinY && p.Y <= r.MaxY;

    /// <summary>Arrows move the selection, Ctrl + arrows move its right or bottom edge; see <see cref="SelectionGeometry.Apply"/>.</summary>
    public static RectD Apply(SelectionGeometry.Key key, bool control, bool shift, RectD rect, RectD bounds)
    {
        double axis = Axis(bounds);
        return Mirror(SelectionGeometry.Apply(key, control, shift, Mirror(rect, axis), bounds), axis);
    }

    /// <summary>The scroll wheel: grows (positive) or shrinks every side; see <see cref="SelectionGeometry.ResizeAllSides"/>.</summary>
    public static RectD ResizeAllSides(RectD rect, double pixels, RectD bounds)
    {
        double axis = Axis(bounds);
        var result = SelectionGeometry.ResizeAllSides(Mirror(rect, axis), pixels, bounds);
        // Null only for a rect outside the bounds, which the overlay never has; keep the selection rather than lose it.
        return result.IsNull ? rect : Mirror(result, axis);
    }

    /// <summary>Each edge on the nearest whole pixel, size kept when only the position is fractional.</summary>
    public static RectD Rounded(RectD rect) => SelectionGeometry.Rounded(rect);

    /// <summary>The rect dragged from <paramref name="start"/> (Shift: square, Alt: from the centre); see <see cref="SelectionGeometry.DragRect"/>.</summary>
    public static RectD DragRect(PointD start, PointD current, bool square, bool fromCenter, RectD bounds)
    {
        double axis = Axis(bounds);
        return Mirror(SelectionGeometry.DragRect(Mirror(start, axis), Mirror(current, axis), square, fromCenter, bounds), axis);
    }

    /// <summary>Drags screen handle <paramref name="screenIndex"/> to <paramref name="point"/>; see <see cref="SelectionGeometry.Resize"/>.</summary>
    public static RectD Resize(RectD rect, int screenIndex, PointD point, RectD bounds)
    {
        double axis = Axis(bounds);
        return Mirror(SelectionGeometry.Resize(Mirror(rect, axis), CoreHandle(screenIndex), Mirror(point, axis), bounds), axis);
    }

    /// <summary>Moves the rect so its top-left corner is at <paramref name="topLeft"/>, kept inside the bounds.</summary>
    public static RectD Move(RectD rect, PointD topLeft, RectD bounds)
    {
        double axis = Axis(bounds);
        // Core's origin is the min-y corner in y-up space: the bottom-left on screen.
        var origin = new PointD(topLeft.X, axis - (topLeft.Y + rect.Height));
        return Mirror(SelectionGeometry.Move(Mirror(rect, axis), origin, bounds), axis);
    }

    private static double Axis(RectD bounds) => bounds.MinY + bounds.MaxY;

    private static PointD Mirror(PointD p, double axis) => new(p.X, axis - p.Y);

    private static RectD Mirror(RectD r, double axis) => r.IsNull ? r : new RectD(r.MinX, axis - r.MaxY, r.Width, r.Height);
}
