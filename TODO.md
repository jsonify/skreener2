# Skreener feature roadmap

Legend: `[x]` done · `[~]` written, **not yet compiled/tested on macOS** · `[ ]` todo
Size: S (<½ day) · M (1–2 days) · L (3+ days)
Issues: `(#N)` links each open item to its GitHub issue (`[~]` items: a "needs testing" issue for the macOS check)

## Shipped (v0.1)
- [x] Area / fullscreen / window capture, global hotkeys
- [x] Quick Access thumbnail (copy, save, edit, dismiss)
- [x] Annotation editor (arrow, rect, ellipse, pen, text, pixelate, undo)
- [x] Auto-copy / auto-save, optional cursor

## Batch 1 — in this branch (needs a build + manual test on macOS)
- [~] Capture Text / OCR (⌃⇧2, Vision) — S (#39)
- [~] Self-timer fullscreen capture (3/5/10 s) — S (#40)
- [~] Pinned screenshots (floating, opacity, zoom) — S (#41)

- [~] Capture Previous Area (menu; hotkey still todo) — S (#42)
- [~] Open… / Open from Clipboard (existing image → editor) — S (#43)
- [~] Pin to the Screen… from file (pin from clipboard / fresh capture still todo) — S (#44)
- [~] Show/Hide Desktop Icons menu toggle (Finder `CreateDesktop`) — S (#45)
- [~] About panel — S (#46)

## Batch 2 — capture polish (high value, low risk)
- [~] Hotkey for Capture Previous Area (⌃⇧1); Pin from Clipboard; Capture Area & Pin (⌃⇧6) — S (#47)
- [~] Freeze screen during area selection (menu toggle; crops from the frozen frame) — S (#48)
- [~] Crosshair magnifier + pixel/size readout, arrow-key nudge (Shift = 10 pt), Space to move selection — M (#49)
- [~] Window capture options: transparent background, shadow toggle, padding (menu → Window Capture) — M (#50)
- [~] Auto-hide desktop icons only while capturing (menu toggle; restores after the capture) — S (#51)
- [~] Self-timer for area/window/fullscreen (pick first, then count down; delay 3/5/10 s in the menu), cancel via Esc or a click — S (#52)

## Batch 3 — screen recording (biggest gap)
- [~] Record area/fullscreen to MP4 (SCStream + AVAssetWriter; Record Screen ⌃⇧7: drag an area or Space to pick a window, whole-screen button in the picker; saved to the save folder; afterwards the same Quick Access preview as screenshots, with open / show in Finder / share / copy; control bar matches the scrolling-capture bar (#95)) — L (#53)
- [~] System audio + microphone options (Settings → Screen Recording; mic needs macOS 15; with both on they end up in one mixed track, see below), cursor, 30/60 fps — M (#54)
- [~] Record Screen picker (CleanShot-style): "Drag to record… Press Space to select a window" banner on every screen (other screens stay dimmed with the banner while adjusting; drag there to move the selection; Space picks a window; with "Remember last selection" it opens on the saved area with the banner on top); then the selection stays adjustable (handles, move, drag a new one, arrow keys, typed width × height, whole screen, aspect/size presets); mode bar (Area, Fullscreen, Window, Timer, OCR, Recording + size card); Recording (or ↩) shows the panel with options, mic / system audio / click / keystroke toggles, Record GIF ⌥↩ / Record Video ↩ — M (#55)
- [~] Recording options popover: show controls, remember last selection, time in menu bar, dim screen, countdown, cursor, highlight clicks (color, size), keystrokes (all/shortcuts, size, top/bottom), frame rate — M (#56)
- [ ] "Do Not Disturb" while recording (no public API; maybe via a user Shortcut) — S (#23)
- [ ] Record in Studio Mode — L (#24)
- [ ] Webcam overlay in recordings — M (#25)
- [~] Record to GIF (records an MP4, converts at 15 fps, max 960 px wide) — M (#57)
- [~] Click highlighting and keystroke display, drawn into the video (keystrokes need Accessibility access) — M (#58)
- [~] Trim editor for recordings: Trim on the recording's Quick Access preview opens a player with AVKit's trim bar; Trim saves the cut over the file (passthrough, no re-encode); a GIF is made again from its trimmed video — M (#26)
- [~] Recording HUD (timer, pause/resume, stop; dashed frame around the area) and menu-bar stop (the icon turns into a stop button; ⌃⇧7 stops too) — S (#59)
- [~] Mix system audio and microphone into one track (players that only play the first audio track miss the mic): recorded to separate tracks, then mixed into one stereo AAC track after stopping (video copied, not re-encoded); if mixing fails the separate tracks are kept — S (#27)

## Batch 4 — editor
- [~] CleanShot-style editor chrome: unified toolbar, 990×750 min size, zoom popup, Drag Me, pin/share/copy/save footer — M (#60)
- [~] Select/move/resize/delete existing annotations (object model, not baked pixels); double-click text to edit; recolor selection; arrow-key nudge — L (#61)
- [~] Undo/redo of every edit (⌘Z / ⇧⌘Z), keyboard shortcuts per tool (V A R O L P T X) — S (#62)
- [~] Mouse navigation: wheel scrolls vertically, Shift + wheel horizontally, ⌘ + wheel zooms around the pointer, middle-button (wheel held down) drag pans; trackpad still pans, pinch zooms — S (#63)
- [~] Inline text editing on the canvas (type in place, live preview; Esc / ⌘Return / click outside to finish) — S (#64)
- [~] Contextual attributes bar: color for all tools, stroke width (shapes/pen), font/size/bold (text), pixel size (pixelate); applies to the selection or to new annotations — M (#65)
- [~] Filled rectangle (F), numbered step counter (N; renumbers when one is deleted), highlighter (H; multiply blend) — M (#66)
- [~] Crop (C or toolbar; eight handles + draggable sides, margin around the canvas; non-destructive, undoable; Return/Esc) — M (#67)
- [~] Background tool (gradient/solid presets, padding, corner radius, shadow; undoable) — M (#68)
- [~] Add Image (toolbar menu: Capture Area…, From Capture History, Open File…, Paste / ⌘V) as a movable layer that keeps its proportions — S (#69)
- [~] Arrange: bring to front / forward, send backward / to back (context menu, style bar, Arrange menu, ⌥⌘] ⌘] ⌘[ ⌥⌘[) — S (#70)
- [~] Background: desktop wallpaper as a fill — S (#71)
- [~] Blur (B; gaussian, strength popup), spotlight (S; dims everything outside, rounded corners) — M (#72)
- [~] Rotate left/right, flip horizontal/vertical (toolbar menu or Image menu; annotations follow, undoable) — S (#73)
- [~] Rounded rectangles (corner popup for rect/filled rect/spotlight), arrow styles (filled, open, double-headed) — M (#74)
- [~] Compact toolbar: small bordered buttons (tools as one segmented control) so everything fits the 990 pt minimum; smaller style bar and footer — S (#75)
- [~] Pill style throughout the editor, in CleanShot's subtle colors: white raised pills with a soft shadow (grey in dark mode); tools as plain icons on a faint grey capsule, the current one in the accent color; Save as / Apply filled; outlined Drag Me; pop-ups are pills with a ▾; color is a dot pill with presets + More Colors…; tabs on the same grey capsule, the current one raised — M (#76)
- [~] Editors open as tabs of one window instead of a window per screenshot (Settings → Editor toggle; ⇧⌘[ / ⇧⌘] switch tabs, Window menu: move tab to new window, merge all windows) — S (#77)
- [~] Own tab row instead of AppKit's tab bar: pill tabs on a dark capsule (like the scrolling-capture bar), × / middle-click closes, right-click: close others, move to new window — M (#78)
- [~] Copy Text via OCR in the editor: all text, or drag over an area (⇧⌘T, toolbar or Image menu); a toast says how many lines were copied — S (#79)
- [~] Redact via OCR: all text, email addresses, phone numbers, links → editable pixelate boxes (toolbar or Image menu) — M (#80)
- [~] Drag Me: Skreener hides while dragging, with a 100×85 pt preview card under the pointer (pointer over its bottom-right quadrant); a cancelled drag brings it back, after a drop the Dock icon / ⌘-Tab does. Pinned screenshots and Quick Access stay on screen — S (#81)

## Batch 5 — capture modes
- [~] Scrolling capture (Capture Scrolling ⌃⇧8): pick an area, scroll it yourself; frames are grabbed ~8×/s (display filter set up once) and stitched off the main thread by matching rows, leaving out blank rows and the scroll-bar strip at the right edge; sticky header/footer worked out per frame and kept once, including a footer that appears mid-capture; mostly blank stretches are bridged (blank space may come out shorter); scrolling back up a little is followed, not lost; max 30,000 px; Done / ⌃⇧8 finishes, Esc / Cancel throws it away — L (#82)
- [~] Scrolling capture: Auto-Scroll button (needs Accessibility): a steady ~60/s stream of small scroll events sent straight to the app under the area, so the pointer stays free; speed measured from how far the content really moves per point posted before each frame was grabbed, with ticks timed by the clock (about a fifth of the area per frame, at most one area height a second); only scrolls down, apart from taking back an overshoot (after waiting a frame, since a one-off mismatch usually clears; never slowing below a floor; stops with "Stuck here" after repeated take-backs that add nothing); finishes when the content stops moving; Stop Scrolling or Esc hands back control (a second Esc cancels); the control bar sits inside the top tenth of the area (left out of the capture) so the pointer starts over the content — M (#83)
- [ ] Scrolling capture: live preview of the stitched image beside the area — S (#28)
- [ ] All-in-one capture mode picker — M (#29)
- [~] Capture history: panel slides down from the top (menu / ⌃⇧H); edit, copy, save, pin, delete, drag out; last 100 kept; Settings toggle — M (#84)
- [ ] Capture history: restore editable annotations (save the editor document, not just the flattened capture) — M (#30)

## Batch 6 — sharing & output
- [~] Settings window: existing options moved out of the menu, shortcut list, version + build commit — S (#85)
- [~] Settings: format PNG/JPEG (JPEG flattens transparency onto white), filename template (%Y %y %m %d %H %M %S; " 2" etc. when the name is taken), save Retina captures at 1× — S (#86)
- [~] Settings: hotkey rebinding, CleanShot-style Shortcuts pane: groups (Screenshots, Screen Recording, Other) with a shortcut recorder per action (click and type; Esc cancels, Delete / × clears; reset arrow per row; Restore Defaults); refuses combinations used by another action or without ⌘/⌃/⌥ (F-keys alone are fine), warns about macOS ones (⇧⌘3/4/5, ⌘Space…), plain ⌘ + key, and ones macOS won't register; saved in UserDefaults, re-registered live, shown in the menu; self-timer, desktop icons, open / pin can have shortcuts too — M (#31, #97)
- [~] Settings window redesign (CleanShot-style): sidebar with colored icons (General, After Capture, Shortcuts, Screenshots, Screen Recording, Annotate, About), options in rounded groups with switches; 810 pt wide (fixed), 660 pt tall by default, height resizable — M (#87)
- [~] Quick Access (CleanShot-style, #21): shown alongside the editor (own Settings toggle); stays until an action; hover shows corner buttons (close, edit, pin, share) and Copy / Save pills; previews stack upwards, newest at the bottom; they fade out while a new capture is taken and come back after its editor opens; Edit brings back the capture's editor tab if it is still open — M (#88)
- [ ] Quick Access: drag-and-drop out, swipe to dismiss, position setting — M (#32)
- [~] Quick Access previews (screenshots and recordings) rest semi-transparent (65%) and turn opaque while hovered; a preview that appears under the pointer, or whose share sheet is open, is opaque — S (#98)
- [ ] Upload to S3-compatible / custom endpoint + copy link — M (#33)
- [~] Share sheet (NSSharingServicePicker) in the editor footer, Quick Access, recording thumbnail and capture history; always shares a named file so the sheet shows its thumbnail and name — S (#89)
- [~] Launch at login (SMAppService; Settings → General; asks to approve in Login Items when macOS wants that) — S (#90)

## Menu parity with CleanShot X (from its menu bar)
- [ ] Check for Updates… (Sparkle or equivalent) — M (#34)
- [~] Settings… (⌘,) — see Settings window in batch 6 (#85)
- [ ] Match CleanShot-style hotkeys (⇧⌘4 area, ⇧⌘3 fullscreen, ⇧⌘6 scrolling, ⇧⌘7 OCR, ⇧⌘5 all-in-one) as rebindable defaults — S (#35)

## Engineering
- [x] CI: macOS runner builds the app and runs `swift test` (test target `SkreenerTests`), warnings as errors — S (#36)
- [x] Unit tests: coordinate conversion, file names + PNG/JPEG/1× output, OCR + redaction on rendered text, scroll matching, GIF export — M (#37)
- [~] Developer-ID signing + notarisation script (`Scripts/release.sh`: hardened runtime + entitlements, notarytool, stapler, DMG + zip; opt-in tag workflow `release.yml`) — M (#38)
- [~] App icon and menu-bar template image — S (#91)
