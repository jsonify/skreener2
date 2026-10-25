using System.Diagnostics;
using Skreener.Core.Output;

namespace Skreener.App.Shell;

/// <summary>Reads and writes %APPDATA%\Skreener\settings.json. The format and defaults live in Skreener.Core.</summary>
internal static class SettingsStore
{
    public static string FilePath { get; } =
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Skreener", "settings.json");

    public static string PicturesFolder => Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);

    /// <summary>Loads the settings (defaults when the file is missing or broken). Writes the defaults on first run so the file can be edited.</summary>
    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath)) return AppSettings.FromJson(File.ReadAllText(FilePath));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Skreener: could not read settings: {e.Message}");
            return new AppSettings();
        }

        var defaults = new AppSettings();
        Save(defaults);
        return defaults;
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(FilePath)!);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, settings.ToJson());
            File.Move(temp, FilePath, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Skreener: could not save settings: {e.Message}");
        }
    }
}
