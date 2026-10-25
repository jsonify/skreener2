using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using Windows.Graphics.Imaging;
using Windows.Win32;
using Windows.Win32.Foundation;

namespace Skreener.App.Shell;

/// <summary>
/// Small borderless topmost thumbnail in the bottom-right corner of the work area after a capture (port of
/// QuickAccess.swift, simplified: one preview at a time, Copy / Save / Close). Closes itself after a few seconds
/// unless the pointer is over it. Owns (and disposes) the bitmap it is given.
/// </summary>
internal sealed class QuickAccessWindow : Window
{
    private const double ThumbnailWidth = 220; // DIPs, like the Mac preview
    private const double Margin = 16;

    private readonly SoftwareBitmap _bitmap;
    private readonly Func<SoftwareBitmap, Task> _copy;
    private readonly Func<SoftwareBitmap, Task> _save;
    private readonly DispatcherQueueTimer _timer;
    private readonly StackPanel _buttons;
    private bool _closed;

    public QuickAccessWindow(SoftwareBitmap bitmap, int seconds, Func<SoftwareBitmap, Task> copy, Func<SoftwareBitmap, Task> save)
    {
        _bitmap = bitmap;
        _copy = copy;
        _save = save;
        Title = "Skreener Quick Access";

        var image = new Image { Stretch = Stretch.Uniform };
        var copyButton = new Button { Content = "Copy" };
        var saveButton = new Button { Content = "Save" };
        var closeButton = new Button { Content = "Close" };
        copyButton.Click += async (_, _) => await RunAction(copyButton, _copy, "Copied");
        saveButton.Click += async (_, _) => await RunAction(saveButton, _save, "Saved");
        closeButton.Click += (_, _) => Close();

        _buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed,
            Children = { copyButton, saveButton, closeButton },
        };
        var root = new Grid { Background = new SolidColorBrush(Colors.Black), Children = { image, _buttons } };
        root.PointerEntered += OnPointerEntered;
        root.PointerExited += OnPointerExited;
        Content = root;

        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(seconds);
        _timer.IsRepeating = false;
        _timer.Tick += (_, _) => Close();

        Closed += OnClosed;
        _ = LoadImageAsync(image);
    }

    private async Task LoadImageAsync(Image image)
    {
        try
        {
            var source = new SoftwareBitmapSource();
            await source.SetBitmapAsync(_bitmap);
            image.Source = source;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: quick access image failed: {e.Message}");
        }
    }

    /// <summary>Positions the window in the bottom-right corner of the primary work area and shows it without taking focus.</summary>
    public void ShowInCorner()
    {
        var presenter = OverlappedPresenter.Create();
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = true;
        presenter.SetBorderAndTitleBar(false, false);
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;

        var hwnd = new HWND(WinRT.Interop.WindowNative.GetWindowHandle(this));
        var scale = Math.Max(PInvoke.GetDpiForWindow(hwnd), 96u) / 96.0;
        var aspect = (double)_bitmap.PixelHeight / Math.Max(_bitmap.PixelWidth, 1);
        var width = (int)Math.Round(ThumbnailWidth * scale);
        var height = (int)Math.Round(Math.Clamp(ThumbnailWidth * aspect, 90, 200) * scale);
        var margin = (int)Math.Round(Margin * scale);
        var work = DisplayArea.Primary.WorkArea;
        AppWindow.MoveAndResize(new RectInt32(work.X + work.Width - width - margin, work.Y + work.Height - height - margin, width, height));
        AppWindow.Show(false);
        _timer.Start();
    }

    private void OnPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        _timer.Stop();
        _buttons.Visibility = Visibility.Visible;
    }

    private void OnPointerExited(object sender, PointerRoutedEventArgs e)
    {
        _buttons.Visibility = Visibility.Collapsed;
        if (!_closed) _timer.Start();
    }

    private async Task RunAction(Button button, Func<SoftwareBitmap, Task> action, string done)
    {
        try
        {
            await action(_bitmap);
            button.Content = done;
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: quick access action failed: {e.Message}");
            button.Content = "Failed";
        }
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _closed = true;
        _timer.Stop();
        _bitmap.Dispose();
    }
}
