using Skreener.Core.Scrolling;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>Scrolling-capture matching on made-up frames: every row of a "page" has its own pattern, like lines of text.</summary>
public class ScrollMatcherTests
{
    private const int Height = 200;

    /// <summary><c>rows</c> rows of <see cref="ScrollRows.Bins"/> mid-range gray values (pseudo-random, the same for the same seed).</summary>
    private static byte[][] Page(int rows, uint seed = 1)
    {
        uint state = seed;
        var page = new byte[rows][];
        for (int r = 0; r < rows; r++)
        {
            page[r] = new byte[ScrollRows.Bins];
            for (int i = 0; i < ScrollRows.Bins; i++)
            {
                unchecked { state = state * 1_664_525 + 1_013_904_223; }
                page[r][i] = (byte)(64 + (state >> 24) / 2);
            }
        }
        return page;
    }

    private static ScrollRows Frame(IEnumerable<byte[]> rows) => new(rows.SelectMany(r => r).ToArray());

    /// <summary>The frame showing <c>rows[top..&lt;top + Height]</c>.</summary>
    private static ScrollRows Frame(byte[][] rows, int top) => Frame(rows.Skip(top).Take(Height));

    [Fact]
    public void SameFrameIsUnchanged()
    {
        var f = Frame(Page(Height), 0);
        Assert.Equal(ScrollMatch.Unchanged, ScrollMatcher.Match(f, f));
    }

    [Fact]
    public void ScrollDown()
    {
        var p = Page(400);
        Assert.Equal(ScrollMatch.Moved(37, 0, 0), ScrollMatcher.Match(Frame(p, 0), Frame(p, 37)));
    }

    [Fact]
    public void ScrollBackUp()
    {
        var p = Page(400);
        Assert.Equal(ScrollMatch.Moved(-30, 0, 0), ScrollMatcher.Match(Frame(p, 30), Frame(p, 0)));
    }

    [Fact]
    public void HintGivesTheSameAnswer()
    {
        var p = Page(400);
        Assert.Equal(ScrollMatch.Moved(50, 0, 0), ScrollMatcher.Match(Frame(p, 0), Frame(p, 50), hint: 50));
    }

    [Fact]
    public void StickyHeaderStaysPut()
    {
        var header = Page(20, seed: 7);
        var content = Page(400);
        var prev = Frame(header.Concat(content[20..Height]));
        var @new = Frame(header.Concat(content[(20 + 40)..(Height + 40)]));
        var match = ScrollMatcher.Match(prev, @new);
        var moved = Assert.IsType<ScrollMatch.MovedMatch>(match);
        Assert.Equal(40, moved.Shift);
        Assert.True(moved.Header is >= 20 and <= 21, $"header {moved.Header}");
        Assert.Equal(0, moved.Footer);
    }

    [Fact]
    public void UnrelatedContentIsLost()
    {
        var a = Frame(Page(Height, seed: 1), 0);
        var b = Frame(Page(Height, seed: 2), 0);
        Assert.Equal(ScrollMatch.Lost, ScrollMatcher.Match(a, b));
    }
}
