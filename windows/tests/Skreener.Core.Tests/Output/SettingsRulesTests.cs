using Skreener.Core.Output;
using Xunit;

namespace Skreener.Core.Tests.Output;

public class SettingsRulesTests
{
    [Theory]
    [InlineData(6, 6)]
    [InlineData(1, 1)]
    [InlineData(60, 60)]
    [InlineData(0, 1)]
    [InlineData(-5, 1)]
    [InlineData(61, 60)]
    [InlineData(1000, 60)]
    [InlineData(2.4, 2)]
    [InlineData(2.5, 3)]
    public void ClampsQuickAccessSeconds(double input, int expected) =>
        Assert.Equal(expected, SettingsRules.ClampQuickAccessSeconds(input, 6));

    [Fact]
    public void NotANumberKeepsTheFallback()
    {
        Assert.Equal(9, SettingsRules.ClampQuickAccessSeconds(double.NaN, 9));
        Assert.Equal(60, SettingsRules.ClampQuickAccessSeconds(double.NaN, 500));
        Assert.Equal(60, SettingsRules.ClampQuickAccessSeconds(double.PositiveInfinity, 6));
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData("", null)]
    [InlineData("   ", null)]
    [InlineData("\"C:\\Shots\"", "C:\\Shots")]
    [InlineData("  C:\\Shots  ", "C:\\Shots")]
    public void NormalizesTheFolderText(string? input, string? expected) =>
        Assert.Equal(expected, SettingsRules.NormalizeFolder(input));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("C:\\Users\\me\\Pictures\\Skreener")]
    [InlineData("D:\\Not\\Yet\\Created")]
    [InlineData("\\\\server\\share\\shots")]
    public void AcceptsUsableFolders(string? folder) => Assert.Null(SettingsRules.FolderProblem(folder));

    [Theory]
    [InlineData("shots")]
    [InlineData("C:shots")]
    [InlineData("C:\\a*b")]
    [InlineData("C:\\a?b")]
    [InlineData("C:\\a|b")]
    [InlineData("C:\\a<b>")]
    [InlineData("C:\\a:b")]
    public void RejectsUnusableFolders(string folder) => Assert.NotNull(SettingsRules.FolderProblem(folder));

    [Fact]
    public void NextFileNameUsesTemplateFormatAndTheDate()
    {
        var s = new AppSettings { FilenameTemplate = "Shot %Y%m%d-%H%M%S", ImageFormat = ImageFormat.Jpeg };
        var name = SettingsRules.NextFileName(s, "P", new DateTime(2026, 10, 26, 14, 3, 5), _ => false);
        Assert.Equal("Shot 20261026-140305.jpg", name);
    }

    [Fact]
    public void NextFileNameDefaultsAndAddsNumberWhenTheFileExists()
    {
        var s = new AppSettings();
        var now = new DateTime(2026, 10, 26, 14, 3, 5);
        Assert.Equal("Skreener 2026-10-26 at 14.03.05.png", SettingsRules.NextFileName(s, "P", now, _ => false));
        Assert.Equal("Skreener 2026-10-26 at 14.03.05 2.png",
            SettingsRules.NextFileName(s, "P", now, p => p.EndsWith("05.png", StringComparison.Ordinal)));
    }

    [Fact]
    public void NextFileNameChecksTheChosenFolder()
    {
        var s = new AppSettings { SaveFolder = Path.Combine("X", "Custom") };
        string? asked = null;
        SettingsRules.NextFileName(s, "P", DateTime.Now, p => { asked = p; return false; });
        Assert.Equal(Path.Combine("X", "Custom"), Path.GetDirectoryName(asked));
    }

    [Fact]
    public void NextFileNameSurvivesABlankTemplate()
    {
        var s = new AppSettings { FilenameTemplate = "  " };
        Assert.StartsWith("Skreener ", SettingsRules.NextFileName(s, "P", DateTime.Now, _ => false));
    }
}
