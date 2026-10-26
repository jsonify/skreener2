namespace Skreener.Core.Text;

/// <summary>Windows OCR refuses images larger than <c>OcrEngine.MaxImageDimension</c> on either side.</summary>
public static class OcrImageSize
{
    /// <summary>
    /// The size to recognize an image of <paramref name="width"/> x <paramref name="height"/> at: unchanged when it fits,
    /// otherwise scaled down evenly (never to less than 1 px) so the longer side equals <paramref name="maxDimension"/>.
    /// Scaling keeps every line whole, which tiling would cut in two at the seams.
    /// </summary>
    public static (int Width, int Height) Fit(int width, int height, int maxDimension)
    {
        if (width <= 0 || height <= 0 || maxDimension <= 0) return (Math.Max(width, 1), Math.Max(height, 1));
        var longest = Math.Max(width, height);
        if (longest <= maxDimension) return (width, height);
        var scale = (double)maxDimension / longest;
        return (Math.Clamp((int)Math.Round(width * scale), 1, maxDimension), Math.Clamp((int)Math.Round(height * scale), 1, maxDimension));
    }
}
