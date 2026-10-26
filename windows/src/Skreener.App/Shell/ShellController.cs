using System.Diagnostics;
using Microsoft.UI.Xaml;
using Skreener.App.Capture;
using Skreener.App.Editor;
using Skreener.Core.Output;

namespace Skreener.App.Shell;

/// <summary>
/// Everything around the capture itself: tray icon and menu, global hotkeys, and what happens to a finished capture
/// (clipboard, file, toast, Quick Access, the editor). Talks to the capture code only through <see cref="ICaptureService"/>.
/// </summary>
internal sealed class ShellController : IDisposable
{
    private const int CmdArea = 1, CmdWindow = 2, CmdFullscreen = 3, CmdPreviousArea = 4, CmdOpenFolder = 5, CmdLaunchAtLogin = 6, CmdQuit = 7;
    private const string IconRelativePath = "Shell/Assets/tray.ico";

    /// <summary>Time for the tray menu (and its selection fade) to leave the screen before a capture freezes it. [verify]</summary>
    private static readonly TimeSpan MenuSettleDelay = TimeSpan.FromMilliseconds(200);
    /// <summary>Time for a hidden toast banner, or a closed Quick Access window, to animate off the screen. [verify]</summary>
    private static readonly TimeSpan ClearScreenDelay = TimeSpan.FromMilliseconds(300);

    private readonly ICaptureService _capture;
    private readonly Notifier _notifier;
    private readonly OutputService _output = new();
    private AppSettings _settings;
    private MessageWindow? _window;
    private TrayIcon? _tray;
    private HotkeyManager? _hotkeys;
    private QuickAccessWindow? _quickAccess;
    /// <summary>Open editors, held until they close.</summary>
    private readonly HashSet<EditorWindow> _editors = new();
    private bool _capturing;

    public ShellController(ICaptureService capture, Notifier notifier, AppSettings settings)
    {
        _capture = capture;
        _notifier = notifier;
        _settings = settings;
    }

    /// <summary>Creates the hidden window, adds the tray icon and registers the hotkeys. Call on the UI thread.</summary>
    public void Start()
    {
        _window = new MessageWindow();
        _window.HotkeyPressed += id => _ = RunCaptureAsync(KindFor(HotkeyManager.ActionFor(id)));
        _window.TrayLeftClick += () => _ = RunCaptureAsync(CaptureKind.Area);
        _window.TrayRightClick += ShowMenu;

        var icon = System.IO.Path.Combine(AppContext.BaseDirectory, IconRelativePath);
        _tray = new TrayIcon(_window.Handle, icon, "Skreener");
        _tray.Add();
        _window.TaskbarCreated += _tray.Add;

        _hotkeys = new HotkeyManager(_window.Handle);
        var failed = _hotkeys.RegisterAll(_settings);
        if (failed.Count > 0)
        {
            _notifier.Show("Some shortcuts are unavailable",
                "Another app already uses: " + string.Join(", ", failed) + ". Change them in " + SettingsStore.FilePath + ".");
        }
    }

    private static CaptureKind KindFor(HotkeyAction action) => action switch
    {
        HotkeyAction.CaptureArea => CaptureKind.Area,
        HotkeyAction.CaptureWindow => CaptureKind.Window,
        HotkeyAction.CaptureFullscreen => CaptureKind.Fullscreen,
        _ => CaptureKind.PreviousArea,
    };

    private void ShowMenu()
    {
        if (_tray is null) return;
        var items = new[]
        {
            new TrayMenuItem(CmdArea, Label("Capture Area", HotkeyAction.CaptureArea)),
            new TrayMenuItem(CmdWindow, Label("Capture Window", HotkeyAction.CaptureWindow)),
            new TrayMenuItem(CmdFullscreen, Label("Capture Fullscreen", HotkeyAction.CaptureFullscreen)),
            new TrayMenuItem(CmdPreviousArea, Label("Capture Previous Area", HotkeyAction.CapturePreviousArea)),
            TrayMenuItem.Separator,
            new TrayMenuItem(CmdOpenFolder, "Open Screenshots Folder"),
            new TrayMenuItem(CmdLaunchAtLogin, "Launch at Login", LaunchAtLogin.IsEnabled),
            TrayMenuItem.Separator,
            new TrayMenuItem(CmdQuit, "Quit"),
        };
        switch (_tray.ShowMenu(items))
        {
            case CmdArea: _ = RunCaptureAsync(CaptureKind.Area, fromMenu: true); break;
            case CmdWindow: _ = RunCaptureAsync(CaptureKind.Window, fromMenu: true); break;
            case CmdFullscreen: _ = RunCaptureAsync(CaptureKind.Fullscreen, fromMenu: true); break;
            case CmdPreviousArea: _ = RunCaptureAsync(CaptureKind.PreviousArea, fromMenu: true); break;
            case CmdOpenFolder: OpenScreenshotsFolder(); break;
            case CmdLaunchAtLogin: ToggleLaunchAtLogin(); break;
            case CmdQuit: Quit(); break;
        }
    }

    private string Label(string title, HotkeyAction action) => title + "\t" + _settings.GetHotkey(action);

    private void OpenScreenshotsFolder()
    {
        try
        {
            var folder = _settings.ResolveSaveFolder(SettingsStore.PicturesFolder);
            Directory.CreateDirectory(folder);
            Explorer.Reveal(folder);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            _notifier.Show("Could not open the screenshots folder", e.Message);
        }
    }

    private void ToggleLaunchAtLogin()
    {
        try { LaunchAtLogin.SetEnabled(!LaunchAtLogin.IsEnabled); }
        catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            _notifier.Show("Could not change Launch at Login", e.Message);
        }
    }

    /// <summary>
    /// The whole flow on the UI thread: hotkeys and tray clicks arrive from <see cref="MessageWindow"/>'s window procedure
    /// on the UI thread, and every await below resumes there (WinUI's synchronization context), which the overlay
    /// windows, the clipboard and the Quick Access window all need.
    /// </summary>
    private async Task RunCaptureAsync(CaptureKind kind, bool fromMenu = false)
    {
        if (_capturing) return;
        _capturing = true;
        try
        {
            await ClearScreenAsync(fromMenu);
            var result = await _capture.CaptureAsync(kind);
            if (result is not null) await FinishAsync(result);
            else if (kind == CaptureKind.PreviousArea)
            {
                // Null here means no area yet, or its monitor is gone (the Mac says the same for both).
                _notifier.Show("No area to repeat",
                    "Capture Previous Area captures the area you captured last. Capture an area first.");
            }
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: capture failed: {e}");
            _notifier.Show("Capture failed", e.Message);
        }
        finally
        {
            _capturing = false;
        }
    }

    /// <summary>
    /// Makes sure nothing of Skreener's own shows in the capture about to start (on the Mac, ScreenCaptureKit leaves the
    /// app's windows out). Area and window captures freeze the screen right away, so this waits for anything it hides.
    /// The overlay windows exclude themselves (WDA_EXCLUDEFROMCAPTURE).
    /// </summary>
    private async Task ClearScreenAsync(bool fromMenu)
    {
        var wait = fromMenu ? MenuSettleDelay : TimeSpan.Zero;
        // Quick Access is excluded from capture where Windows supports it (10 2004+) and stays up, like the Mac's
        // previews; elsewhere it would be in the shot, so it goes.
        if (_quickAccess is { ExcludedFromCapture: false } preview)
        {
            preview.Close();
            wait = ClearScreenDelay;
        }
        if (await _notifier.HideRecentAsync()) wait = ClearScreenDelay;
        if (wait > TimeSpan.Zero) await Task.Delay(wait);
    }

    /// <summary>After-capture actions from Settings: copy, save (with toast) and Quick Access.</summary>
    private async Task FinishAsync(CaptureResult result)
    {
        _settings = SettingsStore.Load(); // picks up edits to settings.json without a restart
        var bitmap = result.Bitmap;
        try
        {
            if (_settings.CopyToClipboard) await TryAsync("Copy failed", () => _output.CopyAsync(bitmap));
            if (_settings.SaveToFile) await TryAsync("Save failed", () => SaveAndNotifyAsync(bitmap));
            if (_settings.ShowQuickAccess)
            {
                _quickAccess?.Close();
                var copy = Windows.Graphics.Imaging.SoftwareBitmap.Copy(bitmap);
                var source = result.ScreenRect;
                var window = new QuickAccessWindow(copy, _settings.QuickAccessSeconds,
                    b => _output.CopyAsync(b), b => SaveAndNotifyAsync(b), b => OpenEditor(b, source));
                _quickAccess = window;
                window.Closed += (_, _) => { if (ReferenceEquals(_quickAccess, window)) _quickAccess = null; };
                window.ShowInCorner();
            }
        }
        finally
        {
            // Quick Access works on its own copy, so the capture's bitmap is always ours to release.
            bitmap.Dispose();
        }
    }

    /// <summary>Opens an editor on a copy of <paramref name="bitmap"/>, on the display it was captured from.</summary>
    private void OpenEditor(Windows.Graphics.Imaging.SoftwareBitmap bitmap, Windows.Graphics.RectInt32 source)
    {
        var image = BgraImage.FromSoftwareBitmap(bitmap, bitmap.PixelWidth, bitmap.PixelHeight);
        var editor = new EditorWindow(image, source, b => _output.CopyAsync(b), b => SaveAndNotifyAsync(b));
        _editors.Add(editor);
        editor.Closed += (_, _) => _editors.Remove(editor);
        editor.ShowNearSource();
    }

    private async Task SaveAndNotifyAsync(Windows.Graphics.Imaging.SoftwareBitmap bitmap)
    {
        var path = await _output.SaveAsync(bitmap, _settings);
        _notifier.Show("Screenshot saved", "Saved to " + path, path);
    }

    private async Task TryAsync(string failureTitle, Func<Task> action)
    {
        try { await action(); }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: {failureTitle}: {e}");
            _notifier.Show(failureTitle, e.Message);
        }
    }

    private void Quit()
    {
        Dispose();
        _notifier.Unregister();
        Application.Current.Exit();
    }

    public void Dispose()
    {
        _hotkeys?.Dispose();
        _hotkeys = null;
        _tray?.Dispose();
        _tray = null;
        _window?.Dispose();
        _window = null;
        _quickAccess?.Close();
        _quickAccess = null;
        _editors.Clear();
    }
}
