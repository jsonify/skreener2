using Skreener.App.Capture;
using Skreener.Core.Geometry;
using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.Input.KeyboardAndMouse;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Skreener.App.Overlay;

/// <summary>
/// The overlay on one monitor: a borderless, topmost Win32 popup exactly covering the monitor (physical pixels), painting
/// the frozen screen with GDI, plus the selection or the window highlight. Port of SelectionView in SelectionOverlay.swift.
/// A plain Win32 window rather than a WinUI one: it must sit at exact physical-pixel bounds on monitors with different
/// DPIs, needs no XAML, and paints a full-screen bitmap per mouse move, which a DIB BitBlt does cheaply.
/// </summary>
internal sealed unsafe class OverlayWindow
{
    private const string ClassName = "SkreenerCaptureOverlay";
    private const int HTCLIENT = 1;
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x11;
    /// <summary>How close (in 96-DPI pixels) the pointer must be to a handle to grab it (8 points on the Mac).</summary>
    private const double GrabDistance = 8;

    private static readonly Dictionary<IntPtr, OverlayWindow> s_byHandle = [];
    // Kept in a static field so the delegate the window class points at is never collected.
    private static readonly WNDPROC s_wndProc = WndProc;
    private static bool s_classRegistered;

    private readonly OverlaySession _session;
    private readonly GdiSurface _frozen;
    private GdiSurface? _areaTint;
    private GdiSurface? _windowTint;
    private GdiSurface? _back;
    private HWND _hwnd;
    private HFONT _labelFont;
    private HFONT _hintFont;
    private double _scale = 1;

    private enum DragKind { None, New, Move, Resize }
    private DragKind _drag;
    private (double X, double Y) _moveOffset;
    private int _resizeHandle;
    private RectD _resizeFrom;
    private (double X, double Y)? _start;
    private (double X, double Y)? _current;
    private (double X, double Y)? _cursor;
    /// <summary>The selection once the drag has ended, while it is being adjusted.</summary>
    private RectD? _adjusted;
    private bool _spaceDown;
    /// <summary>Wheel movement not yet applied: the selection changes by whole pixels.</summary>
    private double _wheelRemainder;

    public OverlayWindow(OverlaySession session, Display display, PixelBuffer frozen)
    {
        _session = session;
        Display = display;
        Frozen = frozen;
        _frozen = GdiSurface.FromPixels(frozen);
        Create();
    }

    public Display Display { get; }
    public PixelBuffer Frozen { get; }
    public bool HasSelection => _adjusted is not null || _drag != DragKind.None;
    /// <summary>Space may switch modes: nothing is being dragged or adjusted here.</summary>
    public bool CanSwitchMode => _start is null && _adjusted is null;

    private int Width => Display.Bounds.Width;
    private int Height => Display.Bounds.Height;
    private RectD Bounds => new(0, 0, Width, Height);

    // ---- Window lifetime -------------------------------------------------------------------------------------------

    private static HINSTANCE Instance => PInvoke.GetModuleHandle((PCWSTR)null);

    private static void RegisterClass()
    {
        if (s_classRegistered) return;
        fixed (char* name = ClassName)
        {
            var wc = new WNDCLASSEXW
            {
                cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<WNDCLASSEXW>(),
                style = WNDCLASS_STYLES.CS_DBLCLKS,   // double-click confirms the selection
                lpfnWndProc = s_wndProc,
                hInstance = Instance,
                lpszClassName = name,
            };
            if (PInvoke.RegisterClassEx(in wc) == 0) throw new InvalidOperationException("Could not register the overlay window class.");
        }
        s_classRegistered = true;
    }

    private void Create()
    {
        RegisterClass();
        var b = Display.Bounds;
        fixed (char* name = ClassName)
        fixed (char* title = "Skreener capture")
        {
            // Tool window: no taskbar button and no Alt+Tab entry. With PerMonitorV2 awareness these coordinates are
            // physical pixels, and the window keeps that size even when it lands on a monitor with another DPI
            // (WM_DPICHANGED is ignored below).
            _hwnd = PInvoke.CreateWindowEx(WINDOW_EX_STYLE.WS_EX_TOPMOST | WINDOW_EX_STYLE.WS_EX_TOOLWINDOW, name, title,
                WINDOW_STYLE.WS_POPUP, b.X, b.Y, b.Width, b.Height, default, default, Instance, null);
        }
        if (_hwnd.IsNull) throw new InvalidOperationException("Could not create the selection overlay.");
        s_byHandle[_hwnd] = this;
        // Keep the overlay out of every capture, ours included, should one run while it is up (Windows 10 2004+;
        // older builds just fail this call, which is harmless: captures are taken before it shows or after it closes).
        PInvoke.SetWindowDisplayAffinity(_hwnd, (WINDOW_DISPLAY_AFFINITY)WDA_EXCLUDEFROMCAPTURE);
        _scale = Math.Max(PInvoke.GetDpiForWindow(_hwnd), 96) / 96.0;
        _labelFont = CreateFont(12, 600);
        _hintFont = CreateFont(20, 400);
    }

    private HFONT CreateFont(double size96, int weight)
    {
        fixed (char* face = "Segoe UI")
        {
            const uint CLEARTYPE_QUALITY = 5;
            return PInvoke.CreateFont(-(int)Math.Round(size96 * _scale), 0, 0, 0, weight, 0, 0, 0, 1 /* DEFAULT_CHARSET */,
                0, 0, CLEARTYPE_QUALITY, 0, face);
        }
    }

    public void Show()
    {
        // Re-assert the exact bounds: creation can be adjusted by the system for the DPI of the target monitor.
        var b = Display.Bounds;
        PInvoke.SetWindowPos(_hwnd, HWND.HWND_TOPMOST, b.X, b.Y, b.Width, b.Height, SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
        PInvoke.ShowWindow(_hwnd, SHOW_WINDOW_CMD.SW_SHOWNOACTIVATE);
    }

    /// <summary>
    /// Brings this overlay to the foreground so it gets the keyboard. [verify] Windows only lets the process that got
    /// the last input (the hotkey press or tray click) do this; otherwise the first click on the overlay activates it.
    /// </summary>
    public void Activate()
    {
        PInvoke.SetForegroundWindow(_hwnd);
        PInvoke.SetFocus(_hwnd);
    }

    public void Close()
    {
        if (_hwnd.IsNull) return;
        var hwnd = _hwnd;
        _hwnd = default;
        if (PInvoke.GetCapture() == hwnd) PInvoke.ReleaseCapture();
        s_byHandle.Remove(hwnd);
        PInvoke.DestroyWindow(hwnd);
        _frozen.Dispose();
        _areaTint?.Dispose();
        _windowTint?.Dispose();
        _back?.Dispose();
        if (!_labelFont.IsNull) PInvoke.DeleteObject((HGDIOBJ)_labelFont.Value);
        if (!_hintFont.IsNull) PInvoke.DeleteObject((HGDIOBJ)_hintFont.Value);
        _labelFont = default;
        _hintFont = default;
    }

    public void Invalidate()
    {
        if (!_hwnd.IsNull) PInvoke.InvalidateRect(_hwnd, (RECT?)null, false);
    }

    public void ClearSelection()
    {
        if (_adjusted is null && _start is null) return;
        _adjusted = null;
        _start = null;
        _current = null;
        _drag = DragKind.None;
        Invalidate();
    }

    // ---- Messages ---------------------------------------------------------------------------------------------------

    private static LRESULT WndProc(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam)
    {
        if (!s_byHandle.TryGetValue(hwnd, out var o)) return PInvoke.DefWindowProc(hwnd, msg, wParam, lParam);
        try
        {
            return o.Handle(msg, wParam, lParam) ?? PInvoke.DefWindowProc(hwnd, msg, wParam, lParam);
        }
        catch (Exception e)
        {
            // An exception must not unwind through the native message loop (it would take the process down): close the
            // overlay and hand the error to whoever awaits the capture.
            o._session.Fail(e);
            return new LRESULT(0);
        }
    }

    private static int LowSigned(LPARAM l) => (short)((nint)l.Value & 0xFFFF);
    private static int HighSigned(LPARAM l) => (short)(((nint)l.Value >> 16) & 0xFFFF);

    /// <summary>Handles a message; null means "let DefWindowProc do it".</summary>
    private LRESULT? Handle(uint msg, WPARAM wParam, LPARAM lParam)
    {
        switch (msg)
        {
            case PInvoke.WM_PAINT:
                Paint();
                return new LRESULT(0);
            case PInvoke.WM_ERASEBKGND:
                return new LRESULT(1);   // everything is painted in WM_PAINT
            case PInvoke.WM_SETCURSOR:
                if (((nint)lParam.Value & 0xFFFF) != HTCLIENT) return null;
                // Sent before WM_MOUSEMOVE: read the pointer now so the shape matches where it is, not where it was.
                if (_drag == DragKind.None && PInvoke.GetCursorPos(out var cp))
                    _cursor = (cp.X - Display.Bounds.X, cp.Y - Display.Bounds.Y);
                PInvoke.SetCursor(PInvoke.LoadCursor(default, CursorName()));
                return new LRESULT(1);
            case PInvoke.WM_MOUSEMOVE:
                MouseMoved(LowSigned(lParam), HighSigned(lParam));
                return new LRESULT(0);
            case PInvoke.WM_LBUTTONDOWN:
                MouseDown(LowSigned(lParam), HighSigned(lParam), doubleClick: false);
                return new LRESULT(0);
            case PInvoke.WM_LBUTTONDBLCLK:
                MouseDown(LowSigned(lParam), HighSigned(lParam), doubleClick: true);
                return new LRESULT(0);
            case PInvoke.WM_LBUTTONUP:
                MouseUp();
                return new LRESULT(0);
            case PInvoke.WM_RBUTTONUP:
                // Windows convenience (not on the Mac): right-click cancels, a way out even if the overlay never got
                // the keyboard focus for Esc.
                _session.Finish(null);
                return new LRESULT(0);
            case PInvoke.WM_CAPTURECHANGED:
                // Mouse capture taken away mid-drag (e.g. a system dialog): end the drag where it is.
                if (_drag != DragKind.None) MouseUp();
                return new LRESULT(0);
            case PInvoke.WM_MOUSEWHEEL:
                _session.OnWheel((short)(((nint)wParam.Value >> 16) & 0xFFFF));
                return new LRESULT(0);
            case PInvoke.WM_KEYDOWN:
            case PInvoke.WM_SYSKEYDOWN:   // Alt (from the center) and Alt+key arrive as system keys
                _session.OnKeyDown((VIRTUAL_KEY)(ushort)wParam.Value, repeat: ((nint)lParam.Value & 0x40000000) != 0);
                return new LRESULT(0);
            case PInvoke.WM_KEYUP:
            case PInvoke.WM_SYSKEYUP:
                _session.OnKeyUp((VIRTUAL_KEY)(ushort)wParam.Value);
                return new LRESULT(0);
            case PInvoke.WM_CLOSE:        // Alt+F4
            case PInvoke.WM_DISPLAYCHANGE:   // monitors changed under us: the stills no longer match
                _session.Finish(null);
                return new LRESULT(0);
            case PInvoke.WM_DPICHANGED:
                return new LRESULT(0);   // keep the exact physical bounds; do not take the suggested rect
            default:
                return null;
        }
    }

    // ---- Pointer ------------------------------------------------------------------------------------------------------

    private static bool IsDown(VIRTUAL_KEY key) => PInvoke.GetKeyState((int)key) < 0;

    /// <summary>The rect being dragged out (Shift: square, Alt: from the center), or the one being adjusted.</summary>
    private RectD? SelectionRect()
    {
        if (_drag == DragKind.New && _start is { } s && _current is { } c)
            return ScreenSelection.DragRect(new PointD(s.X, s.Y), new PointD(c.X, c.Y), IsDown(VIRTUAL_KEY.VK_SHIFT), IsDown(VIRTUAL_KEY.VK_MENU), Bounds);
        return _adjusted;
    }

    private int? HandleAt((double X, double Y) p, RectD r)
    {
        double grab = GrabDistance * _scale;
        var handles = ScreenSelection.Handles(r);
        for (int i = 0; i < handles.Length; i++)
        {
            if (Math.Abs(handles[i].X - p.X) <= grab && Math.Abs(handles[i].Y - p.Y) <= grab) return i;
        }
        return null;
    }

    /// <summary>Resize arrows over the handles, a move cursor inside the selection, the crosshair elsewhere.</summary>
    private PCWSTR CursorName()
    {
        if (_session.Mode == OverlayMode.Window) return PInvoke.IDC_HAND;
        switch (_drag)
        {
            case DragKind.Move: return PInvoke.IDC_SIZEALL;
            case DragKind.Resize: return HandleCursor(_resizeHandle);
            case DragKind.New: return PInvoke.IDC_CROSS;
        }
        if (_adjusted is { } r && _cursor is { } p)
        {
            if (HandleAt(p, r) is { } i) return HandleCursor(i);
            if (ScreenSelection.Contains(r, new PointD(p.X, p.Y))) return PInvoke.IDC_SIZEALL;
        }
        return PInvoke.IDC_CROSS;
    }

    /// <summary>Screen handle order (<see cref="ScreenSelection.Handles"/>): 0 top-left, clockwise.</summary>
    private static PCWSTR HandleCursor(int i) => i switch
    {
        0 or 4 => PInvoke.IDC_SIZENWSE,
        2 or 6 => PInvoke.IDC_SIZENESW,
        1 or 5 => PInvoke.IDC_SIZENS,
        _ => PInvoke.IDC_SIZEWE,
    };

    private void MouseMoved(int x, int y)
    {
        var p = ((double)x, (double)y);
        _cursor = p;
        _session.UpdateHover(Display.Bounds.X + x, Display.Bounds.Y + y);
        if (_session.Mode == OverlayMode.Window) return;
        switch (_drag)
        {
            case DragKind.Move when _adjusted is { } r:
                // Whole-pixel origin, same size.
                _adjusted = ScreenSelection.Move(r, new PointD(Math.Round(p.Item1 - _moveOffset.X), Math.Round(p.Item2 - _moveOffset.Y)), Bounds);
                break;
            case DragKind.Resize:
                var e = ScreenSelection.Rounded(ScreenSelection.Resize(_resizeFrom, _resizeHandle, new PointD(p.Item1, p.Item2), Bounds));
                if (e.Width >= 1 && e.Height >= 1) _adjusted = e;
                break;
            case DragKind.New:
                // Holding Space moves the whole selection instead of resizing it.
                if (_spaceDown && _start is { } s && _current is { } c) _start = (s.X + p.Item1 - c.X, s.Y + p.Item2 - c.Y);
                _current = p;
                break;
            default:
                // Only the pointer moved: repaint only when a selection is shown (for the cursor) or while dragging.
                if (_adjusted is null) return;
                break;
        }
        Invalidate();
    }

    private void MouseDown(int x, int y, bool doubleClick)
    {
        var p = ((double)x, (double)y);
        _cursor = p;
        if (_session.Mode == OverlayMode.Window)
        {
            // Hit-test at the click itself: after Space switched modes there may have been no mouse move yet.
            var w = _session.WindowAt(Display.Bounds.X + x, Display.Bounds.Y + y) ?? _session.HoverWindow;
            if (w is not null) _session.TakeWindow(w);
            return;
        }
        PInvoke.SetCapture(_hwnd);
        if (_adjusted is { } r)
        {
            if (doubleClick && ScreenSelection.Contains(r, new PointD(p.Item1, p.Item2))) { Take(r); return; }
            if (HandleAt(p, r) is { } i) { _drag = DragKind.Resize; _resizeHandle = i; _resizeFrom = r; return; }
            if (ScreenSelection.Contains(r, new PointD(p.Item1, p.Item2))) { _drag = DragKind.Move; _moveOffset = (p.Item1 - r.MinX, p.Item2 - r.MinY); return; }
        }
        // Outside any selection: drag out a new one.
        _adjusted = null;
        _drag = DragKind.New;
        _start = p;
        _current = p;
        _session.SelectionStarted(this);
        Invalidate();
    }

    private void MouseUp()
    {
        var drag = _drag;
        var rect = SelectionRect();
        _drag = DragKind.None;
        if (PInvoke.GetCapture() == _hwnd) PInvoke.ReleaseCapture();
        if (drag != DragKind.New) { Invalidate(); return; }
        _start = null;
        _current = null;
        Invalidate();
        // A click without a real drag does nothing (the Mac needs more than 3 points each way).
        if (rect is not { } r || r.Width <= 3 || r.Height <= 3) return;
        if (_session.Adjustable) _adjusted = ScreenSelection.Rounded(r);
        else Take(r);
    }

    /// <summary>Wheel up grows every side of the selection being adjusted, down shrinks it.</summary>
    public void Wheel(int delta)
    {
        if (_session.Mode == OverlayMode.Window || _adjusted is not { } r || _drag != DragKind.None) return;
        // Two points per notch on the Mac; here two 96-DPI pixels, scaled to the monitor.
        _wheelRemainder += delta / 120.0 * 2 * _scale;
        double step = Math.Truncate(_wheelRemainder);
        if (step == 0) return;
        _wheelRemainder -= step;
        _adjusted = ScreenSelection.Rounded(ScreenSelection.ResizeAllSides(r, step, Bounds));
        Invalidate();
    }

    // ---- Keyboard (routed here by the session) ------------------------------------------------------------------------

    public void KeyDown(VIRTUAL_KEY key)
    {
        if (key is VIRTUAL_KEY.VK_SHIFT or VIRTUAL_KEY.VK_MENU)
        {
            // Shift (square) and Alt (from the center) apply as soon as they are pressed mid-drag.
            if (_drag == DragKind.New) Invalidate();
            return;
        }
        if (_adjusted is { } r && _drag == DragKind.None)
        {
            if (key == VIRTUAL_KEY.VK_RETURN) { Take(r); return; }
            if (ScreenSelection.KeyFor((ushort)key) is { } k)
            {
                _adjusted = ScreenSelection.Apply(k, IsDown(VIRTUAL_KEY.VK_CONTROL), IsDown(VIRTUAL_KEY.VK_SHIFT), r, Bounds);
                Invalidate();
            }
            return;
        }
        double step = IsDown(VIRTUAL_KEY.VK_SHIFT) ? 10 : 1;
        switch (key)
        {
            case VIRTUAL_KEY.VK_SPACE: _spaceDown = true; break;
            case VIRTUAL_KEY.VK_LEFT: NudgePointer(-step, 0); break;
            case VIRTUAL_KEY.VK_RIGHT: NudgePointer(step, 0); break;
            case VIRTUAL_KEY.VK_UP: NudgePointer(0, -step); break;
            case VIRTUAL_KEY.VK_DOWN: NudgePointer(0, step); break;
        }
    }

    public void KeyUp(VIRTUAL_KEY key)
    {
        if (key == VIRTUAL_KEY.VK_SPACE) _spaceDown = false;
        else if (key is VIRTUAL_KEY.VK_SHIFT or VIRTUAL_KEY.VK_MENU && _drag == DragKind.New) Invalidate();
    }

    /// <summary>Arrow keys move the pointer (and the selection corner while dragging) one pixel at a time, ten with Shift.</summary>
    private void NudgePointer(double dx, double dy)
    {
        var from = _cursor ?? (PInvoke.GetCursorPos(out var c) ? (c.X - Display.Bounds.X, c.Y - Display.Bounds.Y) : (Width / 2, Height / 2));
        var p = (X: Math.Min(Math.Max(from.Item1 + dx, 0), Width - 1), Y: Math.Min(Math.Max(from.Item2 + dy, 0), Height - 1));
        if (_spaceDown && _start is { } s && _current is { } cur) _start = (s.X + p.X - cur.X, s.Y + p.Y - cur.Y);
        if (_start is not null) _current = p;
        _cursor = p;
        PInvoke.SetCursorPos(Display.Bounds.X + (int)p.X, Display.Bounds.Y + (int)p.Y);
        Invalidate();
    }

    private void Take(RectD r)
    {
        if (PInvoke.GetCapture() == _hwnd) PInvoke.ReleaseCapture();
        var e = ScreenSelection.Rounded(r);
        _session.TakeArea(this, Rects.Make((int)e.MinX, (int)e.MinY, (int)e.Width, (int)e.Height));
    }

    // ---- Painting -----------------------------------------------------------------------------------------------------

    private static COLORREF Rgb(byte r, byte g, byte b) => new((uint)(r | (g << 8) | (b << 16)));

    // The Mac fills the selection with gray at 25 % and tints a picked window with the highlight colour (system blue) at 28 %.
    private static readonly (byte R, byte G, byte B) AreaFill = (128, 128, 128);
    private static readonly (byte R, byte G, byte B) WindowTint = (0, 122, 255);

    private void Paint()
    {
        var hdc = PInvoke.BeginPaint(_hwnd, out var ps);
        try
        {
            if (_back is null || _back.Width != Width || _back.Height != Height)
            {
                _back?.Dispose();
                _back = GdiSurface.Compatible(hdc, Width, Height);
            }
            var dc = _back.Dc;
            PInvoke.BitBlt(dc, 0, 0, Width, Height, _frozen.Dc, 0, 0, ROP_CODE.SRCCOPY);
            if (_session.Mode == OverlayMode.Window) PaintWindowHighlight(dc);
            else PaintSelection(dc);
            PInvoke.BitBlt(hdc, 0, 0, Width, Height, dc, 0, 0, ROP_CODE.SRCCOPY);
        }
        finally
        {
            PInvoke.EndPaint(_hwnd, &ps);
        }
    }

    private void PaintSelection(HDC dc)
    {
        var sel = SelectionRect();
        if (sel is null)
        {
            if (_start is null && _adjusted is null) PaintHint(dc);
            return;
        }
        var e = ScreenSelection.Rounded(sel.Value);
        int x = (int)e.MinX, y = (int)e.MinY, w = (int)e.Width, h = (int)e.Height;
        _areaTint ??= GdiSurface.FromPixels(Frozen.Tinted(AreaFill.R, AreaFill.G, AreaFill.B, 0.25));
        PInvoke.BitBlt(dc, x, y, w, h, _areaTint.Dc, x, y, ROP_CODE.SRCCOPY);
        FrameRect(dc, x, y, w, h, Rgb(64, 64, 64));
        // A new drag clears the adjusted rect, so handles show only on a selection being adjusted.
        if (_adjusted is not null) PaintHandles(dc, e);

        string dims = $"{w} × {h}";   // physical pixels: the size of the image the capture will have
        int pad = Px(5), gap = Px(8);
        if (_drag == DragKind.New && _current is { } c)
        {
            // While dragging: the size beside the pointer, below-right of it, flipped to stay on the monitor.
            var size = Measure(dc, dims, _labelFont);
            int lw = size.W + 2 * pad, lh = size.H + 2 * Px(2);
            int lx = (int)c.X + Px(16), ly = (int)c.Y + Px(16);
            if (lx + lw > Width - 2) lx = (int)c.X - Px(16) - lw;
            if (ly + lh > Height - 2) ly = (int)c.Y - Px(16) - lh;
            Pill(dc, dims, _labelFont, lx, ly, lw, lh, Rgb(0, 0, 0), Rgb(255, 255, 255), Px(4));
            return;
        }
        string label = _adjusted is not null && _drag == DragKind.None ? dims + "    Enter: capture · Esc: cancel" : dims;
        var s = Measure(dc, label, _labelFont);
        int bw = s.W + 2 * pad, bh = s.H + 2 * Px(2);
        // Below the selection's left edge; kept on the monitor.
        int bx = Math.Min(Math.Max(x, 2), Math.Max(Width - bw - 2, 2));
        int by = Math.Min(y + h + gap, Height - bh - 2);
        Pill(dc, label, _labelFont, bx, by, bw, bh, Rgb(30, 30, 30), Rgb(255, 255, 255), Px(4));
    }

    /// <summary>
    /// Window picking (#129): the part of the window under the pointer that can be seen gets a tint and a border;
    /// windows in front of it stay clear. Nothing is reordered: the window is captured on its own, whole.
    /// </summary>
    private void PaintWindowHighlight(HDC dc)
    {
        var hover = _session.HoverWindow;
        if (hover is null) { PaintHint(dc); return; }
        var b = Display.Bounds;
        var local = Rects.Offset(hover.Bounds, -b.X, -b.Y);
        if (Rects.IsEmpty(Rects.Intersect(local, Rects.Make(0, 0, Width, Height)))) return;

        var visible = PInvoke.CreateRectRgn(local.X, local.Y, local.X + local.Width, local.Y + local.Height);
        try
        {
            // Pickable runs front to back: the ones before the hovered window cover it, so cut them out.
            foreach (var front in _session.Pickable)
            {
                if (front.Handle == hover.Handle) break;
                var f = Rects.Offset(front.Bounds, -b.X, -b.Y);
                if (Rects.IsEmpty(Rects.Intersect(f, local))) continue;
                var cut = PInvoke.CreateRectRgn(f.X, f.Y, f.X + f.Width, f.Y + f.Height);
                PInvoke.CombineRgn(visible, visible, cut, RGN_COMBINE_MODE.RGN_DIFF);
                PInvoke.DeleteObject((HGDIOBJ)cut.Value);
            }
            PInvoke.SelectClipRgn(dc, visible);
            _windowTint ??= GdiSurface.FromPixels(Frozen.Tinted(WindowTint.R, WindowTint.G, WindowTint.B, 0.28));
            PInvoke.BitBlt(dc, local.X, local.Y, local.Width, local.Height, _windowTint.Dc, local.X, local.Y, ROP_CODE.SRCCOPY);
            var border = Rgb(WindowTint.R, WindowTint.G, WindowTint.B);
            int thickness = Math.Max(Px(2), 2);
            for (int i = 0; i < thickness; i++)
                FrameRect(dc, local.X + i, local.Y + i, local.Width - 2 * i, local.Height - 2 * i, border);
        }
        finally
        {
            PInvoke.SelectClipRgn(dc, default(HRGN));
            PInvoke.DeleteObject((HGDIOBJ)visible.Value);
        }
    }

    /// <summary>The instruction pill in the middle of the monitor.</summary>
    private void PaintHint(HDC dc)
    {
        string hint = _session.Hint;
        var s = Measure(dc, hint, _hintFont);
        int w = s.W + Px(56), h = s.H + Px(36);
        Pill(dc, hint, _hintFont, (Width - w) / 2, (Height - h) / 2, w, h, Rgb(255, 255, 255), Rgb(30, 30, 30), h / 2);
    }

    /// <summary>Small square handles on the corners and edge midpoints of the selection being adjusted.</summary>
    private void PaintHandles(HDC dc, RectD r)
    {
        int half = Math.Max(Px(3.5), 3), side = half * 2 + 1;
        var white = PInvoke.CreateSolidBrush(Rgb(255, 255, 255));
        try
        {
            foreach (var (hx, hy) in ScreenSelection.Handles(r))
            {
                var box = new RECT((int)hx - half, (int)hy - half, (int)hx - half + side, (int)hy - half + side);
                PInvoke.FillRect(dc, &box, white);
                FrameRect(dc, box.left, box.top, side, side, Rgb(110, 110, 110));
            }
        }
        finally
        {
            PInvoke.DeleteObject(white);
        }
    }

    private int Px(double size96) => (int)Math.Round(size96 * _scale);

    private static void FrameRect(HDC dc, int x, int y, int w, int h, COLORREF color)
    {
        if (w <= 0 || h <= 0) return;
        var brush = PInvoke.CreateSolidBrush(color);
        var r = new RECT(x, y, x + w, y + h);
        PInvoke.FrameRect(dc, &r, brush);
        PInvoke.DeleteObject(brush);
    }

    private static (int W, int H) Measure(HDC dc, string text, HFONT font)
    {
        var old = PInvoke.SelectObject(dc, (HGDIOBJ)font.Value);
        var r = new RECT();
        fixed (char* t = text)
        {
            PInvoke.DrawText(dc, t, text.Length, &r, DRAW_TEXT_FORMAT.DT_CALCRECT | DRAW_TEXT_FORMAT.DT_SINGLELINE | DRAW_TEXT_FORMAT.DT_NOPREFIX);
        }
        PInvoke.SelectObject(dc, old);
        return (r.right - r.left, r.bottom - r.top);
    }

    /// <summary>A rounded box with centred text.</summary>
    private static void Pill(HDC dc, string text, HFONT font, int x, int y, int w, int h, COLORREF fill, COLORREF ink, int radius)
    {
        var brush = PInvoke.CreateSolidBrush(fill);
        var pen = PInvoke.CreatePen(PEN_STYLE.PS_SOLID, 1, fill);
        var oldBrush = PInvoke.SelectObject(dc, brush);
        var oldPen = PInvoke.SelectObject(dc, (HGDIOBJ)pen.Value);
        PInvoke.RoundRect(dc, x, y, x + w, y + h, radius * 2, radius * 2);
        PInvoke.SelectObject(dc, oldPen);
        PInvoke.SelectObject(dc, oldBrush);
        PInvoke.DeleteObject((HGDIOBJ)pen.Value);
        PInvoke.DeleteObject(brush);

        var oldFont = PInvoke.SelectObject(dc, (HGDIOBJ)font.Value);
        PInvoke.SetBkMode(dc, BACKGROUND_MODE.TRANSPARENT);
        PInvoke.SetTextColor(dc, ink);
        var r = new RECT(x, y, x + w, y + h);
        fixed (char* t = text)
        {
            PInvoke.DrawText(dc, t, text.Length, &r,
                DRAW_TEXT_FORMAT.DT_CENTER | DRAW_TEXT_FORMAT.DT_VCENTER | DRAW_TEXT_FORMAT.DT_SINGLELINE | DRAW_TEXT_FORMAT.DT_NOPREFIX);
        }
        PInvoke.SelectObject(dc, oldFont);
    }
}
