using System.Runtime.InteropServices;
using Skreener.App.Capture;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace Skreener.App.Overlay;

/// <summary>A memory DC with a 32-bit bitmap selected into it: the frozen screen, its tinted copies, or a back buffer.</summary>
internal sealed unsafe class GdiSurface : IDisposable
{
    private HBITMAP _bitmap;
    private HGDIOBJ _previous;

    private GdiSurface(HDC dc, HBITMAP bitmap, int width, int height)
    {
        Dc = dc;
        _bitmap = bitmap;
        Width = width;
        Height = height;
        _previous = PInvoke.SelectObject(dc, (HGDIOBJ)bitmap.Value);
    }

    public HDC Dc { get; private set; }
    public int Width { get; }
    public int Height { get; }

    /// <summary>A top-down 32-bit DIB section holding a copy of <paramref name="pixels"/>.</summary>
    public static GdiSurface FromPixels(BgraImage pixels)
    {
        var info = new BITMAPINFO();
        info.bmiHeader.biSize = (uint)sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = pixels.Width;
        info.bmiHeader.biHeight = -pixels.Height;   // negative: rows top to bottom, like BgraImage
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        info.bmiHeader.biCompression = 0;           // BI_RGB
        void* bits;
        var bitmap = PInvoke.CreateDIBSection(default, &info, DIB_USAGE.DIB_RGB_COLORS, &bits, default, 0);
        if (bitmap.IsNull || bits == null) throw new InvalidOperationException("Could not create a bitmap for the overlay.");
        // 32-bit rows are already DWORD aligned, so the DIB's stride is width * 4, the same as BgraImage's.
        Marshal.Copy(pixels.Pixels, 0, (IntPtr)bits, pixels.Pixels.Length);
        var dc = PInvoke.CreateCompatibleDC(default);
        return new GdiSurface(dc, bitmap, pixels.Width, pixels.Height);
    }

    /// <summary>A back buffer compatible with <paramref name="screenDc"/>.</summary>
    public static GdiSurface Compatible(HDC screenDc, int width, int height)
    {
        var bitmap = PInvoke.CreateCompatibleBitmap(screenDc, width, height);
        if (bitmap.IsNull) throw new InvalidOperationException("Could not create the overlay's back buffer.");
        return new GdiSurface(PInvoke.CreateCompatibleDC(screenDc), bitmap, width, height);
    }

    public void Dispose()
    {
        if (Dc == default) return;
        PInvoke.SelectObject(Dc, _previous);
        PInvoke.DeleteObject((HGDIOBJ)_bitmap.Value);
        PInvoke.DeleteDC(Dc);
        Dc = default;
        _bitmap = default;
        _previous = default;
    }
}
