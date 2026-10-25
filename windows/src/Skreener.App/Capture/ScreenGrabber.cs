using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;

namespace Skreener.App.Capture;

/// <summary>
/// One-shot grabs with Windows.Graphics.Capture (WGC). WGC has no "take a screenshot" call: a capture session is
/// started, the first frame is copied to the CPU, and the session is closed again.
/// </summary>
internal static class ScreenGrabber
{
    /// <summary>How long to wait for the first frame before giving up (a hidden or DRM-protected surface may never send one).</summary>
    private static readonly TimeSpan FrameTimeout = TimeSpan.FromSeconds(3);

    /// <summary>The whole monitor, without the mouse pointer.</summary>
    public static Task<PixelBuffer> GrabMonitorAsync(IntPtr hmonitor, CancellationToken ct = default) =>
        GrabAsync(GraphicsCaptureInterop.CreateItemForMonitor(hmonitor), ct);

    /// <summary>
    /// One window on its own, even when other windows cover it (minimized windows send no frames). WGC captures the
    /// window's DWM surface: no drop shadow and no resize borders. On Windows 11 the corners are rounded by DWM; whether
    /// the pixels outside the rounded corners arrive with alpha 0 or opaque is [verify] (see feature-inventory 4.2).
    /// </summary>
    public static Task<PixelBuffer> GrabWindowAsync(IntPtr hwnd, CancellationToken ct = default) =>
        GrabAsync(GraphicsCaptureInterop.CreateItemForWindow(hwnd), ct);

    private static async Task<PixelBuffer> GrabAsync(GraphicsCaptureItem item, CancellationToken ct)
    {
        // Free-threaded frame pools (frames arrive on a worker thread, no DispatcherQueue needed) are Windows 10 1903+.
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 18362))
            throw new PlatformNotSupportedException("Screen capture needs Windows 10 version 1903 or later.");
        try
        {
            return await GrabOnceAsync(item, ct);
        }
        catch (Exception e) when (e.HResult == unchecked((int)0x887A0005) || e.HResult == unchecked((int)0x887A0007))
        {
            // DXGI_ERROR_DEVICE_REMOVED / _RESET (driver update, GPU switch): retry once on a fresh device.
            GraphicsCaptureInterop.ResetDevice();
            return await GrabOnceAsync(item, ct);
        }
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows10.0.18362.0")]
    private static async Task<PixelBuffer> GrabOnceAsync(GraphicsCaptureItem item, CancellationToken ct)
    {
        var size = item.Size;
        if (size.Width <= 0 || size.Height <= 0) throw new InvalidOperationException("Nothing to capture: the item has no size.");
        using var pool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            GraphicsCaptureInterop.Device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 1, size);
        using var session = pool.CreateCaptureSession(item);
        if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041)) session.IsCursorCaptureEnabled = false;
        GraphicsCaptureInterop.TryDisableBorder(session);

        var arrived = new TaskCompletionSource<Direct3D11CaptureFrame>(TaskCreationOptions.RunContinuationsAsynchronously);
        pool.FrameArrived += (sender, _) =>
        {
            var frame = sender.TryGetNextFrame();
            if (frame is not null && !arrived.TrySetResult(frame)) frame.Dispose();
        };
        session.StartCapture();

        using var first = await arrived.Task.WaitAsync(FrameTimeout, ct);
        // The surface is the pool's size; the content can be smaller (a window that shrank since the item was made).
        var content = first.ContentSize;
        using var bitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(first.Surface, BitmapAlphaMode.Premultiplied);
        int width = content.Width > 0 ? content.Width : bitmap.PixelWidth;
        int height = content.Height > 0 ? content.Height : bitmap.PixelHeight;
        return PixelBuffer.FromSoftwareBitmap(bitmap, width, height);
    }
}
