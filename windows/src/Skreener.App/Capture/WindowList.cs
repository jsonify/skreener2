using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Dwm;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Skreener.App.Capture;

/// <summary>A window that can be picked. <see cref="Bounds"/>: physical pixels, virtual-desktop coordinates, as seen on screen.</summary>
internal sealed record PickableWindow(IntPtr Handle, RectInt32 Bounds, string Title);

/// <summary>
/// The on-screen top-level windows the window picker offers, frontmost first, so a hit test picks the window you
/// actually see under the pointer (CaptureService.onScreenWindows on the Mac).
/// </summary>
internal static class WindowList
{
    /// <summary>Windows smaller than this either way are left out (the Mac uses 40 points; here it is pixels).</summary>
    private const int MinSide = 40;

    // Desktop and shell surfaces that are never "a window" to capture.
    private static readonly HashSet<string> s_shellClasses = new(StringComparer.Ordinal)
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd",
    };

    public static unsafe List<PickableWindow> OnScreen()
    {
        uint me = (uint)Environment.ProcessId;
        var result = new List<PickableWindow>();
        // EnumWindows walks top-level windows in z-order, topmost first.
        PInvoke.EnumWindows((hwnd, _) =>
        {
            if (TryDescribe(hwnd, me) is { } w) result.Add(w);
            return true;
        }, default);
        return result;
    }

    private static unsafe PickableWindow? TryDescribe(HWND hwnd, uint myProcess)
    {
        if (!PInvoke.IsWindowVisible(hwnd) || PInvoke.IsIconic(hwnd)) return null;

        uint pid;
        PInvoke.GetWindowThreadProcessId(hwnd, &pid);
        if (pid == myProcess) return null;   // Skreener's own overlays, editor, etc.

        var exStyle = (WINDOW_EX_STYLE)(uint)PInvoke.GetWindowLong(hwnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
        // Tool windows (floating palettes, tray flyouts) stay out unless they ask to be app windows; click-through
        // windows can't be what the user points at.
        if ((exStyle & WINDOW_EX_STYLE.WS_EX_TOOLWINDOW) != 0 && (exStyle & WINDOW_EX_STYLE.WS_EX_APPWINDOW) == 0) return null;
        if ((exStyle & WINDOW_EX_STYLE.WS_EX_TRANSPARENT) != 0) return null;
        if ((exStyle & WINDOW_EX_STYLE.WS_EX_LAYERED) != 0)
        {
            // Fully transparent windows can't be seen but would still catch the click (the Mac filters alpha ~0 too).
            byte alpha = 255;
            LAYERED_WINDOW_ATTRIBUTES_FLAGS flags = 0;
            if (PInvoke.GetLayeredWindowAttributes(hwnd, null, &alpha, &flags) &&
                (flags & LAYERED_WINDOW_ATTRIBUTES_FLAGS.LWA_ALPHA) != 0 && alpha < 3) return null;
        }

        // UWP apps that are suspended or on another virtual desktop are "cloaked": visible to Win32 but not on screen.
        int cloaked = 0;
        if (PInvoke.DwmGetWindowAttribute(hwnd, DWMWINDOWATTRIBUTE.DWMWA_CLOAKED, &cloaked, sizeof(int)).Succeeded && cloaked != 0)
            return null;

        string cls = ClassName(hwnd);
        if (s_shellClasses.Contains(cls)) return null;

        var bounds = VisibleBounds(hwnd);
        if (bounds.Width < MinSide || bounds.Height < MinSide) return null;
        return new PickableWindow(hwnd, bounds, Title(hwnd));
    }

    /// <summary>
    /// The window as drawn: DWM's extended frame bounds leave out the invisible resize borders (about 7 px each side on
    /// Windows 10/11) that GetWindowRect includes.
    /// </summary>
    public static unsafe RectInt32 VisibleBounds(HWND hwnd)
    {
        RECT r;
        if (PInvoke.DwmGetWindowAttribute(hwnd, DWMWINDOWATTRIBUTE.DWMWA_EXTENDED_FRAME_BOUNDS, &r, (uint)sizeof(RECT)).Succeeded)
            return Rects.From(r);
        return PInvoke.GetWindowRect(hwnd, out r) ? Rects.From(r) : default;
    }

    public static unsafe string Title(HWND hwnd)
    {
        int length = PInvoke.GetWindowTextLength(hwnd);
        if (length <= 0) return "";
        var buffer = new char[length + 1];
        fixed (char* p = buffer)
        {
            int copied = PInvoke.GetWindowText(hwnd, p, buffer.Length);
            return new string(p, 0, Math.Max(copied, 0));
        }
    }

    private static unsafe string ClassName(HWND hwnd)
    {
        var buffer = new char[256];
        fixed (char* p = buffer)
        {
            int copied = PInvoke.GetClassName(hwnd, p, buffer.Length);
            return new string(p, 0, Math.Max(copied, 0));
        }
    }
}
