using Skreener.Core.Geometry;

namespace Skreener.Core.Editor;

/// <summary>The editor's tools (Tool in AnnotationEditor.swift, the ones the Windows editor has so far).</summary>
public enum EditorTool
{
    Select,
    Arrow,
    Rectangle,
    Ellipse,
    Line,
    Pen,
    Pixelate,
}

public static class EditorTools
{
    /// <summary>The tools in toolbar order.</summary>
    public static IReadOnlyList<EditorTool> All { get; } = Enum.GetValues<EditorTool>();

    /// <summary>The annotation a drawing tool makes; null for Select.</summary>
    public static AnnotationKind? Kind(this EditorTool tool) => tool switch
    {
        EditorTool.Arrow => AnnotationKind.Arrow,
        EditorTool.Rectangle => AnnotationKind.Rectangle,
        EditorTool.Ellipse => AnnotationKind.Ellipse,
        EditorTool.Line => AnnotationKind.Line,
        EditorTool.Pen => AnnotationKind.Pen,
        EditorTool.Pixelate => AnnotationKind.Pixelate,
        _ => null,
    };

    /// <summary>The single-key shortcut, as on the Mac (V A R O L P X).</summary>
    public static char Shortcut(this EditorTool tool) => tool switch
    {
        EditorTool.Select => 'V',
        EditorTool.Arrow => 'A',
        EditorTool.Rectangle => 'R',
        EditorTool.Ellipse => 'O',
        EditorTool.Line => 'L',
        EditorTool.Pen => 'P',
        _ => 'X',
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
/// The editor's state and pointer handling, without any drawing: the annotations, the one being drawn, the selection
/// and the undo history (CanvasView's model half in AnnotationEditor.swift). The window feeds it pointer events in
/// image pixels and redraws on <see cref="Changed"/>.
/// <para>
/// As on the Mac, a press first grabs a handle of the selected annotation, then any annotation under the pointer
/// (with any tool), and only on empty canvas starts drawing with the current tool. A whole drag is one undo step.
/// </para>
/// </summary>
public sealed class EditorSession
{
    /// <summary>On-screen distances the Mac uses, in view points: slop around a line, and a handle's grab radius.</summary>
    public const double SlopPoints = 5, HandleRadiusPoints = 8;

    private readonly Stack<IReadOnlyList<Annotation>> _undo = new();
    private readonly Stack<IReadOnlyList<Annotation>> _redo = new();
    private IReadOnlyList<Annotation> _items = Array.Empty<Annotation>();
    private IReadOnlyList<Annotation>? _beforeDrag;
    private Drag _drag = Drag.None;
    private int _handle;
    private PointD _last;
    private int _nextId = 1;
    private AnnotationStyle _style = AnnotationStyle.Default;

    private enum Drag { None, Draw, Move, Resize }

    /// <summary>Raised after anything that changes what is drawn (items, draft, selection).</summary>
    public event Action? Changed;

    /// <summary>The annotations, bottom to top.</summary>
    public IReadOnlyList<Annotation> Items => _items;

    /// <summary>The annotation being drawn right now, not yet in <see cref="Items"/>.</summary>
    public Annotation? Draft { get; private set; }

    public int? SelectedId { get; private set; }

    public Annotation? Selected => SelectedId is int id ? _items.FirstOrDefault(a => a.Id == id) : null;

    public EditorTool Tool { get; set; } = EditorTool.Arrow;

    /// <summary>The style new annotations get. See <see cref="ApplyStyle"/> to also restyle the selection.</summary>
    public AnnotationStyle Style => _style;

    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    /// <summary>Whether anything was changed (the Mac's isEdited: there is something to undo).</summary>
    public bool IsEdited => CanUndo;

    /// <summary>Whether a drag is under way (the window keeps the pointer captured until it ends).</summary>
    public bool IsDragging => _drag != Drag.None;

    /// <summary>
    /// A press at <paramref name="p"/> (image pixels). <paramref name="zoom"/> is view points per image pixel, which
    /// turns the on-screen slop and handle radius into image pixels.
    /// </summary>
    public void PointerDown(PointD p, double zoom)
    {
        if (_drag != Drag.None) return;
        zoom = zoom > 0 ? zoom : 1;
        _beforeDrag = _items;
        _last = p;

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
        if (Tool.Kind() is AnnotationKind kind)
        {
            Draft = new Annotation(_nextId++, kind, p, p, kind == AnnotationKind.Pen ? new[] { p } : Array.Empty<PointD>(), _style);
            _drag = Drag.Draw;
        }
        Changed?.Invoke();
    }

    /// <summary>
    /// The pointer moved to <paramref name="p"/> during a drag. <paramref name="shift"/> keeps a pen stroke straight
    /// (the Mac's Shift for freehand tools).
    /// </summary>
    public void PointerMove(PointD p, bool shift = false)
    {
        switch (_drag)
        {
            case Drag.Draw when Draft is { } d:
                if (d.Kind == AnnotationKind.Pen)
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
    /// Esc: abandons a drag under way (a move or resize goes back to where it started) or else clears the selection.
    /// Returns false when there was nothing to cancel, so the window can treat Esc as "close".
    /// </summary>
    public bool Cancel()
    {
        if (_drag != Drag.None)
        {
            if (_beforeDrag is not null) _items = _beforeDrag;
            Draft = null;
            _drag = Drag.None;
            _beforeDrag = null;
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
        if (_drag != Drag.None || SelectedId is not int id) return false;
        var before = _items;
        _items = _items.Where(a => a.Id != id).ToArray();
        SelectedId = null;
        Commit(before);
        Changed?.Invoke();
        return true;
    }

    /// <summary>Moves the selection by whole pixels (arrow keys; Shift moves 10). False when nothing was selected.</summary>
    public bool Nudge(double dx, double dy)
    {
        if (_drag != Drag.None || Selected is not { } a) return false;
        var before = _items;
        ReplaceLive(a.Translated(dx, dy));
        Commit(before);
        Changed?.Invoke();
        return true;
    }

    /// <summary>
    /// Makes <paramref name="style"/> the style for new annotations, and gives it to the selected annotation too (one
    /// undo step), as the Mac's attributes bar does.
    /// </summary>
    public void ApplyStyle(AnnotationStyle style)
    {
        _style = style;
        if (_drag == Drag.None && Selected is { } a && a.Style != style)
        {
            var before = _items;
            ReplaceLive(a with { Style = style });
            Commit(before);
        }
        Changed?.Invoke();
    }

    public void Undo()
    {
        if (_drag != Drag.None || !_undo.TryPop(out var previous)) return;
        _redo.Push(_items);
        _items = previous;
        DropStaleSelection();
        Changed?.Invoke();
    }

    public void Redo()
    {
        if (_drag != Drag.None || !_redo.TryPop(out var next)) return;
        _undo.Push(_items);
        _items = next;
        DropStaleSelection();
        Changed?.Invoke();
    }

    private void ReplaceLive(Annotation updated) =>
        _items = _items.Select(a => a.Id == updated.Id ? updated : a).ToArray();

    /// <summary>Records <paramref name="before"/> as one undo step, unless nothing changed (a click that selected only).</summary>
    private void Commit(IReadOnlyList<Annotation>? before)
    {
        if (before is null || ReferenceEquals(before, _items) || before.SequenceEqual(_items)) return;
        _undo.Push(before);
        _redo.Clear();
    }

    private void DropStaleSelection()
    {
        if (SelectedId is int id && _items.All(a => a.Id != id)) SelectedId = null;
    }
}
