using System.Diagnostics;
using System.Numerics;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Skreener.App.Capture;
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
/// The annotation editor (AnnotationEditor.swift / EditorWindow.swift, second Windows milestone): a toolbar with the
/// tools, crop, zoom, undo/redo and Copy/Save, a style bar (<see cref="StyleBar"/>), and a Win2D canvas that shows the
/// screenshot (or its crop) fitted to the window, never above 100 %, until the user zooms. All editing state lives in
/// Core's <see cref="EditorSession"/> and the zoom in <see cref="EditorViewport"/>; this window turns pointer and key
/// events into their calls and draws what they hold. Text is typed in a <see cref="TextEditOverlay"/> over the canvas.
/// </summary>
internal sealed class EditorWindow : Window
{
    private const double CanvasPadding = 16; // DIPs around the image
    private const double CropPadding = 28; // more room in crop mode, so every handle can be grabbed
    private const double WheelScrollPerNotch = 48; // DIPs a wheel notch scrolls (about three lines)
    private static readonly Windows.UI.Color CanvasBackground = Windows.UI.Color.FromArgb(255, 0x26, 0x26, 0x26);

    private readonly BgraImage _image;
    private readonly RectInt32 _sourceRect;
    private readonly Func<SoftwareBitmap, Task> _copy;
    private readonly Func<SoftwareBitmap, Task> _save;
    private readonly EditorSession _session;
    private readonly EditorViewport _viewport = new();
    private readonly Dictionary<EditorTool, ToggleButton> _toolButtons = new();
    private readonly ToggleButton _cropButton = new() { Content = "Crop", AllowFocusOnInteraction = false, Padding = new Thickness(10, 4, 10, 4) };
    private readonly Button _undoButton = new() { Content = "Undo" };
    private readonly Button _redoButton = new() { Content = "Redo" };
    private readonly StyleBar _styleBar = new();
    private readonly ZoomMenu _zoomMenu = new();
    private readonly TextEditOverlay _textOverlay;
    private CanvasControl? _canvas;
    private AnnotationRenderer? _renderer;
    private IReadOnlyList<Annotation>? _exported; // the items as last copied or saved
    private RectD? _exportedCrop; // and the crop
    private Point? _panLast; // the pointer's last position during a middle-button pan
    private bool _closeConfirmed;

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
        _session = new EditorSession { ImageSize = new SizeD(image.Width, image.Height), TextMeasurer = TextMetrics.Measure };
        Title = "Skreener Editor";

        var canvas = new CanvasControl { IsTabStop = true, ClearColor = CanvasBackground };
        canvas.CreateResources += OnCreateResources;
        canvas.Draw += OnDraw;
        canvas.PointerPressed += OnPointerPressed;
        canvas.PointerMoved += OnPointerMoved;
        canvas.PointerReleased += OnPointerReleased;
        canvas.PointerCaptureLost += OnPointerCaptureLost;
        canvas.PointerWheelChanged += OnPointerWheelChanged;
        canvas.DoubleTapped += OnDoubleTapped;
        canvas.SizeChanged += (_, _) => Refresh();
        _canvas = canvas;

        // The text box goes in a panel over the canvas; with no background, the panel lets the pointer through.
        var overlayHost = new Canvas();
        _textOverlay = new TextEditOverlay(overlayHost, text => _session.SetEditingText(text), () => _session.FinishTextEditing());
        var stage = new Grid { Children = { canvas, overlayHost } };

        var root = new Grid
        {
            RowDefinitions = { new RowDefinition { Height = GridLength.Auto }, new RowDefinition { Height = new GridLength(1, GridUnitType.Star) } },
        };
        var toolbar = BuildToolbar();
        Grid.SetRow(toolbar, 0);
        Grid.SetRow(stage, 1);
        root.Children.Add(toolbar);
        root.Children.Add(stage);
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
        // Image pixels are screen pixels at 100 %; add the two toolbar rows, the padding and the title bar (all in DIPs).
        const double chrome = 2 * 44 + 32;
        int width = (int)Math.Round(_image.Width + 2 * CanvasPadding * scale);
        int height = (int)Math.Round(_image.Height + (2 * CanvasPadding + chrome) * scale);
        width = Math.Clamp(width, (int)(820 * scale), Math.Max((int)(work.Width * 0.9), 1));
        height = Math.Clamp(height, (int)(520 * scale), Math.Max((int)(work.Height * 0.9), 1));
        AppWindow.MoveAndResize(new RectInt32(work.X + (work.Width - width) / 2, work.Y + (work.Height - height) / 2, width, height));
        Activate();
        _canvas?.Focus(FocusState.Programmatic);
    }

    // MARK: Toolbar

    /// <summary>
    /// Two rows: the tools and Copy/Save, then the style bar with crop, zoom and undo/redo. Each row's left part
    /// scrolls sideways when the window is too narrow for it.
    /// </summary>
    private FrameworkElement BuildToolbar()
    {
        var tools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        foreach (var tool in EditorTools.All)
        {
            var button = new ToggleButton { Content = ToolLabel(tool), AllowFocusOnInteraction = false, Padding = new Thickness(8, 4, 8, 4) };
            ToolTipService.SetToolTip(button, $"{ToolName(tool)} ({tool.Shortcut()})");
            button.Click += (_, _) => SelectTool(tool);
            _toolButtons[tool] = button;
            tools.Children.Add(button);
        }

        _cropButton.Click += (_, _) =>
        {
            if (_session.IsCropping) _session.ApplyCrop(); else _session.BeginCrop();
            SyncToolbar();
            _canvas?.Focus(FocusState.Programmatic);
        };
        ToolTipService.SetToolTip(_cropButton, $"Crop ({EditorTools.CropShortcut}). Enter or Crop again applies, Esc cancels.");

        _zoomMenu.FitPicked += () => Zoom(v => v.Fit());
        _zoomMenu.ScalePicked += scale => Zoom(v => v.ZoomTo(scale));

        _undoButton.AllowFocusOnInteraction = false;
        _redoButton.AllowFocusOnInteraction = false;
        _undoButton.Click += (_, _) => _session.Undo();
        _redoButton.Click += (_, _) => _session.Redo();
        ToolTipService.SetToolTip(_undoButton, "Undo (Ctrl+Z)");
        ToolTipService.SetToolTip(_redoButton, "Redo (Ctrl+Y)");

        _styleBar.Changed += change =>
        {
            _session.ApplyStyle(change(ContextStyle));
            RestoreFocus();
        };

        var copyButton = new Button { Content = "Copy", AllowFocusOnInteraction = false };
        var saveButton = new Button { Content = "Save", AllowFocusOnInteraction = false, Style = AccentStyle() };
        copyButton.Click += async (_, _) => await ExportAsync(_copy, "Copy failed");
        saveButton.Click += async (_, _) => await ExportAsync(_save, "Save failed");
        ToolTipService.SetToolTip(copyButton, "Copy to the clipboard (Ctrl+C)");
        ToolTipService.SetToolTip(saveButton, "Save to the screenshots folder (Ctrl+S)");

        var actions = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center,
            Children = { _cropButton, _zoomMenu.Element, new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2, Children = { _undoButton, _redoButton } } },
        };
        var output = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center, Children = { copyButton, saveButton } };
        return new StackPanel
        {
            Padding = new Thickness(8, 6, 8, 6),
            Spacing = 6,
            Children = { Row(tools, output), Row(_styleBar.Element, actions) },
        };
    }

    /// <summary>A toolbar row: <paramref name="left"/> (scrolling sideways when it doesn't fit) and <paramref name="right"/>.</summary>
    private static Grid Row(FrameworkElement left, FrameworkElement right)
    {
        var scroller = new ScrollViewer
        {
            Content = left,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollMode = ScrollMode.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollMode = ScrollMode.Disabled,
            MinHeight = 36,
        };
        var row = new Grid
        {
            ColumnSpacing = 12,
            ColumnDefinitions = { new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }, new ColumnDefinition { Width = GridLength.Auto } },
            Children = { scroller, right },
        };
        Grid.SetColumn(right, 1);
        return row;
    }

    /// <summary>What the style bar shows and edits: the selection's style, or the one for new annotations.</summary>
    private AnnotationStyle ContextStyle => _session.Selected?.Style ?? _session.Style;

    private static string ToolLabel(EditorTool tool) => tool switch
    {
        EditorTool.Rectangle => "Rect",
        EditorTool.FilledRectangle => "Filled",
        EditorTool.Highlighter => "Highlight",
        _ => tool.ToString(),
    };

    private static string ToolName(EditorTool tool) => tool switch
    {
        EditorTool.Rectangle => "Rectangle",
        EditorTool.FilledRectangle => "Filled rectangle",
        _ => tool.ToString(),
    };

    private static Style? AccentStyle() =>
        Application.Current.Resources.TryGetValue("AccentButtonStyle", out var s) ? s as Style : null;

    private void SelectTool(EditorTool tool)
    {
        _session.Tool = tool; // ends any typing
        SyncToolbar();
        _canvas?.Focus(FocusState.Programmatic);
    }

    /// <summary>
    /// Brings the toolbar in line with the session: the current tool, crop mode, undo/redo, and the style bar for
    /// what is selected (or the tool when nothing is).
    /// </summary>
    private void SyncToolbar()
    {
        foreach (var (tool, button) in _toolButtons) button.IsChecked = tool == _session.Tool;
        _cropButton.IsChecked = _session.IsCropping;
        _undoButton.IsEnabled = _session.CanUndo && !_session.IsCropping;
        _redoButton.IsEnabled = _session.CanRedo && !_session.IsCropping;
        _styleBar.Sync(_session.Selected?.Kind ?? _session.Tool.Kind(), ContextStyle, _session.IsCropping);
    }

    /// <summary>Keyboard focus back where typing goes: the text box while a label is typed, else the canvas.</summary>
    private void RestoreFocus()
    {
        if (_session.IsEditingText) _textOverlay.Focus();
        else _canvas?.Focus(FocusState.Programmatic);
    }

    private void OnSessionChanged()
    {
        SyncToolbar();
        Refresh();
    }

    /// <summary>Re-lays out the canvas (zoom, crop), moves the text box with it and redraws.</summary>
    private void Refresh()
    {
        UpdateViewport();
        SyncTextOverlay();
        _canvas?.Invalidate();
    }

    private void SyncTextOverlay()
    {
        if (_session.Editing is { } a)
        {
            _textOverlay.Show(a, _viewport.ToView(a.Start), _viewport.Zoom);
        }
        else if (_textOverlay.IsShown)
        {
            _textOverlay.Hide();
            _canvas?.Focus(FocusState.Programmatic);
        }
    }

    // MARK: Zoom

    /// <summary>
    /// Feeds the viewport what it lays out: the crop (or, in crop mode, the whole image), the canvas's size and the
    /// display scaling.
    /// </summary>
    private void UpdateViewport()
    {
        if (_canvas is null) return;
        var raster = _canvas.XamlRoot?.RasterizationScale ?? 1;
        _viewport.Update(_session.VisibleBounds, new SizeD(_canvas.ActualWidth, _canvas.ActualHeight), raster,
            _session.IsCropping ? CropPadding : CanvasPadding);
        _zoomMenu.Show(_viewport.Scale);
    }

    private void Zoom(Action<EditorViewport> change)
    {
        UpdateViewport();
        change(_viewport);
        Refresh();
        RestoreFocus();
    }

    private PointD ToImage(Point p)
    {
        UpdateViewport();
        return _viewport.ToImage(new PointD(p.X, p.Y));
    }

    // MARK: Canvas

    private void OnCreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
    {
        // Also runs again after a lost device; the old renderer's bitmaps belong to the old device.
        _renderer?.Dispose();
        _renderer = new AnnotationRenderer(sender, _image);
    }

    private void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        if (_renderer is null) return;
        UpdateViewport();
        var ds = args.DrawingSession;
        var zoom = _viewport.Zoom;
        var origin = _viewport.Origin;
        var content = _viewport.Content;
        // Image pixels to view DIPs: the shown part's corner to the origin, scaled by the zoom.
        ds.Transform = Matrix3x2.CreateTranslation((float)-content.MinX, (float)-content.MinY)
            * Matrix3x2.CreateScale((float)zoom)
            * Matrix3x2.CreateTranslation((float)origin.X, (float)origin.Y);
        // Shrunk: smooth it; at 100 % pixels map one to one, and zoomed in they stay crisp squares.
        var interpolation = _viewport.Scale < 0.999 ? CanvasImageInterpolation.HighQualityCubic : CanvasImageInterpolation.NearestNeighbor;
        IReadOnlyList<Annotation> items = _session.Draft is { } draft ? _session.Items.Append(draft).ToList() : _session.Items;
        if (!_session.IsCropping && _session.Crop is RectD crop)
        {
            // Only the crop shows, as it will be exported.
            using (ds.CreateLayer(1, AnnotationRenderer.ToRect(crop)))
                _renderer.Draw(ds, items, interpolation, _session.EditingId);
        }
        else
        {
            _renderer.Draw(ds, items, interpolation, _session.EditingId);
        }

        if (_session.CropDraft is RectD draftCrop) EditorOverlay.DrawCrop(ds, draftCrop, _session.ImageBounds, zoom);
        else if (_session.Selected is { } selected && !_session.IsEditingText) EditorOverlay.DrawSelection(ds, selected, zoom);
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null) return;
        var point = e.GetCurrentPoint(_canvas);
        if (point.Properties.IsMiddleButtonPressed)
        {
            // Middle-button drag pans (the Mac's otherMouseDragged), whatever the tool.
            _panLast = point.Position;
            _canvas.CapturePointer(e.Pointer);
            e.Handled = true;
            return;
        }
        if (!point.Properties.IsLeftButtonPressed) return;
        _canvas.Focus(FocusState.Pointer);
        _canvas.CapturePointer(e.Pointer);
        var p = ToImage(point.Position);
        _session.PointerDown(p, _viewport.Zoom);
        e.Handled = true;
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null) return;
        if (_panLast is Point last)
        {
            var p = e.GetCurrentPoint(_canvas).Position;
            UpdateViewport();
            _viewport.Pan(p.X - last.X, p.Y - last.Y);
            _panLast = p;
            Refresh();
            e.Handled = true;
            return;
        }
        if (!_session.IsDragging) return;
        _session.PointerMove(ToImage(e.GetCurrentPoint(_canvas).Position), e.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift));
        e.Handled = true;
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null) return;
        if (_panLast is not null)
        {
            if (!e.GetCurrentPoint(_canvas).Properties.IsMiddleButtonPressed)
            {
                _panLast = null;
                _canvas.ReleasePointerCapture(e.Pointer);
            }
            e.Handled = true;
            return;
        }
        _session.PointerUp(ToImage(e.GetCurrentPoint(_canvas).Position), e.KeyModifiers.HasFlag(VirtualKeyModifiers.Shift));
        _canvas.ReleasePointerCapture(e.Pointer);
        e.Handled = true;
    }

    /// <summary>Capture taken away mid-drag (another window popped up): keep what was dragged so far.</summary>
    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        _panLast = null;
        if (_canvas is null || !_session.IsDragging) return;
        _session.PointerUp(ToImage(e.GetCurrentPoint(_canvas).Position));
    }

    /// <summary>
    /// Ctrl+wheel zooms around the pointer; otherwise, once zoomed past fit, the wheel scrolls (Shift+wheel or a
    /// tilt wheel sideways).
    /// </summary>
    private void OnPointerWheelChanged(object sender, PointerRoutedEventArgs e)
    {
        if (_canvas is null) return;
        var point = e.GetCurrentPoint(_canvas);
        var delta = point.Properties.MouseWheelDelta;
        if (delta == 0) return;
        UpdateViewport();
        var step = delta / 120.0 * WheelScrollPerNotch;
        var mods = e.KeyModifiers;
        if (point.Properties.IsHorizontalMouseWheel)
            _viewport.ScrollBy(step, 0); // tilting right shows more to the right
        else if (mods.HasFlag(VirtualKeyModifiers.Control))
            _viewport.ZoomBy(EditorViewport.WheelFactor(delta), new PointD(point.Position.X, point.Position.Y));
        else if (mods.HasFlag(VirtualKeyModifiers.Shift))
            _viewport.ScrollBy(-step, 0);
        else
            _viewport.ScrollBy(0, -step);
        Refresh();
        e.Handled = true;
    }

    /// <summary>A double-click on a text label types in it again.</summary>
    private void OnDoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (_canvas is null) return;
        if (_session.BeginTextEditing(ToImage(e.GetPosition(_canvas)), _viewport.Zoom)) e.Handled = true;
    }

    // MARK: Keys

    private static bool IsDown(VirtualKey key) => PInvoke.GetKeyState((int)key) < 0;

    private async void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        // While a label is typed the keys are the text box's (it ends typing on Esc and Ctrl+Enter itself).
        if (_session.IsEditingText) return;
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
            case VirtualKey.Number0 when ctrl:
            case VirtualKey.NumberPad0 when ctrl:
                Zoom(v => v.Fit());
                break;
            case VirtualKey.Number1 when ctrl:
            case VirtualKey.NumberPad1 when ctrl:
                Zoom(v => v.ZoomTo(1));
                break;
            case OemPlus when ctrl:
            case VirtualKey.Add when ctrl:
                Zoom(v => v.Step(up: true));
                break;
            case OemMinus when ctrl:
            case VirtualKey.Subtract when ctrl:
                Zoom(v => v.Step(up: false));
                break;
            case VirtualKey.Enter:
                if (_session.IsCropping) _session.ApplyCrop();
                else if (_session.Selected is { Kind: AnnotationKind.Text } text)
                    _session.BeginTextEditing(new PointD(text.Rect.MinX + text.Rect.Width / 2, text.Rect.MinY + text.Rect.Height / 2), _viewport.Zoom);
                else e.Handled = false;
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
                if (ctrl || _session.IsCropping || e.Key is < VirtualKey.A or > VirtualKey.Z)
                    e.Handled = false;
                else if ((char)e.Key == EditorTools.CropShortcut)
                    _session.BeginCrop();
                else if (EditorTools.ForShortcut((char)e.Key) is EditorTool tool)
                    SelectTool(tool);
                else
                    e.Handled = false;
                break;
        }
    }

    /// <summary>The = / + key and the - key of the main keyboard (VK_OEM_PLUS, VK_OEM_MINUS), which VirtualKey doesn't name.</summary>
    private const VirtualKey OemPlus = (VirtualKey)0xBB, OemMinus = (VirtualKey)0xBD;

    // MARK: Copy, save, close

    /// <summary>
    /// Flattens the annotations into the screenshot (cut to the crop) and hands the result to Copy or Save. Ends any
    /// typing first. Returns false if it failed.
    /// </summary>
    private async Task<bool> ExportAsync(Func<SoftwareBitmap, Task> action, string failureTitle)
    {
        if (_renderer is null || _session.IsDragging) return false;
        _session.FinishTextEditing();
        var items = _session.Items;
        var crop = _session.Crop;
        try
        {
            using var bitmap = _renderer.Flatten(items, crop);
            await action(bitmap);
            _exported = items;
            _exportedCrop = crop;
            return true;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: editor {failureTitle}: {e}");
            await ShowMessageAsync(failureTitle, e.Message);
            return false;
        }
    }

    /// <summary>Annotations or a crop that were neither copied nor saved since they last changed.</summary>
    private bool HasUnexportedEdits =>
        _session.IsEdited && (!ReferenceEquals(_session.Items, _exported) || _session.Crop != _exportedCrop);

    private async void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_closeConfirmed) return;
        _session.FinishTextEditing(); // a label being typed counts as an edit
        if (!HasUnexportedEdits) return;
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
        _textOverlay.Hide();
        _renderer?.Dispose();
        _renderer = null;
        // Win2D's advice for CanvasControl: detach it so its device resources are released with the window.
        _canvas?.RemoveFromVisualTree();
        _canvas = null;
    }
}
