namespace Skreener.Core.Output;

public enum ImageFormat { Png, Jpeg }

public static class ImageFormatExtensions
{
    public static string FileExtension(this ImageFormat format) => format == ImageFormat.Png ? "png" : "jpg";

    /// <summary>The format a file with this extension (with or without the dot) is in; null for anything but PNG and JPEG.</summary>
    public static ImageFormat? FromFileExtension(string? extension)
    {
        switch (extension?.TrimStart('.').ToLowerInvariant())
        {
            case "png": return ImageFormat.Png;
            case "jpg":
            case "jpeg": return ImageFormat.Jpeg;
            default: return null;
        }
    }
}
