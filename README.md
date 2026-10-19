# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5), previous area (⌃⇧1), area & pin (⌃⇧6)
- Area selection: crosshair + pixel magnifier, arrow keys nudge the pointer (Shift = 10 pt), hold Space to move the selection, optional frozen screen
- Window capture options: shadow, transparent or white background, padding
- Quick Access thumbnail: copy, save, edit, dismiss
- Annotation editor (CleanShot-style unified toolbar, 990×750 minimum window, zoom-to-fit canvas, Drag Me export): arrow, rectangle, ellipse, line, pen, text, pixelate, color. Annotations stay editable: select, move, resize by handles, delete (⌫), double-click text to edit, recolor; undo/redo (⌘Z / ⇧⌘Z); tool keys V A R O L P T X; mouse wheel zooms
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Self-timer fullscreen capture (3/5/10 s) from the menu
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Open… / Open from Clipboard into the editor, Pin to the Screen… from a file or the clipboard
- Show/Hide Desktop Icons toggle (or hide them only while capturing), About panel
- Auto-copy to clipboard, auto-save to folder, optional cursor capture

## Build
```
Scripts/build_app.sh   # produces build/Skreener.app
```
Grant Screen Recording permission on first launch.

To keep that permission across rebuilds, sign with a stable certificate (once):
```
Scripts/make_dev_cert.sh          # creates "Skreener Dev"; build_app.sh then uses it automatically
Scripts/build_app.sh --run        # quits the running copy, rebuilds, relaunches
```

## Not yet implemented (vs. CleanShot X)
See [TODO.md](TODO.md) for the full roadmap.
