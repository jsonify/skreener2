using System.Globalization;

namespace Skreener.Core.Output;

/// <summary>Modifier bits; the values match the Win32 MOD_* constants used by RegisterHotKey.</summary>
[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 0x1,
    Control = 0x2,
    Shift = 0x4,
    Win = 0x8,
}

public enum HotkeyAction { CaptureArea, CaptureWindow, CaptureFullscreen, CapturePreviousArea }

/// <summary>A key combination as stored in settings, e.g. <c>Ctrl+Alt+4</c>. <see cref="VirtualKey"/> is a Win32 VK_* code.</summary>
public readonly record struct HotkeyBinding(HotkeyModifiers Modifiers, uint VirtualKey)
{
    /// <summary>
    /// Windows defaults. The Mac's Ctrl+Shift+digit is the keyboard-layout switch for many users, and Win+Shift+S and
    /// PrintScreen belong to the Snipping Tool, so the digits are kept (same numbers as the Mac) with Ctrl+Alt.
    /// </summary>
    public static IReadOnlyDictionary<HotkeyAction, HotkeyBinding> Defaults { get; } = new Dictionary<HotkeyAction, HotkeyBinding>
    {
        [HotkeyAction.CaptureArea] = new(HotkeyModifiers.Control | HotkeyModifiers.Alt, '4'),
        [HotkeyAction.CaptureFullscreen] = new(HotkeyModifiers.Control | HotkeyModifiers.Alt, '3'),
        [HotkeyAction.CaptureWindow] = new(HotkeyModifiers.Control | HotkeyModifiers.Alt, '5'),
        [HotkeyAction.CapturePreviousArea] = new(HotkeyModifiers.Control | HotkeyModifiers.Alt, '1'),
    };

    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
        parts.Add(KeyName(VirtualKey));
        return string.Join('+', parts);
    }

    /// <summary>Parses <c>Ctrl+Alt+4</c>, <c>Shift+F9</c>... (case-insensitive). Needs at least one modifier and exactly one key.</summary>
    public static bool TryParse(string? text, out HotkeyBinding binding)
    {
        binding = default;
        if (string.IsNullOrWhiteSpace(text)) return false;
        var mods = HotkeyModifiers.None;
        uint? key = null;
        foreach (var raw in text.Split('+', StringSplitOptions.TrimEntries))
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl":
                case "control": mods |= HotkeyModifiers.Control; continue;
                case "alt": mods |= HotkeyModifiers.Alt; continue;
                case "shift": mods |= HotkeyModifiers.Shift; continue;
                case "win": mods |= HotkeyModifiers.Win; continue;
            }
            if (key != null || !TryKey(raw, out var vk)) return false;
            key = vk;
        }
        if (key == null || mods == HotkeyModifiers.None) return false;
        binding = new HotkeyBinding(mods, key.Value);
        return true;
    }

    private static string KeyName(uint vk)
    {
        if (vk is >= '0' and <= '9' or >= 'A' and <= 'Z') return ((char)vk).ToString();
        if (vk is >= 0x70 and <= 0x87) return "F" + (vk - 0x70 + 1);
        return "0x" + vk.ToString("X2", CultureInfo.InvariantCulture);
    }

    private static bool TryKey(string name, out uint vk)
    {
        vk = 0;
        if (name.Length == 1)
        {
            var c = char.ToUpperInvariant(name[0]);
            if (c is >= '0' and <= '9' or >= 'A' and <= 'Z')
            {
                vk = c;
                return true;
            }
            return false;
        }
        if (name.Length is 2 or 3 && (name[0] == 'F' || name[0] == 'f')
            && int.TryParse(name.AsSpan(1), NumberStyles.None, CultureInfo.InvariantCulture, out var f) && f is >= 1 and <= 24)
        {
            vk = (uint)(0x70 + f - 1);
            return true;
        }
        if (name.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            && uint.TryParse(name.AsSpan(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var raw) && raw is > 0 and < 0xFF)
        {
            vk = raw;
            return true;
        }
        return false;
    }
}
