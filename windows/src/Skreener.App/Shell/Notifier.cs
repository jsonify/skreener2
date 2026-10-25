using System.Diagnostics;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Skreener.App.Shell;

/// <summary>Toast notifications (port of the toast half of Notifier.swift). Clicking a toast that carries a file opens its folder.</summary>
internal sealed class Notifier
{
    private bool _registered;

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
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: toast failed: {e.Message}");
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
