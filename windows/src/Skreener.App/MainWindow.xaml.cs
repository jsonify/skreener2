using Microsoft.UI.Xaml;

namespace Skreener.App;

/// <summary>
/// Hidden window that is never activated. It exists so WinUI keeps its message loop (and with it the tray icon
/// and hotkey window owned by <see cref="Shell.ShellController"/>) running; the process exits through Quit.
/// </summary>
public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }
}
