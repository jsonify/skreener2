# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5), previous area (⌃⇧1), area & pin (⌃⇧6)
- Area selection: crosshair + pixel magnifier, arrow keys nudge the pointer (Shift = 10 pt), hold Space to move the selection, optional frozen screen
- Window capture options: shadow, transparent or white background, padding
- Quick Access thumbnail: copy, save, edit, dismiss
- Annotation editor (CleanShot-style unified toolbar, 990×750 minimum window, zoom-to-fit canvas, Drag Me export): arrow, rectangle, filled rectangle, ellipse, line, pen, highlighter, text (typed in place on the image), numbered counter, pixelate. Every tool has its own toolbar button; a style bar under the toolbar shows the options for the current tool or selection: color, stroke width, font, size, bold, pixel size. Annotations stay editable: select, move, resize by handles, delete (⌫), double-click text to edit, recolor; undo/redo (⌘Z / ⇧⌘Z); tool keys V A R F O L P H T N X; mouse wheel zooms; optional subtle drop shadow on annotations; dragging an annotation past the image edge grows the canvas (filled with the image's top-left pixel color), and exports include the grown area. Crop (C; drag corners or draw a new area, Return applies, Esc cancels), Background (gradient or solid fill, padding, corner radius, shadow), Add Image (or paste one with ⌘V) as a movable, resizable layer. While an editor or Settings is open, Skreener shows in the Dock, ⌘-Tab and the menu bar
- Capture History (menu or ⌃⇧H): recent captures slide down from the top of the screen; hover for edit / copy / save / pin / delete, double-click to edit, drag one out as a file; keeps the last 100 (toggle in Settings)
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Self-timer fullscreen capture (3/5/10 s) from the menu
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Open… / Open from Clipboard into the editor, Pin to the Screen… from a file or the clipboard
- Show/Hide Desktop Icons toggle (or hide them only while capturing), About panel
- Settings window (⌘, the menu bar icon, or the editor's gear button): annotation drop shadow, copy/save after capture, save folder, freeze screen, cursor, desktop icons, window capture style, shortcut list, and the running version + build commit

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
