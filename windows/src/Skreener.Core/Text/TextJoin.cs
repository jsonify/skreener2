using System.Text;

namespace Skreener.Core.Text;

/// <summary>Join Lines in the Capture Text scratch pad (port of <c>TextScratchPad.joined</c>), plus how OCR words become lines.</summary>
public static class TextJoin
{
    /// <summary>
    /// <paramref name="text"/> on one line: line breaks become single spaces, blank lines vanish, and a word hyphenated
    /// across a line break is mended ("screen-" + "shot" gives "screenshot"). Only a letter before the hyphen and a
    /// lowercase letter after it count as a broken word, so "Jean-" + "Paul" and "wait -" + "then" keep their hyphen.
    /// </summary>
    public static string Joined(string text)
    {
        var sb = new StringBuilder();
        foreach (var line in SplitLines(text))
        {
            var piece = line.Trim(' ', '\t');
            if (piece.Length == 0) continue;
            if (EndsWithBrokenWord(sb) && char.IsLower(piece[0]))
                sb.Length--;
            else if (sb.Length > 0)
                sb.Append(' ');
            sb.Append(piece);
        }
        return sb.ToString();
    }

    private static bool EndsWithBrokenWord(StringBuilder sb) =>
        sb.Length >= 2 && sb[^1] == '-' && char.IsLetter(sb[^2]);

    /// <summary>Lines split at \n, \r\n, \r, NEL, LS and PS, like Swift's <c>isNewline</c>; empty ones are kept.</summary>
    private static IEnumerable<string> SplitLines(string text)
    {
        var start = 0;
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (c is not ('\n' or '\r' or '\u0085' or '\u2028' or '\u2029')) continue;
            yield return text[start..i];
            if (c == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
            start = i + 1;
        }
        yield return text[start..];
    }

    /// <summary>
    /// One recognized line from its words. Chinese and Japanese are written without spaces, but Windows OCR separates
    /// their words with one; for those languages a space is kept only between two Latin letters or digits.
    /// </summary>
    public static string LineFromWords(IReadOnlyList<string> words, string languageTag)
    {
        if (!WritesWithoutSpaces(languageTag)) return string.Join(' ', words);
        var sb = new StringBuilder();
        foreach (var word in words)
        {
            if (word.Length == 0) continue;
            if (sb.Length > 0 && IsLatinWordChar(sb[^1]) && IsLatinWordChar(word[0])) sb.Append(' ');
            sb.Append(word);
        }
        return sb.ToString();
    }

    private static bool WritesWithoutSpaces(string languageTag)
    {
        var primary = languageTag.Split('-', 2)[0];
        return primary.Equals("zh", StringComparison.OrdinalIgnoreCase) || primary.Equals("ja", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsLatinWordChar(char c) => c < 128 && char.IsLetterOrDigit(c);
}
