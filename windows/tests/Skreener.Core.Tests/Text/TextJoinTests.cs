using Skreener.Core.Text;
using Xunit;

namespace Skreener.Core.Tests.Text;

/// <summary>Join Lines in Capture Text's scratch pad (ported from ScratchPadJoinTests) and OCR line building.</summary>
public class TextJoinTests
{
    [Fact]
    public void JoinsLinesWithSingleSpaces() => Assert.Equal("one two three", TextJoin.Joined("one  \n  two\n\nthree"));

    [Fact]
    public void MendsWordsHyphenatedAcrossLines()
    {
        Assert.Equal("screenshot tool", TextJoin.Joined("screen-\nshot tool"));
        // Not a broken word: a capital after the hyphen, or a dash on its own.
        Assert.Equal("Jean- Paul", TextJoin.Joined("Jean-\nPaul"));
        Assert.Equal("wait - then", TextJoin.Joined("wait -\nthen"));
    }

    [Fact]
    public void HandlesWindowsAndOldMacLineEndings() => Assert.Equal("a b c", TextJoin.Joined("a\r\nb\rc"));

    [Fact]
    public void EmptyAndBlankInputGiveEmpty()
    {
        Assert.Equal("", TextJoin.Joined(""));
        Assert.Equal("", TextJoin.Joined(" \n\t\n  "));
    }

    [Fact]
    public void SingleLineIsTrimmedOnly() => Assert.Equal("hello world", TextJoin.Joined("  hello world\t"));

    [Fact]
    public void MendsAcrossSeveralLines() => Assert.Equal("international standards", TextJoin.Joined("inter-\nnational stan-\ndards"));

    [Fact]
    public void BlankLineBetweenHyphenAndWordStillMends() => Assert.Equal("screenshot", TextJoin.Joined("screen-\n\nshot"));

    [Fact]
    public void HyphenAfterDigitOrAtStartIsKept()
    {
        Assert.Equal("2024- abc", TextJoin.Joined("2024-\nabc"));
        Assert.Equal("- item", TextJoin.Joined("-\nitem"));
    }

    [Fact]
    public void AccentedLettersCountAsLetters() => Assert.Equal("café", TextJoin.Joined("ca-\nfé"));

    [Fact]
    public void LineFromWordsJoinsWithSpacesForEnglish() =>
        Assert.Equal("Skreener reads text", TextJoin.LineFromWords(new[] { "Skreener", "reads", "text" }, "en-US"));

    [Fact]
    public void LineFromWordsDropsSpacesBetweenCjkWords()
    {
        Assert.Equal("你好世界", TextJoin.LineFromWords(new[] { "你好", "世界" }, "zh-Hans-CN"));
        Assert.Equal("日本語", TextJoin.LineFromWords(new[] { "日本", "語" }, "ja"));
    }

    [Fact]
    public void LineFromWordsKeepsSpaceBetweenTwoLatinWordsInCjkLine() =>
        Assert.Equal("你好hello world截图", TextJoin.LineFromWords(new[] { "你好", "hello", "world", "截图" }, "zh-Hans"));

    [Fact]
    public void LineFromWordsOfNothingIsEmpty() => Assert.Equal("", TextJoin.LineFromWords(Array.Empty<string>(), "en"));
}

public class OcrImageSizeTests
{
    [Fact]
    public void ImageThatFitsIsUnchanged() => Assert.Equal((800, 600), OcrImageSize.Fit(800, 600, 10000));

    [Fact]
    public void ExactlyMaxIsUnchanged() => Assert.Equal((10000, 50), OcrImageSize.Fit(10000, 50, 10000));

    [Fact]
    public void TallImageIsScaledToTheMax() => Assert.Equal((500, 10000), OcrImageSize.Fit(1000, 20000, 10000));

    [Fact]
    public void WideImageIsScaledToTheMax() => Assert.Equal((10000, 250), OcrImageSize.Fit(40000, 1000, 10000));

    [Fact]
    public void ThinImageNeverShrinksBelowOnePixel() => Assert.Equal((10000, 1), OcrImageSize.Fit(1_000_000, 10, 10000));

    [Fact]
    public void DegenerateInputsDoNotThrow() => Assert.Equal((1, 1), OcrImageSize.Fit(0, 0, 10000));
}
