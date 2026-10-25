using Skreener.Core.Output;
using Xunit;

namespace Skreener.Core.Tests.Output;

public class AppSettingsTests
{
    [Fact]
    public void DefaultsMatchTheMacApp()
    {
        var s = AppSettings.FromJson(null);
        Assert.Equal(ImageFormat.Png, s.ImageFormat);
        Assert.Equal(FileNaming.DefaultTemplate, s.FilenameTemplate);
        Assert.True(s.CopyToClipboard);
        Assert.True(s.SaveToFile);
        Assert.True(s.ShowQuickAccess);
        Assert.Equal(Path.Combine("pics", "Skreener"), s.ResolveSaveFolder("pics"));
    }

    [Fact]
    public void RoundTrips()
    {
        var s = new AppSettings
        {
            SaveFolder = @"D:\Shots",
            ImageFormat = ImageFormat.Jpeg,
            FilenameTemplate = "%Y-%m-%d",
            CopyToClipboard = false,
            SaveToFile = false,
            ShowQuickAccess = false,
            QuickAccessSeconds = 12,
        };
        s.Hotkeys[HotkeyAction.CaptureArea] = "Ctrl+Shift+F9";
        var back = AppSettings.FromJson(s.ToJson());
        Assert.Equal(@"D:\Shots", back.ResolveSaveFolder("ignored"));
        Assert.Equal(ImageFormat.Jpeg, back.ImageFormat);
        Assert.Equal("%Y-%m-%d", back.FilenameTemplate);
        Assert.False(back.CopyToClipboard);
        Assert.False(back.SaveToFile);
        Assert.False(back.ShowQuickAccess);
        Assert.Equal(12, back.QuickAccessSeconds);
        Assert.Equal("Ctrl+Shift+F9", back.GetHotkey(HotkeyAction.CaptureArea).ToString());
    }

    [Fact]
    public void FormatIsStoredAsText() =>
        Assert.Contains("\"Jpeg\"", new AppSettings { ImageFormat = ImageFormat.Jpeg }.ToJson());

    [Theory]
    [InlineData("")]
    [InlineData("{ not json")]
    [InlineData("null")]
    [InlineData("{\"ImageFormat\": \"Gif\"}")]
    public void BrokenJsonFallsBackToDefaults(string json)
    {
        var s = AppSettings.FromJson(json);
        Assert.Equal(ImageFormat.Png, s.ImageFormat);
        Assert.Equal(FileNaming.DefaultTemplate, s.FilenameTemplate);
    }

    [Fact]
    public void OutOfRangeValuesAreRepaired()
    {
        var s = AppSettings.FromJson("{\"QuickAccessSeconds\": 0, \"FilenameTemplate\": \" \", \"ImageFormat\": 7}");
        Assert.Equal(6, s.QuickAccessSeconds);
        Assert.Equal(FileNaming.DefaultTemplate, s.FilenameTemplate);
        Assert.Equal(ImageFormat.Png, s.ImageFormat);
    }

    [Fact]
    public void PartialFileKeepsOtherDefaults()
    {
        var s = AppSettings.FromJson("{\"CopyToClipboard\": false}");
        Assert.False(s.CopyToClipboard);
        Assert.True(s.SaveToFile);
    }

    [Fact]
    public void BadHotkeyFallsBackToDefault()
    {
        var s = AppSettings.FromJson("{\"Hotkeys\": {\"CaptureArea\": \"banana\", \"CaptureWindow\": \"Ctrl+Alt+9\"}}");
        Assert.Equal(HotkeyBinding.Defaults[HotkeyAction.CaptureArea], s.GetHotkey(HotkeyAction.CaptureArea));
        Assert.Equal("Ctrl+Alt+9", s.GetHotkey(HotkeyAction.CaptureWindow).ToString());
        Assert.Equal(HotkeyBinding.Defaults[HotkeyAction.CaptureFullscreen], s.GetHotkey(HotkeyAction.CaptureFullscreen));
    }
}
