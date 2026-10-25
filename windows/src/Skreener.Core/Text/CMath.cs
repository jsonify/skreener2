using System.Globalization;
using System.Text;

namespace Skreener.Core.Text;

/// <summary>
/// The few C/Swift numeric behaviors the ported code relies on and .NET does differently: <c>rounded()</c> rounds halves
/// away from zero (Math.Round rounds them to even), and <c>String(format: "%.2f")</c> rounds an exact tie to even where
/// .NET's "F2" rounds it up.
/// </summary>
internal static class CMath
{
    /// <summary>Swift's <c>rounded()</c>: to the nearest whole number, halves away from zero.</summary>
    public static double Round(double v) => Math.Round(v, MidpointRounding.AwayFromZero);

    /// <summary>C's <c>%.{digits}f</c>.</summary>
    public static string Fixed(double v, int digits)
    {
        if (double.IsNaN(v)) return "nan";
        if (double.IsInfinity(v)) return v < 0 ? "-inf" : "inf";
        bool negative = double.IsNegative(v);
        // .NET Core 3.0+ prints the exact decimal expansion of a double at any precision; round it by hand so that an
        // exact tie goes to the even digit like printf does.
        string exact = Math.Abs(v).ToString("F" + (digits + 30), CultureInfo.InvariantCulture);
        int dot = exact.IndexOf('.');
        var kept = new StringBuilder(exact[..dot]).Append(exact, dot + 1, digits);
        string rest = exact[(dot + 1 + digits)..];
        bool up = rest[0] > '5' || (rest[0] == '5' && (rest[1..].Any(c => c != '0') || (kept[^1] - '0') % 2 == 1));
        if (up)
        {
            int i = kept.Length - 1;
            while (i >= 0 && kept[i] == '9') kept[i--] = '0';
            if (i >= 0) kept[i]++; else kept.Insert(0, '1');
        }
        int intLength = kept.Length - digits;
        string s = digits == 0 ? kept.ToString() : kept.ToString(0, intLength) + "." + kept.ToString(intLength, digits);
        return negative ? "-" + s : s;
    }
}
