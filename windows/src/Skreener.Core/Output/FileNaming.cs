using System.Globalization;
using System.Text;

namespace Skreener.Core.Output;

/// <summary>Saved-file names: port of the naming half of Output.swift.</summary>
public static class FileNaming
{
    public const string DefaultTemplate = "Skreener %Y-%m-%d at %H.%M.%S";

    private const string ForbiddenOnWindows = "\\/?*\"<>|";

    /// <summary>
    /// File name (without extension) from the template. Tokens: %Y %y %m %d %H %M %S, %% for a percent sign.
    /// Unknown tokens and a trailing % are kept as typed.
    /// </summary>
    public static string Filename(DateTime date, string template)
    {
        var sb = new StringBuilder();
        for (var i = 0; i < template.Length; i++)
        {
            var c = template[i];
            if (c != '%' || i + 1 >= template.Length)
            {
                sb.Append(c);
                continue;
            }
            var token = template[++i];
            var pattern = token switch
            {
                'Y' => "yyyy",
                'y' => "yy",
                'm' => "MM",
                'd' => "dd",
                'H' => "HH",
                'M' => "mm",
                'S' => "ss",
                _ => null,
            };
            if (pattern != null) sb.Append(date.ToString(pattern, CultureInfo.InvariantCulture));
            else if (token == '%') sb.Append('%');
            else sb.Append(c).Append(token);
        }

        // Path separators and characters Windows forbids in file names; ":" becomes "." as on the Mac.
        var cleaned = new StringBuilder();
        foreach (var ch in sb.ToString())
        {
            if (ch == ':') cleaned.Append('.');
            else if (ForbiddenOnWindows.Contains(ch) || char.IsControl(ch)) cleaned.Append('-');
            else cleaned.Append(ch);
        }

        // Windows silently drops trailing dots and spaces.
        var name = cleaned.ToString().Trim().TrimEnd('.', ' ');
        if (name.Length == 0) return "Skreener";
        return name.StartsWith('.') ? "Skreener " + name : name; // a leading dot would hide the file
    }

    /// <summary>
    /// <c>name.ext</c>, or <c>name 2.ext</c>, <c>name 3.ext</c>... when that file already exists (a template without seconds).
    /// <paramref name="exists"/> answers for a full path; defaults to the file system.
    /// </summary>
    public static string UniquePath(string directory, string name, string extension, Func<string, bool>? exists = null)
    {
        exists ??= File.Exists;
        var path = Path.Combine(directory, name + "." + extension);
        for (var n = 2; exists(path); n++)
            path = Path.Combine(directory, $"{name} {n}.{extension}");
        return path;
    }
}
