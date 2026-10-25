namespace Skreener.Core.Shortcuts;

/// <summary>
/// The things a global shortcut (or a skreener:// link) can start. Only the cases and their titles are ported from
/// HotKeyAction in Shortcuts.swift; its Settings sections, subtitles, default key combos and Carbon registration are
/// macOS UI and stay behind.
/// </summary>
public enum HotKeyAction
{
    CaptureArea, AllInOne, CapturePreviousArea, CaptureAreaAndPin, CaptureFullscreen, CaptureWindow, CaptureActiveWindow,
    CaptureScrolling, CaptureText, TimedArea, TimedWindow, TimedFullscreen,
    RecordScreen,
    ShowHistory, ToggleDesktopIcons, OpenFile, OpenClipboard, PinFile, PinClipboard,
}

public static class HotKeyActionExtensions
{
    public static string Title(this HotKeyAction action) => action switch
    {
        HotKeyAction.CaptureArea => "Capture Area",
        HotKeyAction.AllInOne => "All-in-One",
        HotKeyAction.CapturePreviousArea => "Capture Previous Area",
        HotKeyAction.CaptureAreaAndPin => "Capture Area & Pin",
        HotKeyAction.CaptureFullscreen => "Capture Fullscreen",
        HotKeyAction.CaptureWindow => "Capture Window",
        HotKeyAction.CaptureActiveWindow => "Capture Active Window",
        HotKeyAction.CaptureScrolling => "Capture Scrolling",
        HotKeyAction.CaptureText => "Capture Text (OCR)",
        HotKeyAction.TimedArea => "Self-Timer: Area",
        HotKeyAction.TimedWindow => "Self-Timer: Window",
        HotKeyAction.TimedFullscreen => "Self-Timer: Fullscreen",
        HotKeyAction.RecordScreen => "Record Screen",
        HotKeyAction.ShowHistory => "Capture History",
        HotKeyAction.ToggleDesktopIcons => "Show / Hide Desktop Icons",
        HotKeyAction.OpenFile => "Open…",
        HotKeyAction.OpenClipboard => "Open from Clipboard",
        HotKeyAction.PinFile => "Pin to the Screen…",
        HotKeyAction.PinClipboard => "Pin from Clipboard",
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };
}
