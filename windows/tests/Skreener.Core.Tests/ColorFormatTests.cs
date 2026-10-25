using Skreener.Core.Colors;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>Color formats (#108) and contrast (#109), from ColorToolsTests.swift.</summary>
public class ColorFormatTests
{
    [Fact]
    public void EveryFormat()
    {
        var c = RgbColor.FromBytes(255, 194, 0);
        var expected = new Dictionary<ColorFormat, string>
        {
            [ColorFormat.Hex] = "#FFC200",
            [ColorFormat.HexNoHash] = "FFC200",
            [ColorFormat.Css] = "rgba(255, 194, 0, 1)",
            [ColorFormat.RgbUnit] = "(1.00, 0.76, 0.00)",
            [ColorFormat.Android] = "0xFFFFC200",
            [ColorFormat.UiColor] = "UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)",
            [ColorFormat.CSharp] = "Color.FromArgb(255, 194, 0)",
            [ColorFormat.Oklch] = "oklch(84.60% 0.173 85.6)",
        };
        foreach (var f in Enum.GetValues<ColorFormat>()) Assert.Equal(expected[f], f.Format(c));
        Assert.Equal(expected.Count, Enum.GetValues<ColorFormat>().Length);
        Assert.Equal("84.60% 0.173 85.6", ColorFormat.Oklch.Display(c));
        Assert.Equal("#FFC200", ColorFormat.Hex.Display(c));
    }

    [Fact]
    public void TranslucentFormats()
    {
        var c = new RgbColor(1, 0, 0, 0.5);
        Assert.Equal("rgba(255, 0, 0, 0.5)", ColorFormat.Css.Format(c));
        Assert.Equal("0x80FF0000", ColorFormat.Android.Format(c));
        Assert.Equal("Color.FromArgb(128, 255, 0, 0)", ColorFormat.CSharp.Format(c));
    }

    [Fact]
    public void OklchOfGraysHasNoHue()
    {
        Assert.Equal("oklch(100.00% 0.000 0.0)", ColorFormat.Oklch.Format(new RgbColor(1, 1, 1)));
        Assert.Equal("oklch(0.00% 0.000 0.0)", ColorFormat.Oklch.Format(new RgbColor(0, 0, 0)));
        var red = ColorFormatExtensions.OklchComponents(new RgbColor(1, 0, 0));
        Assert.Equal(0.628, red.L, 0.001);
        Assert.Equal(0.258, red.C, 0.001);
        Assert.Equal(29.23, red.H, 0.01);
    }

    [Fact]
    public void Wcag()
    {
        var black = new RgbColor(0, 0, 0); var white = new RgbColor(1, 1, 1); var gray = RgbColor.FromBytes(0x77, 0x77, 0x77);
        Assert.Equal(21, Contrast.Wcag(black, white), 0.001);
        Assert.Equal(21, Contrast.Wcag(white, black), 0.001);
        Assert.Equal(4.48, Contrast.Wcag(gray, white), 0.005);
        Assert.Equal("AA Large", Contrast.WcagRating(Contrast.Wcag(gray, white)));   // just short of AA
        Assert.Equal("AAA", Contrast.WcagRating(21));
        Assert.Equal("AA", Contrast.WcagRating(4.5));
        Assert.Equal("Fail", Contrast.WcagRating(1.2));
        Assert.Equal("4.47:1 · AA Large", Contrast.Summary(gray, white, Contrast.Method.Wcag));
    }

    [Fact]
    public void Apca()
    {
        var black = new RgbColor(0, 0, 0); var white = new RgbColor(1, 1, 1); var gray = RgbColor.FromBytes(0x77, 0x77, 0x77);
        Assert.Equal(106.04, Contrast.Apca(black, white), 0.05);
        Assert.Equal(-107.88, Contrast.Apca(white, black), 0.05);
        Assert.Equal(71.11, Contrast.Apca(gray, white), 0.05);
        Assert.Equal(0, Contrast.Apca(white, white));
        Assert.Equal("Lc 71 · Content text", Contrast.Summary(gray, white, Contrast.Method.Apca));
    }
}
