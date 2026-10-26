using Skreener.App.Settings;
using Skreener.Core.Output;

namespace Skreener.App.Shell;

/// <summary>The Settings window: the tray menu's Settings… item calls <see cref="OpenSettings"/>.</summary>
internal sealed partial class ShellController : ISettingsHost
{
    private SettingsWindow? _settingsWindow;

    /// <summary>Opens the Settings window, or brings the one that is open to the front.</summary>
    private void OpenSettings()
    {
        if (_settingsWindow is not null)
        {
            _settingsWindow.BringToFront();
            return;
        }
        try
        {
            var window = new SettingsWindow(this);
            _settingsWindow = window;
            window.Closed += (_, _) => { if (ReferenceEquals(_settingsWindow, window)) _settingsWindow = null; };
            window.Activate();
        }
        catch (Exception e)
        {
            _settingsWindow = null;
            System.Diagnostics.Debug.WriteLine($"Skreener: could not open Settings: {e}");
            _notifier.Show("Could not open Settings", e.Message);
        }
    }

    AppSettings ISettingsHost.Load() => SettingsStore.Load();

    void ISettingsHost.Save(AppSettings settings)
    {
        SettingsStore.Save(settings);
        _settings = settings; // menu labels and the folder item use it at once; the next capture reloads from disk anyway
    }

    IReadOnlyList<HotkeyAction> ISettingsHost.ApplyHotkeys(AppSettings settings)
    {
        if (_window is null) return Array.Empty<HotkeyAction>();
        _hotkeys?.Dispose(); // the old registrations must go first, or an unchanged combination would collide with itself
        _hotkeys = new HotkeyManager(_window.Handle);
        _hotkeys.RegisterAll(settings);
        return _hotkeys.FailedActions;
    }

    void ISettingsHost.SuspendHotkeys()
    {
        _hotkeys?.Dispose();
        _hotkeys = null;
    }
}
