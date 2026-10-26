using System.Numerics;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Effects;
using Microsoft.Graphics.Canvas.Geometry;
using Microsoft.Graphics.Canvas.Text;
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
/// <para>
/// The highlighter multiplies with what is under it (the Mac's .multiply blend mode). Win2D's drawing session has no
/// multiply blend, so everything below a highlighter is recorded into a command list and composited with the stroke
/// through a <see cref="BlendEffect"/>; drawings with no highlighter are drawn straight onto the session.
/// </para>
/// </summary>
internal sealed class AnnotationRenderer : IDisposable
{
    /// <summary>The highlighter's ink opacity before the multiply (0.45 on the Mac).</summary>
    private const double HighlighterAlpha = 0.45;

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
    /// <summary>The whole image blurred per radius in use; a blur box shows its part of one.</summary>
    private readonly Dictionary<int, GaussianBlurEffect> _blurred = new();
    /// <summary>
    /// Command lists and effects one drawing used. They stay alive until the next drawing (or Dispose): the drawing
    /// session may still need them until it is closed, which happens after <see cref="Draw"/> returns.
    /// </summary>
    private readonly List<IDisposable> _frame = new();

    public AnnotationRenderer(ICanvasResourceCreator creator, BgraImage image)
    {
        _creator = creator;
        _image = image;
        _bitmap = CreateBitmap(image.Pixels);
    }

    public int Width => _image.Width;
    public int Height => _image.Height;

    /// <summary>The whole image, in image pixels.</summary>
    public RectD Bounds => new(0, 0, _image.Width, _image.Height);

    /// <summary>
    /// The screenshot at its pixel size, then each annotation in order, except <paramref name="hiddenId"/> (the text
    /// label being typed, which its text box shows instead).
    /// </summary>
    public void Draw(CanvasDrawingSession ds, IReadOnlyList<Annotation> items, CanvasImageInterpolation interpolation, int? hiddenId = null)
    {
        ReleaseFrame();
        var visible = items.Where(a => a.Id != hiddenId).ToList();
        int last = visible.FindLastIndex(a => a.Kind == AnnotationKind.Highlighter);
        if (last < 0)
        {
            DrawBase(ds, interpolation);
            foreach (var a in visible) DrawAnnotation(ds, a, items);
            return;
        }

        // Record everything up to each highlighter, multiply the stroke onto it, and carry on on top of the result.
        var scene = Track(new CanvasCommandList(ds));
        CanvasDrawingSession? recording = scene.CreateDrawingSession();
        DrawBase(recording, interpolation);
        for (int i = 0; i <= last; i++)
        {
            var a = visible[i];
            if (a.Kind != AnnotationKind.Highlighter)
            {
                DrawAnnotation(recording!, a, items);
                continue;
            }
            recording!.Dispose();
            recording = null;
            var blend = Track(new BlendEffect { Mode = BlendEffectMode.Multiply, Background = scene, Foreground = HighlighterStroke(ds, a) });
            if (i == last)
            {
                ds.DrawImage(blend);
                break;
            }
            scene = Track(new CanvasCommandList(ds));
            recording = scene.CreateDrawingSession();
            recording.DrawImage(blend);
        }
        for (int i = last + 1; i < visible.Count; i++) DrawAnnotation(ds, visible[i], items);
    }

    /// <summary>
    /// The screenshot with <paramref name="items"/> drawn in, at full size, cut to <paramref name="crop"/> when there
    /// is one: what Copy and Save hand on.
    /// </summary>
    public SoftwareBitmap Flatten(IReadOnlyList<Annotation> items, RectD? crop)
    {
        var area = (crop ?? Bounds).Integral.Intersection(Bounds);
        if (area.IsEmpty) area = Bounds;
        int x = (int)area.MinX, y = (int)area.MinY, width = (int)area.Width, height = (int)area.Height;
        using var target = new CanvasRenderTarget(_creator, width, height, 96);
        using (var ds = target.CreateDrawingSession())
        {
            ds.Clear(Windows.UI.Color.FromArgb(0, 0, 0, 0));
            ds.Transform = Matrix3x2.CreateTranslation(-x, -y);
            Draw(ds, items, CanvasImageInterpolation.NearestNeighbor);
        }
        ReleaseFrame();
        var bytes = target.GetPixelBytes();
        return SoftwareBitmap.CreateCopyFromBuffer(bytes.AsBuffer(), BitmapPixelFormat.Bgra8, width, height,
            BitmapAlphaMode.Premultiplied);
    }

    private void DrawBase(CanvasDrawingSession ds, CanvasImageInterpolation interpolation)
    {
        var all = new Rect(0, 0, _image.Width, _image.Height);
        ds.DrawImage(_bitmap, all, all, 1, interpolation);
    }

    /// <param name="all">Every annotation, for numbering the counters.</param>
    private void DrawAnnotation(CanvasDrawingSession ds, Annotation a, IReadOnlyList<Annotation> all)
    {
        var color = ToColor(a.Style.Color);
        var width = (float)a.Style.LineWidth;
        switch (a.Kind)
        {
            case AnnotationKind.Rectangle:
                ds.DrawRectangle(ToRect(a.Rect), color, width, _round);
                break;
            case AnnotationKind.FilledRectangle:
                ds.FillRectangle(ToRect(a.Rect), color);
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
                using var path = StrokePath(ds, a.Points);
                if (path is not null) ds.DrawGeometry(path, color, width, _round);
                break;
            }
            case AnnotationKind.Highlighter:
                // Only reached through Draw's multiply path; drawn on its own it is a translucent stroke.
                ds.DrawImage(HighlighterStroke(ds, a));
                break;
            case AnnotationKind.Text:
            {
                if (a.Text.Length == 0) break;
                using var format = TextMetrics.Format(a.Style);
                using var layout = TextMetrics.Layout(ds, a.Text, format);
                ds.DrawTextLayout(layout, V(a.Start), color);
                break;
            }
            case AnnotationKind.Counter:
                DrawCounter(ds, a, all, color);
                break;
            case AnnotationKind.Pixelate:
            {
                // Only the part over the screenshot: pixels outside it have nothing to pixelate.
                var r = a.Rect.Intersection(Bounds);
                if (r.IsEmpty) break;
                var rect = ToRect(r);
                ds.DrawImage(Pixelated(a.Style.PixelSize), rect, rect, 1, CanvasImageInterpolation.NearestNeighbor);
                break;
            }
            case AnnotationKind.Blur:
            {
                // The screenshot blurred (not the annotations under the box, as on the Mac), shown inside the box.
                var r = a.Rect.Intersection(Bounds);
                if (r.IsEmpty) break;
                var rect = ToRect(r);
                ds.DrawImage(Blurred(a.Style.BlurRadius), rect, rect);
                break;
            }
        }
    }

    /// <summary>
    /// A filled circle with the counter's number (drawCounter on the Mac): white, or black on very light fills, in a
    /// bold font sized to the circle.
    /// </summary>
    private static void DrawCounter(CanvasDrawingSession ds, Annotation a, IReadOnlyList<Annotation> all, Windows.UI.Color color)
    {
        var radius = a.Style.CounterRadius;
        ds.FillCircle(V(a.Start), (float)radius, color);
        var number = AnnotationGeometry.CounterNumber(all, a).ToString(System.Globalization.CultureInfo.InvariantCulture);
        var ink = AnnotationGeometry.CounterUsesDarkText(a.Style.Color) ? Windows.UI.Color.FromArgb(255, 0, 0, 0) : Windows.UI.Color.FromArgb(255, 255, 255, 255);
        using var format = new CanvasTextFormat
        {
            FontFamily = TextMetrics.FontFamily,
            FontSize = (float)(radius * 1.1),
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            WordWrapping = CanvasWordWrapping.NoWrap,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center,
        };
        ds.DrawText(number, ToRect(a.Bounds), ink, format);
    }

    /// <summary>A highlighter stroke on its own, in its color at <see cref="HighlighterAlpha"/>, as an image to multiply with.</summary>
    private CanvasCommandList HighlighterStroke(ICanvasResourceCreator creator, Annotation a)
    {
        var list = Track(new CanvasCommandList(creator));
        using var ds = list.CreateDrawingSession();
        using var path = StrokePath(ds, a.Points);
        if (path is not null)
        {
            var c = a.Style.Color with { A = a.Style.Color.A * HighlighterAlpha };
            ds.DrawGeometry(path, ToColor(c), (float)a.Style.HighlighterWidth, _round);
        }
        return list;
    }

    /// <summary>An open path through <paramref name="points"/>, or null with fewer than two.</summary>
    private static CanvasGeometry? StrokePath(ICanvasResourceCreator creator, IReadOnlyList<PointD> points)
    {
        if (points.Count < 2) return null;
        using var builder = new CanvasPathBuilder(creator);
        builder.BeginFigure(V(points[0]));
        for (int i = 1; i < points.Count; i++) builder.AddLine(V(points[i]));
        builder.EndFigure(CanvasFigureLoop.Open);
        return CanvasGeometry.CreatePath(builder);
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

    private GaussianBlurEffect Blurred(int radius)
    {
        radius = Math.Max(radius, 1);
        if (!_blurred.TryGetValue(radius, out var effect))
        {
            // Hard borders: the edges of the screenshot blur with its own pixels, not with transparency.
            effect = new GaussianBlurEffect
            {
                Source = _bitmap,
                BlurAmount = radius,
                BorderMode = EffectBorderMode.Hard,
                Optimization = EffectOptimization.Quality,
            };
            _blurred[radius] = effect;
        }
        return effect;
    }

    private T Track<T>(T resource) where T : IDisposable
    {
        _frame.Add(resource);
        return resource;
    }

    private void ReleaseFrame()
    {
        foreach (var r in _frame) r.Dispose();
        _frame.Clear();
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
        ReleaseFrame();
        _bitmap.Dispose();
        foreach (var b in _pixelated.Values) b.Dispose();
        _pixelated.Clear();
        foreach (var e in _blurred.Values) e.Dispose();
        _blurred.Clear();
        _round.Dispose();
    }
}
