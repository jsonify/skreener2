using System.Diagnostics;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Skreener.Core.Text;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;
using Windows.System;
using Windows.UI.Core;
using Windows.Win32;
using Windows.Win32.Foundation;

namespace Skreener.App.Ocr;

/// <summary>
/// Capture Text's scratch pad (port of TextScratchPad.swift): a small always-on-top window with the recognized text, to
/// fix up before copying. Copy to Clipboard (Ctrl+Enter) copies all the text and closes it; Esc or the close button
/// closes it without copying. Join Lines turns the selected lines (or all of them) into one line.
/// </summary>
internal sealed class TextScratchPadWindow : Window
{
    private const double WidthDips = 480, HeightDips = 320;

    private readonly TextBox _text;
    private readonly TextBlock _count;
    private readonly Action<int> _onCopied;
    private bool _positioned;

    /// <param name="onCopied">Called with the number of lines copied, after the pad has closed.</param>
    public TextScratchPadWindow(Action<int> onCopied)
    {
        _onCopied = onCopied;
        Title = "Captured Text";

        _text = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            IsSpellCheckEnabled = false,
            VerticalAlignment = VerticalAlignment.Stretch,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        ScrollViewer.SetVerticalScrollBarVisibility(_text, ScrollBarVisibility.Auto);
        _text.TextChanged += (_, _) => UpdateCount();

        var join = new Button { Content = "Join Lines" };
        ToolTipService.SetToolTip(join, "Turn the selected lines (or all of them) into one line");
        join.Click += (_, _) => JoinLines();
        var copy = new Button { Content = "Copy to Clipboard" };
        if (Application.Current.Resources.TryGetValue("AccentButtonStyle", out var accent) && accent is Style accentStyle) copy.Style = accentStyle;
        ToolTipService.SetToolTip(copy, "Copy all the text and close (Ctrl+Enter)");
        copy.Click += (_, _) => CopyAndClose();
        _count = new TextBlock
        {
            VerticalAlignment = VerticalAlignment.Center,
            Opacity = 0.7,
            FontSize = 12,
        };

        var bar = new Grid { ColumnSpacing = 10 };
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(join, 0);
        Grid.SetColumn(_count, 1);
        Grid.SetColumn(copy, 2);
        bar.Children.Add(join);
        bar.Children.Add(_count);
        bar.Children.Add(copy);

        var root = new Grid { Padding = new Thickness(12), RowSpacing = 10 };
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(_text, 0);
        Grid.SetRow(bar, 1);
        root.Children.Add(_text);
        root.Children.Add(bar);
        // handledEventsToo: the multi-line TextBox handles Enter (and Esc) itself.
        root.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler(OnKeyDown), true);
        Content = root;
    }

    /// <summary>Shows <paramref name="text"/> and brings the pad to the front. A pad that is already open takes the new text.</summary>
    public void Present(string text)
    {
        _text.Text = text.Replace('\n', '\r'); // the TextBox's own line break
        UpdateCount();
        if (!_positioned)
        {
            _positioned = true;
            var presenter = OverlappedPresenter.Create();
            presenter.IsAlwaysOnTop = true;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            AppWindow.SetPresenter(presenter);
            PlaceNearPointer();
        }
        Activate();
        var hwnd = new HWND(WinRT.Interop.WindowNative.GetWindowHandle(this));
        // The app has no foreground window (it lives in the tray): ask Windows to focus the pad.
        PInvoke.SetForegroundWindow(hwnd);
        _text.Focus(FocusState.Programmatic);
        _text.SelectAll();
    }

    /// <summary>Centers the window on the work area of the display the pointer is on (the one just captured from).</summary>
    private void PlaceNearPointer()
    {
        var hwnd = new HWND(WinRT.Interop.WindowNative.GetWindowHandle(this));
        var scale = Math.Max(PInvoke.GetDpiForWindow(hwnd), 96u) / 96.0;
        var width = (int)Math.Round(WidthDips * scale);
        var height = (int)Math.Round(HeightDips * scale);
        var area = PInvoke.GetCursorPos(out var p)
            ? DisplayArea.GetFromPoint(new PointInt32(p.X, p.Y), DisplayAreaFallback.Nearest)
            : DisplayArea.Primary;
        var work = area.WorkArea;
        width = Math.Min(width, work.Width);
        height = Math.Min(height, work.Height);
        AppWindow.MoveAndResize(new RectInt32(work.X + (work.Width - width) / 2, work.Y + (work.Height - height) / 2, width, height));
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Escape)
        {
            e.Handled = true;
            Close();
        }
        else if (e.Key == VirtualKey.Enter && IsDown(VirtualKey.Control))
        {
            e.Handled = true;
            CopyAndClose();
        }
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private void JoinLines()
    {
        // The whole text when nothing is selected.
        if (_text.SelectionLength == 0) _text.SelectAll();
        var start = _text.SelectionStart;
        var joined = TextJoin.Joined(_text.SelectedText);
        _text.SelectedText = joined;
        _text.Select(start, joined.Length);
        _text.Focus(FocusState.Programmatic);
    }

    private void CopyAndClose()
    {
        var text = _text.Text.Replace("\r\n", "\n").Replace('\r', '\n');
        if (text.Length == 0) return;
        try
        {
            var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
            package.SetText(text.Replace("\n", "\r\n"));
            Clipboard.SetContent(package);
            try { Clipboard.Flush(); }
            catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException)
            {
                // Flush fails when the app is not in the foreground; the clipboard still holds the (delay-rendered) text.
                Debug.WriteLine($"Skreener: clipboard flush failed: {e.Message}");
            }
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: copying text failed: {e}");
            _count.Text = "Could not copy: " + e.Message;
            return;
        }
        var lines = text.Split('\n').Count(l => l.Length > 0);
        Close();
        _onCopied(Math.Max(lines, 1));
    }

    private void UpdateCount()
    {
        var text = _text.Text.Replace("\r\n", "\n").Replace('\r', '\n');
        var lines = text.Length == 0 ? 0 : text.Split('\n').Length;
        var chars = text.Length;
        _count.Text = $"{lines} line{(lines == 1 ? "" : "s")}, {chars} character{(chars == 1 ? "" : "s")}";
    }
}
