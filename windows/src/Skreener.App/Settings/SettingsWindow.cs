using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Skreener.App.Shell;
using Skreener.Core.Output;
using Windows.Graphics;
using Windows.Storage.Pickers;
using Windows.Win32;
using Windows.Win32.Foundation;

namespace Skreener.App.Settings;

/// <summary>
/// The Settings window (port of SettingsWindow.swift): General, Screenshots, After capture and Shortcuts. Every change is
/// written to settings.json at once and takes effect without a restart; there is no OK button. The rules (shortcut
/// checks, clamping, file-name preview) are in Skreener.Core; this class only builds the controls and wires them.
/// </summary>
internal sealed class SettingsWindow : Window
{
    private const double WindowWidth = 640, WindowHeight = 800; // DIPs
    private const string InUseMessage = "In use by another app";

    private readonly ISettingsHost _host;
    private AppSettings _settings;
    /// <summary>True while the controls are being filled from the settings, so their events do not write back.</summary>
    private bool _loading = true;

    private readonly ToggleSwitch _launchAtLogin = new();
    private readonly TextBlock _generalMessage = MessageText();
    private readonly TextBox _folderBox = new() { MinWidth = 280, HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly TextBlock _folderMessage = MessageText();
    private readonly ComboBox _format = new() { MinWidth = 120 };
    private readonly TextBox _template = new() { HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly TextBlock _preview = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.8 };
    private readonly CheckBox _copy = new() { Content = "Copy to clipboard" };
    private readonly CheckBox _save = new() { Content = "Save to file" };
    private readonly CheckBox _quickAccess = new() { Content = "Show Quick Access thumbnail" };
    private readonly NumberBox _seconds = new()
    {
        Minimum = SettingsRules.MinQuickAccessSeconds,
        Maximum = SettingsRules.MaxQuickAccessSeconds,
        SmallChange = 1,
        SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline,
        Width = 130,
    };
    private readonly Dictionary<HotkeyAction, ShortcutRow> _rows = new();
    private readonly DispatcherQueueTimer _previewTimer;

    private sealed class ShortcutRow
    {
        public required HotkeyAction Action { get; init; }
        public required ShortcutRecorder Recorder { get; init; }
        public required Button Default { get; init; }
        public required TextBlock Message { get; init; }
        /// <summary>The message currently shown is "In use by another app" (so a later successful registration clears it).</summary>
        public bool InUse { get; set; }
    }

    public SettingsWindow(ISettingsHost host)
    {
        _host = host;
        _settings = LoadFresh();
        Title = "Skreener Settings";
        SystemBackdrop = new MicaBackdrop();

        Content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = BuildContent(),
        };

        _previewTimer = DispatcherQueue.CreateTimer();
        _previewTimer.Interval = TimeSpan.FromSeconds(1);
        _previewTimer.IsRepeating = true;
        _previewTimer.Tick += (_, _) => UpdatePreview();

        var hwnd = Handle;
        var scale = Math.Max(PInvoke.GetDpiForWindow(hwnd), 96u) / 96.0;
        AppWindow.Resize(new SizeInt32((int)Math.Round(WindowWidth * scale), (int)Math.Round(WindowHeight * scale)));
        var icon = System.IO.Path.Combine(AppContext.BaseDirectory, "Shell/Assets/tray.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);

        LoadControls();
        _loading = false;

        Activated += OnActivated;
        Closed += OnClosed;
        _previewTimer.Start();
        // Show what is true right now: a shortcut another app owns is marked on its row.
        MarkInUse(_host.ApplyHotkeys(_settings));
    }

    private HWND Handle => new(WinRT.Interop.WindowNative.GetWindowHandle(this));

    /// <summary>Called when Settings… is chosen again: restore if minimized and bring to the front.</summary>
    public void BringToFront()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } presenter) presenter.Restore();
        Activate();
        _ = PInvoke.SetForegroundWindow(Handle);
    }

    // ---- building the controls ----

    private UIElement BuildContent()
    {
        var panel = new StackPanel { Spacing = 8, Padding = new Thickness(28, 12, 28, 28) };

        panel.Children.Add(Heading("General"));
        _launchAtLogin.OnContent = "On";
        _launchAtLogin.OffContent = "Off";
        _launchAtLogin.Toggled += OnLaunchAtLoginToggled;
        panel.Children.Add(Field("Launch at Login", _launchAtLogin));
        panel.Children.Add(_generalMessage);

        panel.Children.Add(Heading("Screenshots"));
        panel.Children.Add(BuildFolderRow());
        panel.Children.Add(_folderMessage);
        _format.Items.Add("PNG");
        _format.Items.Add("JPEG");
        _format.SelectionChanged += OnFormatChanged;
        panel.Children.Add(Field("Format", _format));
        _template.TextChanged += OnTemplateChanged;
        _template.LostFocus += (_, _) => { if (string.IsNullOrWhiteSpace(_template.Text)) _template.Text = FileNaming.DefaultTemplate; };
        panel.Children.Add(Field("File name", _template));
        panel.Children.Add(Field("Next file", _preview));
        panel.Children.Add(Note("Tokens: %Y year, %y two-digit year, %m month, %d day, %H hour, %M minute, %S second, %% a percent sign."));

        panel.Children.Add(Heading("After capture"));
        _copy.Click += (_, _) => Change(s => s.CopyToClipboard = _copy.IsChecked == true);
        _save.Click += (_, _) => Change(s => s.SaveToFile = _save.IsChecked == true);
        _quickAccess.Click += OnQuickAccessClicked;
        _seconds.ValueChanged += OnSecondsChanged;
        panel.Children.Add(_copy);
        panel.Children.Add(_save);
        panel.Children.Add(_quickAccess);
        panel.Children.Add(Field("Quick Access seconds", _seconds));

        panel.Children.Add(Heading("Shortcuts"));
        panel.Children.Add(Note("Click a shortcut, then press the new combination. Esc cancels; Backspace or Delete restores the default."));
        foreach (var action in Enum.GetValues<HotkeyAction>()) panel.Children.Add(BuildShortcutRow(action));
        return panel;
    }

    private UIElement BuildFolderRow()
    {
        var browse = new Button { Content = "Browse…" };
        var reset = new Button { Content = "Reset" };
        var open = new Button { Content = "Open Folder" };
        browse.Click += async (_, _) => await BrowseAsync();
        reset.Click += (_, _) => { _folderBox.Text = ""; CommitFolder(); };
        open.Click += (_, _) => OpenFolder();
        _folderBox.LostFocus += (_, _) => CommitFolder();
        _folderBox.KeyDown += (_, e) =>
        {
            if (e.Key != Windows.System.VirtualKey.Enter) return;
            e.Handled = true;
            CommitFolder();
        };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Children = { browse, reset, open } };
        var stack = new StackPanel { Spacing = 8, Children = { _folderBox, buttons } };
        return Field("Save folder", stack);
    }

    private UIElement BuildShortcutRow(HotkeyAction action)
    {
        var recorder = new ShortcutRecorder();
        var reset = new Button { Content = "Default" };
        var message = MessageText();
        var row = new ShortcutRow { Action = action, Recorder = recorder, Default = reset, Message = message };
        _rows[action] = row;

        recorder.Started += () => OnRecordingStarted(row);
        recorder.Rejected += text => SetMessage(row, text, isError: true);
        recorder.Finished += result => OnRecordingFinished(row, result);
        reset.Click += (_, _) => CommitHotkey(row, HotkeyBinding.Defaults[action]);

        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = new TextBlock { Text = HotkeyManager.Describe(action), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(recorder, 1);
        Grid.SetColumn(reset, 2);
        grid.Children.Add(title);
        grid.Children.Add(recorder);
        grid.Children.Add(reset);
        return new StackPanel { Spacing = 2, Children = { grid, message } };
    }

    private static TextBlock Heading(string text) => new()
    {
        Text = text,
        FontSize = 18,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 16, 0, 2),
    };

    private static TextBlock Note(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap, Opacity = 0.7, FontSize = 12 };

    private static TextBlock MessageText() => new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Visibility = Visibility.Collapsed };

    private static Grid Field(string label, UIElement control)
    {
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn((FrameworkElement)control, 1);
        grid.Children.Add(text);
        grid.Children.Add(control);
        return grid;
    }

    private static void ShowMessage(TextBlock block, string text, bool isError)
    {
        block.Text = text;
        block.Foreground = new SolidColorBrush(isError ? Colors.IndianRed : Colors.DarkOrange);
        block.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
    }

    // ---- settings in and out ----

    /// <summary>The settings from disk; never throws (a missing or broken file gives defaults).</summary>
    private AppSettings LoadFresh()
    {
        try { return _host.Load(); }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: could not load settings: {e.Message}");
            return _settings ?? new AppSettings();
        }
    }

    /// <summary>Applies one edit to the settings as they are on disk now (so edits made to the file by hand are kept) and saves.</summary>
    private void Change(Action<AppSettings> edit)
    {
        if (_loading) return;
        var settings = LoadFresh();
        edit(settings);
        try { _host.Save(settings); }
        catch (Exception e) { Debug.WriteLine($"Skreener: could not save settings: {e.Message}"); }
        _settings = settings;
        UpdatePreview();
    }

    private void LoadControls()
    {
        _launchAtLogin.IsOn = LaunchAtLogin.IsEnabled;
        _folderBox.Text = _settings.ResolveSaveFolder(SettingsStore.PicturesFolder);
        _format.SelectedIndex = _settings.ImageFormat == ImageFormat.Png ? 0 : 1;
        _template.Text = _settings.FilenameTemplate;
        _copy.IsChecked = _settings.CopyToClipboard;
        _save.IsChecked = _settings.SaveToFile;
        _quickAccess.IsChecked = _settings.ShowQuickAccess;
        _seconds.Value = _settings.QuickAccessSeconds;
        _seconds.IsEnabled = _settings.ShowQuickAccess;
        RefreshRows();
        UpdatePreview();
    }

    // ---- General ----

    private void OnLaunchAtLoginToggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        var wanted = _launchAtLogin.IsOn;
        try
        {
            LaunchAtLogin.SetEnabled(wanted);
            ShowMessage(_generalMessage, "", false);
        }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            ShowMessage(_generalMessage, "Could not change Launch at Login: " + ex.Message, true);
            _loading = true;
            _launchAtLogin.IsOn = LaunchAtLogin.IsEnabled;
            _loading = false;
        }
    }

    // ---- Screenshots ----

    private static string DefaultFolder => new AppSettings().ResolveSaveFolder(SettingsStore.PicturesFolder);

    private void CommitFolder()
    {
        if (_loading) return;
        var text = SettingsRules.NormalizeFolder(_folderBox.Text);
        var problem = SettingsRules.FolderProblem(text);
        if (problem is not null)
        {
            ShowMessage(_folderMessage, problem + " The folder was not changed.", true);
            return;
        }
        ShowMessage(_folderMessage, "", false);
        var isDefault = text is null
            || string.Equals(text.TrimEnd('\\', '/'), DefaultFolder.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase);
        var stored = isDefault ? null : text;
        Change(s => s.SaveFolder = stored);
        _folderBox.Text = _settings.ResolveSaveFolder(SettingsStore.PicturesFolder);
    }

    private async Task BrowseAsync()
    {
        try
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary };
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
            var folder = await picker.PickSingleFolderAsync();
            if (folder is null) return;
            _folderBox.Text = folder.Path;
            CommitFolder();
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Skreener: folder picker failed: {e}");
            ShowMessage(_folderMessage, "Could not open the folder picker: " + e.Message, true);
        }
    }

    private void OpenFolder()
    {
        try
        {
            var folder = _settings.ResolveSaveFolder(SettingsStore.PicturesFolder);
            Directory.CreateDirectory(folder);
            Explorer.Reveal(folder);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or NotSupportedException or ArgumentException)
        {
            ShowMessage(_folderMessage, "Could not open the folder: " + e.Message, true);
        }
    }

    private void OnFormatChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || _format.SelectedIndex < 0) return;
        var format = _format.SelectedIndex == 0 ? ImageFormat.Png : ImageFormat.Jpeg;
        Change(s => s.ImageFormat = format);
    }

    private void OnTemplateChanged(object sender, TextChangedEventArgs e)
    {
        UpdatePreview();
        if (_loading || string.IsNullOrWhiteSpace(_template.Text)) return; // a blank template waits for the user to type or leave the box
        var template = _template.Text;
        Change(s => s.FilenameTemplate = template);
    }

    /// <summary>The next file name, from the template being typed and the saved folder and format.</summary>
    private void UpdatePreview()
    {
        var preview = new AppSettings
        {
            SaveFolder = _settings.SaveFolder,
            ImageFormat = _settings.ImageFormat,
            FilenameTemplate = _template.Text,
        };
        _preview.Text = SettingsRules.NextFileName(preview, SettingsStore.PicturesFolder, DateTime.Now);
    }

    // ---- After capture ----

    private void OnQuickAccessClicked(object sender, RoutedEventArgs e)
    {
        var on = _quickAccess.IsChecked == true;
        _seconds.IsEnabled = on;
        Change(s => s.ShowQuickAccess = on);
    }

    private void OnSecondsChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading) return;
        var seconds = SettingsRules.ClampQuickAccessSeconds(sender.Value, _settings.QuickAccessSeconds);
        if (double.IsNaN(sender.Value) || Math.Abs(sender.Value - seconds) > 0.001)
        {
            _loading = true;
            sender.Value = seconds; // shows the clamped value in place of what was typed
            _loading = false;
        }
        Change(s => s.QuickAccessSeconds = seconds);
    }

    // ---- Shortcuts ----

    private void RefreshRows()
    {
        var resolved = HotkeyRules.Resolve(_settings);
        foreach (var (action, row) in _rows)
        {
            row.Recorder.Show(resolved[action]);
            row.Default.IsEnabled = resolved[action] != HotkeyBinding.Defaults[action];
        }
    }

    private void SetMessage(ShortcutRow row, string text, bool isError)
    {
        row.InUse = false;
        ShowMessage(row.Message, text, isError);
    }

    /// <summary>Marks the rows whose combination another app owns, and clears that mark from the others.</summary>
    private void MarkInUse(IReadOnlyList<HotkeyAction> failed)
    {
        foreach (var (action, row) in _rows)
        {
            if (failed.Contains(action))
            {
                SetMessage(row, InUseMessage, isError: true);
                row.InUse = true;
            }
            else if (row.InUse) SetMessage(row, "", isError: false);
        }
    }

    private void OnRecordingStarted(ShortcutRow row)
    {
        SetMessage(row, "", isError: false);
        _host.SuspendHotkeys(); // so the combination being pressed does not trigger a capture
    }

    private void OnRecordingFinished(ShortcutRow row, RecordResult result)
    {
        switch (result.Outcome)
        {
            case RecordOutcome.Reset:
                CommitHotkey(row, HotkeyBinding.Defaults[row.Action]);
                break;
            case RecordOutcome.Binding:
                CommitHotkey(row, result.Binding);
                break;
            default: // cancelled, or focus went elsewhere
                SetMessage(row, "", isError: false);
                MarkInUse(_host.ApplyHotkeys(LoadFresh()));
                break;
        }
    }

    /// <summary>Checks a new shortcut, registers it and saves it; on any problem the old one stays and the row says why.</summary>
    private void CommitHotkey(ShortcutRow row, HotkeyBinding binding)
    {
        var action = row.Action;
        var old = LoadFresh();
        var resolved = HotkeyRules.Resolve(old);

        if (resolved[action] == binding)
        {
            MarkInUse(_host.ApplyHotkeys(old)); // recording unregistered everything
            _settings = old;
            RefreshRows();
            SetMessage(row, HotkeyRules.ReservedWarning(binding) ?? "", isError: false);
            return;
        }

        if (HotkeyRules.FindDuplicate(action, binding, resolved) is { } other)
        {
            MarkInUse(_host.ApplyHotkeys(old));
            _settings = old;
            RefreshRows();
            SetMessage(row, $"Already used by {HotkeyManager.Describe(other)}. Kept {resolved[action]}.", isError: true);
            return;
        }

        var candidate = LoadFresh();
        HotkeyRules.SetHotkey(candidate, action, binding);
        var failed = _host.ApplyHotkeys(candidate);
        if (failed.Contains(action))
        {
            MarkInUse(_host.ApplyHotkeys(old)); // back to the old shortcut, which is still registered afterwards
            _settings = old;
            RefreshRows();
            SetMessage(row, $"{InUseMessage}. Kept {resolved[action]}.", isError: true);
            row.InUse = true;
            return;
        }

        try { _host.Save(candidate); }
        catch (Exception e) { Debug.WriteLine($"Skreener: could not save settings: {e.Message}"); }
        _settings = candidate;
        MarkInUse(failed);
        RefreshRows();
        SetMessage(row, HotkeyRules.ReservedWarning(binding) ?? "", isError: false);
    }

    // ---- window ----

    private void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        // Switching away mid-recording must not leave the global hotkeys off.
        if (args.WindowActivationState == WindowActivationState.Deactivated)
            foreach (var row in _rows.Values) row.Recorder.Cancel();
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _previewTimer.Stop();
        foreach (var row in _rows.Values) row.Recorder.Cancel();
    }
}
