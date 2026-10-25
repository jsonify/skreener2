using Skreener.Core.Text;

namespace Skreener.Core.Colors;

/// <summary>
/// How the editor's color picker writes a color (#108): the format is a setting, used for copying, the live pixel
/// readout and Tab while typing a label.
/// </summary>
public enum ColorFormat { Hex, HexNoHash, Css, RgbUnit, Android, UiColor, CSharp, Oklch }

public static class ColorFormatExtensions
{
    public static string Title(this ColorFormat format) => format switch
    {
        ColorFormat.Hex => "HEX",
        ColorFormat.HexNoHash => "HEX without #",
        ColorFormat.Css => "CSS rgba()",
        ColorFormat.RgbUnit => "RGB 0–1",
        ColorFormat.Android => "Android",
        ColorFormat.UiColor => "UIColor",
        ColorFormat.CSharp => "C#",
        ColorFormat.Oklch => "OKLCH",
        _ => throw new ArgumentOutOfRangeException(nameof(format)),
    };

    /// <summary>
    /// The text copied for <paramref name="c"/>: <c>#FFC200</c>, <c>FFC200</c>, <c>rgba(255, 194, 0, 1)</c>,
    /// <c>(1.00, 0.76, 0.00)</c>, <c>0xFFFFC200</c>, <c>UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)</c>,
    /// <c>Color.FromArgb(255, 194, 0)</c> or <c>oklch(84.60% 0.173 85.6)</c>.
    /// </summary>
    public static string Format(this ColorFormat format, RgbColor c)
    {
        int r = RgbColor.Byte(c.R), g = RgbColor.Byte(c.G), b = RgbColor.Byte(c.B), a = RgbColor.Byte(c.A);
        string hex = r.ToString("X2") + g.ToString("X2") + b.ToString("X2");
        static string Unit(double v) => CMath.Fixed(Math.Min(Math.Max(v, 0), 1), 2);
        return format switch
        {
            ColorFormat.Hex => "#" + hex,
            ColorFormat.HexNoHash => hex,
            ColorFormat.Css => $"rgba({r}, {g}, {b}, {Trimmed(c.A)})",
            ColorFormat.RgbUnit => $"({Unit(c.R)}, {Unit(c.G)}, {Unit(c.B)})",
            ColorFormat.Android => "0x" + a.ToString("X2") + hex,
            ColorFormat.UiColor => $"UIColor(red: {Unit(c.R)}, green: {Unit(c.G)}, blue: {Unit(c.B)}, alpha: {Unit(c.A)})",
            ColorFormat.CSharp => a == 255 ? $"Color.FromArgb({r}, {g}, {b})" : $"Color.FromArgb({a}, {r}, {g}, {b})",
            ColorFormat.Oklch => $"oklch({OklchValues(c)})",
            _ => throw new ArgumentOutOfRangeException(nameof(format)),
        };
    }

    /// <summary>The text shown in the editor's pixel readout: like <see cref="Format"/>, but OKLCH without the <c>oklch()</c> around it.</summary>
    public static string Display(this ColorFormat format, RgbColor c) =>
        format == ColorFormat.Oklch ? OklchValues(c) : format.Format(c);

    /// <summary><c>L% C H</c>, e.g. <c>84.60% 0.173 85.6</c>; grays (no chroma) get hue 0.</summary>
    private static string OklchValues(RgbColor c)
    {
        var (l, chroma, hue) = OklchComponents(c);
        double h = chroma < 0.0005 ? 0 : hue;
        return $"{CMath.Fixed(l * 100, 2)}% {CMath.Fixed(chroma, 3)} {CMath.Fixed(h, 1)}";
    }

    /// <summary>OKLCH (Björn Ottosson's OKLab in polar form): lightness 0 to 1, chroma, hue in degrees 0 to 360.</summary>
    public static (double L, double C, double H) OklchComponents(RgbColor c)
    {
        static double Lin(double v) => v <= 0.04045 ? v / 12.92 : Math.Pow((v + 0.055) / 1.055, 2.4);
        double r = Lin(c.R), g = Lin(c.G), b = Lin(c.B);
        double l = Math.Cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        double m = Math.Cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        double s = Math.Cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        double lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
        double a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        double bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        double hue = Math.Atan2(bb, a) * 180 / Math.PI;
        if (hue < 0) hue += 360;
        // Math.Sqrt rather than a hypot, which .NET lacks: the same up to the last bit, far below the printed digits.
        return (lightness, Math.Sqrt(a * a + bb * bb), hue);
    }

    /// <summary>An alpha without trailing zeros: 1, 0.5, 0.25.</summary>
    private static string Trimmed(double v)
    {
        string s = CMath.Fixed(Math.Min(Math.Max(v, 0), 1), 2);
        while (s.EndsWith('0')) s = s[..^1];
        if (s.EndsWith('.')) s = s[..^1];
        return s;
    }
}
