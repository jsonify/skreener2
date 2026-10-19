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

## Batch 2 — capture polish (high value, low risk)
- [ ] Capture previous area (repeat last rect, hotkey) — S
- [ ] Freeze screen during area selection — S
- [ ] Crosshair magnifier + pixel/size readout, arrow-key nudge, Space to move selection — M
- [ ] Window capture options: transparent background, shadow toggle, padding — M
- [ ] Hide desktop icons while capturing — S
- [ ] Self-timer for area/window, cancel via Esc — S

## Batch 3 — screen recording (biggest gap)
- [ ] Record area/fullscreen to MP4 (SCStream + AVAssetWriter) — L
- [ ] System audio + microphone options — M
- [ ] Record to GIF — M
- [ ] Click/keystroke visualisation, cursor highlight — M
- [ ] Trim editor for recordings — M
- [ ] Recording HUD (timer, pause/stop) and menu-bar stop — S

## Batch 4 — editor
- [ ] Select/move/resize/delete existing annotations (object model, not baked pixels) — L
- [ ] Redo, keyboard shortcuts per tool — S
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

## Engineering
- [ ] CI: macOS runner `swift build` + unit tests (Package has no test target yet) — S
- [ ] Unit tests: coordinate conversion, filename formatting, OCR on fixture — M
- [ ] Developer-ID signing + notarisation script — M
- [ ] App icon and menu-bar template image — S
