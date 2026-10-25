namespace Skreener.Core.Scrolling;

/// <summary>
/// The rows of one scrolling-capture frame, reduced for matching: each row (top first) squeezed into <see cref="Bins"/> gray
/// values, of which only the detail is kept (see the constructor). A flat row (no detail, like the gaps between
/// paragraphs) lines up with any other flat row, so it says nothing about how far the content moved and is left out of
/// the scoring. Rows are top first, so the matching does not depend on which way y points.
/// </summary>
public sealed class ScrollRows
{
    public const int Bins = 96;

    /// <summary>Bins either side that a value is compared with to find its detail.</summary>
    private const int Reach = 4;

    private readonly byte[] _values;
    private readonly bool[] _flat;

    public int Count => _flat.Length;

    /// <summary>
    /// <paramref name="gray"/> holds each row squeezed into <see cref="Bins"/> gray values. What is kept is each value
    /// minus the average of its neighbours in the row, plus its change from the row above (around 128): text, edges and
    /// lines. A smooth background drops out, even one that changes from frame to frame (Messages' animated backgrounds),
    /// as does a change in brightness; it would otherwise swamp the content that moves.
    /// </summary>
    public ScrollRows(byte[] gray)
    {
        int bins = Bins, h = gray.Length / bins;
        var values = new byte[gray.Length];
        Array.Fill(values, (byte)128);
        var sums = new int[bins + 1];
        for (int y = 0; y < h; y++)
        {
            int row = y * bins, above = y > 0 ? row - bins : row;
            for (int x = 0; x < bins; x++) sums[x + 1] = sums[x] + gray[row + x];
            for (int x = 0; x < bins; x++)
            {
                int from = Math.Max(x - Reach, 0), to = Math.Min(x + Reach + 1, bins);
                int mean = (sums[to] - sums[from]) / (to - from);
                int v = gray[row + x];
                values[row + x] = (byte)Math.Clamp(128 + (v - mean) + (v - gray[above + x]), 0, 255);
            }
        }
        _values = values;
        _flat = new bool[values.Length / bins];
        for (int y = 0; y < _flat.Length; y++)
        {
            byte lo = byte.MaxValue, hi = byte.MinValue;
            for (int i = y * bins; i < (y + 1) * bins; i++) { lo = Math.Min(lo, values[i]); hi = Math.Max(hi, values[i]); }
            _flat[y] = hi - lo <= 4;
        }
    }

    /// <summary>Sum of absolute differences between row <paramref name="a"/> here and row <paramref name="b"/> of <paramref name="other"/>.</summary>
    public int Diff(int a, ScrollRows other, int b)
    {
        int sum = 0;
        int pa = a * Bins, pb = b * Bins;
        for (int i = 0; i < Bins; i++) sum += Math.Abs(_values[pa + i] - other._values[pb + i]);
        return sum;
    }

    /// <summary>Whether row <paramref name="a"/> here and row <paramref name="b"/> of <paramref name="other"/> are both flat and alike.</summary>
    public bool Blank(int a, ScrollRows other, int b) =>
        _flat[a] && other._flat[b] && Math.Abs(_values[a * Bins] - other._values[b * Bins]) <= 3;
}

/// <summary>How a new frame lines up with the previous one.</summary>
public abstract record ScrollMatch
{
    private ScrollMatch() { }

    /// <summary>Nothing moved, or too little changed to tell.</summary>
    public static ScrollMatch Unchanged { get; } = new UnchangedMatch();

    /// <summary>No good match: scrolled too far, or the content changed.</summary>
    public static ScrollMatch Lost { get; } = new LostMatch();

    /// <summary>
    /// Row <c>y</c> of the new frame shows what row <c>y + shift</c> of the previous one showed (a negative shift:
    /// scrolled back up). <c>header</c> rows at the top and <c>footer</c> rows at the bottom stayed put (a sticky header
    /// or footer, or blank space that looks the same).
    /// </summary>
    public static ScrollMatch Moved(int shift, int header, int footer) => new MovedMatch(shift, header, footer);

    public sealed record UnchangedMatch : ScrollMatch;

    public sealed record LostMatch : ScrollMatch;

    public sealed record MovedMatch(int Shift, int Header, int Footer) : ScrollMatch;
}

public static class ScrollMatcher
{
    /// <summary>Average difference per value below which two rows count as the same.</summary>
    private const int SameRow = 2;

    /// <summary>Average difference per value a match may have at most (content behind an animated background never matches exactly).</summary>
    private const double MaxCost = 6.0;

    /// <summary>Rows with content (not blank on both sides) a score needs before it is trusted, when every row is looked at.</summary>
    private const int MinEvidence = 6;

    /// <summary>
    /// Finds how far the content moved up from <paramref name="prev"/> to <paramref name="new"/>, or back down by up to
    /// half the area. Rows that stay put at the top and bottom are worked out for this pair of frames alone, so a header
    /// that appears, shrinks or grows a shadow later is still caught. <paramref name="hint"/> (the previous shift) is
    /// scored first, which usually lets the full search stop early. <paramref name="bridgeBlank"/> allows the guess
    /// across blank stretches below; only safe when <paramref name="prev"/> reached the end of what has been stitched.
    /// </summary>
    public static ScrollMatch Match(ScrollRows prev, ScrollRows @new, int? hint = null, bool bridgeBlank = true)
    {
        int h = Math.Min(prev.Count, @new.Count);
        int same = SameRow * ScrollRows.Bins;
        int header = 0;
        while (header < h && prev.Diff(header, @new, header) < same) header++;
        if (header == h) return ScrollMatch.Unchanged;
        int footer = 0;
        while (footer < h - header && prev.Diff(h - 1 - footer, @new, h - 1 - footer) < same) footer++;
        // Static rows past a quarter of the area are blank space that happens to look the same, not a real header
        // or footer; treat them as moving so the search range (and how far a frame may scroll) stays large.
        // The row next to a header or footer carries its edge (each row's detail includes its change from the row
        // above), so it never matches where the content shows elsewhere: count it with the header or footer.
        if (header > 0) header++;
        if (footer > 0) footer++;
        header = Math.Min(header, h / 4);
        footer = Math.Min(footer, h / 4);
        int band = h - header - footer;
        int minOverlap = Math.Max(16, band / 8);
        if (!(band > minOverlap + 1)) return ScrollMatch.Unchanged;

        if (Cost(prev, @new, header, h - footer, 0, double.PositiveInfinity, 1) is not { } still || !(still >= 0.5))
            return ScrollMatch.Unchanged;
        int maxShift = band - minOverlap;
        // Scrolling back up is matched too (less far): the user going back a little, or Auto-Scroll taking back an
        // overshoot that went a bit too far, would otherwise never match again.
        int maxBack = band / 2;
        double best = double.PositiveInfinity;
        int bestShift = 0;
        void Consider(int shift, int rowStep)
        {
            if (shift != 0 && shift >= -maxBack && shift <= maxShift
                && Cost(prev, @new, header, h - footer, shift, best, rowStep) is { } c && c < best)
            {
                best = c; bestShift = shift;
            }
        }
        if (hint is { } hinted) Consider(hinted, 2);
        for (int shift = 1; shift <= maxShift; shift++) Consider(shift, 2);
        for (int shift = 1; shift <= maxBack; shift++) Consider(-shift, 2);
        // The search above looks at every other row, so a neighbouring shift can tie; settle it on every row.
        if (bestShift != 0)
        {
            int coarse = bestShift;
            best = double.PositiveInfinity;
            for (int shift = coarse - 2; shift <= coarse + 2; shift++) Consider(shift, 1);
        }
        if (bestShift != 0 && best < MaxCost && best < still * 0.5) return ScrollMatch.Moved(bestShift, header, footer);

        // Nothing lines up. If that is because the rows both frames share are (nearly all) blank, as when the old
        // content has scrolled out at the top and new content has come in at the bottom, there is too little to score:
        // take the smallest move under which every shared row is blank on both sides or the same. Blank space between
        // the old and new content may come out shorter than it was. Only moves of under half the moving rows count:
        // then what scrolled out (at the top) and what came in (at the bottom) can't sit on the same rows, so an
        // animation on a blank page (a loading spinner) is never taken for scrolling. If some move back up fits as
        // well, it can't be told from scrolling up, so it doesn't count either.
        if (!bridgeBlank) return ScrollMatch.Lost;
        bool Fits(int shift)
        {
            for (int y = Math.Max(header, header - shift); y < Math.Min(h - footer, h - footer - shift); y++)
            {
                if (!(@new.Blank(y, prev, y + shift) || @new.Diff(y, prev, y + shift) < same)) return false;
            }
            return true;
        }
        int found = 0;
        for (int shift = 1; shift < Math.Min(maxShift + 1, band / 2); shift++)
        {
            if (Fits(shift)) { found = shift; break; }
        }
        if (found == 0) return ScrollMatch.Lost;
        for (int back = 1; back <= maxShift; back++)
        {
            if (Fits(-back)) return ScrollMatch.Lost;
        }
        return ScrollMatch.Moved(found, header, footer);
    }

    /// <summary>
    /// Mean difference per value between rows <c>y + shift</c> of <paramref name="prev"/> and rows <c>y</c> of
    /// <paramref name="new"/>, for every <paramref name="rowStep"/>th <c>y</c> where both rows fall in
    /// <c>header..&lt;end</c>, leaving out pairs that are both blank. Null when too few rows have content to tell, or
    /// (once it can't beat <paramref name="limit"/>) a value at least <paramref name="limit"/>.
    /// </summary>
    public static double? Cost(ScrollRows prev, ScrollRows @new, int header, int end, int shift, double limit, int rowStep)
    {
        int from = Math.Max(header, header - shift), to = Math.Min(end, end - shift);
        if (!(to > from)) return null;
        int rows = (to - from + rowStep - 1) / rowStep;
        // Skipped rows only lower the count, so the sum reaching this can no longer end below `limit`.
        double budget = limit * (rows * ScrollRows.Bins);
        int sum = 0, counted = 0;
        for (int y = from; y < to; y += rowStep)
        {
            if (!@new.Blank(y, prev, y + shift))
            {
                sum += @new.Diff(y, prev, y + shift);
                counted++;
                if (sum >= budget) return limit;
            }
        }
        if (counted * rowStep < MinEvidence) return null;
        return (double)sum / (counted * ScrollRows.Bins);
    }
}
