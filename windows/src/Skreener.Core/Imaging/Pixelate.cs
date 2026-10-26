namespace Skreener.Core.Imaging;

/// <summary>
/// The pixelate annotation's mosaic: every <c>block</c> x <c>block</c> square replaced by its average color. The grid
/// starts at the image's top-left corner, so a pixelate box shows the same blocks wherever it is moved. Works on any
/// four-byte-per-pixel layout (BGRA or RGBA, premultiplied or not), as each channel is averaged on its own.
/// </summary>
public static class Pixelate
{
    /// <summary>A pixelated copy of the whole image (rows tightly packed, top row first).</summary>
    public static byte[] Apply(byte[] pixels, int width, int height, int block)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width), "An image has at least one pixel.");
        if (pixels.Length < width * height * 4) throw new ArgumentException("Not enough bytes for the image.", nameof(pixels));
        block = Math.Max(block, 1);
        var result = new byte[width * height * 4];
        int stride = width * 4;
        for (int by = 0; by < height; by += block)
        {
            int y1 = Math.Min(by + block, height);
            for (int bx = 0; bx < width; bx += block)
            {
                int x1 = Math.Min(bx + block, width);
                long c0 = 0, c1 = 0, c2 = 0, c3 = 0;
                for (int y = by; y < y1; y++)
                {
                    for (int i = y * stride + bx * 4, end = y * stride + x1 * 4; i < end; i += 4)
                    {
                        c0 += pixels[i]; c1 += pixels[i + 1]; c2 += pixels[i + 2]; c3 += pixels[i + 3];
                    }
                }
                long n = (long)(x1 - bx) * (y1 - by);
                byte b0 = (byte)((c0 + n / 2) / n), b1 = (byte)((c1 + n / 2) / n), b2 = (byte)((c2 + n / 2) / n), b3 = (byte)((c3 + n / 2) / n);
                for (int y = by; y < y1; y++)
                {
                    for (int i = y * stride + bx * 4, end = y * stride + x1 * 4; i < end; i += 4)
                    {
                        result[i] = b0; result[i + 1] = b1; result[i + 2] = b2; result[i + 3] = b3;
                    }
                }
            }
        }
        return result;
    }
}
