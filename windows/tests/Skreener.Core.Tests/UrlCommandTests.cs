using Skreener.Core.Shortcuts;
using Skreener.Core.Url;
using Xunit;

namespace Skreener.Core.Tests;

/// <summary>skreener:// links (launchers, automation, scripts).</summary>
public class UrlCommandTests
{
    private static UrlParseResult Parse(string s) => UrlCommand.Parse(s);

    private static UrlParseResult Success(UrlCommand c) => UrlParseResult.Success(c);

    private static UrlParseResult Failure(UrlCommandError e) => UrlParseResult.Failure(e);

    private static UrlCommand Run(HotKeyAction a, CaptureActions? then = null, int? delay = null) =>
        new(CommandTarget.Run(a), then, delay);

    [Fact]
    public void AreaWithThen()
    {
        Assert.Equal(Success(Run(HotKeyAction.CaptureArea, CaptureActions.Copy | CaptureActions.Save)),
                     Parse("skreener://grab/area?then=copy,save"));
    }

    [Fact]
    public void CaptureIsAnAliasForGrab()
    {
        Assert.Equal(Success(Run(HotKeyAction.CaptureFullscreen)), Parse("skreener://capture/fullscreen"));
    }

    [Fact]
    public void WithoutSlashesCaseAndTrailingSlash()
    {
        Assert.Equal(Success(Run(HotKeyAction.CaptureWindow)), Parse("skreener:grab/window"));
        Assert.Equal(Success(Run(HotKeyAction.CaptureWindow)), Parse("SKREENER://Grab/Window/"));
    }

    [Fact]
    public void ActiveWindow()
    {
        Assert.Equal(Success(Run(HotKeyAction.CaptureActiveWindow, CaptureActions.Copy)),
                     Parse("skreener://grab/window/active?then=copy"));
        Assert.Equal(Success(Run(HotKeyAction.CaptureActiveWindow)), Parse("skreener://capture/window/active"));
    }

    [Fact]
    public void EveryCommandParses()
    {
        foreach (var (path, command) in UrlCommand.Commands)
            Assert.Equal(Success(new UrlCommand(command)), Parse("skreener://" + path));
    }

    [Fact]
    public void SettingsAndOtherCommands()
    {
        Assert.Equal(Success(new UrlCommand(CommandTarget.Settings)), Parse("skreener://settings"));
        Assert.Equal(Success(Run(HotKeyAction.CaptureText)), Parse("skreener://ocr"));
        Assert.Equal(Success(Run(HotKeyAction.OpenClipboard)), Parse("skreener://load/clipboard"));
    }

    [Fact]
    public void EveryThenOption()
    {
        Assert.Equal(Success(Run(HotKeyAction.CapturePreviousArea,
                                 CaptureActions.Copy | CaptureActions.Save | CaptureActions.Edit | CaptureActions.Pin | CaptureActions.QuickAccess)),
                     Parse("skreener://grab/previous?then=copy,save,edit,pin,quickaccess"));
        Assert.Equal(Success(Run(HotKeyAction.CaptureArea, CaptureActions.Pin)), Parse("skreener://grab/area?then=PIN"));
    }

    [Fact]
    public void Delay()
    {
        Assert.Equal(Success(Run(HotKeyAction.TimedWindow, CaptureActions.Edit, 10)),
                     Parse("skreener://grab/delayed/window?delay=10&then=edit"));
        Assert.Equal(Success(Run(HotKeyAction.TimedArea, delay: 3)), Parse("skreener://grab/delayed?delay=3"));
    }

    [Fact]
    public void Errors()
    {
        Assert.Equal(Failure(UrlCommandError.WrongScheme), Parse("https://grab/area"));
        Assert.Equal(Failure(UrlCommandError.UnknownCommand("grab/everything")), Parse("skreener://grab/everything"));
        Assert.Equal(Failure(UrlCommandError.UnknownCommand("")), Parse("skreener://"));
        Assert.Equal(Failure(UrlCommandError.BadThen("print")), Parse("skreener://grab/area?then=copy,print"));
        Assert.Equal(Failure(UrlCommandError.BadThen("")), Parse("skreener://grab/area?then="));
        Assert.Equal(Failure(UrlCommandError.BadThen("")), Parse("skreener://grab/area?then=copy,"));
        Assert.Equal(Failure(UrlCommandError.ThenNotAllowed("ocr")), Parse("skreener://ocr?then=copy"));
        Assert.Equal(Failure(UrlCommandError.ThenNotAllowed("settings")), Parse("skreener://settings?then=copy"));
        Assert.Equal(Failure(UrlCommandError.DelayNotAllowed("grab/area")), Parse("skreener://grab/area?delay=5"));
        Assert.Equal(Failure(UrlCommandError.BadDelay("0")), Parse("skreener://grab/delayed?delay=0"));
        Assert.Equal(Failure(UrlCommandError.BadDelay("soon")), Parse("skreener://grab/delayed?delay=soon"));
        Assert.Equal(Failure(UrlCommandError.UnknownParameter("size")), Parse("skreener://grab/area?size=big"));
    }

    [Fact]
    public void ErrorMessagesListTheOptions()
    {
        Assert.Contains("\"quickaccess\"", UrlCommandError.BadThen("print").Message);
        Assert.Contains("grab/area", UrlCommandError.UnknownCommand("x").Message);
    }
}
