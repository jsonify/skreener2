# Skreener for Windows

Windows port of Skreener: C# / .NET 8 with WinUI 3 (Windows App SDK). Milestone 1 is the capture core:
tray icon, global hotkeys, area/window/fullscreen capture, copy/save and the quick-access thumbnail.
This folder is a scaffold; there is no feature code yet.

## Layout

| Path | What |
| --- | --- |
| `Skreener.sln` | Solution (Any CPU, x64, ARM64). |
| `Directory.Build.props` | Shared settings: nullable on, latest C#, warnings are errors (same policy as the macOS app). |
| `src/Skreener.Core` | `net8.0` class library with no Windows dependencies: ported pure logic (geometry, scroll matching, color formats, URL commands). Builds and tests on any OS. |
| `src/Skreener.App` | WinUI 3 app, `net8.0-windows10.0.19041.0`, unpackaged and self-contained, x64 and ARM64. References Core. |
| `tests/Skreener.Core.Tests` | xUnit tests for Core. |

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
