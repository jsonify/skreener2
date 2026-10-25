using System.Diagnostics;
using Microsoft.UI.Xaml;
using Skreener.App.Capture;
using Skreener.Core.Output;

namespace Skreener.App.Shell;

/// <summary>
/// Everything around the capture itself: tray icon and menu, global hotkeys, and what happens to a finished capture
/// (clipboard, file, toast, Quick Access). Talks to the capture code only through <see cref="ICaptureService"/>.
/// </summary>
internal sealed class ShellController : IDisposable
{
    private const int CmdArea = 1, CmdWindow = 2, CmdFullscreen = 3, CmdPreviousArea = 4, CmdOpenFolder = 5, CmdLaunchAtLogin = 6, CmdQuit = 7;
    private const string IconRelativePath = "Shell/Assets/tray.ico";

    private readonly ICaptureService _capture;
    private readonly Notifier _notifier;
    private readonly OutputService _output = new();
    private AppSettings _settings;
    private MessageWindow? _window;
    private TrayIcon? _tray;
    private HotkeyManager? _hotkeys;
    private QuickAccessWindow? _quickAccess;
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
            case CmdArea: _ = RunCaptureAsync(CaptureKind.Area); break;
            case CmdWindow: _ = RunCaptureAsync(CaptureKind.Window); break;
            case CmdFullscreen: _ = RunCaptureAsync(CaptureKind.Fullscreen); break;
            case CmdPreviousArea: _ = RunCaptureAsync(CaptureKind.PreviousArea); break;
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

    private async Task RunCaptureAsync(CaptureKind kind)
    {
        if (_capturing) return;
        _capturing = true;
        try
        {
            var result = await _capture.CaptureAsync(kind);
            if (result is not null) await FinishAsync(result);
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
                var window = new QuickAccessWindow(copy, _settings.QuickAccessSeconds,
                    b => _output.CopyAsync(b), b => SaveAndNotifyAsync(b));
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
    }
}
