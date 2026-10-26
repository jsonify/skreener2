using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests.Editor;

/// <summary>Drawing, picking, moving, resizing and undo in the editor model (CanvasView's mouse handling on the Mac).</summary>
public class EditorSessionTests
{
    private static PointD P(double x, double y) => new(x, y);

    private static void Drag(EditorSession s, PointD from, PointD to, bool shift = false)
    {
        s.PointerDown(from, 1);
        s.PointerMove(new PointD((from.X + to.X) / 2, (from.Y + to.Y) / 2), shift);
        s.PointerUp(to, shift);
    }

    [Fact]
    public void DraggingWithADrawingToolAddsAndSelectsTheShape()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        Drag(s, P(10, 10), P(60, 40));
        var a = Assert.Single(s.Items);
        Assert.Equal(AnnotationKind.Rectangle, a.Kind);
        Assert.Equal(new RectD(10, 10, 50, 30), a.Rect);
        Assert.Equal(a.Id, s.SelectedId);
        Assert.Null(s.Draft);
        Assert.True(s.CanUndo);
    }

    [Fact]
    public void TheDraftIsShownWhileDraggingButNotYetAnItem()
    {
        var s = new EditorSession { Tool = EditorTool.Arrow };
        s.PointerDown(P(0, 0), 1);
        s.PointerMove(P(30, 0));
        Assert.Empty(s.Items);
        Assert.Equal(P(30, 0), s.Draft!.End);
        Assert.True(s.IsDragging);
    }

    [Fact]
    public void AClickWithADrawingToolAddsNothing()
    {
        var s = new EditorSession { Tool = EditorTool.Ellipse };
        s.PointerDown(P(10, 10), 1);
        s.PointerUp(P(11, 10));
        Assert.Empty(s.Items);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void ThePenKeepsEveryPointAndShiftMakesItStraight()
    {
        var s = new EditorSession { Tool = EditorTool.Pen };
        s.PointerDown(P(0, 0), 1);
        s.PointerMove(P(5, 5));
        s.PointerMove(P(10, 0));
        s.PointerUp(P(15, 5));
        Assert.Equal(new[] { P(0, 0), P(5, 5), P(10, 0), P(15, 5) }, s.Items[0].Points);

        s.Tool = EditorTool.Pen;
        s.PointerDown(P(0, 50), 1);
        s.PointerMove(P(5, 55), shift: true);
        s.PointerUp(P(20, 50), shift: true);
        Assert.Equal(new[] { P(0, 50), P(20, 50) }, s.Items[1].Points);
    }

    [Fact]
    public void PressingOnAShapeWithAnyToolMovesItAsOneUndoStep()
    {
        var s = new EditorSession { Tool = EditorTool.Line };
        Drag(s, P(0, 0), P(100, 0));
        var id = s.Items[0].Id;

        // Still the Line tool: a press on the line grabs it instead of drawing a new one.
        s.PointerDown(P(50, 1), 1);
        s.PointerMove(P(60, 11));
        s.PointerUp(P(70, 21));
        var moved = Assert.Single(s.Items);
        Assert.Equal(id, moved.Id);
        Assert.Equal(P(20, 20), moved.Start);
        Assert.Equal(P(120, 20), moved.End);

        s.Undo();
        Assert.Equal(P(0, 0), s.Items[0].Start);
        s.Undo();
        Assert.Empty(s.Items);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void AClickThatOnlySelectsIsNoUndoStep()
    {
        var s = new EditorSession { Tool = EditorTool.Pen };
        Drag(s, P(0, 0), P(40, 0));
        s.Cancel(); // deselect
        s.PointerDown(P(20, 0), 1);
        s.PointerUp(P(20, 0));
        Assert.Equal(s.Items[0].Id, s.SelectedId);
        s.Undo();
        Assert.Empty(s.Items); // the one step left was drawing it
    }

    [Fact]
    public void OutlinesAreHitOnTheirLineSoTheInsideStaysFree()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        Drag(s, P(0, 0), P(100, 100));
        // Inside the rectangle, far from its edges: draws a new rectangle rather than grabbing the first.
        Drag(s, P(30, 30), P(60, 60));
        Assert.Equal(2, s.Items.Count);
    }

    [Fact]
    public void PixelateIsHitAnywhereInside()
    {
        var s = new EditorSession { Tool = EditorTool.Pixelate };
        Drag(s, P(0, 0), P(100, 100));
        s.Tool = EditorTool.Rectangle;
        Drag(s, P(30, 30), P(60, 60));
        var a = Assert.Single(s.Items);
        Assert.Equal(new RectD(30, 30, 100, 100), a.Rect);
    }

    [Fact]
    public void TheTopmostShapeIsPicked()
    {
        var s = new EditorSession { Tool = EditorTool.Pixelate };
        Drag(s, P(0, 0), P(50, 50));
        Drag(s, P(60, 60), P(100, 100)); // starts outside the first one
        s.Cancel();
        s.PointerDown(P(70, 70), 1);
        s.PointerUp(P(70, 70));
        Assert.Equal(s.Items[1].Id, s.SelectedId);
    }

    [Fact]
    public void DraggingACornerResizesAgainstTheOppositeOne()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        Drag(s, P(10, 10), P(50, 50));
        // The bottom-right handle, within the handle radius.
        Drag(s, P(52, 49), P(90, 70));
        Assert.Equal(new RectD(10, 10, 80, 60), s.Items[0].Rect);
        // Past the anchor flips it; the rect stays standardized.
        Drag(s, P(90, 70), P(0, 0));
        Assert.Equal(new RectD(0, 0, 10, 10), s.Items[0].Rect);
    }

    [Fact]
    public void DraggingAnArrowEndMovesOnlyThatEnd()
    {
        var s = new EditorSession { Tool = EditorTool.Arrow };
        Drag(s, P(0, 0), P(100, 0));
        Drag(s, P(100, 3), P(100, 80));
        Assert.Equal(P(0, 0), s.Items[0].Start);
        Assert.Equal(P(100, 80), s.Items[0].End);
    }

    [Fact]
    public void HandlesAreOnlyGrabbedOnTheSelection()
    {
        var s = new EditorSession { Tool = EditorTool.Arrow };
        Drag(s, P(0, 0), P(100, 0));
        s.Cancel();
        // Pressing the end of the unselected arrow moves it instead.
        Drag(s, P(100, 0), P(100, 10));
        Assert.Equal(P(0, 10), s.Items[0].Start);
    }

    [Fact]
    public void SlopAndHandlesScaleWithTheZoom()
    {
        var s = new EditorSession { Tool = EditorTool.Line };
        Drag(s, P(0, 0), P(100, 0));
        s.Cancel();
        // 8 px off the line: missed at 100 %, hit at 50 % (where the 5 pt slop is 10 image pixels).
        s.PointerDown(P(50, 8), 1);
        s.Cancel();
        Assert.Null(s.SelectedId);
        s.PointerDown(P(50, 8), 0.5);
        s.PointerUp(P(50, 8));
        Assert.Equal(s.Items[0].Id, s.SelectedId);
    }

    [Fact]
    public void EscAbandonsAMoveThenClearsTheSelectionThenReportsNothingToDo()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        Drag(s, P(0, 0), P(40, 40));
        s.PointerDown(P(0, 20), 1);
        s.PointerMove(P(30, 50));
        Assert.True(s.Cancel());
        Assert.Equal(new RectD(0, 0, 40, 40), s.Items[0].Rect);
        Assert.False(s.IsDragging);
        Assert.NotNull(s.SelectedId);
        Assert.True(s.Cancel());
        Assert.Null(s.SelectedId);
        Assert.False(s.Cancel());
    }

    [Fact]
    public void EscWhileDrawingDropsTheDraft()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        s.PointerDown(P(0, 0), 1);
        s.PointerMove(P(40, 40));
        s.Cancel();
        s.PointerUp(P(50, 50)); // the release after Esc does nothing
        Assert.Empty(s.Items);
        Assert.Null(s.Draft);
    }

    [Fact]
    public void DeleteRemovesTheSelectionAndUndoBringsItBack()
    {
        var s = new EditorSession { Tool = EditorTool.Ellipse };
        Drag(s, P(0, 0), P(40, 40));
        Assert.True(s.DeleteSelected());
        Assert.Empty(s.Items);
        Assert.False(s.DeleteSelected());
        s.Undo();
        Assert.Single(s.Items);
        Assert.Null(s.SelectedId);
        s.Redo();
        Assert.Empty(s.Items);
    }

    [Fact]
    public void NudgeMovesTheSelection()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        Drag(s, P(0, 0), P(40, 40));
        Assert.True(s.Nudge(10, -1));
        Assert.Equal(new RectD(10, -1, 40, 40), s.Items[0].Rect);
        s.Undo();
        Assert.Equal(new RectD(0, 0, 40, 40), s.Items[0].Rect);
    }

    [Fact]
    public void ApplyStyleRestylesTheSelectionAndSetsTheStyleForNewShapes()
    {
        var s = new EditorSession { Tool = EditorTool.Rectangle };
        Drag(s, P(0, 0), P(40, 40));
        var thick = AnnotationStyle.Default with { LineWidth = 12 };
        s.ApplyStyle(thick);
        Assert.Equal(12, s.Items[0].Style.LineWidth);
        s.Undo();
        Assert.Equal(AnnotationStyle.Default.LineWidth, s.Items[0].Style.LineWidth);
        Assert.Equal(thick, s.Style); // undo restores shapes, not the current style

        s.Cancel();
        s.ApplyStyle(thick with { LineWidth = 2 });
        Drag(s, P(100, 100), P(140, 140));
        Assert.Equal(2, s.Items[1].Style.LineWidth);
        Assert.Equal(AnnotationStyle.Default.LineWidth, s.Items[0].Style.LineWidth);
    }

    [Fact]
    public void ANewEditClearsRedo()
    {
        var s = new EditorSession { Tool = EditorTool.Line };
        Drag(s, P(0, 0), P(40, 0));
        s.Undo();
        Assert.True(s.CanRedo);
        Drag(s, P(0, 50), P(40, 50));
        Assert.False(s.CanRedo);
    }

    [Fact]
    public void ChangedFiresForEveryVisibleChange()
    {
        var s = new EditorSession { Tool = EditorTool.Line };
        int count = 0;
        s.Changed += () => count++;
        s.PointerDown(P(0, 0), 1);
        s.PointerMove(P(20, 0));
        s.PointerUp(P(40, 0));
        Assert.True(count >= 3);
    }

    [Theory]
    [InlineData('v', EditorTool.Select)]
    [InlineData('A', EditorTool.Arrow)]
    [InlineData('r', EditorTool.Rectangle)]
    [InlineData('o', EditorTool.Ellipse)]
    [InlineData('l', EditorTool.Line)]
    [InlineData('p', EditorTool.Pen)]
    [InlineData('x', EditorTool.Pixelate)]
    public void ShortcutsMatchTheMac(char key, EditorTool tool) => Assert.Equal(tool, EditorTools.ForShortcut(key));

    [Fact]
    public void UnknownShortcutIsNull() => Assert.Null(EditorTools.ForShortcut('q'));
}
