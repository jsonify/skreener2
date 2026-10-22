# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5), previous area (⌃⇧1), area & pin (⌃⇧6)
- Area selection: crosshair + pixel magnifier, arrow keys nudge the pointer (Shift = 10 pt), hold Space to move the selection, optional frozen screen
- Window capture options: shadow, transparent or white background, padding
- After a capture the screenshot opens in the editor, and a Quick Access preview appears in the bottom-left corner (each can be turned off in Settings → After Capture). The preview stays until you do something with it: hover it for round close / edit / pin / share buttons in the corners and Copy / Save pills in the middle. Previews of later captures stack upwards, and fade away while a new capture is taken. Capture Text and Capture Area & Pin skip both
- Screen recording to MP4 or GIF (Record Screen, ⌃⇧7: drag an area, or press Space and click a window). The area then stays adjustable, with a mode bar (screenshot, fullscreen, window, timer, OCR or Recording, plus width × height); Recording shows a panel with options, audio/click/keystroke toggles and Record GIF (⌥↩) / Record Video (↩). Options: countdown, dim the rest of the screen, remember the last area, time in the menu bar, click highlighting and keystroke display drawn into the video. Also: optional system audio and microphone (macOS 15+; with both on they are mixed into one audio track), cursor, 30/60 fps; a dark control bar (the same style as the scrolling-capture bar) shows the elapsed time with pause/resume and Stop, and the menu bar icon turns into a stop button (⌃⇧7 stops too). Recordings go to the save folder and get the same Quick Access preview as screenshots, showing the first frame (a GIF plays): Close, Open, Show in Finder and Share in the corners, Copy (the file) in the middle
- Annotation editor (CleanShot-style unified toolbar with compact bordered buttons, 990×750 minimum window; each new screenshot opens as a tab of the editor window, shown as pill tabs on a dark capsule like the scrolling-capture bar: click to switch, × or middle-click to close, right-click to close others or move to a new window (Settings can switch back to separate windows), zoom-to-fit canvas, Drag Me export: Skreener hides while you drag a small preview to the drop target): arrow, rectangle, filled rectangle, ellipse, line, pen, highlighter, text (typed in place on the image), numbered counter, pixelate, blur, spotlight. Rectangles can have rounded corners; arrows can be filled, open or double-headed. Every tool has its own toolbar button; a style bar under the toolbar shows the options for the current tool or selection: color, stroke width, font, size, bold, pixel size. Annotations stay editable: select, move, resize by handles, delete (⌫), double-click text to edit, recolor; undo/redo (⌘Z / ⇧⌘Z); tool keys V A R F O L P H T N X B S; the mouse wheel scrolls (Shift + wheel sideways), ⌘ + wheel or pinch zooms around the pointer, and dragging with the wheel held down moves around; optional subtle drop shadow on annotations; dragging an annotation past the image edge grows the canvas (filled with white, or with the image's top-left pixel color if Settings says so), and exports include the grown area. Crop (C; eight handles plus the frame's sides, move, or draw a new area; Return applies, Esc cancels), Background (gradient, solid or your desktop wallpaper; padding, corner radius, shadow), Add Image from a new area capture, the capture history, a file or the clipboard (⌘V) as a movable layer that resizes in proportion. Rotate left/right and flip the whole screenshot with its annotations; Redact finds text with OCR (all text, emails, phone numbers or links) and pixelates it. Copy Text (toolbar or Image menu) copies the screenshot's text with OCR: all of it, or drag over an area (⇧⌘T). Arrange annotations (right-click, the style bar's Arrange button, or the Arrange menu: ⌥⌘] front, ⌘] forward, ⌘[ backward, ⌥⌘[ back); the screenshot always stays underneath. While an editor or Settings is open, Skreener shows in the Dock, ⌘-Tab and the menu bar
- Capture History (menu or ⌃⇧H): recent captures slide down from the top of the screen; hover for edit / copy / save / share / pin / delete, double-click to edit, drag one out as a file; keeps the last 100 (toggle in Settings)
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Capture Scrolling (⌃⇧8): pick an area, then scroll its content, or click Auto-Scroll to have Skreener scroll it to the end (needs Accessibility access); it stitches everything into one tall image (sticky headers and footers kept once). the pointer stays yours while it scrolls; Stop Scrolling or Esc hands back to you; Done or ⌃⇧8 again finishes, Esc (when not auto-scrolling) cancels
- Self-timer for area, window or fullscreen: pick the area/window first, then a 3/5/10 s countdown (Esc or a click cancels)
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Open… / Open from Clipboard into the editor, Pin to the Screen… from a file or the clipboard
- Show/Hide Desktop Icons toggle (or hide them only while capturing), About panel
- Settings window (⌘, the menu bar icon, or the editor's gear button), CleanShot-style with a sidebar: General (launch at login, freeze screen, cursor, desktop icons, export location), After Capture (copy / save / open editor, capture history), Shortcuts, Screenshots (PNG/JPEG, save Retina captures at 1×, file name template, window capture style), Screen Recording (audio, frame rate, cursor), Annotate (drop shadow, editor tabs), About (version + build commit)

## Build
```
Scripts/build_app.sh   # produces build/Skreener.app
swift test             # unit tests
```
Grant Screen Recording permission on first launch.

To keep that permission across rebuilds, sign with a stable certificate (once):
```
Scripts/make_dev_cert.sh          # creates "Skreener Dev"; build_app.sh then uses it automatically
Scripts/build_app.sh --run        # quits the running copy, rebuilds, relaunches
```

## Not yet implemented (vs. CleanShot X)
See [TODO.md](TODO.md) for the full roadmap.
