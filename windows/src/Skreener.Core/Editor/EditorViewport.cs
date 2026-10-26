using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>
/// The editor canvas's zoom and scroll position (the Mac editor's NSScrollView magnification, its fit mode and the
/// middle-button pan in EditorWindow.swift). Maps between view coordinates (DIPs from the canvas's top-left corner)
/// and image pixels.
/// <para>
/// <see cref="Zoom"/> is DIPs per image pixel, what <see cref="EditorSession.PointerDown"/> takes. <see cref="Scale"/>
/// is screen pixels per image pixel, what the user sees as the percentage: 100 % puts one image pixel on one screen
/// pixel at any display scaling. Fit (the default) shows all of <see cref="Content"/> inside the padding, never above
/// 100 %. A content smaller than the view is centered; a larger one scrolls, within limits that keep the padding at its
/// ends.
/// </para>
/// </summary>
public sealed class EditorViewport
{
    /// <summary>The smallest and largest scale the zoom keys, wheel and menu reach (10 % to 800 %).</summary>
    public const double MinScale = 0.1, MaxScale = 8;

    /// <summary>The scales Ctrl+= and Ctrl+- step through.</summary>
    public static IReadOnlyList<double> Steps { get; } = new[] { 0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.5, 2, 3, 4, 6, 8 };

    private double _scale = 1;
    private double _scrollX, _scrollY;

    /// <summary>The part of the image shown, in image pixels: all of it, or the crop.</summary>
    public RectD Content { get; private set; } = new(0, 0, 1, 1);

    /// <summary>The canvas's size in DIPs.</summary>
    public SizeD ViewSize { get; private set; } = new(1, 1);

    /// <summary>Screen pixels per DIP (the display's scaling: 1.5 at 150 %).</summary>
    public double RasterScale { get; private set; } = 1;

    /// <summary>Room left around the content, in DIPs.</summary>
    public double Padding { get; private set; } = 16;

    /// <summary>Whether the zoom follows the view's size (Ctrl+0, the default) rather than staying where it was set.</summary>
    public bool IsFit { get; private set; } = true;

    /// <summary>Screen pixels per image pixel: 1 is 100 %.</summary>
    public double Scale => IsFit ? FitScale : _scale;

    /// <summary>DIPs per image pixel.</summary>
    public double Zoom => Scale / RasterScale;

    /// <summary>The scale that fits <see cref="Content"/> inside the padding, at most 100 %.</summary>
    public double FitScale
    {
        get
        {
            double w = ViewSize.Width - 2 * Padding, h = ViewSize.Height - 2 * Padding;
            var fit = Math.Min(w / Math.Max(Content.Width, 1), h / Math.Max(Content.Height, 1)) * RasterScale;
            return Math.Clamp(fit, 0.01, 1);
        }
    }

    /// <summary>The content's laid-out size in DIPs, padding included (the scrollable document).</summary>
    public SizeD DocumentSize => new(Content.Width * Zoom + 2 * Padding, Content.Height * Zoom + 2 * Padding);

    /// <summary>Whether the content is larger than the view in either direction, so the wheel scrolls it.</summary>
    public bool CanScroll => DocumentSize.Width > ViewSize.Width + 0.5 || DocumentSize.Height > ViewSize.Height + 0.5;

    /// <summary>Where <see cref="Content"/>'s top-left corner sits in the view, in DIPs (whole DIPs when centered).</summary>
    public PointD Origin
    {
        get
        {
            var doc = DocumentSize;
            var x = doc.Width <= ViewSize.Width ? Math.Round((ViewSize.Width - Content.Width * Zoom) / 2) : Padding - _scrollX;
            var y = doc.Height <= ViewSize.Height ? Math.Round((ViewSize.Height - Content.Height * Zoom) / 2) : Padding - _scrollY;
            return new PointD(x, y);
        }
    }

    /// <summary>
    /// Sets what is shown and where. With <see cref="IsFit"/> on, the zoom refits; otherwise it stays and the scroll
    /// position is kept within the new limits.
    /// </summary>
    public void Update(RectD content, SizeD viewSize, double rasterScale, double padding)
    {
        Content = content.IsEmpty ? new RectD(content.MinX, content.MinY, 1, 1) : content.Standardized;
        ViewSize = new SizeD(Math.Max(viewSize.Width, 1), Math.Max(viewSize.Height, 1));
        RasterScale = rasterScale > 0 ? rasterScale : 1;
        Padding = Math.Max(padding, 0);
        ClampScroll();
    }

    /// <summary>A view point (DIPs) in image pixels.</summary>
    public PointD ToImage(PointD view)
    {
        var o = Origin;
        return new PointD(Content.MinX + (view.X - o.X) / Zoom, Content.MinY + (view.Y - o.Y) / Zoom);
    }

    /// <summary>An image point in view DIPs.</summary>
    public PointD ToView(PointD image)
    {
        var o = Origin;
        return new PointD(o.X + (image.X - Content.MinX) * Zoom, o.Y + (image.Y - Content.MinY) * Zoom);
    }

    /// <summary>Back to fit (Ctrl+0, the menu's Fit).</summary>
    public void Fit()
    {
        IsFit = true;
        _scrollX = _scrollY = 0;
    }

    /// <summary>
    /// Zooms to <paramref name="scale"/> (clamped to <see cref="MinScale"/>..<see cref="MaxScale"/>) keeping the image
    /// point under <paramref name="anchor"/> (view DIPs) where it is, as far as the scroll limits allow. A null anchor
    /// is the view's center.
    /// </summary>
    public void ZoomTo(double scale, PointD? anchor = null)
    {
        var a = anchor ?? new PointD(ViewSize.Width / 2, ViewSize.Height / 2);
        var fixedPoint = ToImage(a);
        _scale = Math.Clamp(scale, MinScale, MaxScale);
        IsFit = false;
        // Solve Origin + (fixedPoint - Content.Min) * Zoom = a for the scroll offset, then keep it in range.
        _scrollX = Padding + (fixedPoint.X - Content.MinX) * Zoom - a.X;
        _scrollY = Padding + (fixedPoint.Y - Content.MinY) * Zoom - a.Y;
        ClampScroll();
    }

    /// <summary>Zooms by <paramref name="factor"/> around <paramref name="anchor"/> (Ctrl+wheel).</summary>
    public void ZoomBy(double factor, PointD? anchor = null) => ZoomTo(Scale * factor, anchor);

    /// <summary>The next step in <see cref="Steps"/> above (or below, <paramref name="up"/> false) the current scale.</summary>
    public double NextStep(bool up)
    {
        var s = Scale;
        if (up)
        {
            foreach (var step in Steps)
                if (step > s + 1e-6) return step;
            return MaxScale;
        }
        for (int i = Steps.Count - 1; i >= 0; i--)
            if (Steps[i] < s - 1e-6) return Steps[i];
        return MinScale;
    }

    /// <summary>Ctrl+= / Ctrl+-: the next step up or down, around the view's center.</summary>
    public void Step(bool up) => ZoomTo(NextStep(up));

    /// <summary>The zoom factor for a Ctrl+wheel turn of <paramref name="delta"/> (120 per notch, positive away from the user zooms in).</summary>
    public static double WheelFactor(double delta) => Math.Exp(delta / 120 * 0.2);

    /// <summary>Scrolls by (<paramref name="dx"/>, <paramref name="dy"/>) DIPs (positive shows more to the right and below), within the limits.</summary>
    public void ScrollBy(double dx, double dy)
    {
        _scrollX += dx;
        _scrollY += dy;
        ClampScroll();
    }

    /// <summary>A middle-button drag moved the pointer by (<paramref name="dx"/>, <paramref name="dy"/>) DIPs: the content follows it.</summary>
    public void Pan(double dx, double dy) => ScrollBy(-dx, -dy);

    private void ClampScroll()
    {
        var doc = DocumentSize;
        _scrollX = Math.Clamp(_scrollX, 0, Math.Max(doc.Width - ViewSize.Width, 0));
        _scrollY = Math.Clamp(_scrollY, 0, Math.Max(doc.Height - ViewSize.Height, 0));
    }
}
