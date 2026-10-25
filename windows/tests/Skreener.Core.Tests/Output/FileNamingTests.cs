using Skreener.Core.Output;
using Xunit;

namespace Skreener.Core.Tests.Output;

// Test-for-test port of Tests/SkreenerTests/OutputTests.swift (file-name and format cases; the image-encoding
// cases need an OS imaging stack and are covered by the app).
public class FileNamingTests
{
    /// <summary>7 March 2026, 09:05:02.</summary>
    private static readonly DateTime Date = new(2026, 3, 7, 9, 5, 2);

    [Fact]
    public void DefaultTemplate() =>
        Assert.Equal("Skreener 2026-03-07 at 09.05.02", FileNaming.Filename(Date, FileNaming.DefaultTemplate));

    [Fact]
    public void EveryToken() =>
        Assert.Equal("2026 26 03 07 09 05 02", FileNaming.Filename(Date, "%Y %y %m %d %H %M %S"));

    [Fact]
    public void PercentSigns() =>
        Assert.Equal("100% %q 50%", FileNaming.Filename(Date, "100%% %q 50%"));

    [Fact]
    public void FolderAndColonCharactersAreReplaced() =>
        Assert.Equal("a-b.c", FileNaming.Filename(Date, "a/b:c"));

    [Fact]
    public void WindowsForbiddenCharactersAreReplaced() =>
        Assert.Equal("a-b-c-d-e-f-g-h", FileNaming.Filename(Date, "a\\b?c*d\"e<f>g|h"));

    [Fact]
    public void TrailingDotsAndSpacesAreDropped() =>
        Assert.Equal("Shot", FileNaming.Filename(Date, "Shot. . "));

    [Fact]
    public void EmptyNameFallsBack() =>
        Assert.Equal("Skreener", FileNaming.Filename(Date, "   "));

    [Fact]
    public void LeadingDotIsNotHidden() =>
        Assert.Equal("Skreener .shot 2026", FileNaming.Filename(Date, ".shot %Y"));

    [Fact]
    public void TakenNamesGetANumber()
    {
        var dir = Path.Combine(Path.GetTempPath(), "SkreenerTests-" + Guid.NewGuid());
        Directory.CreateDirectory(dir);
        try
        {
            foreach (var expected in new[] { "Shot.png", "Shot 2.png", "Shot 3.png" })
            {
                var path = FileNaming.UniquePath(dir, "Shot", "png");
                Assert.Equal(expected, Path.GetFileName(path));
                File.WriteAllBytes(path, Array.Empty<byte>());
            }
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void FormatFromExtension()
    {
        Assert.Equal(ImageFormat.Png, ImageFormatExtensions.FromFileExtension("PNG"));
        Assert.Equal(ImageFormat.Jpeg, ImageFormatExtensions.FromFileExtension("jpg"));
        Assert.Equal(ImageFormat.Jpeg, ImageFormatExtensions.FromFileExtension(".jpeg"));
        Assert.Null(ImageFormatExtensions.FromFileExtension("heic"));
    }
}
