using System.Diagnostics;
using Skreener.App.Capture;
using Skreener.App.Ocr;

namespace Skreener.App.Shell;

/// <summary>Capture Text (OCR): its tray menu item and hotkey (Ctrl+Alt+2) call <see cref="CaptureTextAsync"/>.</summary>
internal sealed partial class ShellController
{
    /// <summary>The open scratch pad, if any; a new Capture Text reuses it, like the Mac's.</summary>
    private TextScratchPadWindow? _scratchPad;

    /// <summary>
    /// Area selection, then OCR on the captured pixels, then the scratch pad. The capture itself is not saved, copied as
    /// an image or shown in Quick Access. Same guard and screen clearing as <see cref="RunCaptureAsync"/>.
    /// </summary>
    private async Task CaptureTextAsync(bool fromMenu = false)
    {
        if (_capturing) return;
        _capturing = true;
        try
        {
            await ClearScreenAsync(fromMenu);
            var result = await _capture.CaptureAsync(CaptureKind.Area);
            if (result is null) return;
            using var bitmap = result.Bitmap;

            var engine = TextRecognizer.CreateEngine();
            if (engine is null)
            {
                _notifier.Show("No OCR language installed",
                    "Add a language in Settings > Time & Language > Language & region, then try again.");
                return;
            }

            var text = await TextRecognizer.RecognizeAsync(engine, bitmap);
            if (string.IsNullOrWhiteSpace(text))
            {
                _notifier.Show("No text found", "Skreener could not read any text in that area.");
                return;
            }
            ShowScratchPad(text);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: capture text failed: {e}");
            _notifier.Show("Capture Text failed", e.Message);
        }
        finally
        {
            _capturing = false;
        }
    }

    private void ShowScratchPad(string text)
    {
        if (_scratchPad is null)
        {
            var pad = new TextScratchPadWindow(lines =>
                _notifier.Show(lines == 1 ? "Copied 1 line of text" : $"Copied {lines} lines of text", "The text is on the clipboard."));
            _scratchPad = pad;
            pad.Closed += (_, _) => { if (ReferenceEquals(_scratchPad, pad)) _scratchPad = null; };
        }
        _scratchPad.Present(text);
    }
}
