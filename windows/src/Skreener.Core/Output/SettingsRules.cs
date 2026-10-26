namespace Skreener.Core.Output;

/// <summary>Rules for the non-shortcut fields of the Settings window: no UI, so they are tested on any OS.</summary>
public static class SettingsRules
{
    public const int MinQuickAccessSeconds = 1, MaxQuickAccessSeconds = 60;

    /// <summary>A number from a box (NaN when it is empty or not a number) as Quick Access seconds: rounded, kept in 1 to 60; <paramref name="fallback"/> for NaN.</summary>
    public static int ClampQuickAccessSeconds(double value, int fallback)
    {
        if (double.IsNaN(value)) return Math.Clamp(fallback, MinQuickAccessSeconds, MaxQuickAccessSeconds);
        return (int)Math.Clamp(Math.Round(value, MidpointRounding.AwayFromZero), MinQuickAccessSeconds, MaxQuickAccessSeconds);
    }

    /// <summary>
    /// What the save-folder box holds as a setting: trimmed, surrounding quotes dropped (as pasted from Explorer's "Copy as
    /// path"), and null (the default <c>Pictures\Skreener</c>) when empty.
    /// </summary>
    public static string? NormalizeFolder(string? text)
    {
        var folder = text?.Trim().Trim('"').Trim();
        return string.IsNullOrEmpty(folder) ? null : folder;
    }

    /// <summary>Why <paramref name="folder"/> cannot be a save folder, or null when it can (a folder that does not exist yet is created on the first save).</summary>
    public static string? FolderProblem(string? folder)
    {
        if (string.IsNullOrWhiteSpace(folder)) return null;
        const string Illegal = "That path contains characters Windows does not allow.";
        if (folder.IndexOfAny(Path.GetInvalidPathChars()) >= 0 || folder.IndexOfAny(new[] { '*', '?', '<', '>', '|', '"' }) >= 0)
            return Illegal;
        // Fully qualified by Windows rules, whatever OS this runs on: "C:\x" or "\\server\share".
        var drive = folder.Length >= 3 && char.IsAsciiLetter(folder[0]) && folder[1] == ':' && (folder[2] == '\\' || folder[2] == '/');
        var unc = folder.StartsWith(@"\\", StringComparison.Ordinal) && folder.Length > 2;
        if (!drive && !unc) return "Use a full path such as C:\\Users\\you\\Pictures\\Skreener.";
        // A colon is only valid right after the drive letter.
        var rest = drive ? folder[2..] : folder;
        if (rest.Contains(':') && !folder.StartsWith(@"\\?\", StringComparison.Ordinal)) return Illegal;
        return null;
    }

    /// <summary>
    /// The file name the next capture would get, e.g. <c>Skreener 2026-10-26 at 14.03.05.png</c>, including the
    /// <c>name 2</c> suffix when that file exists already. <paramref name="exists"/> answers for a full path (file system by default).
    /// </summary>
    public static string NextFileName(AppSettings settings, string picturesFolder, DateTime now, Func<string, bool>? exists = null)
    {
        var template = string.IsNullOrWhiteSpace(settings.FilenameTemplate) ? FileNaming.DefaultTemplate : settings.FilenameTemplate;
        var name = FileNaming.Filename(now, template);
        var path = FileNaming.UniquePath(settings.ResolveSaveFolder(picturesFolder), name, settings.ImageFormat.FileExtension(), exists);
        return Path.GetFileName(path);
    }
}
