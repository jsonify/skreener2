using Skreener.Core.Geometry;
using Skreener.Core.Text;

namespace Skreener.Core.Imaging;

/// <summary>
/// Snapping boxes to what's in the screenshot (#123): a box drawn roughly around a button, a field or a card gets that
/// element's exact edges; Repeat on Similar Objects finds the other places in the screenshot that look like the inside
/// of a box (every avatar in a list, every price in a table). All in pixels, top-left origin.
/// </summary>
public static class ObjectSnap
{
    /// <summary>Largest channel difference (0 to 255) between neighboring pixels still counted as the same color.</summary>
    public const int Tolerance = 16;

    /// <summary>An edge has to run along at least this share of the box's side.</summary>
    public const double MinCoverage = 0.45;

    /// <summary>Which sides of a box were moved onto an edge.</summary>
    public readonly record struct Sides(bool Left = false, bool Right = false, bool Top = false, bool Bottom = false)
    {
        public bool Any => Left || Right || Top || Bottom;
    }

    /// <summary>
    /// <paramref name="box"/> with each side moved to the strongest edge within <paramref name="reach"/> pixels of it,
    /// where there is one: a line between two neighboring columns (for the left and right sides) or rows (top and
    /// bottom) along which the color changes for at least <see cref="MinCoverage"/> of the box's height (or width). Of
    /// edges about as strong, the nearest wins.
    /// </summary>
    public static (RectD Rect, Sides Sides) Snap(RectD box, PixelBuffer buf, int reach)
    {
        int x0 = (int)CMath.Round(box.MinX), x1 = (int)CMath.Round(box.MaxX);
        int y0 = (int)CMath.Round(box.MinY), y1 = (int)CMath.Round(box.MaxY);
        if (x1 - x0 < 2 || y1 - y0 < 2 || reach <= 0) return (box, new Sides());
        // Swift traps on a reversed range; a box wholly outside the image just has nothing to measure along.
        int rowStart = Math.Max(y0, 0), rowEnd = Math.Max(Math.Min(y1, buf.Height), rowStart);
        int colStart = Math.Max(x0, 0), colEnd = Math.Max(Math.Min(x1, buf.Width), colStart);

        // The best boundary near `at`: `count` lines across, `along` the pixels each is measured over, `changes(b, i)`
        // whether the color changes at boundary `b` on pixel `i` along it.
        int? Edge(int at, int count, int alongStart, int alongEnd, Func<int, int, bool> changes)
        {
            int length = alongEnd - alongStart;
            if (length <= 0) return null;
            (int B, double Score)? best = null;
            for (int b = Math.Max(at - reach, 1); b <= Math.Min(at + reach, count - 1); b++)
            {
                int n = 0;
                for (int i = alongStart; i < alongEnd; i++) if (changes(b, i)) n++;
                double score = (double)n / length;
                if (score < MinCoverage) continue;
                if (best is { } cur)
                {
                    bool clearlyStronger = score > cur.Score + 0.1;
                    bool asStrongAndNearer = Math.Abs(score - cur.Score) <= 0.1 && Math.Abs(b - at) < Math.Abs(cur.B - at);
                    if (!clearlyStronger && !asStrongAndNearer) continue;
                }
                best = (b, score);
            }
            return best?.B;
        }
        int? ColumnEdge(int x) => Edge(x, buf.Width, rowStart, rowEnd, (b, y) => Differs(buf.Rgba(b - 1, y), buf.Rgba(b, y)));
        int? RowEdge(int y) => Edge(y, buf.Height, colStart, colEnd, (b, x) => Differs(buf.Rgba(x, b - 1), buf.Rgba(x, b)));

        bool left = false, right = false, top = false, bottom = false;
        int l = x0, r = x1, t = y0, btm = y1;
        if (ColumnEdge(x0) is { } el) { l = el; left = true; }
        if (ColumnEdge(x1) is { } er) { r = er; right = true; }
        if (RowEdge(y0) is { } et) { t = et; top = true; }
        if (RowEdge(y1) is { } eb) { btm = eb; bottom = true; }
        // Both sides on the same edge (a thin box near a line): leave that pair alone.
        if (r - l < 2) { l = x0; r = x1; left = false; right = false; }
        if (btm - t < 2) { t = y0; btm = y1; top = false; bottom = false; }
        double minX = left ? l : box.MinX, maxX = right ? r : box.MaxX;
        double minY = top ? t : box.MinY, maxY = bottom ? btm : box.MaxY;
        return (new RectD(minX, minY, maxX - minX, maxY - minY), new Sides(left, right, top, bottom));
    }

    private static bool Differs(Pixel p, Pixel q) =>
        Math.Max(Math.Max(Math.Abs(p.R - q.R), Math.Abs(p.G - q.G)), Math.Max(Math.Abs(p.B - q.B), Math.Abs(p.A - q.A))) > Tolerance;

    // MARK: Similar objects

    /// <summary>Largest mean brightness difference (0 to 255) between the box and a place that counts as looking the same.</summary>
    public const int MaxMeanDifference = 10;

    /// <summary>At most this many places are returned.</summary>
    public const int MaxMatches = 60;

    /// <summary>
    /// The other places in the screenshot that look like the inside of <paramref name="box"/> (same size), best first,
    /// none overlapping <paramref name="box"/> or each other. A box of one flat color matches nothing (it would match
    /// every empty area). Runs on a thread-pool thread.
    /// </summary>
    public static Task<IReadOnlyList<RectD>> SimilarAsync(RectD box, PixelBuffer buf) =>
        Task.Run(() => SimilarNow(box, buf));

    public static IReadOnlyList<RectD> SimilarNow(RectD box, PixelBuffer buf)
    {
        int tx = (int)CMath.Round(box.MinX), ty = (int)CMath.Round(box.MinY);
        int tw = (int)CMath.Round(box.Width), th = (int)CMath.Round(box.Height);
        if (tw < 4 || th < 4 || tx < 0 || ty < 0 || tx + tw > buf.Width || ty + th > buf.Height) return Array.Empty<RectD>();
        var full = new Gray(buf, 1);
        // Searched at a lower resolution (about 10 pixels across the box's short side), then placed exactly.
        int f = Math.Max(1, Math.Min(tw, th) / 10);
        var small = f == 1 ? full : new Gray(buf, f);
        int sw = tw / f, sh = th / f, sx = tx / f, sy = ty / f;
        if (sw < 2 || sh < 2) return Array.Empty<RectD>();
        var template = new int[sw * sh];
        for (int y = 0; y < sh; y++) for (int x = 0; x < sw; x++) template[y * sw + x] = small[sx + x, sy + y];
        int mean = template.Sum() / template.Length;
        int spread = template.Sum(v => Math.Abs(v - mean)) / template.Length;
        if (spread < 6) return Array.Empty<RectD>();

        // The low-resolution pass is loose (a block straddling an edge differs even where the objects are the same);
        // each candidate is then placed and checked at full resolution.
        int limit = 3 * MaxMeanDifference * sw * sh;
        var found = new List<(int X, int Y, int Cost)>();
        if (small.Width >= sw && small.Height >= sh)
        {
            for (int y = 0; y <= small.Height - sh; y++)
            {
                for (int x = 0; x <= small.Width - sw; x++)
                {
                    int cost = 0;
                    for (int j = 0; j < sh; j++)
                    {
                        for (int i = 0; i < sw; i++) cost += Math.Abs(small[x + i, y + j] - template[j * sw + i]);
                        if (cost > limit) break;
                    }
                    if (cost <= limit) found.Add((x, y, cost));
                }
            }
        }

        var original = new RectD(tx, ty, tw, th);
        var kept = new List<RectD>();
        // A neighbor of a place already kept (or of the box itself) is the same object again.
        bool Taken(RectD r)
        {
            var core = r.InsetBy(tw * 0.2, th * 0.2);
            return core.Intersects(original) || kept.Any(k => core.Intersects(k));
        }
        int samples = ((tw + 1) / 2) * ((th + 1) / 2);
        foreach (var m in found.OrderBy(m => m.Cost).Take(2000))
        {
            if (Taken(new RectD(m.X * f, m.Y * f, tw, th))) continue;
            var at = Refine(m.X * f, m.Y * f, f == 1 ? 0 : f, (tx, ty, tw, th), full);
            if (at.Cost > MaxMeanDifference * samples) continue;
            var r = new RectD(at.X, at.Y, tw, th);
            if (Taken(r)) continue;
            kept.Add(r);
            if (kept.Count == MaxMatches) break;
        }
        return kept;
    }

    /// <summary>
    /// The best place for the box within <paramref name="search"/> pixels of (x, y), at full resolution, and how much it
    /// differs there (summed over every other pixel each way).
    /// </summary>
    private static (int X, int Y, int Cost) Refine(int x, int y, int search, (int X, int Y, int W, int H) box, Gray g)
    {
        var best = (X: x, Y: y, Cost: int.MaxValue);
        for (int dy = -search; dy <= search; dy++)
        {
            for (int dx = -search; dx <= search; dx++)
            {
                int px = x + dx, py = y + dy;
                if (px < 0 || py < 0 || px + box.W > g.Width || py + box.H > g.Height) continue;
                int cost = 0;
                for (int j = 0; j < box.H; j += 2)
                {
                    for (int i = 0; i < box.W; i += 2) cost += Math.Abs(g[px + i, py + j] - g[box.X + i, box.Y + j]);
                    if (cost >= best.Cost) break;
                }
                if (cost < best.Cost) best = (px, py, cost);
            }
        }
        return best;
    }

    /// <summary>Brightness (0 to 255), each value the mean of a <c>factor</c> x <c>factor</c> block of pixels.</summary>
    private sealed class Gray
    {
        public int Width { get; }
        public int Height { get; }
        private readonly int[] _values;

        public Gray(PixelBuffer buf, int f)
        {
            Width = buf.Width / f;
            Height = buf.Height / f;
            var v = new int[Width * Height];
            for (int y = 0; y < Height; y++)
            {
                for (int x = 0; x < Width; x++)
                {
                    int sum = 0;
                    for (int j = 0; j < f; j++)
                    {
                        for (int i = 0; i < f; i++)
                        {
                            var p = buf.Rgba(x * f + i, y * f + j);
                            sum += (p.R * 299 + p.G * 587 + p.B * 114) / 1000;
                        }
                    }
                    v[y * Width + x] = sum / (f * f);
                }
            }
            _values = v;
        }

        public int this[int x, int y] => _values[y * Width + x];
    }
}
