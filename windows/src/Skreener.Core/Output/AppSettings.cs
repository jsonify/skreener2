using System.Text.Json;
using System.Text.Json.Serialization;

namespace Skreener.Core.Output;

/// <summary>User settings, stored as JSON in %APPDATA%\Skreener\settings.json. Pure (de)serialization; the app does the file I/O.</summary>
public sealed class AppSettings
{
    /// <summary>Folder for saved screenshots; null or empty means <c>Pictures\Skreener</c> (see <see cref="ResolveSaveFolder"/>).</summary>
    public string? SaveFolder { get; set; }
    public ImageFormat ImageFormat { get; set; } = ImageFormat.Png;
    public string FilenameTemplate { get; set; } = FileNaming.DefaultTemplate;

    // After-capture actions (same defaults as the Mac app).
    public bool CopyToClipboard { get; set; } = true;
    public bool SaveToFile { get; set; } = true;
    public bool ShowQuickAccess { get; set; } = true;
    public int QuickAccessSeconds { get; set; } = 6;

    /// <summary>Hotkeys as text ("Ctrl+Alt+4"); a missing or unparsable entry falls back to the default. See <see cref="GetHotkey"/>.</summary>
    public Dictionary<HotkeyAction, string> Hotkeys { get; set; } = new();

    public string ResolveSaveFolder(string picturesFolder) =>
        string.IsNullOrWhiteSpace(SaveFolder) ? Path.Combine(picturesFolder, "Skreener") : SaveFolder;

    public HotkeyBinding GetHotkey(HotkeyAction action) =>
        Hotkeys.TryGetValue(action, out var text) && HotkeyBinding.TryParse(text, out var b) ? b : HotkeyBinding.Defaults[action];

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public string ToJson() => JsonSerializer.Serialize(this, Options);

    /// <summary>Settings from JSON; anything missing, invalid or out of range falls back to its default, and unreadable JSON gives all defaults.</summary>
    public static AppSettings FromJson(string? json)
    {
        AppSettings? s = null;
        if (!string.IsNullOrWhiteSpace(json))
        {
            try { s = JsonSerializer.Deserialize<AppSettings>(json, Options); }
            catch (JsonException) { }
            catch (NotSupportedException) { }
        }
        s ??= new AppSettings();
        s.Hotkeys ??= new();
        if (!Enum.IsDefined(s.ImageFormat)) s.ImageFormat = ImageFormat.Png;
        if (string.IsNullOrWhiteSpace(s.FilenameTemplate)) s.FilenameTemplate = FileNaming.DefaultTemplate;
        if (s.QuickAccessSeconds is < 1 or > 60) s.QuickAccessSeconds = 6;
        return s;
    }
}
