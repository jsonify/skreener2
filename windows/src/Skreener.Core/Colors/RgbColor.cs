namespace Skreener.Core.Colors;

/// <summary>
/// An sRGB color with components from 0 to 1, as the editor's color picker, ruler and contrast checker read them
/// (RGBColor in PixelBuffer.swift).
/// </summary>
public readonly record struct RgbColor(double R, double G, double B, double A = 1)
{
    /// <summary>8-bit channel values (0 to 255).</summary>
    public static RgbColor FromBytes(int r, int g, int b, int a = 255) => new(r / 255.0, g / 255.0, b / 255.0, a / 255.0);

    /// <summary>A channel as 0 to 255.</summary>
    public static int Byte(double v) => (int)Text.CMath.Round(Math.Min(Math.Max(v, 0), 1) * 255);

    /// <summary>WCAG 2 relative luminance (linear-light, 0 for black, 1 for white).</summary>
    public double Luminance
    {
        get
        {
            static double Lin(double c) => c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
            return 0.2126 * Lin(R) + 0.7152 * Lin(G) + 0.0722 * Lin(B);
        }
    }
}
