# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5), previous area (⌃⇧1), area & pin (⌃⇧6)
- Area selection: crosshair + pixel magnifier, arrow keys nudge the pointer (Shift = 10 pt), hold Space to move the selection, optional frozen screen
- Window capture options: shadow, transparent or white background, padding
- After a capture the screenshot opens in the editor (Settings → After Capture can switch back to the Quick Access thumbnail: copy, save, edit, pin, share, dismiss); Capture Text and Capture Area & Pin skip it
- Screen recording to MP4 or GIF (Record Screen, ⌃⇧7: drag an area, or press Space and click a window). The area then stays adjustable, with a mode bar (screenshot, fullscreen, window, timer, OCR or Recording, plus width × height); Recording shows a panel with options, audio/click/keystroke toggles and Record GIF (⌥↩) / Record Video (↩). Options: countdown, dim the rest of the screen, remember the last area, time in the menu bar, click highlighting and keystroke display drawn into the video. Also: optional system audio and microphone (macOS 15+), cursor, 30/60 fps; a small HUD shows the elapsed time with pause/resume and stop, and the menu bar icon turns into a stop button (⌃⇧7 stops too). Recordings go to the save folder; a thumbnail offers open, show in Finder and copy
- Annotation editor (CleanShot-style unified toolbar with compact bordered buttons, 990×750 minimum window; each new screenshot opens as a tab of the editor window (Settings can switch back to separate windows), zoom-to-fit canvas, Drag Me export): arrow, rectangle, filled rectangle, ellipse, line, pen, highlighter, text (typed in place on the image), numbered counter, pixelate, blur, spotlight. Rectangles can have rounded corners; arrows can be filled, open or double-headed. Every tool has its own toolbar button; a style bar under the toolbar shows the options for the current tool or selection: color, stroke width, font, size, bold, pixel size. Annotations stay editable: select, move, resize by handles, delete (⌫), double-click text to edit, recolor; undo/redo (⌘Z / ⇧⌘Z); tool keys V A R F O L P H T N X B S; mouse wheel zooms; optional subtle drop shadow on annotations; dragging an annotation past the image edge grows the canvas (filled with the image's top-left pixel color), and exports include the grown area. Crop (C; eight handles plus the frame's sides, move, or draw a new area; Return applies, Esc cancels), Background (gradient, solid or your desktop wallpaper; padding, corner radius, shadow), Add Image from a new area capture, the capture history, a file or the clipboard (⌘V) as a movable layer that resizes in proportion. Rotate left/right and flip the whole screenshot with its annotations; Redact finds text with OCR (all text, emails, phone numbers or links) and pixelates it. Arrange annotations (right-click, the style bar's Arrange button, or the Arrange menu: ⌥⌘] front, ⌘] forward, ⌘[ backward, ⌥⌘[ back); the screenshot always stays underneath. While an editor or Settings is open, Skreener shows in the Dock, ⌘-Tab and the menu bar
- Capture History (menu or ⌃⇧H): recent captures slide down from the top of the screen; hover for edit / copy / save / share / pin / delete, double-click to edit, drag one out as a file; keeps the last 100 (toggle in Settings)
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Self-timer for area, window or fullscreen: pick the area/window first, then a 3/5/10 s countdown (Esc or a click cancels)
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Open… / Open from Clipboard into the editor, Pin to the Screen… from a file or the clipboard
- Show/Hide Desktop Icons toggle (or hide them only while capturing), About panel
- Settings window (⌘, the menu bar icon, or the editor's gear button), CleanShot-style with a sidebar: General (launch at login, freeze screen, cursor, desktop icons, export location), After Capture (copy / save / open editor, capture history), Shortcuts, Screenshots (PNG/JPEG, save Retina captures at 1×, file name template, window capture style), Screen Recording (audio, frame rate, cursor), Annotate (drop shadow, editor tabs), About (version + build commit)

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
