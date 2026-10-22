# Shottr 1.9.3 vs Skreener: Measuring, color, OCR, QR, zoom, overlay compare

Sources used: strings from the Shottr arm64 binary (`cap/strings.txt`, `tools/allstrings.txt`), imported symbols (`cap/nm.txt`), `otool -L`, editor/preferences nib dumps (`tools/editor_nib.txt` plus `strings` on `/Applications/Shottr.app/Contents/Resources/**/*.nib`), and the shottr.cc homepage changelog (fetched 2026-10-22). REA/Hopper could not start (Spotlight cannot find Hopper), so there is **no decompiled code**. Every algorithm detail below is *inferred* from strings, symbols and docs.

Labels: **[obs-bin]** = string or symbol seen in the binary or nib; **[obs-web]** = stated on shottr.cc; **[inf]** = inferred.

## Gaps summary

| # | Feature | Shottr | Skreener | Effort |
|---|---------|--------|----------|--------|
| 1 | Pixel ruler with auto edge detection (keys 1/2 or arrows; Shift = outer size; click to imprint) | yes | **missing** | M–L |
| 2 | Guide lines (Opt+S vertical / Opt+D horizontal, click to imprint) | yes | **missing** | S |
| 3 | PX / PT toggle for sizes (P key, click the size box) | yes | **missing** (the overlay shows points only) | S |
| 4 | Editor color picker: Tab = pixel color, Shift+Tab = darkest color in 20 px, C = average color of the selection | yes | **missing** | S–M |
| 5 | Color formats: HEX, HEX without #, CSS rgba, RGB 0–1, Android 0xFF…, UIColor, C# Color.fromArgb, OKLCH | yes | **missing** | S |
| 6 | Live pixel-color readout box in the editor toolbar | yes | **missing** | S |
| 7 | Contrast checker for the selection (WCAG 2.0 + APCA, Opt+Click to switch) | yes | **missing** | M |
| 8 | Tab while editing a text label inserts the color under the cursor | yes | **missing** | S |
| 9 | Capture loupe shows pixel color | probably (inf) | **partial**: the loupe shows coordinates, no color | S |
| 10 | OCR from a hotkey (area) → clipboard | yes | **present** | – |
| 11 | OCR in the editor (whole image / area, ⌘O) | yes | **present** (Copy Text, ⇧⌘T) | – |
| 12 | QR code reading in the same OCR flow | yes (CIDetector QR) | **missing** | S |
| 13 | OCR primary language setting (≈30 languages, incl. CJK) | yes | **missing** (Vision default) | S |
| 14 | OCR "Remove line breaks" (button on the toast plus a default setting) | yes | **missing** | S |
| 15 | OCR feedback: "No text detected", "Area is too large", OCR warming up, permissions | yes | **partial** (beep in capture mode, toast in the editor) | S |
| 16 | Editor zoom: ⌘1 fit, ⌘0 100 %, ⌘2 zoom to selection, Q/W zoom to the selection's corners, Z+click / Z+drag, up to about 1550 % | yes | **partial** (Fit/25–400 % menu, ⌘/pinch, max 800 %, smoothed pixels) | S–M |
| 17 | Pixel-exact rendering at high zoom (nearest neighbour) | yes (inf, `setMagnificationFilter:`) | **missing** (base image is drawn with default interpolation) | S |
| 18 | Magnifier annotation (M): zoomed-in callout | yes (v1.9) | **missing** | M (editor area, cross-ref) |
| 19 | Image overlay from the clipboard with transparency (key 5) to compare | yes | **partial** (Add Image layer exists, no opacity) | S |
| 20 | "Before/After" 2-frame GIF from overlay + screenshot | yes | **missing** | S |
| 21 | OCR-indexed screenshot library search | yes | cross-area (output/library agent) | – |

---

## 1. Pixel ruler with auto edge detection
**What Shottr does**
- Tool "Ruler (1 or 2)" in the editor tool list (`ruler`, icon `20-measure-lite-sf`, class `ObjRuler`, `_TtC6Shottr5Ruler`) [obs-bin].
- Hint text in the editor: "Hold a ⓵ or ⓶ key, or an arrow key, and move your mouse over the area which you want to measure" [obs-bin, nib].
- From the docs: ↑/↓ measure vertical size and ←/→ horizontal size. Move the mouse into a gap between two objects to measure the gap. **Shift** gives an element's outer size. Click to imprint the measurement on the screenshot [obs-web].
- Setting key `ruler:sensitivity` [obs-bin]: an edge-detection colour tolerance [inf]. Helper `detectBG(rect:maxSamples:)` sits next to it [obs-bin]. It probably samples the background colour around the cursor [inf].
- Algorithm [inf]: from the cursor pixel, walk left and right (or up and down) until the pixel colour differs from the start colour by more than the sensitivity. The run length is the measured distance. Shift keeps walking across the first edge to the next background edge, which gives the outer size.

**Skreener**: missing. `AnnotationEditor.swift` has no ruler tool (tool keys are V A R F O L P H T N X B S, README.md:12).

**Suggested implementation**
- Add a `RulerScanner` (pure Swift, unit-testable) over the editor's base `CGImage`:
  - Copy the pixels once into a `[UInt8]` RGBA buffer, using `CGContext` with `CGImageAlphaInfo.premultipliedLast` in sRGB.
  - `func span(from p: (x, y), axis: .horizontal|.vertical, tolerance: Int, outer: Bool) -> (start, end)`: compare each channel's abs difference (or ΔE) against the start pixel. When `outer` is set, skip the first run of different colour and stop at the next return to the background colour.
- In `CanvasView`, while the 1/2 or arrow key is held (`keyDown`/`keyUp`, `flagsChanged` for Shift), update the span on `mouseMoved`. Draw a 1-px line with end caps and a pill label "123 px" (or pt).
- On click, append an `Annotation` of a new kind `.measure(start, end)` that renders like the live preview, so it stays editable and exports.
- Add a sensitivity slider in the Annotate settings (default tolerance about 10/255).

**Acceptance criteria**
- On a flat 100-px-wide coloured box, holding 1 (or ←/→) with the pointer inside shows "100 px". Holding 2 shows the box height.
- Pointer in the gap between two boxes 40 px apart: "40".
- Shift with the pointer inside a bordered button gives the outer width, including the border.
- Clicking imprints a measurement that can be selected, moved and deleted, and shows in the export.
- Unit test: synthetic `CGImage` → `RulerScanner` returns the exact spans.

## 2. Guide lines
**Shottr**: Opt+S shows a vertical guide and Opt+D a horizontal one. Click imprints it (v1.5.2) [obs-web].

**Skreener**: missing.

**Approach**: while the modifier+key is held, draw a full-height or full-width 1-px dashed line at the pointer. On click, add a `.line` annotation spanning the image.

**Acceptance**: Opt+S follows the mouse vertically, and clicking leaves a line from the top edge to the bottom edge.

## 3. PX / PT toggle
**Shottr**
- Segmented control "PX | PT" (`scRulerPixels`, `editorSetRulerPixels:`) and a switch "Show Size in Logical Points" (`swPixelsPoints`, setting `setting-realPixels`) [obs-bin].
- Help text: "One logical point is equal two physical pixels on Retina displays. Use shortcut P to switch modes." [obs-bin].
- "Click to switch PX/PT" on the size box. The toolbar shows the image size, e.g. `5160×2880px` [obs-bin].
- The docs say sizes default to logical pixels on Retina [obs-web].

**Skreener**: missing. `SelectionOverlay.swift:280` shows `W × H` in points only. The editor shows no image size.

**Approach**
- Store `pixelsPerPoint` on the editor document (the capture's `backingScaleFactor`, or the image `pixelsWide` / `size.width`).
- Add a Preferences bool `showPhysicalPixels`.
- Use one formatter for the ruler, the selection size and the toolbar size label. P toggles it.

**Acceptance**: on a Retina capture of a 100-pt box, the ruler reads 100 pt or 200 px after pressing P, and the setting persists.

## 4. Editor color picker (Tab / Shift+Tab / C)
**Shottr** [obs-bin unless noted]
- "Hover mouse over any pixel and press Tab".
- "Press Shift+Tab to copy the darkest color in the 20px area around the cursor".
- "Select an area and press C to copy its average color".
- Menu or labels "Copy Pixel Color", "Copy Text Color", "Copy Average Color".
- Functions `avgColorFast(selection:mode:)`, `editorPickColor:`, `colorCopyString`, `colorDisplayString`, class `ColorPicker`, toast "Copied to the clipboard".
- The docs suggest zooming in first [obs-web].

**Skreener**: missing. No colour sampling anywhere in `Sources/Skreener` (grep for sampler / pixel colour / average colour found nothing).

**Approach**
- Reuse the RGBA buffer from §1.
  - `pixel(at:)`.
  - `darkest(in: 20×20 px)`: lowest relative luminance.
  - `average(in: rect)`: for speed use `CIFilter.areaAverage()` (CoreImage `CIAreaAverage`) rendered to a 1×1 bitmap, or sum the buffer.
- Keys in `CanvasView.keyDown`:
  - Tab copies the pixel colour.
  - Shift+Tab copies the darkest colour.
  - C copies the average colour when a selection rectangle exists. C is now Crop in Skreener, so use C only while an area selection is active, or ⇧C.
- Copy with `NSPasteboard` as a string in the chosen format (§5) and show the existing toast (`EditorWindow.swift:492`), e.g. "#FFC200 copied".

**Acceptance**
- Tab over a pure red pixel copies `#FF0000`.
- Shift+Tab over black text on white copies a near-black value.
- An average over a half-black/half-white area gives about `#808080` (or the sRGB-averaged value; document which).
- Unit tests on synthetic images.

## 5. Color formats
**Shottr**: formats in a "Color Format" pop-up (`ddlColorFormat`, `changeColorFormat:`, setting `setting-colorFormat`) [obs-bin]. Format templates [obs-bin]:

| Format | Example |
|--------|---------|
| HEX | `#FFC200` |
| HEXno | `FFC200` |
| RGBA / CSS | `rgba(255, 194, 0, 1)` |
| RGB1 | `(1.00, 0.76, 0.00)` |
| Android | `0xFFFFC200` |
| UIColor | `UIColor(red: 1.00, green: 0.76, blue: 0.00, alpha: 1.00)` |
| CSharp | `Color.fromArgb(255, 194, 0);` |
| OKLCH | display `L% C H`, copy `oklch(L% C H)` |

- `convertColorSpaces(r:g:b:)` and `sRGBColorSpace` suggest values are converted to sRGB before formatting [inf].

**Skreener**: missing.

**Approach**
- `enum ColorFormat: String, CaseIterable { case hex, hexNoHash, cssRGBA, rgbUnit, android, uiColor, csharp, oklch }` with `func string(for c: NSColor) -> String`.
- Convert with `c.usingColorSpace(.sRGB)`. OKLCH: sRGB → linear → OKLab (Björn Ottosson matrices) → LCH.
- Add a pop-up in the editor toolbar next to the live colour box (§6) and in Settings ▸ Annotate. Store it in `Preferences`.

**Acceptance**: unit test that sRGB (1, 0.76, 0) produces each exact template string above, and that OKLCH for `#FFC200` matches a reference converter to 2 decimals.

## 6. Live pixel-colour box
**Shottr**: toolbar shows a colour swatch plus value (`boxColor`, `labelColor`, `clickableColorBox`, `colorBoxClicked:`, placeholder `#FFFFFF`). The zoom box shows e.g. `100%` / `1550%` (`clickableZoomBox`, `labelZoom`) [obs-bin]. Clicking the colour box opens the format choice [obs-web].

**Skreener**: missing.

**Approach**: a small pill in the editor footer or toolbar, updated on `mouseMoved` with the pixel under the pointer. Clicking it shows the format menu.

**Acceptance**: moving over the image updates the swatch and text live, and the value matches the Tab result.

## 7. Contrast checker
**Shottr**
- Labels "WCAG 2.0 Contrast Ratio: " and " APCA Contrast Ratio: " [obs-bin].
- Tooltip: "Contrast ratio within the selection box. W3C accessibility guidelines recommend WCAG contrast ratio of at least 4.5 for regular text and 3.0 for large text and UI elements." [obs-bin].
- Setting `setting-contrastType`, outlets `ltextContrast` / `ltextbgContrast` [obs-bin].
- Opt+Click toggles WCAG/APCA [obs-web].
- How it works [inf]: within a selection, it takes the text colour (darkest, or the less frequent colour cluster; `ColorMagic.dominantColorFrequencies`) and the background colour (most frequent).

**Skreener**: missing.

**Approach**
- On area selection in the editor, compute the two dominant colours: a histogram on colours quantized to 4 bits per channel, taking the most frequent as the background and the most distant frequent colour as the foreground.
- WCAG: `(L1+0.05)/(L2+0.05)` with sRGB relative luminance.
- APCA: SAPC-APCA 0.0.98G constants.
- Show "4.6:1 AA" in the selection size pill, and let Opt+Click switch to APCA (Lc 75).

**Acceptance**: black text on white gives 21:1 (APCA Lc ≈ 106). `#777` on white gives about 4.48:1 and is marked as failing AA.

## 8. Tab while editing a text label inserts colour
**Shottr**: v1.5.0, while editing a text label, Tab adds the colour under the cursor to the label text [obs-web].

**Skreener**: missing.

**Approach**: in the text annotation's field editor, intercept `insertTab:` and insert the formatted colour of the pixel under the mouse.

**Acceptance**: while typing a label, hovering over red and pressing Tab inserts `#FF0000` at the caret.

## 9. Capture loupe colour
**Shottr**: no capture-time loupe strings found. Its magnification happens in the editor [inf].

**Skreener**: **partial**. `SelectionOverlay.swift:302-337` draws a 15×15 cell loupe at 9× with coordinates only.

**Approach**: read the centre pixel from `snapshot` (a `CGImage`) and add a swatch plus hex to the pill. Optionally, Tab during area selection copies the colour and cancels.

**Acceptance**: the loupe pill shows `x, y · #RRGGBB` and the value matches the editor picker.

## 10–11. OCR (hotkey and in editor)
**Shottr**
- Menu "Recognize Text/QR". Editor button "Recognize Text or QR (⌘O)" [obs-bin].
- Flow: select an area → text copied. Messages [obs-bin]:
  - "Text copied to the clipboard"
  - "Text without line breaks copied"
  - "No text detected"
  - "Selected area seems to be empty"
  - "Area is too large" / "Select a smaller area and try again"
  - "OCR is still running" / "OCR is not ready yet"
  - "The first run after a system update or language change can take a minute or two…"
  - screen-recording permission prompts
- Uses `VNRecognizeTextRequest` with `setRecognitionLevel:`, `setRecognitionLanguages:`, `setMinimumTextHeight:`, `setRevision:`, `supportedRecognitionLanguagesForTextRecognitionLevel:revision:error:`. Also `ocr(cgImage:fast:onReady:)`, which suggests a fast-level pass is used somewhere (likely library indexing) [obs-bin / inf].
- `VNRecognizedText.boundingBox(for:)` is imported [obs-bin].

**Skreener**: **present**.
- `TextRecognizer.swift:8-22` (`.accurate`, language correction on).
- Hotkey Capture Text ⌃⇧2 (`AppDelegate.swift:372,449-458`).
- Editor Copy Text / Copy Text from Area ⇧⌘T (`AnnotationEditor.swift:720-754`) with a toast.
- Redact via OCR (`TextRecognizer.boxes`).

Skreener lacks: QR (§12), languages (§13), the line-break option (§14), and clear messages in hotkey mode (§15).

## 12. QR code reading
**Shottr**: the same OCR flow also reads QR codes. It imports `CIDetector`, `CIDetectorTypeQRCode`, `CIDetectorAccuracyHigh`, `CIQRCodeFeature`, `messageString` [obs-bin]. Only QR (no other barcodes) [inf: no `VNDetectBarcodesRequest` symbol]. Prompt: "select the area containing the text or QR code" [obs-bin]. The result is probably copied as text, with no auto-open [inf: no QR-specific "open" string].

**Skreener**: missing (no CIDetector or barcode code).

**Approach**
- In `TextRecognizer.recognize`, run a `VNDetectBarcodesRequest` alongside the text request on the same `VNImageRequestHandler`. It covers QR plus EAN, Code128, Aztec, PDF417 and DataMatrix, which goes beyond Shottr.
- If any `payloadStringValue` exists, put it first (or alone) in the result.
- If the payload is a URL (`NSDataDetector` .link), show a toast "QR link copied" with an **Open** button.
- Keep the editor toolbar label "Copy Text / QR".

**Acceptance**
- Capture Text over an on-screen QR code for `https://example.com` copies exactly that URL.
- A toast or notification offers Open.
- A screenshot with both text and QR copies the QR payload (document the choice).
- Unit test: generate a QR with `CIFilter.qrCodeGenerator()`, render it, and recognise it.

## 13. OCR language
**Shottr**: Preferences ▸ Advanced "Primary OCR language" (`ddlPrimaryOCR`, `setting-primaryOCRLang`, default English) [obs-bin]. List [obs-bin]:
- English, French, Chinese (zh-Hans/zh-Hant, yue), Italian, Spanish, German, Portuguese (pt-BR), Korean, Japanese, Ukrainian, Russian ("Cyrillic"), Thai, Vietnamese, Arabic, Arabic (Najdi), Turkish, Indonesian, Czech, Danish, Dutch, Norwegian (no/nn/nb), Malay, Polish, Romanian, Swedish, Finnish, Hindi, Marathi.

The chosen language is probably placed first in `recognitionLanguages`, with English kept as a fallback [inf from the repeated "zh-Hans zh-Hant en-US" groupings].

**Skreener**: missing (Vision default languages only).

**Approach**
- Settings ▸ General (or Screenshots) pop-up "Text recognition language", filled from `try VNRecognizeTextRequest().supportedRecognitionLanguages()` (macOS 12+), plus "Automatic".
- Set `request.recognitionLanguages = [primary, "en-US"]`. For Automatic, set `request.automaticallyDetectsLanguage = true` (macOS 13+).

**Acceptance**: with Chinese selected, a capture of Chinese text copies the correct characters. With English it may garble them, which matches Shottr's own note.

## 14. Remove line breaks
**Shottr**: setting "OCR line breaks: Remove line breaks" (`cbRemoveBreaksOCR`, `setting-ocrRemoveBreaks`) plus a button on the result toast. Toast: "Text without line breaks copied" [obs-bin, obs-web v1.7.0]. v1.8.1 avoids double spaces [obs-web].

**Skreener**: missing (`TextRecognizer.swift:19` always joins with `\n`).

**Approach**
- Add a `TextRecognizer.join(lines:, keepBreaks:)` helper.
  - Join with a space and collapse runs of whitespace.
  - Join a hyphen-wrapped word ("exam-\nple") without a space.
  - For CJK, join without a space.
- Add a Preferences bool, plus an action button on the editor toast "Without line breaks" that re-copies.

**Acceptance**: a two-line paragraph is copied as one line with a single space. A unit test covers the hyphen and CJK cases.

## 15. OCR feedback messages
**Shottr**: see §10. The messages tell the user why nothing was copied.

**Skreener**: **partial**. The hotkey path beeps on empty (`AppDelegate.swift:458`). The editor has a toast.

**Approach**: post a user notification or a small HUD from the hotkey path: "Copied N lines", "No text found", "Copied QR: …".

**Acceptance**: a Capture Text area over blank space shows "No text found" instead of only a beep.

## 16–17. Editor zoom and pixel-exact rendering
**Shottr** [obs-web, obs-bin]
- Main-menu items "Zoom In / Zoom Out / Zoom To 100% / Zoom To Fit / Zoom To Selection / Magnifier". Selectors `menu:ZoomTopLeft`, `menu:ZoomBottomRight`.
- Shortcuts:
  - ⌘1 fit, ⌘0 100 %, ⌘± zoom in/out
  - ⌘2 zoom to selection; Q / W zoom to the selection's top-left / bottom-right corner (for precise edge checks)
  - Z+click zoom in at a spot, Z+drag zoom to an area
  - Space+drag or right-drag to pan
- Settings:
  - "Zoom with mouse wheel" (`enableMagicMouseZoom`) and "Reverse scroll direction" (`altZoomDirection`)
  - "Default zoom level: Prefer 100%"
- The zoom label shows up to `1550%` in the nib placeholder.
- `setMagnificationFilter:` is used, which points to nearest-neighbour pixels at high zoom [inf].

**Skreener**: **partial**.
- Zoom pop-up Fit/25/50/100/200/400 % (`EditorWindow.swift:566-629`).
- ⌘+wheel and pinch zoom.
- `maxMagnification = 8` (`EditorWindow.swift:447`).
- The base image is drawn with default interpolation (`AnnotationEditor.swift:1091`), so it blurs at 800 %.
- No zoom to selection, no Q/W, no Z tool, no Space-pan in the editor (Space-pan is in capture only).

**Approach**
- Raise `maxMagnification` to 16–32.
- Before `base.draw`, set `NSGraphicsContext.current?.imageInterpolation = magnification >= 2 ? .none : .high`.
- Add a 1-px pixel grid when the zoom is 8× or more.
- Add menu items ⌘0 / ⌘1 / ⌘2 using `scroll.magnify(toFit:)` on the selection rect.
- Add Q/W to center the selection's corners at 8×.
- Z+click/drag as a temporary zoom tool, and Space+drag pan (the cursor becomes an open hand).

**Acceptance**
- At 1600 % the pixels are crisp squares and a grid shows.
- ⌘2 with a crop or selection active fills the view with it.
- Q jumps to the top-left corner at high zoom.

## 18. Magnifier annotation (cross-area: editor)
**Shottr**: tool "Magnifier (M)" (`ObjMagnifier`, icon `20-lens-sf`, `accMagnification`), v1.9: a zoomed-in callout [obs-bin, obs-web].

**Skreener**: missing.

**Approach**
- New `Annotation` kind `.magnifier(source: CGRect, dest: CGRect, zoom)`.
- Render: a circle or rounded rect at `dest`, clipped, drawing the base image's `source` scaled with nearest neighbour, a border, and an optional connector line to the source.
- Handles move the lens and change the zoom.

**Acceptance**: pressing M and dragging over small text creates a 2–4× round callout that stays editable and exports.

## 19–20. Image overlay compare and Before/After GIF
**Shottr** [obs-bin, obs-web]
- "Image overlay takes the image from the clipboard". Key 5 turns on transparency (`overlayBlendMode`).
- "For better result, align overlay and the background using the transparency mode."
- "Before/After" GIF: "creates an animation of two alternating frames: the image overlay, and the screenshot under the overlay." Uses `saveGIF(img1:img2:delay:urlFolder:)` and the editor button `btnGIF`.

**Skreener**
- **partial**: Add Image from clipboard ⌘V as a movable layer (README.md:12).
- No opacity or difference mode.
- `GIFExporter.swift` exists for recordings.

**Approach**
- Image annotations get an `opacity` property: key 5 toggles 50 %, and the style bar gets a slider.
- Optionally add a "Difference" blend (`CIDifferenceBlendMode`) to highlight changes.
- "Export Before/After GIF" (shown when an image layer is selected): frame A = base with the layer hidden, frame B = flattened with the layer at 100 %. Write it with the existing `GIFExporter` (or `CGImageDestination` with `kUTTypeGIF`, delay about 1 s, loop 0) to the save folder, then show Quick Access.

**Acceptance**
- After pasting an image, 5 makes it semi-transparent so it can be aligned.
- The GIF action creates a looping 2-frame GIF in the save folder that alternates the two images.

## 21. Cross-area notes (not my lane)
- The library indexes screenshots with OCR (`ocr(cgImage:fast:onReady:)`, URL/domain regexes, `lib-tool-28-ocr`) for search. This is for the output/library agent.
- "Instant Text/QR Recognition" has its own global shortcut (`vInstantOCRHolder`). Skreener already has ⌃⇧2.
- Background removal uses `VNGenerateForegroundInstanceMaskRequest`. This is for the editor agent.

## Verification and suggested order
- Re-checked on resume: `EditorWindow.swift:447` sets `maxMagnification = 8`. `TextRecognizer.swift:19` always joins lines with `\n`. Neither `CIDetector` nor `VNDetectBarcodesRequest` appears anywhere in `Sources/`. The only `imageInterpolation = .none` is the capture loupe (`SelectionOverlay.swift:321`); the editor base image does not use it.
- Suggested order (most value for the least work first):
  1. QR (§12)
  2. Remove line breaks (§14)
  3. OCR language (§13)
  4. Nearest-neighbour zoom plus ⌘0/⌘1/⌘2 (§16–17)
  5. Color picker plus formats plus live box (§4–6)
  6. Overlay opacity (§19)
  7. Ruler (§1–3)
  8. Contrast (§7)
  9. Magnifier (§18)
  10. Before/After GIF (§20)
