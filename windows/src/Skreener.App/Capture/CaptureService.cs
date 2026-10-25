using Skreener.App.Overlay;
using Windows.Graphics;

namespace Skreener.App.Capture;

/// <summary>
/// Area, window, fullscreen and previous-area capture (CaptureService.swift and the capture flows in AppDelegate.swift).
///
/// Coordinates: everything is physical pixels in virtual-desktop coordinates (top-left of the primary monitor is 0,0;
/// other monitors can be negative). Skreener is PerMonitorV2 DPI-aware, so Win32 reports exactly that and nothing here
/// converts between DPIs; the overlay works in its monitor's client pixels and offsets by the monitor origin.
///
/// Call from the UI thread: the overlay windows are created on the calling thread and need its message loop.
/// </summary>
public sealed class CaptureService : ICaptureService
{
    /// <summary>Time for the overlay to leave the screen before live pixels are grabbed (the Mac waits 150 ms too).</summary>
    private static readonly TimeSpan SettleDelay = TimeSpan.FromMilliseconds(150);

    // The last area captured, for Capture Previous Area. Static: it is app-wide state, whoever makes the service.
    private static RectInt32? s_lastArea;
    private static bool s_busy;

    public CaptureService()
    {
    }

    /// <summary>Keep the dragged area adjustable (handles, arrows, wheel) until Return or a double-click (Settings on the Mac).</summary>
    public bool AdjustAreaBeforeCapture { get; set; } = true;

    /// <summary>Whether Capture Previous Area has an area to repeat.</summary>
    public static bool HasPreviousArea => s_lastArea is not null;

    public async Task<CaptureResult?> CaptureAsync(CaptureKind kind, CancellationToken cancellationToken = default)
    {
        // One capture at a time: a second hotkey press while picking would stack another set of overlays.
        if (s_busy) return null;
        s_busy = true;
        try
        {
            var result = kind switch
            {
                CaptureKind.Area => await PickAsync(OverlayMode.Area, cancellationToken),
                CaptureKind.Window => await PickAsync(OverlayMode.Window, cancellationToken),
                CaptureKind.Fullscreen => await CaptureFullscreenAsync(cancellationToken),
                CaptureKind.PreviousArea => await CapturePreviousAreaAsync(cancellationToken),
                _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
            };
            cancellationToken.ThrowIfCancellationRequested();
            return result;
        }
        finally
        {
            s_busy = false;
        }
    }

    /// <summary>The monitor under the pointer.</summary>
    private static async Task<CaptureResult> CaptureFullscreenAsync(CancellationToken ct)
    {
        var display = Displays.UnderCursor();
        // Let a tray menu that started this fade out first.
        await Task.Delay(SettleDelay, ct);
        var pixels = await ScreenGrabber.GrabMonitorAsync(display.Handle, ct);
        return new CaptureResult(pixels.ToSoftwareBitmap(), CaptureKind.Fullscreen, display.Bounds, null);
    }

    /// <summary>
    /// Every monitor in one image covering the virtual desktop's bounding box (gaps between monitors of different sizes
    /// stay transparent). Not in <see cref="ICaptureService"/>; Kind is <see cref="CaptureKind.Fullscreen"/>.
    /// </summary>
    public async Task<CaptureResult> CaptureAllMonitorsAsync(CancellationToken cancellationToken = default)
    {
        var displays = Displays.All();
        if (displays.Count == 0) throw new InvalidOperationException("No monitor found.");
        await Task.Delay(SettleDelay, cancellationToken);
        var stills = await Task.WhenAll(displays.Select(d => ScreenGrabber.GrabMonitorAsync(d.Handle, cancellationToken)));
        int x0 = displays.Min(d => d.Bounds.X), y0 = displays.Min(d => d.Bounds.Y);
        int x1 = displays.Max(d => d.Bounds.X + d.Bounds.Width), y1 = displays.Max(d => d.Bounds.Y + d.Bounds.Height);
        var all = new BgraImage(x1 - x0, y1 - y0);
        for (int i = 0; i < displays.Count; i++) all.Blit(stills[i], displays[i].Bounds.X - x0, displays[i].Bounds.Y - y0);
        return new CaptureResult(all.ToSoftwareBitmap(), CaptureKind.Fullscreen, Rects.Make(x0, y0, x1 - x0, y1 - y0), null);
    }

    /// <summary>
    /// The last captured area again, grabbed live. Null when there is none yet, or when no monitor shows it any more
    /// (the Mac checks that its screen still exists); the caller can tell the two apart with <see cref="HasPreviousArea"/>.
    /// </summary>
    private static async Task<CaptureResult?> CapturePreviousAreaAsync(CancellationToken ct)
    {
        if (s_lastArea is not { } area) return null;
        var display = Displays.Containing(Displays.All(), area);
        if (display is null) return null;
        await Task.Delay(SettleDelay, ct);
        var still = await ScreenGrabber.GrabMonitorAsync(display.Handle, ct);
        // Areas never span monitors (selection is per monitor), but monitors may have moved since: clip to this one.
        var rect = Rects.Intersect(area, display.Bounds);
        var crop = CropScreenRect(still, display, rect);
        if (crop is null) return null;
        return new CaptureResult(crop.ToSoftwareBitmap(), CaptureKind.PreviousArea, rect, null);
    }

    /// <summary>
    /// Freeze first, then select (the Mac's "freeze screen"): grab a still of every monitor, show the overlay over the
    /// stills, then crop the area from its still, or capture the picked window on its own.
    /// </summary>
    private async Task<CaptureResult?> PickAsync(OverlayMode mode, CancellationToken ct)
    {
        var displays = Displays.All();
        if (displays.Count == 0) throw new InvalidOperationException("No monitor found.");
        // The window list is taken before the overlay covers anything; the overlay's own windows are filtered out anyway.
        List<PickableWindow>? windows = mode == OverlayMode.Window ? WindowList.OnScreen() : null;
        var stills = await Task.WhenAll(displays.Select(d => ScreenGrabber.GrabMonitorAsync(d.Handle, ct)));
        var screens = displays.Select((d, i) => new OverlayScreen(d, stills[i])).ToList();

        var picked = await OverlaySession.RunAsync(screens, mode, allowModeSwitch: true, AdjustAreaBeforeCapture,
            () => windows ??= WindowList.OnScreen(), ct);

        switch (picked)
        {
            case AreaPicked area:
            {
                var crop = CropScreenRect(area.Frozen, area.Display, area.ScreenRect);
                if (crop is null) return null;
                s_lastArea = area.ScreenRect;
                return new CaptureResult(crop.ToSoftwareBitmap(), CaptureKind.Area, area.ScreenRect, null);
            }
            case WindowPicked window:
            {
                // Let the overlay leave the screen (not strictly needed: WGC captures the window's own surface).
                await Task.Delay(SettleDelay, ct);
                var pixels = await ScreenGrabber.GrabWindowAsync(window.Window.Handle, ct);
                var bounds = WindowList.VisibleBounds(new Windows.Win32.Foundation.HWND(window.Window.Handle));
                if (Rects.IsEmpty(bounds)) bounds = window.Window.Bounds;
                // [verify] The WGC frame should match the DWM extended frame bounds; report the frame's real size.
                var rect = Rects.Make(bounds.X, bounds.Y, pixels.Width, pixels.Height);
                return new CaptureResult(pixels.ToSoftwareBitmap(), CaptureKind.Window, rect, window.Window.Title);
            }
            default:
                return null;
        }
    }

    /// <summary>
    /// Cuts a virtual-desktop rect out of a still of <paramref name="display"/>. The still should be exactly the monitor's
    /// size; if it is not (a mode change mid-capture), the rect is scaled to the still.
    /// </summary>
    private static BgraImage? CropScreenRect(BgraImage still, Display display, RectInt32 screenRect)
    {
        var local = Rects.Offset(screenRect, -display.Bounds.X, -display.Bounds.Y);
        if (still.Width != display.Bounds.Width || still.Height != display.Bounds.Height)
        {
            double sx = (double)still.Width / display.Bounds.Width, sy = (double)still.Height / display.Bounds.Height;
            int x = (int)Math.Floor(local.X * sx), y = (int)Math.Floor(local.Y * sy);
            local = Rects.Make(x, y, (int)Math.Ceiling((local.X + local.Width) * sx) - x, (int)Math.Ceiling((local.Y + local.Height) * sy) - y);
        }
        return still.Crop(local);
    }
}
