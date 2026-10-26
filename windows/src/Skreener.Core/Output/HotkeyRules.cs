namespace Skreener.Core.Output;

/// <summary>What the shortcut recorder should do after a key press.</summary>
public enum RecordOutcome
{
    /// <summary>A modifier on its own: keep waiting for the real key.</summary>
    Ignored,
    /// <summary>Esc: stop recording and keep the old shortcut.</summary>
    Cancel,
    /// <summary>Backspace or Delete: go back to the default shortcut.</summary>
    Reset,
    /// <summary>A usable combination (still to be checked for duplicates).</summary>
    Binding,
    /// <summary>Not usable; <see cref="RecordResult.Message"/> says why. The recorder keeps listening.</summary>
    Rejected,
}

public readonly record struct RecordResult(RecordOutcome Outcome, HotkeyBinding Binding = default, string? Message = null);

/// <summary>Rules behind the Settings window's shortcut recorder: no UI, so they are tested on any OS.</summary>
public static class HotkeyRules
{
    private const uint VkBack = 0x08, VkEscape = 0x1B, VkDelete = 0x2E, VkShift = 0x10, VkMenu = 0x12,
        VkLWin = 0x5B, VkRWin = 0x5C, VkLShift = 0xA0, VkRMenu = 0xA5, VkPrintScreen = 0x2C, VkTab = 0x09,
        VkF4 = 0x73, VkSpace = 0x20;

    /// <summary>
    /// Turns a key-down plus the modifiers held at that moment into what the recorder should do.
    /// <paramref name="virtualKey"/> is a Win32 VK_* code.
    /// </summary>
    public static RecordResult Interpret(uint virtualKey, HotkeyModifiers modifiers)
    {
        if (IsModifierKey(virtualKey)) return new RecordResult(RecordOutcome.Ignored);
        if (modifiers == HotkeyModifiers.None)
        {
            if (virtualKey == VkEscape) return new RecordResult(RecordOutcome.Cancel);
            if (virtualKey is VkBack or VkDelete) return new RecordResult(RecordOutcome.Reset);
        }
        if (!IsSupportedKey(virtualKey))
            return new RecordResult(RecordOutcome.Rejected, Message: "Use a letter, a digit or a function key (F1 to F24).");
        if ((modifiers & (HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Win)) == 0)
            return new RecordResult(RecordOutcome.Rejected, Message: "Include Ctrl, Alt or Win (Shift alone would block typing).");
        return new RecordResult(RecordOutcome.Binding, new HotkeyBinding(modifiers, virtualKey));
    }

    /// <summary>Keys <see cref="HotkeyBinding"/> can write and read back by name: A-Z, 0-9, F1-F24.</summary>
    public static bool IsSupportedKey(uint vk) => vk is >= '0' and <= '9' or >= 'A' and <= 'Z' or >= 0x70 and <= 0x87;

    public static bool IsModifierKey(uint vk) => vk is >= VkShift and <= VkMenu or VkLWin or VkRWin or >= VkLShift and <= VkRMenu;

    /// <summary>The action (other than <paramref name="action"/>) that already uses <paramref name="binding"/>, or null.</summary>
    public static HotkeyAction? FindDuplicate(HotkeyAction action, HotkeyBinding binding, IReadOnlyDictionary<HotkeyAction, HotkeyBinding> current)
    {
        foreach (var (other, existing) in current)
            if (other != action && existing == binding) return other;
        return null;
    }

    /// <summary>Every action's effective shortcut (a missing or unparsable entry gives the default).</summary>
    public static Dictionary<HotkeyAction, HotkeyBinding> Resolve(AppSettings settings)
    {
        var result = new Dictionary<HotkeyAction, HotkeyBinding>();
        foreach (var action in Enum.GetValues<HotkeyAction>()) result[action] = settings.GetHotkey(action);
        return result;
    }

    /// <summary>Stores <paramref name="binding"/> for the action; the default is stored by removing the entry.</summary>
    public static void SetHotkey(AppSettings settings, HotkeyAction action, HotkeyBinding binding)
    {
        if (binding == HotkeyBinding.Defaults[action]) settings.Hotkeys.Remove(action);
        else settings.Hotkeys[action] = binding.ToString();
    }

    private static readonly (HotkeyModifiers Mods, uint Vk, string Warning)[] Reserved =
    {
        (HotkeyModifiers.Win | HotkeyModifiers.Shift, 'S', "Windows uses Win+Shift+S for the Snipping Tool, so it will most likely not register."),
        (HotkeyModifiers.Win, VkPrintScreen, "Windows uses Win+PrintScreen to save a screenshot."),
        (HotkeyModifiers.Win, 'L', "Windows uses Win+L to lock the PC, so it will not register."),
        (HotkeyModifiers.Win, 'D', "Windows uses Win+D to show the desktop."),
        (HotkeyModifiers.Win, 'E', "Windows uses Win+E to open File Explorer."),
        (HotkeyModifiers.Win, 'R', "Windows uses Win+R for the Run box."),
        (HotkeyModifiers.Win, 'V', "Windows uses Win+V for the clipboard history."),
        (HotkeyModifiers.Win, VkTab, "Windows uses Win+Tab for Task View."),
        (HotkeyModifiers.Alt, VkTab, "Windows uses Alt+Tab to switch windows, so it will not register."),
        (HotkeyModifiers.Alt, VkF4, "Alt+F4 closes the active window in almost every app."),
        (HotkeyModifiers.Alt, VkSpace, "Alt+Space opens the window menu in almost every app."),
        (HotkeyModifiers.Control | HotkeyModifiers.Shift, VkEscape, "Windows uses Ctrl+Shift+Esc to open Task Manager."),
        (HotkeyModifiers.Control | HotkeyModifiers.Alt, VkDelete, "Windows uses Ctrl+Alt+Delete, so it will not register."),
        (HotkeyModifiers.Control | HotkeyModifiers.Shift, VkTab, "Ctrl+Shift+Tab switches tabs in many apps."),
        (HotkeyModifiers.None, VkPrintScreen, "PrintScreen belongs to Windows (Snipping Tool)."),
        (HotkeyModifiers.Alt, VkPrintScreen, "Alt+PrintScreen copies the active window in Windows."),
    };

    /// <summary>
    /// A warning for combinations Windows or most apps already use, or null. It is advice, not a ban: the combination can
    /// still be tried (Windows decides whether it registers).
    /// </summary>
    public static string? ReservedWarning(HotkeyBinding binding)
    {
        foreach (var (mods, vk, warning) in Reserved)
            if (binding.Modifiers == mods && binding.VirtualKey == vk) return warning;

        // Win+digit starts or switches the taskbar app.
        if (binding.Modifiers == HotkeyModifiers.Win && binding.VirtualKey is >= '0' and <= '9')
            return "Windows uses Win+" + (char)binding.VirtualKey + " for the taskbar.";

        // Ctrl (or Alt) + one letter or digit is a shortcut in nearly every app; registering it takes it from all of them.
        var onlyCtrlOrAlt = binding.Modifiers is HotkeyModifiers.Control or HotkeyModifiers.Alt;
        if (onlyCtrlOrAlt && binding.VirtualKey is (>= '0' and <= '9') or (>= 'A' and <= 'Z'))
            return binding + " is a shortcut in many apps; Skreener would take it from all of them. Adding Shift or another modifier avoids that.";
        return null;
    }
}
