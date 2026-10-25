using Windows.Graphics;
using Windows.Graphics.Imaging;

namespace Skreener.App.Capture;

public enum CaptureKind { Area, Window, Fullscreen, PreviousArea }

/// <summary>A finished capture. <see cref="Bitmap"/> is BGRA8 premultiplied; <see cref="ScreenRect"/> is in physical pixels, virtual-desktop coordinates.</summary>
public sealed record CaptureResult(SoftwareBitmap Bitmap, CaptureKind Kind, RectInt32 ScreenRect, string? WindowTitle);

public interface ICaptureService
{
    /// <summary>Runs the capture flow for <paramref name="kind"/>. Returns null when the user cancels.</summary>
    Task<CaptureResult?> CaptureAsync(CaptureKind kind, CancellationToken cancellationToken = default);
}
