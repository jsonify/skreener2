using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Windows.System;
using Windows.Win32;

namespace Skreener.App.Editor;

/// <summary>
/// Typing a text label in place (InlineTextView and startEditor / layoutEditor in AnnotationEditor.swift): a
/// borderless, transparent WinUI <see cref="TextBox"/> laid over the canvas exactly where the label is, in its font and
/// color at the current zoom. The canvas leaves that label out while it is typed, so only the text box shows it.
/// Esc and Ctrl+Enter finish (Enter starts a new line); the window finishes on a click outside.
/// </summary>
internal sealed class TextEditOverlay
{
    private readonly Canvas _host;
    private readonly Action<string> _textChanged;
    private readonly Action _finish;
    private TextBox? _box;
    private int _id;
    private Windows.UI.Color _color;
    private bool _syncing;

    /// <param name="host">The panel over the canvas the text box goes in (same size and position as the canvas).</param>
    /// <param name="textChanged">The text typed so far, with line breaks as <c>\n</c>.</param>
    /// <param name="finish">Esc or Ctrl+Enter.</param>
    public TextEditOverlay(Canvas host, Action<string> textChanged, Action finish)
    {
        _host = host;
        _textChanged = textChanged;
        _finish = finish;
    }

    public bool IsShown => _box is not null;

    /// <summary>
    /// Shows the text box for <paramref name="a"/> with its top-left corner at <paramref name="topLeft"/> (view DIPs)
    /// and its font scaled by <paramref name="zoom"/> (DIPs per image pixel), or moves and restyles the one already
    /// shown. A new label (or a new color, which the text box only takes when it is made) makes a new text box.
    /// </summary>
    public void Show(Annotation a, PointD topLeft, double zoom)
    {
        var color = AnnotationRenderer.ToColor(a.Style.Color);
        if (_box is null || _id != a.Id || color != _color)
        {
            var caret = _box?.SelectionStart;
            Hide();
            _id = a.Id;
            _color = color;
            _box = Make(color);
            _syncing = true;
            _box.Text = a.Text;
            _syncing = false;
            _box.SelectionStart = Math.Min(caret ?? _box.Text.Length, _box.Text.Length);
            _host.Children.Add(_box);
            _box.Loaded += (s, _) => ((TextBox)s).Focus(FocusState.Programmatic);
        }
        var box = _box;
        box.FontSize = Math.Max(a.Style.FontSize * zoom, 1);
        box.FontWeight = TextMetrics.Weight(a.Style.Bold);
        // A little wider than the text, so the caret after the last character is never cut off.
        var width = a.Rect.Width * zoom + Math.Max(box.FontSize, 8);
        box.Width = width + 2 * BorderWidth;
        box.MinHeight = a.Rect.Height * zoom + 2 * BorderWidth;
        // The border sits outside the text, so the text lands exactly on the label's corner.
        Canvas.SetLeft(box, topLeft.X - BorderWidth);
        Canvas.SetTop(box, topLeft.Y - BorderWidth);
    }

    /// <summary>Removes the text box (typing ended).</summary>
    public void Hide()
    {
        if (_box is null) return;
        _box.TextChanged -= OnTextChanged;
        _box.PreviewKeyDown -= OnPreviewKeyDown;
        _host.Children.Remove(_box);
        _box = null;
    }

    /// <summary>Gives the text box the keyboard focus back (after a pick in the style bar).</summary>
    public void Focus() => _box?.Focus(FocusState.Programmatic);

    private const double BorderWidth = 1;

    private TextBox Make(Windows.UI.Color color)
    {
        var box = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.NoWrap,
            IsSpellCheckEnabled = false,
            IsTextPredictionEnabled = false,
            FontFamily = new FontFamily(TextMetrics.FontFamily),
            Padding = new Thickness(0),
            MinWidth = 0,
            BorderThickness = new Thickness(BorderWidth),
            CornerRadius = new CornerRadius(2),
        };
        // Lightweight styling: the template's states take these, so the box stays clear with the label's color
        // and an accent frame (like the Mac's) whether or not it has the focus or the pointer.
        var clear = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
        var ink = new SolidColorBrush(color);
        var frame = Application.Current.Resources.TryGetValue("AccentFillColorDefaultBrush", out var b) && b is Brush accent
            ? accent
            : new SolidColorBrush(EditorOverlay.HandleStroke);
        foreach (var state in new[] { "", "PointerOver", "Focused", "Disabled" })
        {
            box.Resources["TextControlBackground" + state] = clear;
            box.Resources["TextControlForeground" + state] = ink;
            box.Resources["TextControlBorderBrush" + state] = frame;
        }
        box.Resources["TextControlBorderThemeThicknessFocused"] = new Thickness(BorderWidth);
        box.Foreground = ink;
        box.TextChanged += OnTextChanged;
        box.PreviewKeyDown += OnPreviewKeyDown;
        return box;
    }

    private void OnTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_syncing || sender is not TextBox box) return;
        // TextBox keeps line breaks as \r; the labels use \n.
        _textChanged(box.Text.Replace("\r\n", "\n").Replace('\r', '\n'));
    }

    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        bool ctrl = PInvoke.GetKeyState((int)VirtualKey.Control) < 0;
        if (e.Key == VirtualKey.Escape || (e.Key == VirtualKey.Enter && ctrl))
        {
            e.Handled = true;
            _finish();
        }
    }
}
