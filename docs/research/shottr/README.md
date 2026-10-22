# Shottr 1.9.3 vs Skreener: merged gap list

Merged from five research reports (same folder): `prefs.md`, `capture.md`, `editor.md`, `measure.md`, `output.md`.
Each report has per-feature evidence (observed vs. inferred), Skreener file refs, an implementation approach and
acceptance criteria. Shottr was never launched; REA/Hopper could not be used in the re-run, so evidence is binary
strings, Swift field metadata, decoded nibs and shottr.cc. "#NN" = existing GitHub issue.

## High

| Gap | Area | Existing | Report |
|---|---|---|---|
| Area selection stays adjustable after the drag; Return/double-click captures (reuse `RecordAreaPicker` selection view) | Capture | — | capture #1 |
| Area keyboard: Shift = square, arrows move 1/10 px, ⌘+arrows resize, `[` `]` grow/shrink | Capture | — | capture #2 |
| URL scheme automation (`skreener://grab/area?then=copy,save`), opt-in with first-use confirm | App | — | prefs #1, capture #19 |
| Upload to S3-compatible + copy link (SigV4, presigned/public URL, Test Connection, Keychain secret, size fallback) | Output | #33 | output #1–2 |
| Smart Erase (fill with detected background) and Erase/Blur Text (only text inside a box) | Editor | — | editor #1 |
| Magnifier callout annotation (M) | Editor | — | editor #2, measure #18 |

## Medium

| Gap | Area | Existing | Report |
|---|---|---|---|
| Pixel ruler with auto edge detection (1/2 or arrows; Shift = outer; click to imprint) | Measure | — | measure #1 |
| Color picker (Tab/Shift+Tab/C), 8 copy formats, live pixel-color box | Measure | — | measure #4–6 |
| Contrast checker (WCAG 2 + APCA) | Measure | — | measure #7 |
| Capture Active Window (frontmost, no click) | Capture | related #100 | capture #4 |
| Editor opens on the capture's display, not `NSScreen.main` | Capture | — | capture #6 |
| Explanatory capture/permission errors instead of beeps; permission status view with Privacy deep links | Capture/App | — | capture #11, prefs #18 |
| Confirmation style: None / system notification / HUD; sounds can be turned off | App | — | prefs #3 |
| Update check | App | #34 | prefs #8 |
| ⇧⌘3/⇧⌘4 reassignment guide with Open System Settings | App | related #35 | prefs #6 |
| Esc copies or saves, then closes the editor | Editor | — | editor #25, prefs #11 |
| Pins: hover toolbar, context menu (50/100/200%, copy, edit), drag out as file | Output | — | output #4–7 |
| Library indexes the save folder; search + filters | Output | related #30 | output #8–9 |
| Re-save edits over the same file instead of a new " 2" copy | Output | — | output #15 |
| Drag out of the Quick Access thumbnail | Output | #32 | output #19 |
| Hand-drawn/curved arrows; freehand shape correction and smoothing | Editor | — | editor #3–4 |
| Translucent fill and filled oval; text background box, callout tail, wrapping | Editor | — | editor #5, #7 |
| Cut Out (likely background removal via Vision; unconfirmed) | Editor | — | editor #10 |
| Resize image to exact pixels | Editor | — | editor #11 |
| Snap to objects while drawing | Editor | — | editor #13 |
| Backdrop: aspect presets, gradients, custom image, inset, shadow slider | Editor | — | editor #14 |
| Copy/paste annotations between screenshots | Editor | — | editor #17 |

## Low / quick wins

| Gap | Area | Existing | Report |
|---|---|---|---|
| QR/barcode reading in the OCR flow (Vision `VNDetectBarcodesRequest`) | Measure | — | measure #12 |
| OCR language setting; "Remove line breaks" option | Measure | — | measure #13–14 |
| Nearest-neighbour rendering at high zoom; ⌘0/⌘1/⌘2 zoom items; zoom > 800% | Measure/Editor | — | measure #16–17, editor #21 |
| PX/PT toggle for sizes; size label in physical pixels | Measure/Capture | — | measure #3, capture #7 |
| Guide lines (Opt+S / Opt+D) | Measure | — | measure #2 |
| Overlay layer transparency; Before/After GIF | Editor | — | measure #19–20, editor #9 |
| Scrolling capture upward; speed and max-height settings | Capture | — | capture #8–9 |
| Cursor Auto/Include/Exclude; repeat area kept across relaunch | Capture | — | capture #10, #12 |
| Write `kMDItemIsScreenCapture` metadata; copy as file; Print | Output | — | output #14, #16–17 |
| Hide menu-bar icon; open images from Finder; Reset all settings; help links | App | — | prefs #4, #19–21 |
| Dashed lines; counter styles/start number; per-tool color memory; Rasterize | Editor | — | editor #6, #8, #15, #22 |

## Already at parity or ahead

Launch at login; rebindable shortcuts (17 vs 8); delayed capture; crosshair/magnifier/freeze; capture any window;
fullscreen under the pointer; append capture; OCR from a hotkey and in the editor; filename template; PNG/JPEG/1×;
share sheet; basic pins; spotlight, highlighter, text, shapes, counter, blur/pixelate, undo/redo; rotate/flip (Shottr has none).

## Not recommended

Licensing/trial UX, telemetry, the native `screencapture -i` grabber option.
