using Skreener.Core.Text;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>The C/Swift number behaviors Skreener.Core copies (no Swift counterpart: these are what the ported tests lean on).</summary>
public class CMathTests
{
    [Theory]
    [InlineData(2.5, 0, "2")]       // exact ties go to even, like printf
    [InlineData(3.5, 0, "4")]
    [InlineData(0.125, 2, "0.12")]
    [InlineData(0.375, 2, "0.38")]
    [InlineData(0.76, 2, "0.76")]
    [InlineData(0.1, 2, "0.10")]
    [InlineData(9.996, 2, "10.00")]
    [InlineData(0.9996, 3, "1.000")]
    [InlineData(-0.4, 0, "-0")]
    [InlineData(-71.4, 0, "-71")]
    [InlineData(84.6, 1, "84.6")]
    [InlineData(1, 0, "1")]
    public void FixedMatchesPrintf(double v, int digits, string expected) =>
        Assert.Equal(expected, CMath.Fixed(v, digits));

    [Fact]
    public void RoundGoesAwayFromZero()
    {
        Assert.Equal(3, CMath.Round(2.5));
        Assert.Equal(-3, CMath.Round(-2.5));
        Assert.Equal(2, CMath.Round(1.5 + 0.4));
    }
}
