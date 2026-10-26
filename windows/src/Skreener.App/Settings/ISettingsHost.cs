using Skreener.Core.Output;

namespace Skreener.App.Settings;

/// <summary>What the Settings window needs from the shell: the settings file and the global hotkeys.</summary>
internal interface ISettingsHost
{
    /// <summary>The settings from disk (defaults when the file is missing or broken).</summary>
    AppSettings Load();

    /// <summary>Writes the settings file and makes the shell use these settings from now on.</summary>
    void Save(AppSettings settings);

    /// <summary>Registers the hotkeys from <paramref name="settings"/> in place of the current ones. Returns the actions whose combination another app owns.</summary>
    IReadOnlyList<HotkeyAction> ApplyHotkeys(AppSettings settings);

    /// <summary>Unregisters every hotkey (while a shortcut is being recorded, so pressing one does not trigger it).</summary>
    void SuspendHotkeys();
}
