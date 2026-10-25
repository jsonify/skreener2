using Microsoft.UI.Xaml;
using Skreener.App.Capture;
using Skreener.App.Shell;

namespace Skreener.App;

public partial class App : Application
{
    // Held for the process lifetime: owning this named mutex is what makes the first launch the only instance.
    private static Mutex? s_singleInstance;

    // Held so the window (and with it the process message loop) stays alive for the app's lifetime.
    private Window? _mainWindow;
    private ShellController? _shell;

    public App()
    {
        s_singleInstance = new Mutex(initiallyOwned: true, @"Local\Skreener.SingleInstance", out var isFirst);
        if (!isFirst)
        {
            // Already running: the existing instance lives in the tray, so a second launch just exits.
            Environment.Exit(0);
        }
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Skreener lives in the tray: the window is created but never activated, so it stays hidden.
        _mainWindow = new MainWindow();
        GC.KeepAlive(s_singleInstance);

        var notifier = new Notifier();
        notifier.Register();
        var settings = SettingsStore.Load();

        // Composition root: swapped for CaptureService when the capture branch merges.
        ICaptureService capture = new PlaceholderCaptureService(notifier);

        _shell = new ShellController(capture, notifier, settings);
        _shell.Start();
    }
}
