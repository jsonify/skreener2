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
- [ ] Self-timer for area/window, cancel via Esc — S

## Batch 3 — screen recording (biggest gap)
- [ ] Record area/fullscreen to MP4 (SCStream + AVAssetWriter) — L
- [ ] System audio + microphone options — M
- [ ] Record to GIF — M
- [ ] Click/keystroke visualisation, cursor highlight — M
- [ ] Trim editor for recordings — M
- [ ] Recording HUD (timer, pause/stop) and menu-bar stop — S

## Batch 4 — editor
- [~] CleanShot-style editor chrome: unified toolbar, 990×750 min size, zoom popup, Drag Me, pin/share/copy/save footer — M (not yet compiled on macOS; crop/filled rect/counter/highlighter/stroke/background buttons are disabled placeholders)
- [~] Select/move/resize/delete existing annotations (object model, not baked pixels); double-click text to edit; recolor selection; arrow-key nudge — L
- [~] Undo/redo of every edit (⌘Z / ⇧⌘Z), keyboard shortcuts per tool (V A R O L P T X) — S
- [~] Mouse-wheel zoom around the pointer (trackpad still pans; ⌘+scroll and pinch zoom) — S
- [ ] Numbered step counter, highlighter, blur (gaussian), spotlight — M
- [ ] Line, rounded rectangle, arrow styles, stroke width — M
- [ ] Crop & rotate — M
- [ ] Background tool (gradient/solid, padding, corner radius, shadow) — M
- [ ] Redact: auto-detect emails/text via OCR — M

## Batch 5 — capture modes
- [ ] Scrolling capture (stitching) — L
- [ ] All-in-one capture mode picker — M
- [ ] Capture history (browse / re-open / delete) — M

## Batch 6 — sharing & output
- [ ] Preferences window (hotkey rebinding, format PNG/JPG, filename template, retina downscale) — M
- [ ] Quick Access: stacking, drag-and-drop out, swipe to dismiss, position setting — M
- [ ] Upload to S3-compatible / custom endpoint + copy link — M
- [ ] Share sheet (NSSharingServicePicker) — S
- [ ] Launch at login (SMAppService) — S

## Menu parity with CleanShot X (from its menu bar)
- [ ] Check for Updates… (Sparkle or equivalent) — M
- [ ] Settings… (⌘,) — see Preferences window in batch 6
- [ ] Match CleanShot-style hotkeys (⇧⌘4 area, ⇧⌘3 fullscreen, ⇧⌘6 scrolling, ⇧⌘7 OCR, ⇧⌘5 all-in-one) as rebindable defaults — S

## Engineering
- [ ] CI: macOS runner `swift build` + unit tests (Package has no test target yet) — S
- [ ] Unit tests: coordinate conversion, filename formatting, OCR on fixture — M
- [ ] Developer-ID signing + notarisation script — M
- [ ] App icon and menu-bar template image — S
