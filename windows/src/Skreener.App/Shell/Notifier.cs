using System.Diagnostics;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Skreener.App.Shell;

/// <summary>Toast notifications (port of the toast half of Notifier.swift). Clicking a toast that carries a file opens its folder.</summary>
internal sealed class Notifier
{
    /// <summary>
    /// How long after showing a toast its banner may still be on screen: about 7 s by default, longer while the pointer
    /// rests on it or with a longer "show notifications for" setting. Generous on purpose: hiding is cheap.
    /// </summary>
    private static readonly TimeSpan BannerLifetime = TimeSpan.FromSeconds(30);

    private bool _registered;
    private DateTime _lastShownUtc = DateTime.MinValue;

    /// <summary>Registers for toasts; call once at startup. Toasts are skipped (not fatal) when registration fails.</summary>
    public void Register()
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += OnInvoked;
            AppNotificationManager.Default.Register();
            _registered = true;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: toast registration failed: {e.Message}");
        }
    }

    public void Unregister()
    {
        if (!_registered) return;
        try { AppNotificationManager.Default.Unregister(); }
        catch (Exception e) { Debug.WriteLine($"Skreener: toast unregister failed: {e.Message}"); }
    }

    /// <param name="path">Optional file; clicking the toast shows it in Explorer.</param>
    public void Show(string title, string text, string? path = null)
    {
        if (!_registered) return;
        try
        {
            var builder = new AppNotificationBuilder().AddText(title).AddText(text);
            if (path is not null) builder.AddArgument("path", path);
            AppNotificationManager.Default.Show(builder.BuildNotification());
            _lastShownUtc = DateTime.UtcNow;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: toast failed: {e.Message}");
        }
    }

    /// <summary>
    /// Takes Skreener's toasts off the screen before a capture, so a banner never ends up in the screenshot (toasts
    /// belong to the shell, so they cannot be excluded from capture like our own windows). Removes them from the
    /// notification centre too. Returns whether a banner may have been showing, i.e. whether to let it animate away.
    /// </summary>
    public async Task<bool> HideRecentAsync()
    {
        if (!_registered || DateTime.UtcNow - _lastShownUtc > BannerLifetime) return false;
        _lastShownUtc = DateTime.MinValue;
        try
        {
            await AppNotificationManager.Default.RemoveAllAsync();
            return true;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: could not hide toasts: {e.Message}");
            return false;
        }
    }

    // Runs on a background thread.
    private static void OnInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
    {
        if (args.Arguments.TryGetValue("path", out var path)) Explorer.Reveal(path);
    }
}

internal static class Explorer
{
    /// <summary>Opens Explorer with the file selected, or just opens the folder when the path is a directory.</summary>
    public static void Reveal(string path)
    {
        try
        {
            var arguments = Directory.Exists(path) ? $"\"{path}\"" : $"/select,\"{path}\"";
            Process.Start(new ProcessStartInfo("explorer.exe", arguments) { UseShellExecute = false });
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: could not open Explorer: {e.Message}");
        }
    }
}
