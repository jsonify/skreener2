using System.Diagnostics;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Geometry;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Skreener.App.Capture;
using Skreener.Core.Colors;
using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Windows.Foundation;
using Windows.Graphics;
using Windows.Graphics.Imaging;
using Windows.System;
using Windows.Win32;
using Windows.Win32.Foundation;

namespace Skreener.App.Editor;

/// <summary>
/// The annotation editor (first Windows milestone of AnnotationEditor.swift / EditorWindow.swift): a toolbar with the
/// tools, color and size, undo/redo and Copy/Save, over a Win2D canvas that shows the screenshot fitted to the window
/// (never above 100 %, one image pixel per screen pixel). All editing state lives in Core's
/// <see cref="EditorSession"/>; this window turns pointer and key events into its calls and draws what it holds.
/// </summary>
internal sealed class EditorWindow : Window
{
    private const double CanvasPadding = 16; // DIPs around the image
    private static readonly Windows.UI.Color CanvasBackground = Windows.UI.Color.FromArgb(255, 0x26, 0x26, 0x26);
    private static readonly Windows.UI.Color HandleFill = Windows.UI.Color.FromArgb(255, 255, 255, 255);
    private static readonly Windows.UI.Color HandleStroke = Windows.UI.Color.FromArgb(255, 0x00, 0x78, 0xD4);

    /// <summary>Preset colors (the Mac's color pill presets): red, orange, yellow, green, blue, purple, black, white.</summary>
    private static readonly RgbColor[] Presets =
    {
        RgbColor.FromBytes(255, 59, 48), RgbColor.FromBytes(255, 149, 0), RgbColor.FromBytes(255, 204, 0),
        RgbColor.FromBytes(52, 199, 89), RgbColor.FromBytes(0, 122, 255), RgbColor.FromBytes(175, 82, 222),
        RgbColor.FromBytes(0, 0, 0), RgbColor.FromBytes(255, 255, 255),
    };
    private static readonly double[] LineWidths = { 2, 4, 6, 8, 12, 16 };
    private static readonly int[] PixelSizes = { 6, 10, 16, 24 };

    private readonly BgraImage _image;
    private readonly RectInt32 _sourceRect;
    private readonly Func<SoftwareBitmap, Task> _copy;
    private readonly Func<SoftwareBitmap, Task> _save;
    private readonly EditorSession _session = new();
    private readonly Dictionary<EditorTool, ToggleButton> _toolButtons = new();
    private readonly List<(Button Button, Border Swatch, RgbColor Color)> _colorButtons = new();
    private readonly ComboBox _widthBox = new();
    private readonly ComboBox _pixelBox = new();
    private readonly StackPanel _colorPanel = new() { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button _undoButton = new() { Content = "Undo" };
    private readonly Button _redoButton = new() { Content = "Redo" };
    private CanvasControl? _canvas;
    private AnnotationRenderer? _renderer;
    private IReadOnlyList<Annotation>? _exported; // the items as last copied or saved
    private bool _closeConfirmed;
    private bool _syncingStyleBar;

    /// <param name="image">The screenshot; the editor keeps it, so pass one nobody else changes.</param>
    /// <param name="sourceRect">Where it was captured (physical pixels, virtual desktop): the editor opens on that display.</param>
    /// <param name="copy">Puts a bitmap on the clipboard. The editor disposes the bitmap afterwards.</param>
    /// <param name="save">Saves a bitmap with the settings' folder, name and format. The editor disposes the bitmap afterwards.</param>
    public EditorWindow(BgraImage image, RectInt32 sourceRect, Func<SoftwareBitmap, Task> copy, Func<SoftwareBitmap, Task> save)
    {
        _image = image;
        _sourceRect = sourceRect;
        _copy = copy;
        _save = save;
        Title = "Skreener Editor";

        var canvas = new CanvasControl { IsTabStop = true, ClearColor = CanvasBackground };
        canvas.CreateResources += OnCreateResources;
        canvas.Draw += OnDraw;
        canvas.PointerPressed += OnPointerPressed;
        canvas.PointerMoved += OnPointerMoved;
        canvas.PointerReleased += OnPointerReleased;
        canvas.PointerCaptureLost += OnPointerCaptureLost;
        canvas.SizeChanged += (_, _) => canvas.Invalidate();
        _canvas = canvas;

        var root = new Grid
        {
            RowDefinitions = { new RowDefinition { Height = GridLength.Auto }, new RowDefinition { Height = new GridLength(1, GridUnitType.Star) } },
        };
        var toolbar = BuildToolbar();
        Grid.SetRow(toolbar, 0);
        Grid.SetRow(canvas, 1);
        root.Children.Add(toolbar);
        root.Children.Add(canvas);
        root.KeyDown += OnKeyDown;
        Content = root;

        _session.Changed += OnSessionChanged;
        AppWindow.Closing += OnClosing;
        Closed += OnClosed;
        SyncToolbar();
    }

    /// <summary>Sizes the window to the screenshot at 100 % (within the display's work area), centers it there and shows it.</summary>
    public void ShowNearSource()
    {
        var display = DisplayArea.GetFromRect(_sourceRect, DisplayAreaFallback.Nearest);
        var work = display.WorkArea;
        var hwnd = new HWND(WinRT.Interop.WindowNative.GetWindowHandle(this));
        var scale = Math.Max(PInvoke.GetDpiForWindow(hwnd), 96u) / 96.0;
        // Image pixels are screen pixels at 100 %; add the toolbar, the padding and the title bar (all in DIPs).
        const double chrome = 48 + 32;
        int width = (int)Math.Round(_image.Width + 2 * CanvasPadding * scale);
        int height = (int)Math.Round(_image.Height + (2 * CanvasPadding + chrome) * scale);
        width = Math.Clamp(width, (int)(820 * scale), Math.Max((int)(work.Width * 0.9), 1));
        height = Math.Clamp(height, (int)(520 * scale), Math.Max((int)(work.Height * 0.9), 1));
        AppWindow.MoveAndResize(new RectInt32(work.X + (work.Width - width) / 2, work.Y + (work.Height - height) / 2, width, height));
        Activate();
        _canvas?.Focus(FocusState.Programmatic);
    }

    // MARK: Toolbar

    private FrameworkElement BuildToolbar()
    {
        var tools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        foreach (var tool in EditorTools.All)
        {
            var button = new ToggleButton { Content = ToolLabel(tool), AllowFocusOnInteraction = false, Padding = new Thickness(10, 4, 10, 4) };
            ToolTipService.SetToolTip(button, $"{ToolLabel(tool)} ({tool.Shortcut()})");
            button.Click += (_, _) => SelectTool(tool);
            _toolButtons[tool] = button;
            tools.Children.Add(button);
        }

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
            button.Click += (_, _) => _session.ApplyStyle(ContextStyle with { Color = color });
            _colorButtons.Add((button, swatch, color));
            _colorPanel.Children.Add(button);
        }

        foreach (var w in LineWidths) _widthBox.Items.Add($"{w:0} px");
        _widthBox.SelectionChanged += (_, _) =>
        {
            if (_syncingStyleBar || _widthBox.SelectedIndex < 0) return;
            _session.ApplyStyle(ContextStyle with { LineWidth = LineWidths[_widthBox.SelectedIndex] });
            _canvas?.Focus(FocusState.Programmatic);
        };
        ToolTipService.SetToolTip(_widthBox, "Line width");

        foreach (var p in PixelSizes) _pixelBox.Items.Add($"Blocks {p} px");
        _pixelBox.SelectionChanged += (_, _) =>
        {
            if (_syncingStyleBar || _pixelBox.SelectedIndex < 0) return;
            _session.ApplyStyle(ContextStyle with { PixelSize = PixelSizes[_pixelBox.SelectedIndex] });
            _canvas?.Focus(FocusState.Programmatic);
        };
        ToolTipService.SetToolTip(_pixelBox, "Pixelate block size");

        _undoButton.AllowFocusOnInteraction = false;
        _redoButton.AllowFocusOnInteraction = false;
        _undoButton.Click += (_, _) => _session.Undo();
        _redoButton.Click += (_, _) => _session.Redo();
        ToolTipService.SetToolTip(_undoButton, "Undo (Ctrl+Z)");
        ToolTipService.SetToolTip(_redoButton, "Redo (Ctrl+Y)");

        var copyButton = new Button { Content = "Copy", AllowFocusOnInteraction = false };
        var saveButton = new Button { Content = "Save", AllowFocusOnInteraction = false, Style = AccentStyle() };
        copyButton.Click += async (_, _) => await ExportAsync(_copy, "Copy failed");
        saveButton.Click += async (_, _) => await ExportAsync(_save, "Save failed");
        ToolTipService.SetToolTip(copyButton, "Copy to the clipboard (Ctrl+C)");
        ToolTipService.SetToolTip(saveButton, "Save to the screenshots folder (Ctrl+S)");

        var left = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Children = { tools, _colorPanel, _widthBox, _pixelBox, new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2, Children = { _undoButton, _redoButton } } },
        };
        var right = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center, Children = { copyButton, saveButton } };
        var bar = new Grid
        {
            Padding = new Thickness(8, 6, 8, 6),
            ColumnDefinitions = { new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }, new ColumnDefinition { Width = GridLength.Auto } },
            Children = { left, right },
        };
        Grid.SetColumn(right, 1);
        return bar;
    }

    /// <summary>What the style bar shows and edits: the selection's style, or the one for new annotations.</summary>
    private AnnotationStyle ContextStyle => _session.Selected?.Style ?? _session.Style;

    private static string ToolLabel(EditorTool tool) => tool == EditorTool.Rectangle ? "Rect" : tool.ToString();

    private static Style? AccentStyle() =>
        Application.Current.Resources.TryGetValue("AccentButtonStyle", out var s) ? s as Style : null;

    private void SelectTool(EditorTool tool)
    {
        _session.Tool = tool;
        SyncToolbar();
        _canvas?.Focus(FocusState.Programmatic);
    }

    /// <summary>
    /// Brings the toolbar in line with the session: the current tool, undo/redo, and the style bar for what is
    /// selected (or the tool when nothing is): colors and width for strokes, block size for pixelate.
    /// </summary>
    private void SyncToolbar()
    {
        foreach (var (tool, button) in _toolButtons) button.IsChecked = tool == _session.Tool;
        _undoButton.IsEnabled = _session.CanUndo;
        _redoButton.IsEnabled = _session.CanRedo;

        var kind = _session.Selected?.Kind ?? _session.Tool.Kind();
        var style = ContextStyle;
        var pixelate = kind == AnnotationKind.Pixelate;
        _colorPanel.Visibility = pixelate ? Visibility.Collapsed : Visibility.Visible;
        _widthBox.Visibility = pixelate ? Visibility.Collapsed : Visibility.Visible;
        _pixelBox.Visibility = pixelate ? Visibility.Visible : Visibility.Collapsed;

        _syncingStyleBar = true;
        try
        {
            _widthBox.SelectedIndex = Array.IndexOf(LineWidths, style.LineWidth);
            _pixelBox.SelectedIndex = Array.IndexOf(PixelSizes, style.PixelSize);
        }
        finally
        {
            _syncingStyleBar = false;
        }
        var ring = (Brush?)(Application.Current.Resources.TryGetValue("AccentFillColorDefaultBrush", out var b) ? b as Brush : null)
            ?? new SolidColorBrush(HandleStroke);
        var none = new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
        foreach (var (button, _, color) in _colorButtons) button.BorderBrush = color == style.Color ? ring : none;
    }

    private void OnSessionChanged()
    {
        SyncToolbar();
        _canvas?.Invalidate();
    }

    // MARK: Canvas

    private void OnCreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
    {
        // Also runs again after a lost device; the old renderer's bitmaps belong to the old device.
        _renderer?.Dispose();
        _renderer = new AnnotationRenderer(sender, _image);
    }

    /// <summary>
    /// The zoom (DIPs per image pixel) and the image's top-left corner in the canvas: fitted inside the padding, never
    /// larger than one image pixel per screen pixel, centered.
    /// </summary>
    private (double Zoom, Vector2 Offset) Layout()
    {
        if (_canvas is null) return (1, Vector2.Zero);
        var raster = _canvas.XamlRoot?.RasterizationScale ?? 1;
        double w = _canvas.ActualWidth, h = _canvas.ActualHeight;
        var zoom = Math.Min(1 / raster, Math.Min((w - 2 * CanvasPadding) / _image.Width, (h - 2 * CanvasPadding) / _image.Height));
        zoom = Math.Max(zoom, 0.01);
        var offset = new Vector2((float)Math.Round((w - _image.Width * zoom) / 2), (float)Math.Round((h - _image.Height * zoom) / 2));
        return (zoom, offset);
    }

    private PointD ToImage(Point p)
    {
        var (zoom, offset) = Layout();
        return new PointD((p.X - offset.X) / zoom, (p.Y - offset.Y) / zoom);
    }

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        if (_renderer is null) return;
        var ds = args.DrawingSession;
        var (zoom, offset) = Layout();
        ds.Transform = Matrix3x2.CreateScale((float)zoom) * Matrix3x2.CreateTranslation(offset);
        var raster = sender.XamlRoot?.RasterizationScale ?? 1;
        // Shrunk to fit: smooth it; at 100 % pixels map one to one.
        var interpolation = zoom * raster < 0.999 ? CanvasImageInterpolation.HighQualityCubic : CanvasImageInterpolation.NearestNeighbor;
        var items = _session.Draft is { } draft ? _session.Items.Append(draft) : _session.Items;
        _renderer.Draw(ds, items, interpolation);
        if (_session.Selected is { } selected) DrawSelection(ds, selected, zoom);
    }

    /// <summary>The selection's handles (white dots with an accent ring, a fixed size on screen); a pen stroke, which has none, gets a dashed frame.</summary>
    private static void DrawSelection(CanvasDrawingSession ds, Annotation a, double zoom)
    {
        var handles = AnnotationGeometry.Handles(a);
        var line = (float)(1.5 / zoom);
        if (handles.Count == 0)
        {
            var outset = AnnotationGeometry.InkOutset(a) + 3 / zoom;
            using var dashed = new CanvasStrokeStyle { DashStyle = CanvasDashStyle.Dash };
            ds.DrawRectangle(AnnotationRenderer.ToRect(a.Bounds.InsetBy(-outset, -outset)), HandleStroke, line, dashed);
            return;
        }
        var radius = (float)(5 / zoom);
        foreach (var h in handles)
        {
            ds.FillCircle(AnnotationRenderer.V(h), radius, HandleFill);
            ds.DrawCircle(AnnotationRenderer.V(h), radius, HandleStroke, line);
        }
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null) return;
        var point = e.GetCurrentPoint(_canvas);
        if (!point.Properties.IsLeftButtonPressed) return;
        _canvas.Focus(FocusState.Pointer);
        _canvas.CapturePointer(e.Pointer);
        _session.PointerDown(ToImage(point.Position), Layout().Zoom);
        e.Handled = true;
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null || !_session.IsDragging) return;
        _session.PointerMove(ToImage(e.GetCurrentPoint(_canvas).Position), e.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift));
        e.Handled = true;
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null) return;
        _session.PointerUp(ToImage(e.GetCurrentPoint(_canvas).Position), e.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift));
        _canvas.ReleasePointerCapture(e.Pointer);
        e.Handled = true;
    }

    /// <summary>Capture taken away mid-drag (another window popped up): keep what was dragged so far.</summary>
    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null || !_session.IsDragging) return;
        _session.PointerUp(ToImage(e.GetCurrentPoint(_canvas).Position));
    }

    // MARK: Keys

    private static bool IsDown(VirtualKey key) => PInvoke.GetKeyState((int)key) < 0;

    private async void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        bool ctrl = IsDown(VirtualKey.Control), shift = IsDown(VirtualKey.Shift);
        e.Handled = true;
        switch (e.Key)
        {
            case VirtualKey.Z when ctrl && shift:
            case VirtualKey.Y when ctrl:
                _session.Redo();
                break;
            case VirtualKey.Z when ctrl:
                _session.Undo();
                break;
            case VirtualKey.C when ctrl:
                await ExportAsync(_copy, "Copy failed");
                break;
            case VirtualKey.S when ctrl:
                await ExportAsync(_save, "Save failed");
                break;
            case VirtualKey.Delete:
            case VirtualKey.Back:
                _session.DeleteSelected();
                break;
            case VirtualKey.Escape:
                _session.Cancel();
                break;
            case VirtualKey.Left: _session.Nudge(shift ? -10 : -1, 0); break;
            case VirtualKey.Right: _session.Nudge(shift ? 10 : 1, 0); break;
            case VirtualKey.Up: _session.Nudge(0, shift ? -10 : -1); break;
            case VirtualKey.Down: _session.Nudge(0, shift ? 10 : 1); break;
            default:
                if (!ctrl && e.Key is >= VirtualKey.A and <= VirtualKey.Z && EditorTools.ForShortcut((char)e.Key) is EditorTool tool)
                    SelectTool(tool);
                else
                    e.Handled = false;
                break;
        }
    }

    // MARK: Copy, save, close

    /// <summary>Flattens the annotations into the screenshot and hands the result to Copy or Save. Returns false if it failed.</summary>
    private async Task<bool> ExportAsync(Func<SoftwareBitmap, Task> action, string failureTitle)
    {
        if (_renderer is null || _session.IsDragging) return false;
        var items = _session.Items;
        try
        {
            using var bitmap = _renderer.Flatten(items);
            await action(bitmap);
            _exported = items;
            return true;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: editor {failureTitle}: {e}");
            await ShowMessageAsync(failureTitle, e.Message);
            return false;
        }
    }

    /// <summary>Annotations that were neither copied nor saved since they last changed.</summary>
    private bool HasUnexportedEdits => _session.IsEdited && !ReferenceEquals(_session.Items, _exported);

    private async void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_closeConfirmed || !HasUnexportedEdits) return;
        args.Cancel = true;
        if (Content?.XamlRoot is not { } xamlRoot) return;
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = "Save your changes?",
            Content = "The annotations have not been saved or copied.",
            PrimaryButtonText = "Save",
            SecondaryButtonText = "Don't Save",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        var answer = await dialog.ShowAsync();
        if (answer == ContentDialogResult.None) return;
        if (answer == ContentDialogResult.Primary && !await ExportAsync(_save, "Save failed")) return;
        _closeConfirmed = true;
        Close();
    }

    private async Task ShowMessageAsync(string title, string message)
    {
        if (Content?.XamlRoot is not { } xamlRoot) return;
        try
        {
            await new ContentDialog { XamlRoot = xamlRoot, Title = title, Content = message, CloseButtonText = "OK" }.ShowAsync();
        }
        catch (Exception e) when (e is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            // Another dialog is already open; the failure is in the debug log.
            Debug.WriteLine($"Skreener: could not show '{title}': {e.Message}");
        }
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _session.Changed -= OnSessionChanged;
        _renderer?.Dispose();
        _renderer = null;
        // Win2D's advice for CanvasControl: detach it so its device resources are released with the window.
        _canvas?.RemoveFromVisualTree();
        _canvas = null;
    }
}
