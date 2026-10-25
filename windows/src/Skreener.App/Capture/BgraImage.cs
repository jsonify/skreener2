using System.Runtime.InteropServices;
using Windows.Foundation;
using Windows.Graphics;
using Windows.Graphics.Imaging;
using WinRT;

namespace Skreener.App.Capture;

/// <summary>
/// A BGRA8 premultiplied image in managed memory, rows tightly packed (stride = width * 4), top row first: the raw
/// capture buffer. The overlay paints the frozen screen from it and area captures are cropped from it. Not to be confused
/// with Skreener.Core's PixelBuffer, the read-only RGBA view the editor's colour picker and ruler read pixels from.
/// </summary>
internal sealed class BgraImage
{
    public BgraImage(int width, int height, byte[]? pixels = null)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width), "An image needs at least one pixel.");
        Width = width;
        Height = height;
        Pixels = pixels ?? new byte[checked(width * height * 4)];
        if (Pixels.Length != width * height * 4) throw new ArgumentException("Pixel data does not match the size.", nameof(pixels));
    }

    public int Width { get; }
    public int Height { get; }
    public int Stride => Width * 4;
    public byte[] Pixels { get; }

    /// <summary>
    /// The part of this image inside <paramref name="rect"/> (pixels, this image's own top-left origin), clipped to the
    /// image. Null when nothing is left after clipping.
    /// </summary>
    public BgraImage? Crop(RectInt32 rect)
    {
        int x0 = Math.Max(rect.X, 0), y0 = Math.Max(rect.Y, 0);
        int x1 = Math.Min(rect.X + rect.Width, Width), y1 = Math.Min(rect.Y + rect.Height, Height);
        if (x1 <= x0 || y1 <= y0) return null;
        var result = new BgraImage(x1 - x0, y1 - y0);
        for (int y = y0; y < y1; y++)
            Buffer.BlockCopy(Pixels, y * Stride + x0 * 4, result.Pixels, (y - y0) * result.Stride, result.Stride);
        return result;
    }

    /// <summary>Copies <paramref name="source"/> into this image with its top-left at (x, y); parts outside are dropped.</summary>
    public void Blit(BgraImage source, int x, int y)
    {
        int x0 = Math.Max(x, 0), y0 = Math.Max(y, 0);
        int x1 = Math.Min(x + source.Width, Width), y1 = Math.Min(y + source.Height, Height);
        if (x1 <= x0 || y1 <= y0) return;
        for (int row = y0; row < y1; row++)
            Buffer.BlockCopy(source.Pixels, (row - y) * source.Stride + (x0 - x) * 4, Pixels, row * Stride + x0 * 4, (x1 - x0) * 4);
    }

    /// <summary>
    /// A copy blended towards a solid colour (<paramref name="amount"/> 0..1), alpha kept. The overlay uses it for the
    /// translucent selection fill and the window-picking tint: blending once up front keeps painting a plain BitBlt.
    /// </summary>
    public BgraImage Tinted(byte r, byte g, byte b, double amount)
    {
        var result = new BgraImage(Width, Height);
        int keep = (int)Math.Round((1 - amount) * 256), add = 256 - keep;
        int tb = b * add, tg = g * add, tr = r * add;
        var src = Pixels;
        var dst = result.Pixels;
        for (int i = 0; i < src.Length; i += 4)
        {
            dst[i] = (byte)((src[i] * keep + tb) >> 8);
            dst[i + 1] = (byte)((src[i + 1] * keep + tg) >> 8);
            dst[i + 2] = (byte)((src[i + 2] * keep + tr) >> 8);
            dst[i + 3] = src[i + 3];
        }
        return result;
    }

    /// <summary>Copies the top-left <paramref name="width"/> x <paramref name="height"/> pixels of a BGRA8 bitmap.</summary>
    public static unsafe BgraImage FromSoftwareBitmap(SoftwareBitmap bitmap, int width, int height)
    {
        if (bitmap.BitmapPixelFormat != BitmapPixelFormat.Bgra8)
            throw new NotSupportedException($"Expected a BGRA8 bitmap, got {bitmap.BitmapPixelFormat}.");
        width = Math.Min(width, bitmap.PixelWidth);
        height = Math.Min(height, bitmap.PixelHeight);
        var result = new BgraImage(width, height);
        using var locked = bitmap.LockBuffer(BitmapBufferAccessMode.Read);
        var plane = locked.GetPlaneDescription(0);
        using var reference = locked.CreateReference();
        byte* data = MemoryBufferAccess.GetBytes(reference, out uint capacity);
        for (int y = 0; y < height; y++)
        {
            long offset = plane.StartIndex + (long)y * plane.Stride;
            if (offset + result.Stride > capacity) throw new InvalidOperationException("Bitmap buffer is smaller than its size says.");
            Marshal.Copy((IntPtr)(data + offset), result.Pixels, y * result.Stride, result.Stride);
        }
        return result;
    }

    /// <summary>This image as a new BGRA8 premultiplied <see cref="SoftwareBitmap"/>.</summary>
    public unsafe SoftwareBitmap ToSoftwareBitmap()
    {
        var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, Width, Height, BitmapAlphaMode.Premultiplied);
        using (var locked = bitmap.LockBuffer(BitmapBufferAccessMode.Write))
        {
            var plane = locked.GetPlaneDescription(0);
            using var reference = locked.CreateReference();
            byte* data = MemoryBufferAccess.GetBytes(reference, out uint capacity);
            for (int y = 0; y < Height; y++)
            {
                long offset = plane.StartIndex + (long)y * plane.Stride;
                if (offset + Stride > capacity) throw new InvalidOperationException("Bitmap buffer is smaller than its size says.");
                Marshal.Copy(Pixels, y * Stride, (IntPtr)(data + offset), Stride);
            }
        }
        return bitmap;
    }
}

/// <summary>Raw access to an <see cref="IMemoryBufferReference"/>'s bytes through the COM IMemoryBufferByteAccess interface.</summary>
internal static class MemoryBufferAccess
{
    private static readonly Guid IidIMemoryBufferByteAccess = new("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D");

    /// <summary>The buffer's first byte. Valid only while <paramref name="reference"/> is open.</summary>
    public static unsafe byte* GetBytes(IMemoryBufferReference reference, out uint capacity)
    {
        IntPtr unknown = MarshalInterface<IMemoryBufferReference>.FromManaged(reference);
        try
        {
            Guid iid = IidIMemoryBufferByteAccess;
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, ref iid, out IntPtr access));
            try
            {
                byte* bytes;
                uint size;
                // IMemoryBufferByteAccess::GetBuffer is the first method after IUnknown (vtable slot 3).
                var getBuffer = (delegate* unmanaged[Stdcall]<IntPtr, byte**, uint*, int>)(*(void***)access)[3];
                Marshal.ThrowExceptionForHR(getBuffer(access, &bytes, &size));
                capacity = size;
                return bytes;
            }
            finally
            {
                // The bytes stay valid: `reference` still holds the buffer.
                Marshal.Release(access);
            }
        }
        finally
        {
            Marshal.Release(unknown);
        }
    }
}
