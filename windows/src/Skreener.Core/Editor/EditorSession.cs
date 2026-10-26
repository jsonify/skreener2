using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>The editor's tools (Tool in AnnotationEditor.swift, the ones the Windows editor has so far), in the Mac's toolbar order.</summary>
public enum EditorTool
{
    Select,
    Arrow,
    Rectangle,
    FilledRectangle,
    Ellipse,
    Line,
    Pen,
    Highlighter,
    Text,
    Counter,
    Pixelate,
    Blur,
}

public static class EditorTools
{
    /// <summary>Crop is a mode rather than a tool (the Mac's Crop button): this key starts it.</summary>
    public const char CropShortcut = 'C';

    /// <summary>The tools in toolbar order.</summary>
    public static IReadOnlyList<EditorTool> All { get; } = Enum.GetValues<EditorTool>();

    /// <summary>The annotation a drawing tool makes; null for Select.</summary>
    public static AnnotationKind? Kind(this EditorTool tool) => tool switch
    {
        EditorTool.Arrow => AnnotationKind.Arrow,
        EditorTool.Rectangle => AnnotationKind.Rectangle,
        EditorTool.FilledRectangle => AnnotationKind.FilledRectangle,
        EditorTool.Ellipse => AnnotationKind.Ellipse,
        EditorTool.Line => AnnotationKind.Line,
        EditorTool.Pen => AnnotationKind.Pen,
        EditorTool.Highlighter => AnnotationKind.Highlighter,
        EditorTool.Text => AnnotationKind.Text,
        EditorTool.Counter => AnnotationKind.Counter,
        EditorTool.Pixelate => AnnotationKind.Pixelate,
        EditorTool.Blur => AnnotationKind.Blur,
        _ => null,
    };

    /// <summary>The single-key shortcut, as on the Mac (V A R F O L P H T N X B).</summary>
    public static char Shortcut(this EditorTool tool) => tool switch
    {
        EditorTool.Select => 'V',
        EditorTool.Arrow => 'A',
        EditorTool.Rectangle => 'R',
        EditorTool.FilledRectangle => 'F',
        EditorTool.Ellipse => 'O',
        EditorTool.Line => 'L',
        EditorTool.Pen => 'P',
        EditorTool.Highlighter => 'H',
        EditorTool.Text => 'T',
        EditorTool.Counter => 'N',
        EditorTool.Pixelate => 'X',
        _ => 'B',
    };

    /// <summary>The tool for a shortcut key (either case), or null.</summary>
    public static EditorTool? ForShortcut(char key)
    {
        key = char.ToUpperInvariant(key);
        foreach (var tool in All)
            if (tool.Shortcut() == key) return tool;
        return null;
    }
}

/// <summary>
/// The editor's state and pointer handling, without any drawing: the annotations, the one being drawn, the selection,
/// the text being typed, the crop and the undo history (CanvasView's model half in AnnotationEditor.swift). The window
/// feeds it pointer events in image pixels and redraws on <see cref="Changed"/>.
/// <para>
/// As on the Mac, a press first grabs a handle of the selected annotation, then any annotation under the pointer
/// (with any tool), and only on empty canvas starts drawing with the current tool. A whole drag is one undo step, and
/// so is typing a text label from the click that placed it to the end of editing.
/// </para>
/// </summary>
public sealed class EditorSession
{
    /// <summary>On-screen distances the Mac uses, in view points: slop around a line, and a handle's grab radius.</summary>
    public const double SlopPoints = 5, HandleRadiusPoints = 8;

    /// <summary>What one undo step restores (Snapshot on the Mac, the parts this editor has).</summary>
    private readonly record struct Snapshot(IReadOnlyList<Annotation> Items, RectD? Crop);

    private readonly Stack<Snapshot> _undo = new();
    private readonly Stack<Snapshot> _redo = new();
    private IReadOnlyList<Annotation> _items = Array.Empty<Annotation>();
    private Snapshot? _beforeDrag;
    private Snapshot? _beforeEditing;
    private Drag _drag = Drag.None;
    private int _handle;
    private PointD _last;
    private CropDrag _cropDrag;
    private PointD _cropAnchor;
    private RectD? _cropBeforeDrag;
    private int _nextId = 1;
    private AnnotationStyle _style = AnnotationStyle.Default;
    private EditorTool _tool = EditorTool.Arrow;

    private enum Drag { None, Draw, Move, Resize, Crop }

    /// <summary>Raised after anything that changes what is drawn (items, draft, selection, text, crop).</summary>
    public event Action? Changed;

    /// <summary>The screenshot's size in pixels: what the crop is clamped to. Crop mode needs it set.</summary>
    public SizeD ImageSize { get; init; }

    /// <summary>
    /// Measures a text label (its text in its style, image pixels); the window supplies the real one. Without it a
    /// rough estimate (<see cref="AnnotationGeometry.EstimateTextSize"/>) sizes the box.
    /// </summary>
    public Func<string, AnnotationStyle, SizeD>? TextMeasurer { get; set; }

    /// <summary>The annotations, bottom to top.</summary>
    public IReadOnlyList<Annotation> Items => _items;

    /// <summary>The annotation being drawn right now, not yet in <see cref="Items"/>.</summary>
    public Annotation? Draft { get; private set; }

    public int? SelectedId { get; private set; }

    public Annotation? Selected => SelectedId is int id ? Find(id) : null;

    /// <summary>The text label being typed (it is in <see cref="Items"/>, and selected), or null.</summary>
    public int? EditingId { get; private set; }

    public Annotation? Editing => EditingId is int id ? Find(id) : null;

    public bool IsEditingText => EditingId is not null;

    /// <summary>The crop kept (image pixels, whole pixels), or null for the whole image. Copy and Save export only this part.</summary>
    public RectD? Crop { get; private set; }

    /// <summary>While in crop mode, the area being chosen; null otherwise.</summary>
    public RectD? CropDraft { get; private set; }

    public bool IsCropping => CropDraft is not null;

    /// <summary>The whole image, in image pixels.</summary>
    public RectD ImageBounds => new(0, 0, ImageSize.Width, ImageSize.Height);

    /// <summary>What the canvas shows: the whole image while cropping (so all of it can be chosen), else the crop or the whole image.</summary>
    public RectD VisibleBounds => IsCropping ? ImageBounds : Crop ?? ImageBounds;

    /// <summary>The current tool. Changing it ends any text typing.</summary>
    public EditorTool Tool
    {
        get => _tool;
        set
        {
            FinishTextEditing();
            _tool = value;
        }
    }

    /// <summary>The style new annotations get. See <see cref="ApplyStyle"/> to also restyle the selection.</summary>
    public AnnotationStyle Style => _style;

    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    /// <summary>Whether anything was changed (the Mac's isEdited: there is something to undo).</summary>
    public bool IsEdited => CanUndo;

    /// <summary>Whether a drag is under way (the window keeps the pointer captured until it ends).</summary>
    public bool IsDragging => _drag != Drag.None;

    private Snapshot Current => new(_items, Crop);

    /// <summary>
    /// A press at <paramref name="p"/> (image pixels). <paramref name="zoom"/> is view points per image pixel, which
    /// turns the on-screen slop and handle radius into image pixels. While typing, a press ends the typing and does
    /// nothing else (a click outside the text box, as on the Mac).
    /// </summary>
    public void PointerDown(PointD p, double zoom)
    {
        if (_drag != Drag.None) return;
        if (FinishTextEditing()) return;
        zoom = zoom > 0 ? zoom : 1;
        _last = p;

        if (CropDraft is RectD crop)
        {
            _cropDrag = CropGeometry.HitTest(crop, p, CropGeometry.HandleRadiusPoints / zoom, CropGeometry.SideSlopPoints / zoom);
            _cropAnchor = p;
            _cropBeforeDrag = crop;
            _drag = Drag.Crop;
            return;
        }

        _beforeDrag = Current;
        if (Selected is { } selected && AnnotationGeometry.HandleAt(selected, p, HandleRadiusPoints / zoom) is int handle)
        {
            _drag = Drag.Resize;
            _handle = handle;
            return;
        }
        if (AnnotationGeometry.TopmostHit(_items, p, SlopPoints / zoom) is { } hit)
        {
            SelectedId = hit.Id;
            _drag = Drag.Move;
            Changed?.Invoke();
            return;
        }

        SelectedId = null;
        switch (Tool.Kind())
        {
            case AnnotationKind.Text:
            {
                // Placed so the click lands on the first line's vertical center; typing starts right away.
                var line = Measure("", _style).Height;
                var start = new PointD(p.X, p.Y - line / 2);
                var text = Measured(new Annotation(_nextId++, AnnotationKind.Text, start, start, Array.Empty<PointD>(), _style));
                _items = _items.Append(text).ToArray();
                SelectedId = EditingId = text.Id;
                _beforeEditing = _beforeDrag;
                _beforeDrag = null;
                break;
            }
            case AnnotationKind.Counter:
            {
                // Placed on press; dragging before the release moves it, and both are one undo step.
                var counter = new Annotation(_nextId++, AnnotationKind.Counter, p, p, Array.Empty<PointD>(), _style);
                _items = _items.Append(counter).ToArray();
                SelectedId = counter.Id;
                _drag = Drag.Move;
                break;
            }
            case AnnotationKind kind:
                Draft = new Annotation(_nextId++, kind, p, p, kind is AnnotationKind.Pen or AnnotationKind.Highlighter ? new[] { p } : Array.Empty<PointD>(), _style);
                _drag = Drag.Draw;
                break;
        }
        Changed?.Invoke();
    }

    /// <summary>
    /// The pointer moved to <paramref name="p"/> during a drag. <paramref name="shift"/> keeps a pen or highlighter
    /// stroke straight (the Mac's Shift for freehand tools).
    /// </summary>
    public void PointerMove(PointD p, bool shift = false)
    {
        switch (_drag)
        {
            case Drag.Draw when Draft is { } d:
                if (d.IsFreehand)
                {
                    var points = shift ? new List<PointD> { d.Points[0] } : new List<PointD>(d.Points);
                    points.Add(p);
                    Draft = d with { End = p, Points = points };
                }
                else
                {
                    Draft = d with { End = p };
                }
                break;
            case Drag.Move when Selected is { } a:
                if (p == _last) return;
                ReplaceLive(a.Translated(p.X - _last.X, p.Y - _last.Y));
                break;
            case Drag.Resize when Selected is { } a:
                if (p == _last) return;
                ReplaceLive(AnnotationGeometry.Resized(a, _handle, p));
                break;
            case Drag.Crop when CropDraft is RectD r:
                if (p == _last) return;
                CropDraft = _cropDrag.Kind switch
                {
                    CropDragKind.Edges => CropGeometry.DragEdges(r, _cropDrag.Edges, p, ImageBounds),
                    CropDragKind.Move => CropGeometry.Moved(r, p.X - _last.X, p.Y - _last.Y, ImageBounds),
                    _ => CropGeometry.NewArea(_cropAnchor, p, ImageBounds),
                };
                break;
            default:
                return;
        }
        _last = p;
        Changed?.Invoke();
    }

    /// <summary>The press ended at <paramref name="p"/>: a drawn annotation is added (if it is more than a click) and selected.</summary>
    public void PointerUp(PointD p, bool shift = false)
    {
        if (_drag == Drag.None) return;
        PointerMove(p, shift);
        if (_drag == Drag.Crop)
        {
            // A click outside the crop (no real area drawn) keeps the crop as it was. The crop itself is recorded
            // for undo when it is applied.
            if (CropDraft is RectD r && (r.Width < CropGeometry.MinSize || r.Height < CropGeometry.MinSize)) CropDraft = _cropBeforeDrag;
            _drag = Drag.None;
            _cropBeforeDrag = null;
            Changed?.Invoke();
            return;
        }
        if (_drag == Drag.Draw && Draft is { } d)
        {
            if (d.IsDrawable)
            {
                _items = _items.Append(d).ToArray();
                SelectedId = d.Id;
            }
            Draft = null;
        }
        _drag = Drag.None;
        Commit(_beforeDrag);
        _beforeDrag = null;
        Changed?.Invoke();
    }

    /// <summary>
    /// Esc: ends text typing; abandons a drag under way (a move or resize goes back to where it started); leaves crop
    /// mode without changing the crop; or else clears the selection. Returns false when there was nothing to cancel,
    /// so the window can treat Esc as "close".
    /// </summary>
    public bool Cancel()
    {
        if (FinishTextEditing()) return true;
        if (_drag == Drag.Crop)
        {
            CropDraft = _cropBeforeDrag;
            _cropBeforeDrag = null;
            _drag = Drag.None;
        }
        else if (_drag != Drag.None)
        {
            if (_beforeDrag is { } before) _items = before.Items;
            Draft = null;
            _drag = Drag.None;
            _beforeDrag = null;
            DropStaleSelection();
        }
        else if (IsCropping)
        {
            CropDraft = null;
        }
        else if (SelectedId is not null)
        {
            SelectedId = null;
        }
        else
        {
            return false;
        }
        Changed?.Invoke();
        return true;
    }

    /// <summary>Removes the selected annotation (Delete / Backspace). False when nothing was selected.</summary>
    public bool DeleteSelected()
    {
        if (_drag != Drag.None || IsEditingText || IsCropping || SelectedId is not int id) return false;
        var before = Current;
        _items = _items.Where(a => a.Id != id).ToArray();
        SelectedId = null;
        Commit(before);
        Changed?.Invoke();
        return true;
    }

    /// <summary>Moves the selection by whole pixels (arrow keys; Shift moves 10). False when nothing was selected.</summary>
    public bool Nudge(double dx, double dy)
    {
        if (_drag != Drag.None || IsEditingText || IsCropping || Selected is not { } a) return false;
        var before = Current;
        ReplaceLive(a.Translated(dx, dy));
        Commit(before);
        Changed?.Invoke();
        return true;
    }

    /// <summary>
    /// Makes <paramref name="style"/> the style for new annotations, and gives it to the selected annotation too (one
    /// undo step), as the Mac's attributes bar does. While typing, the label being typed takes it as part of the
    /// typing's undo step.
    /// </summary>
    public void ApplyStyle(AnnotationStyle style)
    {
        _style = style;
        if (_drag == Drag.None && Selected is { } a && a.Style != style)
        {
            var before = Current;
            ReplaceLive(Measured(a with { Style = style }));
            if (!IsEditingText) Commit(before);
        }
        Changed?.Invoke();
    }

    // MARK: Text

    /// <summary>
    /// A double-click at <paramref name="p"/>: starts typing in the text label there again. False (nothing changes)
    /// when there is no text label under the pointer.
    /// </summary>
    public bool BeginTextEditing(PointD p, double zoom)
    {
        if (_drag != Drag.None || IsCropping) return false;
        zoom = zoom > 0 ? zoom : 1;
        FinishTextEditing();
        if (AnnotationGeometry.TopmostHit(_items, p, SlopPoints / zoom) is not { Kind: AnnotationKind.Text } hit) return false;
        _beforeEditing = Current;
        SelectedId = EditingId = hit.Id;
        Changed?.Invoke();
        return true;
    }

    /// <summary>The text typed so far into the label being edited (no undo step until the typing ends).</summary>
    public void SetEditingText(string text)
    {
        if (Editing is not { } a || a.Text == text) return;
        ReplaceLive(Measured(a with { Text = text }));
        Changed?.Invoke();
    }

    /// <summary>
    /// Ends typing (Esc, Ctrl+Enter, a click outside): keeps the text, or drops a label left empty, and records one
    /// undo step for the whole edit. False when nothing was being typed.
    /// </summary>
    public bool FinishTextEditing()
    {
        if (EditingId is not int id) return false;
        if (Find(id) is { } a && string.IsNullOrWhiteSpace(a.Text))
        {
            _items = _items.Where(i => i.Id != id).ToArray();
            SelectedId = null;
        }
        EditingId = null;
        Commit(_beforeEditing);
        _beforeEditing = null;
        Changed?.Invoke();
        return true;
    }

    // MARK: Crop

    /// <summary>
    /// Enters crop mode with the current crop (or the whole image) chosen, as the Mac's beginCrop. False when already
    /// cropping, during a drag, or without an <see cref="ImageSize"/>.
    /// </summary>
    public bool BeginCrop()
    {
        if (IsCropping || _drag != Drag.None || ImageSize.Width <= 0 || ImageSize.Height <= 0) return false;
        FinishTextEditing();
        SelectedId = null;
        CropDraft = Crop ?? ImageBounds;
        Changed?.Invoke();
        return true;
    }

    /// <summary>
    /// Enter: keeps the chosen area (one undo step). Choosing everything removes the crop; a tiny area is ignored
    /// (see <see cref="CropGeometry.Applied"/>). False when not cropping.
    /// </summary>
    public bool ApplyCrop()
    {
        if (CropDraft is not RectD draft || _drag != Drag.None) return false;
        var before = Current;
        Crop = CropGeometry.Applied(draft, ImageBounds, Crop);
        CropDraft = null;
        Commit(before);
        Changed?.Invoke();
        return true;
    }

    /// <summary>Leaves crop mode without changing the crop. False when not cropping.</summary>
    public bool CancelCrop()
    {
        if (!IsCropping || _drag != Drag.None) return false;
        CropDraft = null;
        Changed?.Invoke();
        return true;
    }

    // MARK: Undo

    public void Undo()
    {
        if (_drag != Drag.None || IsCropping) return;
        FinishTextEditing();
        if (!_undo.TryPop(out var previous)) return;
        _redo.Push(Current);
        Restore(previous);
    }

    public void Redo()
    {
        if (_drag != Drag.None || IsCropping) return;
        FinishTextEditing();
        if (!_redo.TryPop(out var next)) return;
        _undo.Push(Current);
        Restore(next);
    }

    private void Restore(Snapshot s)
    {
        _items = s.Items;
        Crop = s.Crop;
        DropStaleSelection();
        Changed?.Invoke();
    }

    private Annotation? Find(int id) => _items.FirstOrDefault(a => a.Id == id);

    private SizeD Measure(string text, AnnotationStyle style) =>
        (TextMeasurer ?? AnnotationGeometry.EstimateTextSize)(text, style);

    /// <summary>A text label with its <see cref="Annotation.End"/> moved to fit its measured text; anything else unchanged.</summary>
    private Annotation Measured(Annotation a)
    {
        if (a.Kind != AnnotationKind.Text) return a;
        var size = Measure(a.Text, a.Style);
        return a with { End = new PointD(a.Start.X + size.Width, a.Start.Y + size.Height) };
    }

    private void ReplaceLive(Annotation updated) =>
        _items = _items.Select(a => a.Id == updated.Id ? updated : a).ToArray();

    /// <summary>Records <paramref name="before"/> as one undo step, unless nothing changed (a click that selected only).</summary>
    private void Commit(Snapshot? before)
    {
        if (before is not { } b || (b.Crop == Crop && (ReferenceEquals(b.Items, _items) || b.Items.SequenceEqual(_items)))) return;
        _undo.Push(b);
        _redo.Clear();
    }

    private void DropStaleSelection()
    {
        if (SelectedId is int id && _items.All(a => a.Id != id)) SelectedId = null;
    }
}
