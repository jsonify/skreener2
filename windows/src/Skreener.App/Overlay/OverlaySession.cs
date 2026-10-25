using Skreener.App.Capture;
using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.Input.KeyboardAndMouse;

namespace Skreener.App.Overlay;

internal enum OverlayMode { Area, Window }

/// <summary>What the user picked in the overlay.</summary>
internal abstract record OverlayResult;

/// <summary>
/// An area on one monitor. <see cref="ScreenRect"/>: physical pixels, virtual-desktop coordinates.
/// <see cref="Frozen"/> is that monitor's still, to crop the capture from (the Mac's "freeze screen" behaviour).
/// </summary>
internal sealed record AreaPicked(Display Display, RectInt32 ScreenRect, PixelBuffer Frozen) : OverlayResult;

internal sealed record WindowPicked(PickableWindow Window) : OverlayResult;

/// <summary>One monitor to cover and the still of it, grabbed before the overlay appears.</summary>
internal sealed record OverlayScreen(Display Display, PixelBuffer Frozen);

/// <summary>
/// The selection overlay: one borderless, topmost window per monitor, each showing that monitor frozen
/// (SelectionOverlay.swift). Everything is in physical pixels: monitor bounds in virtual-desktop coordinates, the
/// selection in the client coordinates of the monitor's own overlay window, converted to virtual-desktop coordinates
/// only when the result is handed back. A selection lives on one monitor (like the Mac's one view per screen): starting
/// a new one on another monitor drops it. Must run on a thread with a message loop (the UI thread).
/// </summary>
internal sealed class OverlaySession
{
    private static OverlaySession? s_active;

    private readonly List<OverlayWindow> _overlays = [];
    private readonly TaskCompletionSource<OverlayResult?> _done = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Func<List<PickableWindow>> _windowSource;
    private List<PickableWindow>? _pickable;

    private OverlaySession(OverlayMode mode, bool allowModeSwitch, bool adjustable, Func<List<PickableWindow>> windowSource)
    {
        Mode = mode;
        AllowModeSwitch = allowModeSwitch;
        Adjustable = adjustable;
        _windowSource = windowSource;
    }

    public OverlayMode Mode { get; private set; }

    /// <summary>Space (before a drag) switches between area and window picking.</summary>
    public bool AllowModeSwitch { get; }

    /// <summary>Keep the dragged area on screen with handles until Return or a double-click (#102).</summary>
    public bool Adjustable { get; }

    public bool IsFinished => _done.Task.IsCompleted;

    /// <summary>The window under the pointer while picking a window, frontmost first like <see cref="Pickable"/>.</summary>
    public PickableWindow? HoverWindow { get; private set; }

    /// <summary>The pickable windows, front to back; fetched the first time window picking needs them.</summary>
    public List<PickableWindow> Pickable => _pickable ??= _windowSource();

    /// <summary>Banner text shown in the middle of every monitor until a selection starts.</summary>
    public string Hint => Mode == OverlayMode.Window
        ? "Click a window to capture it." + (AllowModeSwitch ? " Press Space to select an area." : "")
        : "Drag to capture an area." + (AllowModeSwitch ? " Press Space to pick a window." : "");

    /// <summary>
    /// Shows the overlay on every screen in <paramref name="screens"/> and completes with the pick, or null when the
    /// user cancels (Esc, right-click) or <paramref name="ct"/> fires. A second call while one is open returns null.
    /// </summary>
    public static Task<OverlayResult?> RunAsync(IReadOnlyList<OverlayScreen> screens, OverlayMode mode, bool allowModeSwitch,
        bool adjustable, Func<List<PickableWindow>> windowSource, CancellationToken ct)
    {
        if (s_active is not null || screens.Count == 0) return Task.FromResult<OverlayResult?>(null);
        var session = new OverlaySession(mode, allowModeSwitch, adjustable, windowSource);
        s_active = session;
        try
        {
            session.Show(screens);
        }
        catch
        {
            session.Finish(null);
            throw;
        }
        if (ct.CanBeCanceled)
        {
            // Back on this (UI) thread: the overlay windows can only be destroyed by the thread that made them.
            var registration = ct.Register(() => session.Finish(null), useSynchronizationContext: true);
            session._done.Task.ContinueWith(_ => registration.Dispose(), TaskScheduler.Default);
        }
        return session._done.Task;
    }

    private void Show(IReadOnlyList<OverlayScreen> screens)
    {
        foreach (var s in screens) _overlays.Add(new OverlayWindow(this, s.Display, s.Frozen));
        if (Mode == OverlayMode.Window && PInvoke.GetCursorPos(out var p)) UpdateHover(p.X, p.Y);
        foreach (var o in _overlays) o.Show();
        // Keyboard (Space, arrows, Esc) needs one overlay in the foreground; take the one under the pointer. Every
        // overlay forwards keys here, so which one has focus does not matter after that.
        (OverlayUnderCursor() ?? _overlays[0]).Activate();
    }

    /// <summary>Closes every overlay window and completes the session. Safe to call more than once.</summary>
    public void Finish(OverlayResult? result)
    {
        if (_done.Task.IsCompleted) return;
        if (s_active == this) s_active = null;
        foreach (var o in _overlays) o.Close();
        _overlays.Clear();
        _done.TrySetResult(result);
    }

    /// <summary>Closes the overlay and fails the session with <paramref name="error"/>.</summary>
    public void Fail(Exception error)
    {
        if (_done.Task.IsCompleted) return;
        if (s_active == this) s_active = null;
        foreach (var o in _overlays)
        {
            try { o.Close(); }
            catch (Exception) { /* already failing: closing the rest matters more than a second error */ }
        }
        _overlays.Clear();
        _done.TrySetException(error);
    }

    public void TakeArea(OverlayWindow overlay, RectInt32 clientRect)
    {
        var b = overlay.Display.Bounds;
        Finish(new AreaPicked(overlay.Display, Rects.Offset(clientRect, b.X, b.Y), overlay.Frozen));
    }

    public void TakeWindow(PickableWindow window) => Finish(new WindowPicked(window));

    /// <summary>The frontmost pickable window at a virtual-desktop point.</summary>
    public PickableWindow? WindowAt(int x, int y) => Pickable.FirstOrDefault(w => Rects.Contains(w.Bounds, x, y));

    /// <summary>Called on every pointer move (virtual-desktop coordinates): keeps the hovered window current.</summary>
    public void UpdateHover(int x, int y)
    {
        var hover = Mode == OverlayMode.Window ? WindowAt(x, y) : null;
        if (hover?.Handle == HoverWindow?.Handle) return;
        HoverWindow = hover;
        InvalidateAll();
    }

    /// <summary>A new selection on one monitor replaces one waiting to be adjusted on another.</summary>
    public void SelectionStarted(OverlayWindow overlay)
    {
        foreach (var o in _overlays)
        {
            if (o != overlay) o.ClearSelection();
        }
    }

    /// <summary>Space before a drag: area to window picking and back.</summary>
    private void ToggleMode()
    {
        Mode = Mode == OverlayMode.Area ? OverlayMode.Window : OverlayMode.Area;
        foreach (var o in _overlays) o.ClearSelection();
        HoverWindow = null;
        if (PInvoke.GetCursorPos(out var p)) UpdateHover(p.X, p.Y);
        InvalidateAll();
    }

    public void OnKeyDown(VIRTUAL_KEY key, bool repeat)
    {
        if (key == VIRTUAL_KEY.VK_ESCAPE) { Finish(null); return; }
        var target = KeyTarget();
        if (key == VIRTUAL_KEY.VK_SPACE && AllowModeSwitch && !repeat && (Mode == OverlayMode.Window || target?.CanSwitchMode == true))
        {
            ToggleMode();
            return;
        }
        if (Mode == OverlayMode.Area) target?.KeyDown(key);
    }

    public void OnKeyUp(VIRTUAL_KEY key) => KeyTarget()?.KeyUp(key);

    public void OnWheel(int delta) => KeyTarget()?.Wheel(delta);

    /// <summary>Keys go to the monitor holding a selection, else to the one under the pointer.</summary>
    private OverlayWindow? KeyTarget() =>
        _overlays.FirstOrDefault(o => o.HasSelection) ?? OverlayUnderCursor() ?? _overlays.FirstOrDefault();

    private OverlayWindow? OverlayUnderCursor() =>
        PInvoke.GetCursorPos(out var p) ? _overlays.FirstOrDefault(o => Rects.Contains(o.Display.Bounds, p.X, p.Y)) : null;

    private void InvalidateAll()
    {
        foreach (var o in _overlays) o.Invalidate();
    }
}
