using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Diagnostics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Skreener.App.Shell;

/// <summary>
/// A hidden top-level window (never shown) that receives the tray icon's callbacks, WM_HOTKEY and the broadcast
/// "TaskbarCreated" message. It is a normal hidden window rather than a message-only one because message-only
/// windows do not get broadcasts, and without those the tray icon would not come back after Explorer restarts.
/// Must be created on the UI thread: its messages are delivered by the WinUI message loop.
/// </summary>
internal sealed unsafe class MessageWindow : IDisposable
{
    public const uint TrayCallbackMessage = 0x8001; // WM_APP + 1
    private const uint WmHotkey = 0x0312;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmRButtonUp = 0x0205;
    private const string ClassName = "Skreener.ShellWindow";

    // Kept in a static so the delegate handed to Win32 is never collected.
    private static readonly WNDPROC s_proc = StaticProc;
    private static MessageWindow? s_instance;

    private readonly uint _taskbarCreated;

    public MessageWindow()
    {
        s_instance = this;
        _taskbarCreated = PInvoke.RegisterWindowMessage("TaskbarCreated");
        var module = PInvoke.GetModuleHandle((PCWSTR)null);
        var instance = new HINSTANCE(module.Value);

        fixed (char* className = ClassName)
        {
            var wc = new WNDCLASSEXW
            {
                cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
                lpfnWndProc = s_proc,
                hInstance = instance,
                lpszClassName = className,
            };
            if (PInvoke.RegisterClassEx(in wc) == 0) throw new Win32Exception();
        }

        fixed (char* className = ClassName)
        fixed (char* title = "Skreener")
        {
            Handle = PInvoke.CreateWindowEx(0, className, title, WINDOW_STYLE.WS_POPUP, 0, 0, 0, 0,
                HWND.Null, HMENU.Null, instance, null);
        }
        if (Handle == HWND.Null) throw new Win32Exception();
    }

    public HWND Handle { get; }

    /// <summary>A registered hotkey was pressed; the argument is the id given to RegisterHotKey.</summary>
    public event Action<int>? HotkeyPressed;
    public event Action? TrayLeftClick;
    public event Action? TrayRightClick;
    /// <summary>Explorer restarted: the tray icon has to be added again.</summary>
    public event Action? TaskbarCreated;

    private static LRESULT StaticProc(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam)
    {
        try
        {
            s_instance?.Dispatch(msg, wParam, lParam);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: shell window handler failed: {e}");
        }
        return PInvoke.DefWindowProc(hwnd, msg, wParam, lParam);
    }

    private void Dispatch(uint msg, WPARAM wParam, LPARAM lParam)
    {
        if (msg == WmHotkey)
        {
            HotkeyPressed?.Invoke((int)wParam.Value);
        }
        else if (msg == TrayCallbackMessage)
        {
            var mouse = (uint)((long)lParam.Value & 0xFFFF);
            if (mouse == WmLButtonUp) TrayLeftClick?.Invoke();
            else if (mouse == WmRButtonUp) TrayRightClick?.Invoke();
        }
        else if (msg == _taskbarCreated && _taskbarCreated != 0)
        {
            TaskbarCreated?.Invoke();
        }
    }

    public void Dispose()
    {
        PInvoke.DestroyWindow(Handle);
        if (ReferenceEquals(s_instance, this)) s_instance = null;
    }
}
