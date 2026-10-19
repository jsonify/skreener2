# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5)
- Quick Access thumbnail: copy, save, edit, dismiss
- Annotation editor: arrow, rectangle, ellipse, pen, text, pixelate, color, undo
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Self-timer fullscreen capture (3/5/10 s) from the menu
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Auto-copy to clipboard, auto-save to folder, optional cursor capture

## Build
```
Scripts/build_app.sh   # produces build/Skreener.app
```
Grant Screen Recording permission on first launch.

## Not yet implemented (vs. CleanShot X)
See [TODO.md](TODO.md) for the full roadmap.
