using Microsoft.UI.Xaml;

namespace Skreener.App;

public partial class App : Application
{
    // Held so the window (and with it the process message loop) stays alive for the app's lifetime.
    private Window? _mainWindow;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Skreener lives in the tray: the window is created but never activated, so it stays hidden.
        _mainWindow = new MainWindow();
    }
}
