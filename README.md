# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5)
- Quick Access thumbnail: copy, save, edit, dismiss
- Annotation editor: arrow, rectangle, ellipse, pen, text, pixelate, color, undo
- Auto-copy to clipboard, auto-save to folder, optional cursor capture

## Build
```
Scripts/build_app.sh   # produces build/Skreener.app
```
Grant Screen Recording permission on first launch.

## Not yet implemented (vs. CleanShot X)
Screen recording/GIF, scrolling capture, OCR, self-timer, cloud upload, background tool, pinned screenshots.
