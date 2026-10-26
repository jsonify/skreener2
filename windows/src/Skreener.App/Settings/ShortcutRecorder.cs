using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Skreener.Core.Output;
using Windows.System;
using Windows.UI.Core;

namespace Skreener.App.Settings;

/// <summary>
/// A button that shows a shortcut; click it (or press Enter or Space on it), then press the new combination.
/// Esc cancels, Backspace or Delete asks for the default. The rules live in <see cref="HotkeyRules"/>.
/// </summary>
internal sealed class ShortcutRecorder : Button
{
    private string _shown = "";

    public bool IsRecording { get; private set; }

    /// <summary>Recording began (the owner should unregister the global hotkeys).</summary>
    public event Action? Started;
    /// <summary>Recording ended with a combination, Reset or Cancel (also when focus is lost).</summary>
    public event Action<RecordResult>? Finished;
    /// <summary>A key press that cannot be used; recording goes on.</summary>
    public event Action<string>? Rejected;

    public ShortcutRecorder()
    {
        Width = 180;
        HorizontalContentAlignment = HorizontalAlignment.Center;
        Click += (_, _) => Start();
        LostFocus += (_, _) => Cancel();
    }

    public void Show(HotkeyBinding binding)
    {
        _shown = binding.ToString();
        if (!IsRecording) Content = _shown;
    }

    public void Cancel()
    {
        if (!IsRecording) return;
        Stop();
        Finished?.Invoke(new RecordResult(RecordOutcome.Cancel));
    }

    private void Start()
    {
        if (IsRecording) return;
        IsRecording = true;
        Content = "Press a shortcut…";
        Started?.Invoke();
        Focus(FocusState.Keyboard);
    }

    private void Stop()
    {
        IsRecording = false;
        Content = _shown;
    }

    protected override void OnKeyDown(KeyRoutedEventArgs e)
    {
        if (!IsRecording)
        {
            // Enter and Space start recording on key-up; keep the button's own press handling out of it.
            if (e.Key is VirtualKey.Enter or VirtualKey.Space) e.Handled = true;
            else base.OnKeyDown(e);
            return;
        }

        e.Handled = true;
        var result = HotkeyRules.Interpret((uint)e.Key, CurrentModifiers());
        switch (result.Outcome)
        {
            case RecordOutcome.Ignored:
                break;
            case RecordOutcome.Rejected:
                Rejected?.Invoke(result.Message ?? "That shortcut cannot be used.");
                break;
            default:
                Stop();
                Finished?.Invoke(result);
                break;
        }
    }

    protected override void OnKeyUp(KeyRoutedEventArgs e)
    {
        if (IsRecording) { e.Handled = true; return; }
        if (e.Key is VirtualKey.Enter or VirtualKey.Space)
        {
            e.Handled = true;
            Start();
            return;
        }
        base.OnKeyUp(e);
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private static HotkeyModifiers CurrentModifiers()
    {
        var mods = HotkeyModifiers.None;
        if (IsDown(VirtualKey.Control)) mods |= HotkeyModifiers.Control;
        if (IsDown(VirtualKey.Menu)) mods |= HotkeyModifiers.Alt;
        if (IsDown(VirtualKey.Shift)) mods |= HotkeyModifiers.Shift;
        if (IsDown(VirtualKey.LeftWindows) || IsDown(VirtualKey.RightWindows)) mods |= HotkeyModifiers.Win;
        return mods;
    }
}
