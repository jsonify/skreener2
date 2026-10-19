# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5)
- Quick Access thumbnail: copy, save, edit, dismiss
- Annotation editor (CleanShot-style unified toolbar, 990×750 minimum window, zoom-to-fit canvas, Drag Me export): arrow, rectangle, ellipse, line, pen, text, pixelate, color, undo
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Self-timer fullscreen capture (3/5/10 s) from the menu
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Capture Previous Area, Open… / Open from Clipboard into the editor, Pin to the Screen… from a file
- Show/Hide Desktop Icons toggle, About panel
- Auto-copy to clipboard, auto-save to folder, optional cursor capture

## Build
```
Scripts/build_app.sh   # produces build/Skreener.app
```
Grant Screen Recording permission on first launch.

To keep that permission across rebuilds, sign with a stable certificate (once):
```
Scripts/make_dev_cert.sh
SKREENER_SIGN_IDENTITY="Skreener Dev" Scripts/build_app.sh --run   # quits the running copy, rebuilds, relaunches
```

## Not yet implemented (vs. CleanShot X)
See [TODO.md](TODO.md) for the full roadmap.
