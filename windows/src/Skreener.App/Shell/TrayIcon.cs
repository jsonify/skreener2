using System.ComponentModel;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.Shell;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Skreener.App.Shell;

/// <summary>One row of the tray menu. A null <see cref="Text"/> is a separator.</summary>
internal readonly record struct TrayMenuItem(int Id, string? Text, bool Checked = false)
{
    public static TrayMenuItem Separator => new(0, null);
}

/// <summary>The notification-area icon and its context menu (Shell_NotifyIcon).</summary>
internal sealed unsafe class TrayIcon : IDisposable
{
    private const uint IconId = 1;
    private const uint WmNull = 0;
    private const int SmCxSmIcon = 49; // SM_CXSMICON

    private readonly HWND _window;
    private readonly string _tooltip;
    private HICON _icon;
    private bool _added;

    public TrayIcon(HWND window, string iconPath, string tooltip)
    {
        _window = window;
        _tooltip = tooltip;
        var size = PInvoke.GetSystemMetrics((SYSTEM_METRICS_INDEX)SmCxSmIcon);
        var handle = PInvoke.LoadImage(default, iconPath, GDI_IMAGE_TYPE.IMAGE_ICON, size, size, IMAGE_FLAGS.LR_LOADFROMFILE);
        _icon = new HICON(handle.Value);
        if (_icon.IsNull) throw new Win32Exception();
    }

    /// <summary>Adds the icon (again, after Explorer restarts).</summary>
    public void Add()
    {
        var data = Data();
        _added = PInvoke.Shell_NotifyIcon(NOTIFY_ICON_MESSAGE.NIM_ADD, in data);
    }

    private NOTIFYICONDATAW Data()
    {
        var data = new NOTIFYICONDATAW
        {
            cbSize = (uint)sizeof(NOTIFYICONDATAW),
            hWnd = _window,
            uID = IconId,
            uFlags = NOTIFY_ICON_DATA_FLAGS.NIF_ICON | NOTIFY_ICON_DATA_FLAGS.NIF_MESSAGE | NOTIFY_ICON_DATA_FLAGS.NIF_TIP,
            uCallbackMessage = MessageWindow.TrayCallbackMessage,
            hIcon = _icon,
        };
        _tooltip.AsSpan().CopyTo(data.szTip.AsSpan());
        return data;
    }

    /// <summary>Shows the menu at the cursor and returns the chosen item's id, or 0 when dismissed.</summary>
    public int ShowMenu(IReadOnlyList<TrayMenuItem> items)
    {
        var menu = PInvoke.CreatePopupMenu();
        try
        {
            foreach (var item in items)
            {
                if (item.Text is null)
                {
                    PInvoke.AppendMenu(menu, MENU_ITEM_FLAGS.MF_SEPARATOR, 0, (string?)null);
                    continue;
                }
                var flags = MENU_ITEM_FLAGS.MF_STRING | (item.Checked ? MENU_ITEM_FLAGS.MF_CHECKED : MENU_ITEM_FLAGS.MF_UNCHECKED);
                PInvoke.AppendMenu(menu, flags, (nuint)item.Id, item.Text);
            }

            PInvoke.GetCursorPos(out var cursor);
            // Without this the menu would not close when the user clicks elsewhere.
            PInvoke.SetForegroundWindow(_window);
            var chosen = PInvoke.TrackPopupMenuEx(menu,
                (uint)(TRACK_POPUP_MENU_FLAGS.TPM_RETURNCMD | TRACK_POPUP_MENU_FLAGS.TPM_RIGHTBUTTON | TRACK_POPUP_MENU_FLAGS.TPM_BOTTOMALIGN),
                cursor.x, cursor.y, _window, null);
            PInvoke.PostMessage(_window, WmNull, 0, 0);
            return chosen.Value;
        }
        finally
        {
            PInvoke.DestroyMenu(menu);
        }
    }

    public void Dispose()
    {
        if (_added)
        {
            var data = Data();
            PInvoke.Shell_NotifyIcon(NOTIFY_ICON_MESSAGE.NIM_DELETE, in data);
            _added = false;
        }
        if (!_icon.IsNull)
        {
            PInvoke.DestroyIcon(_icon);
            _icon = default;
        }
    }
}
