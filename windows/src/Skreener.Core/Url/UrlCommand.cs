using System.Globalization;
using Skreener.Core.Shortcuts;

namespace Skreener.Core.Url;

/// <summary>
/// What happens to a capture afterwards. Settings, After Capture gives the usual set; a skreener:// link can pick its
/// own with <c>then=</c>. The Swift <c>fromPreferences</c> reads macOS Preferences and is not ported.
/// </summary>
[Flags]
public enum CaptureActions
{
    None = 0,
    Copy = 1 << 0,
    Save = 1 << 1,
    Edit = 1 << 2,
    Pin = 1 << 3,
    QuickAccess = 1 << 4,
}

public static class CaptureActionNames
{
    /// <summary>Names for <c>then=</c>, in the order error messages list them.</summary>
    public static IReadOnlyList<(string Name, CaptureActions Action)> All { get; } = new[]
    {
        ("copy", CaptureActions.Copy), ("save", CaptureActions.Save), ("edit", CaptureActions.Edit),
        ("pin", CaptureActions.Pin), ("quickaccess", CaptureActions.QuickAccess),
    };
}

/// <summary>What a link runs: a shortcut action, or the settings window (Swift's <c>URLCommand.Command</c>).</summary>
public readonly record struct CommandTarget(HotKeyAction? Action)
{
    public static CommandTarget Settings => new(null);
    public static CommandTarget Run(HotKeyAction action) => new(action);
    public bool IsSettings => Action is null;
}

/// <summary>
/// A skreener:// link, for launchers, automation and scripts: <c>skreener://grab/area?then=copy,save</c>,
/// <c>skreener://grab/delayed/window?delay=10</c>, <c>skreener://settings</c>. <c>capture/…</c> works as well as
/// <c>grab/…</c>.
/// </summary>
/// <param name="Command">What to run.</param>
/// <param name="Then">After-capture steps for this capture only (null: the After Capture settings).</param>
/// <param name="Delay">Self-timer seconds for this capture only (null: the Self-Timer menu's delay).</param>
public sealed record UrlCommand(CommandTarget Command, CaptureActions? Then = null, int? Delay = null)
{
    public const string Scheme = "skreener";
    public const int MinDelay = 1;
    public const int MaxDelay = 60;

    private static CommandTarget Run(HotKeyAction a) => CommandTarget.Run(a);

    /// <summary>Every command, as written after <c>skreener://</c>.</summary>
    public static IReadOnlyList<(string Path, CommandTarget Command)> Commands { get; } = new[]
    {
        ("grab/area", Run(HotKeyAction.CaptureArea)),
        ("grab/previous", Run(HotKeyAction.CapturePreviousArea)),
        ("grab/fullscreen", Run(HotKeyAction.CaptureFullscreen)),
        ("grab/window", Run(HotKeyAction.CaptureWindow)),
        ("grab/window/active", Run(HotKeyAction.CaptureActiveWindow)),
        ("grab/scrolling", Run(HotKeyAction.CaptureScrolling)),
        ("grab/delayed", Run(HotKeyAction.TimedArea)),
        ("grab/delayed/area", Run(HotKeyAction.TimedArea)),
        ("grab/delayed/window", Run(HotKeyAction.TimedWindow)),
        ("grab/delayed/fullscreen", Run(HotKeyAction.TimedFullscreen)),
        ("ocr", Run(HotKeyAction.CaptureText)),
        ("record", Run(HotKeyAction.RecordScreen)),
        ("load/clipboard", Run(HotKeyAction.OpenClipboard)),
        ("load/file", Run(HotKeyAction.OpenFile)),
        ("pin/clipboard", Run(HotKeyAction.PinClipboard)),
        ("pin/file", Run(HotKeyAction.PinFile)),
        ("history", Run(HotKeyAction.ShowHistory)),
        ("settings", CommandTarget.Settings),
    };

    /// <summary>Commands whose screenshot goes through the after-capture steps, so <c>then=</c> applies.</summary>
    private static readonly HashSet<HotKeyAction> TakesThen = new()
    {
        HotKeyAction.CaptureArea, HotKeyAction.CapturePreviousArea, HotKeyAction.CaptureFullscreen,
        HotKeyAction.CaptureWindow, HotKeyAction.CaptureActiveWindow, HotKeyAction.CaptureScrolling,
        HotKeyAction.TimedArea, HotKeyAction.TimedWindow, HotKeyAction.TimedFullscreen,
    };

    private static readonly HashSet<HotKeyAction> TakesDelay = new()
    {
        HotKeyAction.TimedArea, HotKeyAction.TimedWindow, HotKeyAction.TimedFullscreen,
    };

    /// <summary>What the command does, for alerts.</summary>
    public string Title => Command.Action is { } action ? action.Title() : "Settings";

    /// <summary>
    /// Reads a link. The Swift version takes a Foundation <c>URL</c>; this one takes the text, since System.Uri does not
    /// read <c>skreener:grab/area</c> (no slashes) or <c>SKREENER://Grab/Window/</c> the way URLComponents does. Text with
    /// no scheme at all is a wrong scheme.
    /// </summary>
    public static UrlParseResult Parse(string url)
    {
        var parts = SplitUrl(url);
        if (parts is null || !string.Equals(parts.Scheme, Scheme, StringComparison.OrdinalIgnoreCase))
            return UrlParseResult.Failure(UrlCommandError.WrongScheme);
        // skreener://grab/area has host "grab" and path "/area"; skreener:grab/area has only a path.
        var segments = new List<string> { parts.Host }
            .Concat(parts.Path.Split('/', StringSplitOptions.RemoveEmptyEntries))
            .Select(s => s.ToLowerInvariant()).Where(s => s.Length > 0);
        string path = string.Join("/", segments);
        if (path.StartsWith("capture/", StringComparison.Ordinal)) path = "grab/" + path["capture/".Length..];
        CommandTarget? found = null;
        foreach (var (p, c) in Commands) if (p == path) { found = c; break; }
        if (found is not { } command) return UrlParseResult.Failure(UrlCommandError.UnknownCommand(path));
        var result = new UrlCommand(command);
        HotKeyAction? action = command.Action;
        foreach (var (itemName, itemValue) in parts.Query)
        {
            string value = itemValue ?? "";
            switch (itemName.ToLowerInvariant())
            {
                case "then":
                {
                    if (action is not { } a || !TakesThen.Contains(a)) return UrlParseResult.Failure(UrlCommandError.ThenNotAllowed(path));
                    var then = CaptureActions.None;
                    foreach (var piece in value.ToLowerInvariant().Split(','))
                    {
                        string name = TrimWhitespace(piece);
                        CaptureActions? named = null;
                        foreach (var (n, act) in CaptureActionNames.All) if (n == name) { named = act; break; }
                        if (named is not { } flag) return UrlParseResult.Failure(UrlCommandError.BadThen(name));
                        then |= flag;
                    }
                    result = result with { Then = then };
                    break;
                }
                case "delay":
                {
                    if (action is not { } a || !TakesDelay.Contains(a)) return UrlParseResult.Failure(UrlCommandError.DelayNotAllowed(path));
                    // Swift's Int(_:) takes an optional sign and digits, nothing else.
                    if (!int.TryParse(value, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out int s) || s < MinDelay || s > MaxDelay)
                        return UrlParseResult.Failure(UrlCommandError.BadDelay(value));
                    result = result with { Delay = s };
                    break;
                }
                default:
                    return UrlParseResult.Failure(UrlCommandError.UnknownParameter(itemName));
            }
        }
        return UrlParseResult.Success(result);
    }

    /// <summary>Foundation's <c>.whitespaces</c>: spaces and tabs, but not line breaks.</summary>
    private static string TrimWhitespace(string s)
    {
        static bool IsWhitespace(char c) => c == '\t' || char.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;
        int start = 0, end = s.Length;
        while (start < end && IsWhitespace(s[start])) start++;
        while (end > start && IsWhitespace(s[end - 1])) end--;
        return s[start..end];
    }

    private sealed record UrlParts(string Scheme, string Host, string Path, List<(string Name, string? Value)> Query);

    /// <summary>The pieces URLComponents would give: scheme, host (empty when there is none), percent-decoded path and query items.</summary>
    private static UrlParts? SplitUrl(string url)
    {
        int colon = url.IndexOf(':');
        if (colon <= 0) return null;
        string scheme = url[..colon];
        string rest = url[(colon + 1)..];
        int hash = rest.IndexOf('#');
        if (hash >= 0) rest = rest[..hash];
        string query = "";
        int q = rest.IndexOf('?');
        if (q >= 0) { query = rest[(q + 1)..]; rest = rest[..q]; }
        string host = "", path = rest;
        if (rest.StartsWith("//", StringComparison.Ordinal))
        {
            int slash = rest.IndexOf('/', 2);
            string authority = slash < 0 ? rest[2..] : rest[2..slash];
            path = slash < 0 ? "" : rest[slash..];
            // Drop user info and port.
            int at = authority.LastIndexOf('@');
            if (at >= 0) authority = authority[(at + 1)..];
            int port = authority.LastIndexOf(':');
            if (port >= 0 && !authority.EndsWith(']')) authority = authority[..port];
            host = Decode(authority);
        }
        var items = new List<(string, string?)>();
        if (query.Length > 0)
        {
            foreach (var item in query.Split('&'))
            {
                int eq = item.IndexOf('=');
                items.Add(eq < 0 ? (Decode(item), null) : (Decode(item[..eq]), Decode(item[(eq + 1)..])));
            }
        }
        return new UrlParts(scheme, host, Decode(path), items);
    }

    private static string Decode(string s) => Uri.UnescapeDataString(s);
}

public enum UrlCommandErrorKind { WrongScheme, UnknownCommand, UnknownParameter, ThenNotAllowed, BadThen, DelayNotAllowed, BadDelay }

/// <summary>Why a link was refused; <see cref="Value"/> is the path, parameter name or option the message is about.</summary>
public readonly record struct UrlCommandError(UrlCommandErrorKind Kind, string Value = "")
{
    public static UrlCommandError WrongScheme => new(UrlCommandErrorKind.WrongScheme);
    public static UrlCommandError UnknownCommand(string path) => new(UrlCommandErrorKind.UnknownCommand, path);
    public static UrlCommandError UnknownParameter(string name) => new(UrlCommandErrorKind.UnknownParameter, name);
    public static UrlCommandError ThenNotAllowed(string path) => new(UrlCommandErrorKind.ThenNotAllowed, path);
    public static UrlCommandError BadThen(string name) => new(UrlCommandErrorKind.BadThen, name);
    public static UrlCommandError DelayNotAllowed(string path) => new(UrlCommandErrorKind.DelayNotAllowed, path);
    public static UrlCommandError BadDelay(string value) => new(UrlCommandErrorKind.BadDelay, value);

    public string Message
    {
        get
        {
            switch (Kind)
            {
                case UrlCommandErrorKind.WrongScheme:
                    return $"Links must start with {UrlCommand.Scheme}://.";
                case UrlCommandErrorKind.UnknownCommand:
                {
                    string list = string.Join(", ", UrlCommand.Commands.Select(c => c.Path));
                    return $"\"{Value}\" is not a command. Available commands: {list} (capture/… works as well as grab/…).";
                }
                case UrlCommandErrorKind.UnknownParameter:
                    return $"Unknown parameter \"{Value}\". Available parameters: then (capture commands), delay (grab/delayed).";
                case UrlCommandErrorKind.ThenNotAllowed:
                    return $"\"{Value}\" does not take a \"then\" parameter; only grab/… commands do.";
                case UrlCommandErrorKind.BadThen:
                {
                    string list = string.Join(", ", CaptureActionNames.All.Select(n => $"\"{n.Name}\""));
                    return $"Unrecognized \"then\" option \"{Value}\". Available options: {list}, or a comma-separated combination.";
                }
                case UrlCommandErrorKind.DelayNotAllowed:
                    return $"\"{Value}\" does not take a \"delay\" parameter; only grab/delayed commands do.";
                case UrlCommandErrorKind.BadDelay:
                    return $"\"{Value}\" is not a valid delay. Use whole seconds from {UrlCommand.MinDelay} to {UrlCommand.MaxDelay}.";
                default:
                    throw new InvalidOperationException();
            }
        }
    }
}

/// <summary>Swift's <c>Result&lt;URLCommand, URLCommandError&gt;</c>.</summary>
public readonly record struct UrlParseResult(UrlCommand? Command, UrlCommandError? Error)
{
    public bool IsSuccess => Command is not null;
    public static UrlParseResult Success(UrlCommand command) => new(command, null);
    public static UrlParseResult Failure(UrlCommandError error) => new(null, error);
}
