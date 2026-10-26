using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Geometry;
using Skreener.Core.Editor;
using Skreener.Core.Geometry;

namespace Skreener.App.Editor;

/// <summary>
/// What the canvas draws over the screenshot but never exports: the selection's handles and the crop frame
/// (drawSelection and the crop drawing in AnnotationEditor.swift). Drawn in image pixels like the annotations;
/// <c>zoom</c> (DIPs per image pixel) keeps line widths and handles the same size on screen at any zoom.
/// </summary>
internal static class EditorOverlay
{
    public static readonly Windows.UI.Color HandleFill = Windows.UI.Color.FromArgb(255, 255, 255, 255);
    public static readonly Windows.UI.Color HandleStroke = Windows.UI.Color.FromArgb(255, 0x00, 0x78, 0xD4);
    private static readonly Windows.UI.Color CropShade = Windows.UI.Color.FromArgb(0x99, 0, 0, 0);

    /// <summary>
    /// The selection's handles (white dots with an accent ring, a fixed size on screen); a shape without handles (a
    /// stroke, a text label, a counter) gets a dashed frame instead.
    /// </summary>
    public static void DrawSelection(CanvasDrawingSession ds, Annotation a, double zoom)
    {
        var handles = AnnotationGeometry.Handles(a);
        var line = (float)(1.5 / zoom);
        if (handles.Count == 0)
        {
            var outset = AnnotationGeometry.InkOutset(a) + 3 / zoom;
            using var dashed = new CanvasStrokeStyle { DashStyle = CanvasDashStyle.Dash };
            ds.DrawRectangle(AnnotationRenderer.ToRect(a.Bounds.InsetBy(-outset, -outset)), HandleStroke, line, dashed);
            return;
        }
        var radius = (float)(5 / zoom);
        foreach (var h in handles)
        {
            ds.FillCircle(AnnotationRenderer.V(h), radius, HandleFill);
            ds.DrawCircle(AnnotationRenderer.V(h), radius, HandleStroke, line);
        }
    }

    /// <summary>
    /// Crop mode: everything of <paramref name="image"/> outside <paramref name="crop"/> dimmed, the crop framed, and
    /// its eight handles (corners and side middles) as white squares.
    /// </summary>
    public static void DrawCrop(CanvasDrawingSession ds, RectD crop, RectD image, double zoom)
    {
        // Four bands around the crop: above, below, then left and right of it.
        var bands = new[]
        {
            new RectD(image.MinX, image.MinY, image.Width, crop.MinY - image.MinY),
            new RectD(image.MinX, crop.MaxY, image.Width, image.MaxY - crop.MaxY),
            new RectD(image.MinX, crop.MinY, crop.MinX - image.MinX, crop.Height),
            new RectD(crop.MaxX, crop.MinY, image.MaxX - crop.MaxX, crop.Height),
        };
        foreach (var b in bands)
            if (b.Width > 0 && b.Height > 0) ds.FillRectangle(AnnotationRenderer.ToRect(b), CropShade);

        var line = (float)(1.5 / zoom);
        ds.DrawRectangle(AnnotationRenderer.ToRect(crop), HandleFill, line);
        // Rule-of-thirds guides, faint, as most croppers show.
        var guide = Windows.UI.Color.FromArgb(0x60, 255, 255, 255);
        for (int i = 1; i < 3; i++)
        {
            var x = (float)(crop.MinX + crop.Width * i / 3);
            var y = (float)(crop.MinY + crop.Height * i / 3);
            ds.DrawLine(x, (float)crop.MinY, x, (float)crop.MaxY, guide, (float)(1 / zoom));
            ds.DrawLine((float)crop.MinX, y, (float)crop.MaxX, y, guide, (float)(1 / zoom));
        }
        var half = 5 / zoom;
        foreach (var (p, _) in CropGeometry.Handles(crop))
        {
            var r = AnnotationRenderer.ToRect(new RectD(p.X - half, p.Y - half, 2 * half, 2 * half));
            ds.FillRectangle(r, HandleFill);
            ds.DrawRectangle(r, HandleStroke, line);
        }
    }
}
