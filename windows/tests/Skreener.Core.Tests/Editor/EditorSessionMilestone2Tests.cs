using Skreener.Core.Editor;
using Skreener.Core.Geometry;
using Xunit;

namespace Skreener.Core.Tests.Editor;

/// <summary>Text, counters, highlighter, filled rectangle, blur and crop in the editor model (the second editor milestone).</summary>
public class EditorSessionMilestone2Tests
{
    private static PointD P(double x, double y) => new(x, y);

    /// <summary>Ten pixels per character, twenty per line: easy numbers to check text boxes against.</summary>
    private static SizeD FakeMeasure(string text, AnnotationStyle style)
    {
        var lines = text.Split('\n');
        return new SizeD(Math.Max(lines.Max(l => l.Length) * 10, 5), lines.Length * 20);
    }

    private static EditorSession NewSession(EditorTool tool) =>
        new() { Tool = tool, ImageSize = new SizeD(200, 100), TextMeasurer = FakeMeasure };

    private static void Drag(EditorSession s, PointD from, PointD to)
    {
        s.PointerDown(from, 1);
        s.PointerMove(new PointD((from.X + to.X) / 2, (from.Y + to.Y) / 2));
        s.PointerUp(to);
    }

    private static void Click(EditorSession s, PointD p)
    {
        s.PointerDown(p, 1);
        s.PointerUp(p);
    }

    // MARK: Text

    [Fact]
    public void AClickWithTheTextToolPlacesALabelAndStartsTyping()
    {
        var s = NewSession(EditorTool.Text);
        s.PointerDown(P(50, 40), 1);
        s.PointerUp(P(50, 40));
        var a = Assert.Single(s.Items);
        Assert.Equal(AnnotationKind.Text, a.Kind);
        Assert.Equal(a.Id, s.EditingId);
        Assert.Equal(a.Id, s.SelectedId);
        // The click is on the middle of the first line: one 20 px line, so the top is 10 px above it.
        Assert.Equal(P(50, 30), a.Start);
        Assert.False(s.CanUndo); // nothing recorded until the typing ends
    }

    [Fact]
    public void TypingResizesTheBoxAndFinishingIsOneUndoStep()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("Hi");
        s.SetEditingText("Hello\nyou");
        Assert.Equal(new RectD(50, 30, 50, 40), s.Items[0].Rect);
        Assert.True(s.FinishTextEditing());
        Assert.Null(s.EditingId);
        Assert.Equal("Hello\nyou", s.Items[0].Text);
        s.Undo();
        Assert.Empty(s.Items);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void ALabelLeftEmptyIsDropped()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("  \n ");
        s.FinishTextEditing();
        Assert.Empty(s.Items);
        Assert.Null(s.SelectedId);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void APressWhileTypingOnlyEndsTheTyping()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("A");
        s.PointerDown(P(150, 80), 1); // outside the box: finishes, does not place a second label
        s.PointerUp(P(150, 80));
        Assert.Single(s.Items);
        Assert.Null(s.EditingId);
    }

    [Fact]
    public void EscAndChangingToolEndTheTyping()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("A");
        Assert.True(s.Cancel());
        Assert.Null(s.EditingId);
        Assert.Single(s.Items);

        Click(s, P(120, 80));
        s.SetEditingText("B");
        s.Tool = EditorTool.Arrow;
        Assert.Null(s.EditingId);
        Assert.Equal(2, s.Items.Count);
    }

    [Fact]
    public void TextIsHitAnywhereInItsBoxAndMovesWithoutHandles()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("Hello");
        s.FinishTextEditing();
        s.Cancel(); // deselect
        Assert.Empty(AnnotationGeometry.Handles(s.Items[0]));
        // Inside the box, away from any edge, with the text tool still on: grabs the label.
        Drag(s, P(75, 40), P(85, 50));
        var a = Assert.Single(s.Items);
        Assert.Equal(P(60, 40), a.Start);
        Assert.Null(s.EditingId);
    }

    [Fact]
    public void DoubleClickingALabelEditsItAgainAsOneStep()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("One");
        s.FinishTextEditing();
        s.Tool = EditorTool.Arrow;

        Assert.False(s.BeginTextEditing(P(180, 90), 1)); // nothing there
        Assert.True(s.BeginTextEditing(P(60, 40), 1));
        Assert.Equal(s.Items[0].Id, s.EditingId);
        s.SetEditingText("Two");
        s.FinishTextEditing();
        Assert.Equal("Two", s.Items[0].Text);
        s.Undo();
        Assert.Equal("One", s.Items[0].Text);
    }

    [Fact]
    public void AStyleChangeWhileTypingRestylesTheLabelWithoutAStepOfItsOwn()
    {
        var s = NewSession(EditorTool.Text);
        s.TextMeasurer = (text, style) => new SizeD(text.Length * style.FontSize / 2, style.FontSize);
        Click(s, P(50, 40));
        s.SetEditingText("Hi");
        s.ApplyStyle(s.Style with { FontSize = 40, Bold = false });
        Assert.Equal(40, s.Items[0].Style.FontSize);
        Assert.Equal(new RectD(s.Items[0].Start.X, s.Items[0].Start.Y, 40, 40), s.Items[0].Rect); // re-measured
        s.FinishTextEditing();
        s.Undo();
        Assert.Empty(s.Items); // one step: placing, typing and restyling together
    }

    [Fact]
    public void UndoWhileTypingFinishesTheTypingFirst()
    {
        var s = NewSession(EditorTool.Text);
        Click(s, P(50, 40));
        s.SetEditingText("A");
        s.Undo();
        Assert.Null(s.EditingId);
        Assert.Empty(s.Items);
        s.Redo();
        Assert.Equal("A", Assert.Single(s.Items).Text);
    }

    [Fact]
    public void WithoutAMeasurerTheTextIsEstimated()
    {
        var s = new EditorSession { Tool = EditorTool.Text };
        Click(s, P(0, 50));
        s.SetEditingText("abcd");
        var expected = AnnotationGeometry.EstimateTextSize("abcd", s.Style);
        Assert.Equal(expected.Width, s.Items[0].Rect.Width, 6);
        Assert.Equal(expected.Height, s.Items[0].Rect.Height, 6);
    }

    // MARK: Counter

    [Fact]
    public void ACounterIsPlacedOnPressAndADragMovesItInOneStep()
    {
        var s = NewSession(EditorTool.Counter);
        s.PointerDown(P(30, 30), 1);
        Assert.Equal(P(30, 30), Assert.Single(s.Items).Start); // already there before the release
        s.PointerMove(P(40, 35));
        s.PointerUp(P(50, 40));
        Assert.Equal(P(50, 40), s.Items[0].Start);
        Assert.Equal(s.Items[0].Id, s.SelectedId);
        s.Undo();
        Assert.Empty(s.Items);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void CountersNumberInCreationOrderAndRenumberAfterADelete()
    {
        var s = NewSession(EditorTool.Counter);
        Click(s, P(20, 20));
        Click(s, P(80, 20));
        Click(s, P(140, 20));
        int Number(int i) => AnnotationGeometry.CounterNumber(s.Items, s.Items[i]);
        Assert.Equal(new[] { 1, 2, 3 }, new[] { Number(0), Number(1), Number(2) });

        Click(s, P(80, 20)); // selects the second
        Assert.True(s.DeleteSelected());
        Assert.Equal(new[] { 1, 2 }, new[] { Number(0), Number(1) });
        Assert.Equal(P(140, 20), s.Items[1].Start);
    }

    [Fact]
    public void AClickOnACounterSelectsItInsteadOfPlacingAnother()
    {
        var s = NewSession(EditorTool.Counter);
        Click(s, P(50, 50));
        Click(s, P(55, 52)); // within the radius
        Assert.Single(s.Items);
    }

    // MARK: Highlighter, filled rectangle, blur

    [Fact]
    public void TheHighlighterIsFreehandLikeThePen()
    {
        var s = NewSession(EditorTool.Highlighter);
        s.PointerDown(P(0, 0), 1);
        s.PointerMove(P(10, 5));
        s.PointerUp(P(20, 0));
        var a = Assert.Single(s.Items);
        Assert.Equal(AnnotationKind.Highlighter, a.Kind);
        Assert.Equal(new[] { P(0, 0), P(10, 5), P(20, 0) }, a.Points);

        s.PointerDown(P(0, 50), 1);
        s.PointerMove(P(10, 60), shift: true);
        s.PointerUp(P(40, 50), shift: true);
        Assert.Equal(new[] { P(0, 50), P(40, 50) }, s.Items[1].Points);
    }

    [Theory]
    [InlineData(EditorTool.FilledRectangle, AnnotationKind.FilledRectangle)]
    [InlineData(EditorTool.Blur, AnnotationKind.Blur)]
    public void FilledBoxesAreHitInsideAndResizeByTheirCorners(EditorTool tool, AnnotationKind kind)
    {
        var s = NewSession(tool);
        Drag(s, P(10, 10), P(90, 60));
        Assert.Equal(kind, s.Items[0].Kind);
        Assert.Equal(4, AnnotationGeometry.Handles(s.Items[0]).Count);
        s.Cancel();
        Drag(s, P(50, 35), P(60, 45)); // inside: moves it rather than drawing a new box
        Assert.Equal(new RectD(20, 20, 80, 50), Assert.Single(s.Items).Rect);
        Drag(s, P(100, 70), P(120, 90)); // the bottom-right handle
        Assert.Equal(new RectD(20, 20, 100, 70), s.Items[0].Rect);
    }

    // MARK: Crop

    [Fact]
    public void CropModeStartsWithEverythingAndEnterKeepsTheChosenArea()
    {
        var s = NewSession(EditorTool.Arrow);
        Drag(s, P(10, 10), P(50, 50)); // an arrow, selected
        Assert.True(s.BeginCrop());
        Assert.Null(s.SelectedId);
        Assert.Equal(new RectD(0, 0, 200, 100), s.CropDraft);
        Assert.Equal(s.ImageBounds, s.VisibleBounds);

        Drag(s, P(0, 0), P(20.4, 10.6)); // the top-left corner handle
        Drag(s, P(200, 50), P(150.5, 50)); // the right side
        Assert.True(s.ApplyCrop());
        Assert.False(s.IsCropping);
        Assert.Equal(new RectD(20, 10, 131, 90), s.Crop); // rounded outwards to whole pixels
        Assert.Equal(s.Crop, s.VisibleBounds);
        Assert.Single(s.Items); // annotations are untouched

        s.Undo();
        Assert.Null(s.Crop);
        s.Redo();
        Assert.Equal(new RectD(20, 10, 131, 90), s.Crop);
    }

    [Fact]
    public void EscLeavesCropModeWithoutChangingTheCrop()
    {
        var s = NewSession(EditorTool.Arrow);
        s.BeginCrop();
        Drag(s, P(200, 50), P(100, 50));
        Assert.True(s.Cancel());
        Assert.False(s.IsCropping);
        Assert.Null(s.Crop);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void CroppingNothingAwayOrAlmostNothingKeepsNoCrop()
    {
        var s = NewSession(EditorTool.Arrow);
        s.BeginCrop();
        s.ApplyCrop();
        Assert.Null(s.Crop);
        Assert.False(s.CanUndo);
    }

    [Fact]
    public void AClickOutsideTheCropKeepsItAndADragThereDrawsANewOne()
    {
        var s = NewSession(EditorTool.Arrow);
        s.BeginCrop();
        Drag(s, P(200, 100), P(100, 60)); // bottom-right corner in
        Click(s, P(150, 80)); // outside: no area drawn
        Assert.Equal(new RectD(0, 0, 100, 60), s.CropDraft);
        Drag(s, P(150, 80), P(250, 40)); // a new area, clamped to the image
        Assert.Equal(new RectD(150, 40, 50, 40), s.CropDraft);
    }

    [Fact]
    public void DraggingInsideTheCropMovesItWithinTheImage()
    {
        var s = NewSession(EditorTool.Arrow);
        s.BeginCrop();
        Drag(s, P(200, 100), P(100, 50)); // now 0,0 100x50
        Drag(s, P(50, 25), P(500, 25));
        Assert.Equal(new RectD(100, 0, 100, 50), s.CropDraft);
    }

    [Fact]
    public void ReenteringCropModeStartsFromTheCrop()
    {
        var s = NewSession(EditorTool.Arrow);
        s.BeginCrop();
        Drag(s, P(200, 100), P(100, 50));
        s.ApplyCrop();
        Assert.True(s.BeginCrop());
        Assert.Equal(new RectD(0, 0, 100, 50), s.CropDraft);
        Assert.Equal(s.ImageBounds, s.VisibleBounds); // the whole image shows while choosing
    }

    [Fact]
    public void EditsAreBlockedWhileCropping()
    {
        var s = NewSession(EditorTool.Rectangle);
        Drag(s, P(10, 10), P(50, 50));
        s.BeginCrop();
        Drag(s, P(30, 30), P(40, 40)); // moves the crop (inside it), draws nothing
        Assert.Single(s.Items);
        Assert.False(s.Nudge(1, 0));
        s.Undo(); // ignored while cropping
        Assert.Single(s.Items);
    }

    [Fact]
    public void CropModeNeedsAnImageSize() => Assert.False(new EditorSession().BeginCrop());

    // MARK: Shortcuts

    [Theory]
    [InlineData('f', EditorTool.FilledRectangle)]
    [InlineData('H', EditorTool.Highlighter)]
    [InlineData('t', EditorTool.Text)]
    [InlineData('n', EditorTool.Counter)]
    [InlineData('b', EditorTool.Blur)]
    public void NewShortcutsMatchTheMac(char key, EditorTool tool) => Assert.Equal(tool, EditorTools.ForShortcut(key));

    [Fact]
    public void CIsCropNotATool()
    {
        Assert.Equal('C', EditorTools.CropShortcut);
        Assert.Null(EditorTools.ForShortcut('c'));
    }

    [Fact]
    public void EveryToolHasItsOwnShortcut() =>
        Assert.Equal(EditorTools.All.Count, EditorTools.All.Select(t => t.Shortcut()).Distinct().Count());

    [Fact]
    public void EveryDrawingToolMakesItsKind()
    {
        foreach (var tool in EditorTools.All.Where(t => t != EditorTool.Select))
            Assert.Equal(tool.ToString(), tool.Kind().ToString());
    }
}
