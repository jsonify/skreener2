using Skreener.Core.Output;
using Xunit;

namespace Skreener.Core.Tests.Output;

public class HotkeyBindingTests
{
    [Fact]
    public void DefaultsAreDistinctAndAvoidShellCombos()
    {
        Assert.Equal(4, HotkeyBinding.Defaults.Count);
        Assert.Equal(4, HotkeyBinding.Defaults.Values.Distinct().Count());
        foreach (var b in HotkeyBinding.Defaults.Values)
        {
            Assert.False(b.Modifiers.HasFlag(HotkeyModifiers.Win));
            Assert.NotEqual(HotkeyModifiers.Control | HotkeyModifiers.Shift, b.Modifiers);
        }
    }

    [Theory]
    [InlineData("Ctrl+Alt+4")]
    [InlineData("Ctrl+Shift+F12")]
    [InlineData("Alt+Win+Z")]
    public void ParseAndFormatRoundTrip(string text)
    {
        Assert.True(HotkeyBinding.TryParse(text, out var b));
        Assert.Equal(text, b.ToString());
    }

    [Fact]
    public void ParseIsCaseInsensitive()
    {
        Assert.True(HotkeyBinding.TryParse("control + alt + f5", out var b));
        Assert.Equal(HotkeyModifiers.Control | HotkeyModifiers.Alt, b.Modifiers);
        Assert.Equal(0x74u, b.VirtualKey);
    }

    [Theory]
    [InlineData("")]
    [InlineData("4")]
    [InlineData("Ctrl")]
    [InlineData("Ctrl+4+5")]
    [InlineData("Ctrl+F25")]
    [InlineData("Ctrl+Hyper")]
    public void RejectsInvalid(string text) => Assert.False(HotkeyBinding.TryParse(text, out _));
}
