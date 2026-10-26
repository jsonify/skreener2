namespace Skreener.App.Shell;

/// <summary>Capture Text (OCR): its tray menu item and hotkey (Ctrl+Alt+2) call <see cref="CaptureTextAsync"/>.</summary>
internal sealed partial class ShellController
{
    /// <summary>Placeholder until Capture Text lands: says it is coming instead of doing nothing.</summary>
    private Task CaptureTextAsync(bool fromMenu = false)
    {
        _notifier.Show("Capture Text is coming soon", "Recognizing text in a captured area is not in this build yet.");
        return Task.CompletedTask;
    }
}
