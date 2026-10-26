using System.Runtime.InteropServices.WindowsRuntime;
using Skreener.App.Shell;
using Skreener.Core.Output;
using Skreener.Core.Text;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace Skreener.App.Ocr;

/// <summary>On-device OCR with Windows.Media.Ocr (port of TextRecognizer.recognize).</summary>
internal static class TextRecognizer
{
    /// <summary>An engine for the user's profile languages, or null when no OCR language pack is installed.</summary>
    public static OcrEngine? CreateEngine() => OcrEngine.TryCreateFromUserProfileLanguages();

    /// <summary>
    /// The text in <paramref name="bitmap"/>, one recognized line per line, in the engine's reading order. Empty when
    /// nothing was found. Images over <see cref="OcrEngine.MaxImageDimension"/> are scaled down to fit.
    /// </summary>
    public static async Task<string> RecognizeAsync(OcrEngine engine, SoftwareBitmap bitmap)
    {
        var (width, height) = OcrImageSize.Fit(bitmap.PixelWidth, bitmap.PixelHeight, (int)OcrEngine.MaxImageDimension);
        var scaled = width != bitmap.PixelWidth || height != bitmap.PixelHeight;
        var source = scaled ? await ScaleAsync(bitmap, width, height) : PrepareForOcr(bitmap);
        try
        {
            var result = await engine.RecognizeAsync(source);
            var tag = engine.RecognizerLanguage.LanguageTag;
            var lines = result.Lines.Select(line => TextJoin.LineFromWords(line.Words.Select(w => w.Text).ToList(), tag));
            return string.Join('\n', lines.Where(l => l.Length > 0));
        }
        finally
        {
            if (!ReferenceEquals(source, bitmap)) source.Dispose();
        }
    }

    /// <summary>The engine reads Bgra8 (any alpha) and Gray8; the capture already is Bgra8, so only other formats convert.</summary>
    private static SoftwareBitmap PrepareForOcr(SoftwareBitmap bitmap) =>
        bitmap.BitmapPixelFormat == BitmapPixelFormat.Bgra8
            ? bitmap
            : SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);

    /// <summary>A copy at the given size, through the imaging pipeline's high-quality scaler.</summary>
    private static async Task<SoftwareBitmap> ScaleAsync(SoftwareBitmap bitmap, int width, int height)
    {
        var png = await OutputService.EncodeAsync(bitmap, ImageFormat.Png);
        using var stream = new InMemoryRandomAccessStream();
        await stream.WriteAsync(png.AsBuffer());
        stream.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(stream);
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)width,
            ScaledHeight = (uint)height,
            InterpolationMode = BitmapInterpolationMode.Fant,
        };
        return await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
            ExifOrientationMode.IgnoreExif, ColorManagementMode.DoNotColorManage);
    }
}
