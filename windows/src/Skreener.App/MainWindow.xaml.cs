using Microsoft.UI.Xaml;

namespace Skreener.App;

/// <summary>Hidden placeholder window; it owns the message loop until the tray icon lands.</summary>
public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }
}
