using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Skreener.Core.Colors;
using Skreener.Core.Editor;

namespace Skreener.App.Editor;

/// <summary>
/// The editor's style bar (the attributes bar in EditorWindow.swift): the options of the selected annotation, or of
/// the current tool when nothing is selected. Colors where a color shows, line width for strokes, font size and bold
/// for text (font size alone for counters), block size for pixelate, strength for blur. It edits nothing itself: each
/// pick is raised as a change to apply to the style it shows.
/// </summary>
internal sealed class StyleBar
{
    /// <summary>Preset colors (the Mac's color pill presets): red, orange, yellow, green, blue, purple, black, white.</summary>
    private static readonly RgbColor[] Presets =
    {
        RgbColor.FromBytes(255, 59, 48), RgbColor.FromBytes(255, 149, 0), RgbColor.FromBytes(255, 204, 0),
        RgbColor.FromBytes(52, 199, 89), RgbColor.FromBytes(0, 122, 255), RgbColor.FromBytes(175, 82, 222),
        RgbColor.FromBytes(0, 0, 0), RgbColor.FromBytes(255, 255, 255),
    };
    private static readonly double[] LineWidths = { 2, 4, 6, 8, 12, 16 };
    private static readonly int[] PixelSizes = { 6, 10, 16, 24 };
    private static readonly double[] FontSizes = { 14, 18, 22, 28, 36, 48 };
    /// <summary>Blur strengths (the Mac's Strength popup: Light, Medium, Strong, Heavy) as Gaussian radii.</summary>
    private static readonly (string Label, int Radius)[] BlurStrengths = { ("Light", 6), ("Medium", 10), ("Strong", 18), ("Heavy", 28) };

    private readonly List<(Button Button, RgbColor Color)> _colorButtons = new();
    private readonly StackPanel _colorPanel = new() { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
    private readonly ComboBox _widthBox = new();
    private readonly ComboBox _pixelBox = new();
    private readonly ComboBox _fontSizeBox = new();
    private readonly ComboBox _blurBox = new();
    private readonly ToggleButton _boldButton = new()
    {
        Content = "B",
        FontWeight = Microsoft.UI.Text.FontWeights.Bold,
        AllowFocusOnInteraction = false,
        Padding = new Thickness(10, 4, 10, 4),
    };
    private readonly TextBlock _cropHint = new()
    {
        Text = "Drag the handles or sides to choose the area. Enter applies, Esc cancels.",
        VerticalAlignment = VerticalAlignment.Center,
        Opacity = 0.8,
    };
    private bool _syncing;

    /// <summary>A pick: the change to make to the style the bar shows.</summary>
    public event Action<Func<AnnotationStyle, AnnotationStyle>>? Changed;

    public FrameworkElement Element { get; }

    public StyleBar()
    {
        foreach (var color in Presets)
        {
            var swatch = new Border
            {
                Width = 16,
                Height = 16,
                CornerRadius = new CornerRadius(8),
                Background = new SolidColorBrush(AnnotationRenderer.ToColor(color)),
                BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(0x60, 0x80, 0x80, 0x80)),
                BorderThickness = new Thickness(1),
            };
            var button = new Button
            {
                Content = swatch,
                Padding = new Thickness(3),
                MinWidth = 0,
                AllowFocusOnInteraction = false,
                Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0)),
                BorderThickness = new Thickness(2),
                CornerRadius = new CornerRadius(12),
            };
            button.Click += (_, _) => Changed?.Invoke(s => s with { Color = color });
            _colorButtons.Add((button, color));
            _colorPanel.Children.Add(button);
        }

        Setup(_widthBox, LineWidths.Select(w => $"{w:0} px"), "Line width", i => s => s with { LineWidth = LineWidths[i] });
        Setup(_pixelBox, PixelSizes.Select(p => $"Blocks {p} px"), "Pixelate block size", i => s => s with { PixelSize = PixelSizes[i] });
        Setup(_fontSizeBox, FontSizes.Select(f => $"{f:0} px"), "Font size", i => s => s with { FontSize = FontSizes[i] });
        Setup(_blurBox, BlurStrengths.Select(b => $"Blur: {b.Label}"), "Blur strength", i => s => s with { BlurRadius = BlurStrengths[i].Radius });
        _boldButton.Click += (_, _) =>
        {
            if (!_syncing) Changed?.Invoke(s => s with { Bold = _boldButton.IsChecked == true });
        };
        ToolTipService.SetToolTip(_boldButton, "Bold");

        Element = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Children = { _colorPanel, _widthBox, _fontSizeBox, _boldButton, _pixelBox, _blurBox, _cropHint },
        };
    }

    private void Setup(ComboBox box, IEnumerable<string> labels, string tip, Func<int, Func<AnnotationStyle, AnnotationStyle>> change)
    {
        foreach (var label in labels) box.Items.Add(label);
        box.SelectionChanged += (_, _) =>
        {
            if (_syncing || box.SelectedIndex < 0) return;
            Changed?.Invoke(change(box.SelectedIndex));
        };
        ToolTipService.SetToolTip(box, tip);
    }

    /// <summary>
    /// Shows the options for <paramref name="kind"/> (null: nothing selected and the Select tool, which shows colors
    /// and width) set to <paramref name="style"/>; in crop mode only a hint.
    /// </summary>
    public void Sync(AnnotationKind? kind, AnnotationStyle style, bool cropping)
    {
        bool obscures = kind is AnnotationKind.Pixelate or AnnotationKind.Blur;
        bool stroke = kind is null or AnnotationKind.Arrow or AnnotationKind.Rectangle or AnnotationKind.Ellipse
            or AnnotationKind.Line or AnnotationKind.Pen or AnnotationKind.Highlighter;
        Show(_colorPanel, !cropping && !obscures);
        Show(_widthBox, !cropping && stroke);
        Show(_fontSizeBox, !cropping && kind is AnnotationKind.Text or AnnotationKind.Counter);
        Show(_boldButton, !cropping && kind == AnnotationKind.Text);
        Show(_pixelBox, !cropping && kind == AnnotationKind.Pixelate);
        Show(_blurBox, !cropping && kind == AnnotationKind.Blur);
        Show(_cropHint, cropping);

        _syncing = true;
        try
        {
            _widthBox.SelectedIndex = Array.IndexOf(LineWidths, style.LineWidth);
            _pixelBox.SelectedIndex = Array.IndexOf(PixelSizes, style.PixelSize);
            _fontSizeBox.SelectedIndex = Array.IndexOf(FontSizes, style.FontSize);
            _blurBox.SelectedIndex = Array.FindIndex(BlurStrengths, b => b.Radius == style.BlurRadius);
            _boldButton.IsChecked = style.Bold;
        }
        finally
        {
            _syncing = false;
        }
        var ring = (Brush?)(Application.Current.Resources.TryGetValue("AccentFillColorDefaultBrush", out var b) ? b as Brush : null)
            ?? new SolidColorBrush(EditorOverlay.HandleStroke);
        var none = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
        foreach (var (button, color) in _colorButtons) button.BorderBrush = color == style.Color ? ring : none;
    }

    private static void Show(UIElement e, bool visible) => e.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
}
