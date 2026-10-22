# Skreener

A clean-room, CleanShot X–style screenshot tool for macOS 14+ (menu bar app, Swift/AppKit/ScreenCaptureKit).
Built from publicly documented behavior only; no code from CleanShot X was decompiled or copied.

## Features
- Capture area / fullscreen / window (global hotkeys ⌃⇧4 / ⌃⇧3 / ⌃⇧5 by default; every hotkey can be changed in Settings → Shortcuts), previous area (⌃⇧1), area & pin (⌃⇧6)
- Area selection: crosshair + pixel magnifier, arrow keys nudge the pointer (Shift = 10 pt), hold Space to move the selection, Shift while dragging = square, ⌥ = from the center, optional frozen screen. After the drag the selection stays adjustable (Settings → General, on by default): drag its handles or move it, arrows move it, ⌘ + arrows resize it (right/bottom edge) (Shift = 10 pt), the scroll wheel grows (up) or shrinks (down) every side; Return or a double-click inside captures, Esc cancels
- Window capture: hover a window to tint the part of it you can see blue with a camera pointer, click to capture it; options: shadow, transparent or white background, padding
- After a capture the screenshot opens in the editor, and a Quick Access preview appears in the bottom-left corner (each can be turned off in Settings → After Capture). The preview stays until you do something with it: hover it for round close / edit / pin / share buttons in the corners and Copy / Save pills in the middle; double-click it to open the editor (a recording opens in its player). Previews of later captures stack upwards, and fade away while a new capture is taken. Previews stay semi-transparent until the pointer is over them (#98). Capture Text and Capture Area & Pin skip both
- Screen recording to MP4 or GIF (Record Screen, ⌃⇧7: drag an area, or press Space and click a window). The area then stays adjustable, with a mode bar (screenshot, fullscreen, window, timer, OCR or Recording, plus width × height); Recording shows a panel with options, audio/click/keystroke toggles and Record GIF (⌥↩) / Record Video (↩). Options: countdown, dim the rest of the screen, remember the last area, time in the menu bar, click highlighting and keystroke display drawn into the video. Also: optional system audio and microphone (macOS 15+; with both on they are mixed into one audio track), cursor, 30/60 fps; a dark control bar (the same style as the scrolling-capture bar) shows the elapsed time with pause/resume and Stop, and the menu bar icon turns into a stop button (⌃⇧7 stops too). Recordings go to the save folder and get the same Quick Access preview as screenshots, showing the first frame (a GIF plays): Close, Open, Show in Finder and Share in the corners, Copy (the file) and Trim in the middle. Trim opens the recording in a player with a trim bar: drag the yellow handles and click Trim to cut off the start and end (saved over the file, without re-encoding; a GIF is made again from the trimmed video)
- Annotation editor (CleanShot-style unified toolbar with compact bordered buttons, 990×750 minimum window; each new screenshot opens as a tab of the editor window, shown as pill tabs on a dark capsule like the scrolling-capture bar: click to switch, × or middle-click to close, right-click to close others or move to a new window (Settings can switch back to separate windows), zoom-to-fit canvas, Drag Me export: Skreener hides while you drag a small preview to the drop target): arrow, rectangle, filled rectangle, ellipse, line, pen, highlighter, text (typed in place on the image), numbered counter, pixelate, blur, erase (fills the box with the background color around it), spotlight, magnifier (a lens showing an area enlarged 1.5–4×, circle or rectangle, with a line to the area; drag the lens and the area separately). Pixelate, blur and erase have a Text Only option that hides just the lines of text OCR finds in the box (found again when the box moves or resizes). Rectangles can have rounded corners; arrows can be filled, open or double-headed. Every tool has its own toolbar button; a style bar under the toolbar shows the options for the current tool or selection: color, stroke width, font, size, bold, pixel size. Annotations stay editable: select, move, resize by handles, delete (⌫), double-click text to edit, recolor; undo/redo (⌘Z / ⇧⌘Z); tool keys V A R F O L P H T N X B E S M; the mouse wheel scrolls (Shift + wheel sideways), ⌘ + wheel or pinch zooms around the pointer, and dragging with the wheel held down moves around; optional subtle drop shadow on annotations; dragging an annotation past the image edge grows the canvas (filled with white, or with the image's top-left pixel color if Settings says so), and exports include the grown area. Crop (C; eight handles plus the frame's sides, move, or draw a new area; Return applies, Esc cancels), Background (gradient, solid or your desktop wallpaper; padding, corner radius, shadow), Add Image from a new area capture, the capture history, a file or the clipboard (⌘V) as a movable layer that resizes in proportion. Rotate left/right and flip the whole screenshot with its annotations; Redact finds text with OCR (all text, emails, phone numbers or links) and pixelates it. Copy Text (toolbar or Image menu) copies the screenshot's text with OCR: all of it, or drag over an area (⇧⌘T). Measure and pick colors: hold 1 (or ← →) or 2 (or ↑ ↓ when nothing is selected) to measure the run of color under the pointer, Shift to include its border, click to keep the measurement; Tab copies the color under the pointer, ⇧Tab the darkest color near it, ⇧C an area's average color, in a format chosen from the footer's live color readout (HEX, CSS rgba, RGB 0–1, Android, UIColor, C#, OKLCH…); Tab while typing a label inserts the color; Check Contrast (⇧K) shows the WCAG 2 ratio or APCA Lc of the text and background in an area. Arrange annotations (right-click, the style bar's Arrange button, or the Arrange menu: ⌥⌘] front, ⌘] forward, ⌘[ backward, ⌥⌘[ back); the screenshot always stays underneath. While an editor or Settings is open, Skreener shows in the Dock, ⌘-Tab and the menu bar
- skreener:// links for Raycast, Alfred, Shortcuts and scripts, e.g. `open "skreener://grab/area?then=copy,save"`: grab/area, grab/previous, grab/fullscreen, grab/window, grab/scrolling, grab/delayed[/area|/window|/fullscreen]?delay=N, ocr, record, load/clipboard, load/file, pin/clipboard, pin/file, history, settings (capture/… works too); `then=` (copy, save, edit, pin, quickaccess) replaces Settings → After Capture for that capture. Off until allowed in Settings → General or from the prompt the first link shows
- Capture History (menu or ⌃⇧H): recent captures slide down from the top of the screen; hover for edit / copy / save / share / pin / delete, double-click to edit, drag one out as a file; keeps the last 100 (toggle in Settings)
- Capture Text (OCR, ⌃⇧2): on-device Vision text recognition copied to clipboard
- Capture Scrolling (⌃⇧8): pick an area, then scroll its content, or click Auto-Scroll to have Skreener scroll it to the end (needs Accessibility access); it stitches everything into one tall image (sticky headers and footers kept once). the pointer stays yours while it scrolls; Stop Scrolling or Esc hands back to you; Done or ⌃⇧8 again finishes, Esc (when not auto-scrolling) cancels
- Self-timer for area, window or fullscreen: pick the area/window first, then a 3/5/10 s countdown (Esc or a click cancels)
- Pin screenshots on top of other windows (Quick Access → Pin; scroll = opacity, ⌘+scroll/pinch = zoom, double-click/Esc = close)
- Open… / Open from Clipboard into the editor, Pin to the Screen… from a file or the clipboard
- Show/Hide Desktop Icons toggle (or hide them only while capturing), About panel
- Settings window (⌘, the menu bar icon, or the editor's gear button), CleanShot-style with a sidebar: General (launch at login, freeze screen, cursor, desktop icons, export location), After Capture (copy / save / open editor, capture history), Shortcuts (click a shortcut and type a new one, for any capture, recording, self-timer, history, desktop icons or open / pin command; × clears, the arrow resets one, Restore Defaults resets all; warns about combinations macOS or another action already uses; changes apply at once and show in the menu), Screenshots (PNG/JPEG, save Retina captures at 1×, file name template, window capture style and highlight color), Screen Recording (audio, frame rate, cursor), Annotate (drop shadow, editor tabs), About (version + build commit)

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

## Release (Developer ID + notarisation)
`Scripts/release.sh` builds the app, signs it with your Developer ID Application certificate (hardened
runtime, `Resources/Skreener.entitlements`), notarises and staples it, and writes
`build/release/Skreener-<version>.dmg`, `.zip` and `SHA256SUMS`. Credentials come from your keychain
or environment, never the repo. One-time setup:
1. A **Developer ID Application** certificate in your login keychain (Xcode → Settings → Accounts →
   Manage Certificates → + → Developer ID Application).
2. A notarytool keychain profile (asks for an app-specific password from appleid.apple.com):
   ```
   xcrun notarytool store-credentials skreener-notary --apple-id you@example.com --team-id TEAMID
   ```

Then:
```
SKREENER_NOTARY_PROFILE=skreener-notary Scripts/release.sh --version 0.2.0
Scripts/release.sh --skip-notarize      # sign + package only, to check signing without Apple
Scripts/release.sh --help               # all options, API-key / Apple ID credentials
```
With several Developer ID identities, pick one with `SKREENER_DEVELOPER_ID="Developer ID Application: Name (TEAMID)"`.

Pushing a `v*` tag runs `.github/workflows/release.yml`, which does the same on CI and attaches the
DMG and zip to a draft GitHub release. It needs the secrets listed at the top of that file
(the certificate as a base64 `.p12` and an App Store Connect API key); normal pushes and PRs never run it.

## Not yet implemented (vs. CleanShot X)
See [TODO.md](TODO.md) for the full roadmap.
