using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace Skreener.App.Capture;

/// <summary>
/// A monitor. <see cref="Bounds"/> is in physical pixels, virtual-desktop coordinates (top-left of the primary monitor
/// is 0,0; others can be negative). That is what Win32 reports to a PerMonitorV2-aware process, which Skreener is
/// (app.manifest), so no DPI conversion happens here.
/// </summary>
internal sealed record Display(IntPtr Handle, RectInt32 Bounds, bool IsPrimary);

internal static class Displays
{
    private const uint MONITORINFOF_PRIMARY = 1;

    /// <summary>Every monitor attached to the desktop, in the order Windows enumerates them.</summary>
    public static unsafe List<Display> All()
    {
        var list = new List<Display>();
        PInvoke.EnumDisplayMonitors(default, (RECT?)null, (monitor, _, _, _) =>
        {
            var info = new MONITORINFO { cbSize = (uint)sizeof(MONITORINFO) };
            if (PInvoke.GetMonitorInfo(monitor, ref info))
                list.Add(new Display(monitor, Rects.From(info.rcMonitor), (info.dwFlags & MONITORINFOF_PRIMARY) != 0));
            return true;
        }, default);
        return list;
    }

    /// <summary>The monitor under the mouse pointer (or the nearest one), as in the Mac app's fullscreen capture.</summary>
    public static Display UnderCursor()
    {
        var all = All();
        if (all.Count == 0) throw new InvalidOperationException("No monitor found.");
        if (!PInvoke.GetCursorPos(out var p)) return all.FirstOrDefault(d => d.IsPrimary) ?? all[0];
        return all.FirstOrDefault(d => Rects.Contains(d.Bounds, p.X, p.Y)) ?? Nearest(all, p.X, p.Y);
    }

    /// <summary>The monitor that shows most of <paramref name="rect"/>, or null when none shows any of it.</summary>
    public static Display? Containing(IReadOnlyList<Display> displays, RectInt32 rect)
    {
        Display? best = null;
        long bestArea = 0;
        foreach (var d in displays)
        {
            var i = Rects.Intersect(d.Bounds, rect);
            long area = (long)i.Width * i.Height;
            if (area > bestArea) { best = d; bestArea = area; }
        }
        return best;
    }

    private static Display Nearest(List<Display> all, int x, int y) =>
        all.MinBy(d =>
        {
            long dx = Math.Max(Math.Max(d.Bounds.X - x, 0), x - (d.Bounds.X + d.Bounds.Width - 1));
            long dy = Math.Max(Math.Max(d.Bounds.Y - y, 0), y - (d.Bounds.Y + d.Bounds.Height - 1));
            return dx * dx + dy * dy;
        })!;
}

/// <summary>Small helpers for <see cref="RectInt32"/> (exclusive right/bottom edges, like Win32 RECTs).</summary>
internal static class Rects
{
    public static RectInt32 Make(int x, int y, int width, int height) => new() { X = x, Y = y, Width = width, Height = height };

    public static RectInt32 From(RECT r) => Make(r.left, r.top, r.right - r.left, r.bottom - r.top);

    public static bool Contains(RectInt32 r, int x, int y) => x >= r.X && x < r.X + r.Width && y >= r.Y && y < r.Y + r.Height;

    public static bool IsEmpty(RectInt32 r) => r.Width <= 0 || r.Height <= 0;

    /// <summary>The overlap of two rects; empty (all zero) when they do not overlap.</summary>
    public static RectInt32 Intersect(RectInt32 a, RectInt32 b)
    {
        int x0 = Math.Max(a.X, b.X), y0 = Math.Max(a.Y, b.Y);
        int x1 = Math.Min(a.X + a.Width, b.X + b.Width), y1 = Math.Min(a.Y + a.Height, b.Y + b.Height);
        return x1 > x0 && y1 > y0 ? Make(x0, y0, x1 - x0, y1 - y0) : default;
    }

    public static RectInt32 Offset(RectInt32 r, int dx, int dy) => Make(r.X + dx, r.Y + dy, r.Width, r.Height);
}
