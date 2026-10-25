using System.Runtime.InteropServices.WindowsRuntime;
using Skreener.Core.Output;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Skreener.App.Shell;

/// <summary>Copy to the clipboard and save to a file (the image half of Output.swift). File naming lives in Skreener.Core.</summary>
internal sealed class OutputService
{
    /// <summary>Puts the capture on the clipboard as a PNG-backed bitmap.</summary>
    public async Task CopyAsync(SoftwareBitmap bitmap)
    {
        var png = await EncodeAsync(bitmap, ImageFormat.Png);
        // Left undisposed on purpose: the clipboard reads from it until Flush() has copied the data out.
        var stream = new InMemoryRandomAccessStream();
        await stream.WriteAsync(png.AsBuffer());
        var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
        package.SetBitmap(RandomAccessStreamReference.CreateFromStream(stream));
        Clipboard.SetContent(package);
        try { Clipboard.Flush(); }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            // Flush fails when the app is not in the foreground; the clipboard still holds the (delay-rendered) image.
            System.Diagnostics.Debug.WriteLine($"Skreener: clipboard flush failed: {e.Message}");
        }
    }

    /// <summary>Saves into the folder and format from Settings, named from the template. Returns the file's path.</summary>
    public async Task<string> SaveAsync(SoftwareBitmap bitmap, AppSettings settings)
    {
        var folder = settings.ResolveSaveFolder(SettingsStore.PicturesFolder);
        Directory.CreateDirectory(folder);
        var name = FileNaming.Filename(DateTime.Now, settings.FilenameTemplate);
        var path = FileNaming.UniquePath(folder, name, settings.ImageFormat.FileExtension());
        var data = await EncodeAsync(bitmap, settings.ImageFormat);
        await File.WriteAllBytesAsync(path, data);
        return path;
    }

    /// <summary>The image as PNG or JPEG bytes. JPEG has no alpha, so transparent areas (window captures) become white.</summary>
    public static async Task<byte[]> EncodeAsync(SoftwareBitmap bitmap, ImageFormat format)
    {
        var source = bitmap;
        if (source.BitmapPixelFormat != BitmapPixelFormat.Bgra8)
            source = SoftwareBitmap.Convert(source, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);

        using var stream = new InMemoryRandomAccessStream();
        BitmapEncoder encoder;
        if (format == ImageFormat.Jpeg)
        {
            var quality = new BitmapPropertySet { { "ImageQuality", new BitmapTypedValue(0.9f, PropertyType.Single) } };
            encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, stream, quality);
            using var flat = FlattenOnWhite(source);
            encoder.SetSoftwareBitmap(flat);
            await encoder.FlushAsync();
        }
        else
        {
            encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetSoftwareBitmap(source);
            await encoder.FlushAsync();
        }

        var bytes = new byte[stream.Size];
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync((uint)bytes.Length);
        reader.ReadBytes(bytes);
        return bytes;
    }

    /// <summary>Composites a BGRA8 premultiplied bitmap over white and drops the alpha channel.</summary>
    private static SoftwareBitmap FlattenOnWhite(SoftwareBitmap bitmap)
    {
        var pixels = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4];
        bitmap.CopyToBuffer(pixels.AsBuffer());
        for (var i = 0; i < pixels.Length; i += 4)
        {
            var uncovered = 255 - pixels[i + 3];
            pixels[i] = (byte)Math.Min(255, pixels[i] + uncovered);
            pixels[i + 1] = (byte)Math.Min(255, pixels[i + 1] + uncovered);
            pixels[i + 2] = (byte)Math.Min(255, pixels[i + 2] + uncovered);
            pixels[i + 3] = 255;
        }
        return SoftwareBitmap.CreateCopyFromBuffer(pixels.AsBuffer(), BitmapPixelFormat.Bgra8,
            bitmap.PixelWidth, bitmap.PixelHeight, BitmapAlphaMode.Ignore);
    }
}
