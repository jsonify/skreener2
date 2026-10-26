using System.Numerics;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Geometry;
using Skreener.App.Capture;
using Skreener.Core.Colors;
using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Skreener.Core.Imaging;
using Windows.Foundation;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;

namespace Skreener.App.Editor;

/// <summary>
/// Draws the screenshot and its annotations with Win2D, in image pixels (the caller sets the zoom as the session's
/// transform), and flattens them into a new bitmap for Copy and Save. Both paths share the drawing code, so what is
/// saved is what the canvas shows. Resources belong to one Win2D device: make a new renderer when it is recreated.
/// </summary>
internal sealed class AnnotationRenderer : IDisposable
{
    private readonly ICanvasResourceCreator _creator;
    private readonly BgraImage _image;
    private readonly CanvasBitmap _bitmap;
    private readonly CanvasStrokeStyle _round = new()
    {
        StartCap = CanvasCapStyle.Round,
        EndCap = CanvasCapStyle.Round,
        LineJoin = CanvasLineJoin.Round,
    };
    /// <summary>The whole image pixelated per block size in use, made on first use; a box shows its part of one.</summary>
    private readonly Dictionary<int, CanvasBitmap> _pixelated = new();

    public AnnotationRenderer(ICanvasResourceCreator creator, BgraImage image)
    {
        _creator = creator;
        _image = image;
        _bitmap = CreateBitmap(image.Pixels);
    }

    public int Width => _image.Width;
    public int Height => _image.Height;

    /// <summary>The screenshot at its pixel size, then each annotation in order.</summary>
    public void Draw(CanvasDrawingSession ds, IEnumerable<Annotation> items, CanvasImageInterpolation interpolation)
    {
        var all = new Rect(0, 0, _image.Width, _image.Height);
        ds.DrawImage(_bitmap, all, all, 1, interpolation);
        foreach (var a in items) DrawAnnotation(ds, a);
    }

    /// <summary>The screenshot with <paramref name="items"/> drawn in, at full size: what Copy and Save hand on.</summary>
    public SoftwareBitmap Flatten(IEnumerable<Annotation> items)
    {
        using var target = new CanvasRenderTarget(_creator, _image.Width, _image.Height, 96);
        using (var ds = target.CreateDrawingSession())
        {
            ds.Clear(Windows.UI.Color.FromArgb(0, 0, 0, 0));
            Draw(ds, items, CanvasImageInterpolation.NearestNeighbor);
        }
        var bytes = target.GetPixelBytes();
        return SoftwareBitmap.CreateCopyFromBuffer(bytes.AsBuffer(), BitmapPixelFormat.Bgra8, _image.Width, _image.Height,
            BitmapAlphaMode.Premultiplied);
    }

    private void DrawAnnotation(CanvasDrawingSession ds, Annotation a)
    {
        var color = ToColor(a.Style.Color);
        var width = (float)a.Style.LineWidth;
        switch (a.Kind)
        {
            case AnnotationKind.Rectangle:
                ds.DrawRectangle(ToRect(a.Rect), color, width, _round);
                break;
            case AnnotationKind.Ellipse:
            {
                var r = a.Rect;
                ds.DrawEllipse(new Vector2((float)(r.MinX + r.Width / 2), (float)(r.MinY + r.Height / 2)),
                    (float)(r.Width / 2), (float)(r.Height / 2), color, width, _round);
                break;
            }
            case AnnotationKind.Line:
                ds.DrawLine(V(a.Start), V(a.End), color, width, _round);
                break;
            case AnnotationKind.Arrow:
            {
                if (AnnotationGeometry.ArrowShape(a.Start, a.End, a.Style.LineWidth) is not { } shape) break;
                ds.DrawLine(V(a.Start), V(shape.ShaftEnd), color, width, _round);
                using var head = CanvasGeometry.CreatePolygon(ds, shape.Head.Select(V).ToArray());
                ds.FillGeometry(head, color);
                break;
            }
            case AnnotationKind.Pen:
            {
                if (a.Points.Count < 2) break;
                using var builder = new CanvasPathBuilder(ds);
                builder.BeginFigure(V(a.Points[0]));
                for (int i = 1; i < a.Points.Count; i++) builder.AddLine(V(a.Points[i]));
                builder.EndFigure(CanvasFigureLoop.Open);
                using var path = CanvasGeometry.CreatePath(builder);
                ds.DrawGeometry(path, color, width, _round);
                break;
            }
            case AnnotationKind.Pixelate:
            {
                // Only the part over the screenshot: pixels outside it have nothing to pixelate.
                var r = a.Rect.Intersection(new RectD(0, 0, _image.Width, _image.Height));
                if (r.IsEmpty) break;
                var rect = ToRect(r);
                ds.DrawImage(Pixelated(a.Style.PixelSize), rect, rect, 1, CanvasImageInterpolation.NearestNeighbor);
                break;
            }
        }
    }

    private CanvasBitmap Pixelated(int block)
    {
        block = Math.Max(block, 1);
        if (!_pixelated.TryGetValue(block, out var bitmap))
        {
            bitmap = CreateBitmap(Pixelate.Apply(_image.Pixels, _image.Width, _image.Height, block));
            _pixelated[block] = bitmap;
        }
        return bitmap;
    }

    /// <summary>A BGRA8 premultiplied bitmap at 96 DPI, so one image pixel is one unit in the drawing session.</summary>
    private CanvasBitmap CreateBitmap(byte[] pixels) =>
        CanvasBitmap.CreateFromBytes(_creator, pixels, _image.Width, _image.Height, DirectXPixelFormat.B8G8R8A8UIntNormalized,
            96, CanvasAlphaMode.Premultiplied);

    public static Windows.UI.Color ToColor(RgbColor c) =>
        Windows.UI.Color.FromArgb((byte)RgbColor.Byte(c.A), (byte)RgbColor.Byte(c.R), (byte)RgbColor.Byte(c.G), (byte)RgbColor.Byte(c.B));

    public static Vector2 V(PointD p) => new((float)p.X, (float)p.Y);

    public static Rect ToRect(RectD r) => new(r.MinX, r.MinY, r.Width, r.Height);

    public void Dispose()
    {
        _bitmap.Dispose();
        foreach (var b in _pixelated.Values) b.Dispose();
        _pixelated.Clear();
        _round.Dispose();
    }
}
