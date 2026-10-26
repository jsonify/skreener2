using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Text;
using Skreener.Core.Editor;
using Skreener.Core.Geometry;

namespace Skreener.App.Editor;

/// <summary>
/// The text labels' font (the Mac's Style.font: the system font, semibold when bold) as Win2D text formats, and the
/// measurer <see cref="EditorSession.TextMeasurer"/> uses, so the session's text boxes match what the renderer draws.
/// Sizes are image pixels: the renderer draws in image pixels, so a font size in pixels needs no conversion.
/// </summary>
internal static class TextMetrics
{
    /// <summary>The UI font of Windows 10 and 11; TextBox uses it too, so typed and drawn text look alike.</summary>
    public const string FontFamily = "Segoe UI";

    /// <summary>A single-line-per-paragraph format for <paramref name="style"/> (no wrapping, top-left aligned).</summary>
    public static CanvasTextFormat Format(AnnotationStyle style) => new()
    {
        FontFamily = FontFamily,
        FontSize = (float)Math.Max(style.FontSize, 1),
        FontWeight = Weight(style.Bold),
        WordWrapping = CanvasWordWrapping.NoWrap,
    };

    public static Windows.UI.Text.FontWeight Weight(bool bold) =>
        bold ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;

    /// <summary>The text's layout for drawing at its top-left corner. Dispose it after drawing.</summary>
    public static CanvasTextLayout Layout(ICanvasResourceCreator creator, string text, CanvasTextFormat format) =>
        new(creator, text, format, 100_000, 100_000);

    /// <summary>
    /// How big <paramref name="text"/> is in <paramref name="style"/>, in image pixels: at least one line high and
    /// half an em wide, so an empty label being typed still has a box. A trailing line break counts as a line.
    /// </summary>
    public static SizeD Measure(string text, AnnotationStyle style)
    {
        // A line holding only a space is measured for an empty text (one line high) and after a trailing break.
        var measured = text.Length == 0 || text.EndsWith('\n') ? text + " " : text;
        using var format = Format(style);
        using var layout = Layout(CanvasDevice.GetSharedDevice(), measured, format);
        var bounds = layout.LayoutBounds;
        var width = text.Length == 0 ? 0 : bounds.Width;
        return new SizeD(Math.Max(Math.Ceiling(width), Math.Ceiling(style.FontSize * 0.5)), Math.Ceiling(bounds.Height));
    }
}
