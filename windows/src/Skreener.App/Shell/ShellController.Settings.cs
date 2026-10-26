namespace Skreener.App.Shell;

/// <summary>The Settings window: the tray menu's Settings… item calls <see cref="OpenSettings"/>.</summary>
internal sealed partial class ShellController
{
    /// <summary>Placeholder until the Settings window lands: points to the settings file.</summary>
    private void OpenSettings() =>
        _notifier.Show("Settings window is coming soon", "For now, edit " + SettingsStore.FilePath + ".");
}
