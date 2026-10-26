using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Skreener.App.Editor;

/// <summary>
/// The zoom readout in the toolbar (the Mac editor's zoom popup): shows the current percentage, and its menu picks Fit
/// or a fixed zoom.
/// </summary>
internal sealed class ZoomMenu
{
    /// <summary>The menu's fixed zooms, as scales (screen pixels per image pixel).</summary>
    private static readonly double[] Scales = { 0.5, 1, 2, 4 };

    private readonly DropDownButton _button = new() { AllowFocusOnInteraction = false, MinWidth = 76 };

    /// <summary>Fit was picked.</summary>
    public event Action? FitPicked;

    /// <summary>A fixed scale was picked (1 is 100 %).</summary>
    public event Action<double>? ScalePicked;

    public FrameworkElement Element => _button;

    public ZoomMenu()
    {
        var menu = new MenuFlyout();
        var fit = new MenuFlyoutItem { Text = "Fit (Ctrl+0)" };
        fit.Click += (_, _) => FitPicked?.Invoke();
        menu.Items.Add(fit);
        foreach (var scale in Scales)
        {
            var label = $"{scale * 100:0} %" + (scale == 1 ? " (Ctrl+1)" : "");
            var item = new MenuFlyoutItem { Text = label };
            item.Click += (_, _) => ScalePicked?.Invoke(scale);
            menu.Items.Add(item);
        }
        _button.Flyout = menu;
        _button.Content = "100 %";
        ToolTipService.SetToolTip(_button, "Zoom (Ctrl+wheel, Ctrl+= and Ctrl+-)");
    }

    /// <summary>Shows <paramref name="scale"/> as a whole percentage.</summary>
    public void Show(double scale)
    {
        var text = $"{Math.Round(scale * 100):0} %";
        if (_button.Content as string != text) _button.Content = text;
    }
}
