# Skreener feature roadmap

Legend: `[x]` done · `[~]` written, **not yet compiled/tested on macOS** · `[ ]` todo
Size: S (<½ day) · M (1–2 days) · L (3+ days)

## Shipped (v0.1)
- [x] Area / fullscreen / window capture, global hotkeys
- [x] Quick Access thumbnail (copy, save, edit, dismiss)
- [x] Annotation editor (arrow, rect, ellipse, pen, text, pixelate, undo)
- [x] Auto-copy / auto-save, optional cursor

## Batch 1 — in this branch (needs a build + manual test on macOS)
- [~] Capture Text / OCR (⌃⇧2, Vision) — S
- [~] Self-timer fullscreen capture (3/5/10 s) — S
- [~] Pinned screenshots (floating, opacity, zoom) — S

- [~] Capture Previous Area (menu; hotkey still todo) — S
- [~] Open… / Open from Clipboard (existing image → editor) — S
- [~] Pin to the Screen… from file (pin from clipboard / fresh capture still todo) — S
- [~] Show/Hide Desktop Icons menu toggle (Finder `CreateDesktop`) — S
- [~] About panel — S

## Batch 2 — capture polish (high value, low risk)
- [~] Hotkey for Capture Previous Area (⌃⇧1); Pin from Clipboard; Capture Area & Pin (⌃⇧6) — S
- [~] Freeze screen during area selection (menu toggle; crops from the frozen frame) — S
- [~] Crosshair magnifier + pixel/size readout, arrow-key nudge (Shift = 10 pt), Space to move selection — M
- [~] Window capture options: transparent background, shadow toggle, padding (menu → Window Capture) — M
- [~] Auto-hide desktop icons only while capturing (menu toggle; restores after the capture) — S
- [~] Self-timer for area/window/fullscreen (pick first, then count down; delay 3/5/10 s in the menu), cancel via Esc or a click — S

## Batch 3 — screen recording (biggest gap)
- [~] Record area/fullscreen to MP4 (SCStream + AVAssetWriter; Record Screen ⌃⇧7: drag an area or Space to pick a window, whole-screen button in the picker; saved to the save folder; thumbnail with open / show in Finder / copy afterwards) — L
- [~] System audio + microphone options (Settings → Screen Recording; mic needs macOS 15; each goes to its own audio track), cursor, 30/60 fps — M
- [~] Record Screen picker (CleanShot-style): "Drag to record… Press Space to select a window" banner on every screen (other screens stay dimmed with the banner while adjusting; drag there to move the selection; Space picks a window; with "Remember last selection" it opens on the saved area with the banner on top); then the selection stays adjustable (handles, move, drag a new one, arrow keys, typed width × height, whole screen, aspect/size presets); mode bar (Area, Fullscreen, Window, Timer, OCR, Recording + size card); Recording (or ↩) shows the panel with options, mic / system audio / click / keystroke toggles, Record GIF ⌥↩ / Record Video ↩ — M
- [~] Recording options popover: show controls, remember last selection, time in menu bar, dim screen, countdown, cursor, highlight clicks (color, size), keystrokes (all/shortcuts, size, top/bottom), frame rate — M
- [ ] "Do Not Disturb" while recording (no public API; maybe via a user Shortcut) — S
- [ ] Record in Studio Mode — L
- [ ] Webcam overlay in recordings — M
- [~] Record to GIF (records an MP4, converts at 15 fps, max 960 px wide) — M
- [~] Click highlighting and keystroke display, drawn into the video (keystrokes need Accessibility access) — M
- [ ] Trim editor for recordings — M
- [~] Recording HUD (timer, pause/resume, stop; dashed frame around the area) and menu-bar stop (the icon turns into a stop button; ⌃⇧7 stops too) — S
- [ ] Mix system audio and microphone into one track (players that only play the first audio track miss the mic) — S

## Batch 4 — editor
- [~] CleanShot-style editor chrome: unified toolbar, 990×750 min size, zoom popup, Drag Me, pin/share/copy/save footer — M
- [~] Select/move/resize/delete existing annotations (object model, not baked pixels); double-click text to edit; recolor selection; arrow-key nudge — L
- [~] Undo/redo of every edit (⌘Z / ⇧⌘Z), keyboard shortcuts per tool (V A R O L P T X) — S
- [~] Mouse-wheel zoom around the pointer (trackpad still pans; ⌘+scroll and pinch zoom) — S
- [~] Inline text editing on the canvas (type in place, live preview; Esc / ⌘Return / click outside to finish) — S
- [~] Contextual attributes bar: color for all tools, stroke width (shapes/pen), font/size/bold (text), pixel size (pixelate); applies to the selection or to new annotations — M
- [~] Filled rectangle (F), numbered step counter (N; renumbers when one is deleted), highlighter (H; multiply blend) — M
- [~] Crop (C or toolbar; eight handles + draggable sides, margin around the canvas; non-destructive, undoable; Return/Esc) — M
- [~] Background tool (gradient/solid presets, padding, corner radius, shadow; undoable) — M
- [~] Add Image (toolbar menu: Capture Area…, From Capture History, Open File…, Paste / ⌘V) as a movable layer that keeps its proportions — S
- [~] Arrange: bring to front / forward, send backward / to back (context menu, style bar, Arrange menu, ⌥⌘] ⌘] ⌘[ ⌥⌘[) — S
- [~] Background: desktop wallpaper as a fill — S
- [~] Blur (B; gaussian, strength popup), spotlight (S; dims everything outside, rounded corners) — M
- [~] Rotate left/right, flip horizontal/vertical (toolbar menu or Image menu; annotations follow, undoable) — S
- [~] Rounded rectangles (corner popup for rect/filled rect/spotlight), arrow styles (filled, open, double-headed) — M
- [~] Compact toolbar: small bordered buttons (tools as one segmented control) so everything fits the 990 pt minimum; smaller style bar and footer — S
- [~] Editors open as tabs of one window instead of a window per screenshot (Settings → Editor toggle; ⇧⌘[ / ⇧⌘] switch tabs, Window menu: move tab to new window, merge all windows) — S
- [~] Redact via OCR: all text, email addresses, phone numbers, links → editable pixelate boxes (toolbar or Image menu) — M
- [~] Drag Me: Skreener hides while dragging, with a 100×85 pt preview card under the pointer (pointer over its bottom-right quadrant); a cancelled drag brings it back, after a drop the Dock icon / ⌘-Tab does. Pinned screenshots and Quick Access stay on screen — S

## Batch 5 — capture modes
- [~] Scrolling capture (Capture Scrolling ⌃⇧8): pick an area, scroll it yourself; frames are grabbed ~8×/s and stitched by matching rows (sticky header/footer kept once, max 30,000 px); Done / ⌃⇧8 finishes, Esc / Cancel throws it away — L
- [ ] Scrolling capture: auto-scroll (needs Accessibility to post scroll events), live preview of the stitched image beside the area — M
- [ ] All-in-one capture mode picker — M
- [~] Capture history: panel slides down from the top (menu / ⌃⇧H); edit, copy, save, pin, delete, drag out; last 100 kept; Settings toggle — M
- [ ] Capture history: restore editable annotations (save the editor document, not just the flattened capture) — M

## Batch 6 — sharing & output
- [~] Settings window: existing options moved out of the menu, shortcut list, version + build commit — S
- [~] Settings: format PNG/JPEG (JPEG flattens transparency onto white), filename template (%Y %y %m %d %H %M %S; " 2" etc. when the name is taken), save Retina captures at 1× — S
- [ ] Settings: hotkey rebinding — M
- [~] Settings window redesign (CleanShot-style): sidebar with colored icons (General, After Capture, Shortcuts, Screenshots, Screen Recording, Annotate, About), options in rounded groups with switches; 810 pt wide (fixed), 660 pt tall by default, height resizable — M
- [ ] Quick Access: stacking, drag-and-drop out, swipe to dismiss, position setting — M
- [ ] Upload to S3-compatible / custom endpoint + copy link — M
- [~] Share sheet (NSSharingServicePicker) in the editor footer, Quick Access, recording thumbnail and capture history; always shares a named file so the sheet shows its thumbnail and name — S
- [~] Launch at login (SMAppService; Settings → General; asks to approve in Login Items when macOS wants that) — S

## Menu parity with CleanShot X (from its menu bar)
- [ ] Check for Updates… (Sparkle or equivalent) — M
- [~] Settings… (⌘,) — see Settings window in batch 6
- [ ] Match CleanShot-style hotkeys (⇧⌘4 area, ⇧⌘3 fullscreen, ⇧⌘6 scrolling, ⇧⌘7 OCR, ⇧⌘5 all-in-one) as rebindable defaults — S

## Engineering
- [ ] CI: macOS runner `swift build` + unit tests (Package has no test target yet) — S
- [ ] Unit tests: coordinate conversion, filename formatting, OCR on fixture — M
- [ ] Developer-ID signing + notarisation script — M
- [~] App icon and menu-bar template image — S
