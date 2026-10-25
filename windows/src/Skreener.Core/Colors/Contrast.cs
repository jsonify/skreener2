using Skreener.Core.Text;

namespace Skreener.Core.Colors;

/// <summary>Contrast between two colors (#109), the way accessibility guidelines measure it.</summary>
public static class Contrast
{
    public enum Method
    {
        /// <summary>WCAG 2: a ratio from 1:1 to 21:1.</summary>
        Wcag,
        /// <summary>APCA (the candidate for WCAG 3): a lightness contrast Lc from about -108 to 106; negative for light text on a dark background.</summary>
        Apca,
    }

    /// <summary>The WCAG 2 contrast ratio, 1 to 21 (the order of the colors does not matter).</summary>
    public static double Wcag(RgbColor a, RgbColor b)
    {
        double la = a.Luminance, lb = b.Luminance;
        return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
    }

    /// <summary>What a WCAG 2 ratio passes: AAA (7), AA (4.5) or AA for large text and UI (3).</summary>
    public static string WcagRating(double ratio)
    {
        // Rounded down to two decimals, so 4.499 doesn't show as 4.50 and pass.
        double r = Math.Floor(ratio * 100) / 100;
        if (r >= 7) return "AAA";
        if (r >= 4.5) return "AA";
        if (r >= 3) return "AA Large";
        return "Fail";
    }

    /// <summary>APCA's Lc for <paramref name="text"/> on <paramref name="background"/> (SAPC-APCA 0.0.98G-4g constants). Black on white is about 106, white on black about -108.</summary>
    public static double Apca(RgbColor text, RgbColor background)
    {
        static double Y(RgbColor c) =>
            0.2126729 * Math.Pow(c.R, 2.4) + 0.7151522 * Math.Pow(c.G, 2.4) + 0.0721750 * Math.Pow(c.B, 2.4);
        // Soft-clamps near-black, where screens and eyes stop telling shades apart.
        static double Clamped(double v) => v > 0.022 ? v : v + Math.Pow(0.022 - v, 1.414);
        double yt = Clamped(Y(text)), yb = Clamped(Y(background));
        if (!(Math.Abs(yb - yt) >= 0.0005)) return 0;
        if (yb > yt)
        {
            double sapc = (Math.Pow(yb, 0.56) - Math.Pow(yt, 0.57)) * 1.14;
            return sapc < 0.1 ? 0 : (sapc - 0.027) * 100;
        }
        else
        {
            double sapc = (Math.Pow(yb, 0.65) - Math.Pow(yt, 0.62)) * 1.14;
            return sapc > -0.1 ? 0 : (sapc + 0.027) * 100;
        }
    }

    /// <summary>What an APCA Lc is enough for (by its size, whichever polarity), after APCA's bronze-level guidance.</summary>
    public static string ApcaRating(double lc)
    {
        double v = Math.Abs(lc);
        if (v >= 90) return "Any text";
        if (v >= 75) return "Body text";
        if (v >= 60) return "Content text";
        if (v >= 45) return "Large text";
        if (v >= 30) return "Spot text";
        if (v >= 15) return "Non-text";
        return "Fail";
    }

    /// <summary>One line for the editor: <c>4.48:1 · AA Large</c> or <c>Lc 71 · Content text</c>.</summary>
    public static string Summary(RgbColor text, RgbColor background, Method method)
    {
        switch (method)
        {
            case Method.Wcag:
            {
                double ratio = Wcag(text, background);
                return CMath.Fixed(Math.Floor(ratio * 100) / 100, 2) + ":1" + " · " + WcagRating(ratio);
            }
            default:
            {
                double lc = Apca(text, background);
                return "Lc " + CMath.Fixed(lc, 0) + " · " + ApcaRating(lc);
            }
        }
    }
}
