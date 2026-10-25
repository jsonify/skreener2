using Skreener.Core.Output;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.Input.KeyboardAndMouse;

namespace Skreener.App.Shell;

/// <summary>Global hotkeys through RegisterHotKey (port of HotKeys.swift). Ids are the <see cref="HotkeyAction"/> value + 1.</summary>
internal sealed class HotkeyManager : IDisposable
{
    private const uint ModNoRepeat = 0x4000;

    private readonly HWND _window;
    private readonly List<int> _registered = new();

    public HotkeyManager(HWND window) => _window = window;

    public static HotkeyAction ActionFor(int id) => (HotkeyAction)(id - 1);

    /// <summary>Registers every action; returns a readable line for each combination another app already owns.</summary>
    public IReadOnlyList<string> RegisterAll(AppSettings settings)
    {
        var failures = new List<string>();
        foreach (var action in Enum.GetValues<HotkeyAction>())
        {
            var binding = settings.GetHotkey(action);
            var id = (int)action + 1;
            var modifiers = (HOT_KEY_MODIFIERS)((uint)binding.Modifiers | ModNoRepeat);
            bool ok = PInvoke.RegisterHotKey(_window, id, modifiers, binding.VirtualKey);
            if (ok) _registered.Add(id);
            else failures.Add($"{binding} ({Describe(action)})");
        }
        return failures;
    }

    public static string Describe(HotkeyAction action) => action switch
    {
        HotkeyAction.CaptureArea => "Capture Area",
        HotkeyAction.CaptureWindow => "Capture Window",
        HotkeyAction.CaptureFullscreen => "Capture Fullscreen",
        HotkeyAction.CapturePreviousArea => "Capture Previous Area",
        _ => action.ToString(),
    };

    public void Dispose()
    {
        foreach (var id in _registered) PInvoke.UnregisterHotKey(_window, id);
        _registered.Clear();
    }
}
