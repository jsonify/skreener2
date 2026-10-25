# Skreener for Windows

Windows port of Skreener: C# / .NET 8 with WinUI 3 (Windows App SDK). Milestone 1 is the capture core:
tray icon, global hotkeys, area/window/fullscreen capture, copy/save and the quick-access thumbnail. That
path works end to end; the editor, recording and the rest of the Mac features are still to come.

## Layout

| Path | What |
| --- | --- |
| `Skreener.sln` | Solution (Any CPU, x64, ARM64). |
| `Directory.Build.props` | Shared settings: nullable on, latest C#, warnings are errors (same policy as the macOS app). |
| `src/Skreener.Core` | `net8.0` class library with no Windows dependencies: ported pure logic (selection geometry, pixel buffer, scroll matching, color formats, URL commands, settings and file naming in `Output/`). Builds and tests on any OS. Faithful to the Swift code, so its geometry is y-up. |
| `src/Skreener.App` | WinUI 3 app, `net8.0-windows10.0.19041.0`, unpackaged and self-contained, x64 and ARM64. References Core. |
| `src/Skreener.App/Shell` | Tray icon and menu, global hotkeys, settings file, clipboard/save, toasts, Quick Access. `ShellController` runs a capture through `ICaptureService` and handles the result. |
| `src/Skreener.App/Capture` | `CaptureService` (area, window, fullscreen, previous area) with Windows.Graphics.Capture; `BgraImage` is the raw capture buffer. |
| `src/Skreener.App/Overlay` | The per-monitor Win32 selection overlay. `ScreenSelection` is its only bridge to Core's y-up `SelectionGeometry` (top-left pixels mirrored in and out). |
| `tests/Skreener.Core.Tests` | xUnit tests for Core, plus `ScreenSelection` (compiled in by path, since it is pure). |

The composition root is `App.OnLaunched`: it makes the `CaptureService` and hands it to the `ShellController`.
Win32 APIs come from CsWin32: each feature folder lists what it uses in its own `NativeMethods.txt`.

## Using it

Skreener has no window: it lives in the tray. Left-click the tray icon to capture an area; right-click for the menu
(captures, Open Screenshots Folder, Launch at Login, Quit). Default hotkeys:

| Hotkey | Action |
| --- | --- |
| Ctrl+Alt+4 | Capture area (drag; then adjust with handles, arrows, Ctrl+arrows, wheel; Enter or double-click to capture) |
| Ctrl+Alt+5 | Capture window (Space in the overlay switches between area and window) |
| Ctrl+Alt+3 | Capture the monitor under the pointer |
| Ctrl+Alt+1 | Capture the previous area again |

Esc or right-click cancels. A capture is copied to the clipboard, saved to `Pictures\Skreener` and shown in Quick
Access (bottom-right); change that, the folder, format and hotkeys in `%APPDATA%\Skreener\settings.json` (read on each
capture; hotkeys on the next launch). Skreener's own overlay, Quick Access (Windows 10 2004+) and toasts are kept out
of captures.

## Build and run (Windows 10 1809+ / 11)

Requires the .NET 8 SDK (Visual Studio 2022 with the ".NET desktop development" workload also works).

```powershell
cd windows
dotnet build                                            # whole solution; the app builds as x64
dotnet build src/Skreener.App -c Release -p:Platform=ARM64
dotnet run --project src/Skreener.App -p:Platform=x64
```

The app is unpackaged: no MSIX and no installed Windows App SDK runtime are needed. The window is never shown;
Skreener is meant to live in the tray.

## Run the Core tests on any OS

```sh
cd windows
dotnet test tests/Skreener.Core.Tests
```

Build `src/Skreener.Core` and the tests by project path on Linux/macOS. Building `Skreener.sln` or `Skreener.App`
needs Windows because of the Windows SDK and WinUI.

## CI

`.github/workflows/windows.yml` runs only when `windows/**` or the workflow changes: Core tests on Ubuntu, then a
Release build of the app for x64 and ARM64 on `windows-latest`, uploaded as `Skreener-windows-<platform>`.
