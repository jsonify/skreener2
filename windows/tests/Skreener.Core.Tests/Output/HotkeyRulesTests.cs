using Skreener.Core.Output;
using Xunit;

namespace Skreener.Core.Tests.Output;

public class HotkeyRulesTests
{
    private const HotkeyModifiers Ctrl = HotkeyModifiers.Control, Alt = HotkeyModifiers.Alt, Shift = HotkeyModifiers.Shift, Win = HotkeyModifiers.Win;

    [Theory]
    [InlineData(0x10u)] // Shift
    [InlineData(0x11u)] // Ctrl
    [InlineData(0x12u)] // Alt
    [InlineData(0x5Bu)] // left Win
    [InlineData(0x5Cu)] // right Win
    [InlineData(0xA2u)] // left Ctrl
    public void ModifierKeysAreIgnored(uint vk) =>
        Assert.Equal(RecordOutcome.Ignored, HotkeyRules.Interpret(vk, Ctrl).Outcome);

    [Fact]
    public void EscapeCancelsAndBackspaceOrDeleteResetsWhenNoModifierIsHeld()
    {
        Assert.Equal(RecordOutcome.Cancel, HotkeyRules.Interpret(0x1B, HotkeyModifiers.None).Outcome);
        Assert.Equal(RecordOutcome.Reset, HotkeyRules.Interpret(0x08, HotkeyModifiers.None).Outcome);
        Assert.Equal(RecordOutcome.Reset, HotkeyRules.Interpret(0x2E, HotkeyModifiers.None).Outcome);
    }

    [Fact]
    public void ModifiedEscapeIsNotACancel()
    {
        Assert.Equal(RecordOutcome.Rejected, HotkeyRules.Interpret(0x1B, Ctrl | Shift).Outcome); // Esc cannot be stored
    }

    [Fact]
    public void BuildsABindingFromKeyAndModifiers()
    {
        var r = HotkeyRules.Interpret('4', Ctrl | Alt);
        Assert.Equal(RecordOutcome.Binding, r.Outcome);
        Assert.Equal(new HotkeyBinding(Ctrl | Alt, '4'), r.Binding);
        Assert.Equal("Ctrl+Alt+4", r.Binding.ToString());
    }

    [Fact]
    public void FunctionKeysWork()
    {
        var r = HotkeyRules.Interpret(0x78, Alt); // F9
        Assert.Equal(RecordOutcome.Binding, r.Outcome);
        Assert.Equal("Alt+F9", r.Binding.ToString());
    }

    [Theory]
    [InlineData(HotkeyModifiers.None)]
    [InlineData(Shift)]
    public void RejectsWithoutCtrlAltOrWin(HotkeyModifiers mods)
    {
        var r = HotkeyRules.Interpret('A', mods);
        Assert.Equal(RecordOutcome.Rejected, r.Outcome);
        Assert.Contains("Ctrl", r.Message);
    }

    [Theory]
    [InlineData(0x20u)] // Space
    [InlineData(0x09u)] // Tab
    [InlineData(0x2Cu)] // PrintScreen
    [InlineData(0x60u)] // Numpad 0
    public void RejectsKeysThatCannotBeStored(uint vk)
    {
        var r = HotkeyRules.Interpret(vk, Ctrl | Alt);
        Assert.Equal(RecordOutcome.Rejected, r.Outcome);
        Assert.NotNull(r.Message);
    }

    [Fact]
    public void RecordedBindingsRoundTripThroughTheSettingsText()
    {
        foreach (uint vk in new uint[] { '0', '9', 'A', 'Z', 0x70, 0x87 })
        {
            var r = HotkeyRules.Interpret(vk, Ctrl | Shift);
            Assert.Equal(RecordOutcome.Binding, r.Outcome);
            Assert.True(HotkeyBinding.TryParse(r.Binding.ToString(), out var back));
            Assert.Equal(r.Binding, back);
        }
    }

    [Fact]
    public void FindsDuplicatesOfOtherActionsOnly()
    {
        var current = HotkeyRules.Resolve(new AppSettings());
        var area = HotkeyBinding.Defaults[HotkeyAction.CaptureArea];
        Assert.Null(HotkeyRules.FindDuplicate(HotkeyAction.CaptureArea, area, current)); // its own shortcut
        Assert.Equal(HotkeyAction.CaptureArea, HotkeyRules.FindDuplicate(HotkeyAction.CaptureWindow, area, current));
        Assert.Null(HotkeyRules.FindDuplicate(HotkeyAction.CaptureWindow, new HotkeyBinding(Ctrl | Alt, 'K'), current));
    }

    [Fact]
    public void ResolveFallsBackToDefaultsForMissingOrBadEntries()
    {
        var s = new AppSettings();
        s.Hotkeys[HotkeyAction.CaptureArea] = "Ctrl+Shift+K";
        s.Hotkeys[HotkeyAction.CaptureText] = "nonsense";
        var r = HotkeyRules.Resolve(s);
        Assert.Equal(Enum.GetValues<HotkeyAction>().Length, r.Count);
        Assert.Equal(new HotkeyBinding(Ctrl | Shift, 'K'), r[HotkeyAction.CaptureArea]);
        Assert.Equal(HotkeyBinding.Defaults[HotkeyAction.CaptureText], r[HotkeyAction.CaptureText]);
        Assert.Equal(HotkeyBinding.Defaults[HotkeyAction.CaptureWindow], r[HotkeyAction.CaptureWindow]);
    }

    [Fact]
    public void SetHotkeyStoresTextAndRemovesTheEntryForTheDefault()
    {
        var s = new AppSettings();
        HotkeyRules.SetHotkey(s, HotkeyAction.CaptureArea, new HotkeyBinding(Ctrl | Shift, 'K'));
        Assert.Equal("Ctrl+Shift+K", s.Hotkeys[HotkeyAction.CaptureArea]);
        Assert.Equal("Ctrl+Shift+K", AppSettings.FromJson(s.ToJson()).GetHotkey(HotkeyAction.CaptureArea).ToString());

        HotkeyRules.SetHotkey(s, HotkeyAction.CaptureArea, HotkeyBinding.Defaults[HotkeyAction.CaptureArea]);
        Assert.False(s.Hotkeys.ContainsKey(HotkeyAction.CaptureArea));
    }

    [Theory]
    [InlineData("Win+Shift+S")]
    [InlineData("Win+L")]
    [InlineData("Win+D")]
    [InlineData("Win+3")]
    [InlineData("Alt+0x09")]
    [InlineData("Alt+F4")]
    [InlineData("Ctrl+Shift+0x1B")]
    [InlineData("Win+0x2C")]
    [InlineData("Ctrl+C")]
    [InlineData("Alt+K")]
    public void WarnsAboutReservedAndCommonCombos(string text)
    {
        Assert.True(HotkeyBinding.TryParse(text, out var b));
        Assert.False(string.IsNullOrEmpty(HotkeyRules.ReservedWarning(b)));
    }

    [Fact]
    public void DoesNotWarnAboutTheDefaultsOrOrdinaryCombos()
    {
        foreach (var b in HotkeyBinding.Defaults.Values) Assert.Null(HotkeyRules.ReservedWarning(b));
        Assert.Null(HotkeyRules.ReservedWarning(new HotkeyBinding(Ctrl | Shift, 'K')));
        Assert.Null(HotkeyRules.ReservedWarning(new HotkeyBinding(Win | Alt, 'Z')));
        Assert.Null(HotkeyRules.ReservedWarning(new HotkeyBinding(Ctrl, 0x78))); // Ctrl+F9
    }
}
