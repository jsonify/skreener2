# Shottr 1.9.3 vs Skreener: Editor and annotation tools

Status: COMPLETE. The REA session had no binary open, so the extra evidence came from the shell extracts only (see "Addendum").

Evidence sources (all read-only):
- `allstrings.txt`: Shottr binary strings. Includes the instrument table at lines ~5555-5660 (`arrow|Arrow (A)|20-arrow-sf|...`).
- `fields.txt`: Swift field metadata (class/struct stored properties and Codable `Dump` keys for every annotation object).
- `editor_nib.txt`: decoded Preview storyboard nib (editor attribute bar, export segments, tooltips).
- `backdrop.txt`: decoded Backdrop nib.
- `Base.lproj/Main.storyboardc/MainMenu.nib`, decoded with `tools/nib.py` (menu titles and key equivalents).

All of these extracts are in a temporary scratch folder (not kept).

How evidence is labeled:
- **Observed** means the text is literally in the binary or nib.
- **Inferred** means it was deduced from names or structure. It was not confirmed by running Shottr, which was not launched.

Skreener files:
- `Sources/Skreener/AnnotationEditor.swift`: `Tool` enum and shortcuts (lines 4-39), `Style` (47-72), `Background` (76-131), `CanvasView`.
- `Sources/Skreener/EditorWindow.swift`: toolbar, attributes bar (`buildAttributesBar` ~693), background bar (~766), crop bar, footer.

## Gaps summary

| # | Feature (Shottr) | Skreener | Priority |
|---|---|---|---|
| 1 | Smart **Erase** (fill the area with the surrounding background color), plus **Erase Text** and **Blur Text** that act only on the text found inside a box | **missing** (Skreener has pixelate/blur boxes, plus OCR "Redact" of all text/emails/phones/links) | High |
| 2 | **Magnifier** object (M): a lens showing a zoomed copy of an area, circle or rect, with border and pointer line | **missing** | High |
| 3 | **Hand-drawn style** for arrows, rects and ovals (seeded jitter); arrow types line, shape, hand-drawn and double; curved arrows (midpoint handle) | partial (filled/open/double straight arrows only) | Med |
| 4 | Freehand **shape correction**: a drawn stroke snaps to a clean line, rect, oval or blob; pressure/speed-based width; smoothing | **missing** (pen is a raw polyline) | Med |
| 5 | Fill modes for rect/oval: transparent (outline only), translucent, opaque, plus a border toggle | partial (Skreener has Rectangle and Filled Rectangle as separate tools; no translucent fill; no filled oval) | Med |
| 6 | Dashed lines (`dash`) / dotted line option | **missing** | Low-Med |
| 7 | Text styles: a callout **with a pointer tail** (`pointy`: draggable tail side/position/distance), a "goofy" handwritten font (Chalkboard SE), a background box toggle (`nobg`), max-width wrapping | partial (fonts, size and bold; no background box, no callout tail, no wrapping width) | Med |
| 8 | Counter styles (`style` Int) and a manually settable start number (`count`) | partial (one badge style; auto-renumbers by creation order) | Low |
| 9 | **Image overlay** (paste an image as an object) and a **"Before/After" GIF** made from overlay and background, with an overlay transparency toggle for alignment | partial (Add Image exists; no transparency toggle, no Before/After GIF) | Low-Med |
| 10 | **Cut Out** (selection bar, scissors icon). Two readings: (a) lift the subject / remove the background via `VNGenerateForegroundInstanceMaskRequest` + `CIBlendWithAlphaMask` (strings observed); (b) remove a strip (`cutterMoveResize`). See the Addendum | **missing** | Med |
| 11 | **Resize image** to an exact px/pt size (W×H fields, preset sizes `scSizes`, ⇧] shortcut) | **missing** | Med |
| 12 | Crop **auto-suggestion**, **Autoadjust (A)** that shrinks the selection to content edges (`checkHomogeneitySide`, `scout`), click-to-select a region by flood fill (`floodfill-select`) (`CropTool.suggestion`) and "Hit Enter to crop"; Reset Crop / uncrop; Autoadjust (A) for the selection | partial (manual crop with handles; no suggestion) | Low-Med |
| 13 | **Snap to Objects / Snap to Similar Objects** while drawing a selection or box (`lsnap`, `setting-snappingMode`) | **missing** | Med |
| 14 | Backdrop: Solid / Colormix (mesh, linear, radial, diagonal gradients + noise + randomize) / Image (custom file, blur); padding, inset, inner and outer radius, shadow slider; **aspect presets** (1:1, 4:3, 3:2, 16:9, Twitter, Facebook, LinkedIn, YouTube, Pinterest); auto-crop; saved custom colors and gradients | partial (8 presets + wallpaper, padding/corner popups, shadow on/off) | Med |
| 15 | Per-tool color memory: separate drawing, highlighter and backdrop custom colors; 8-color drawing palette and 8-color highlighter palette | partial (one color for all tools; preset dots + More Colors) | Low-Med |
| 16 | Size slider (continuous) shared across tools; per-object size index into `widths`/`fontsizes`/`diameters` tables | partial (popups with fixed values) | Low |
| 17 | Copy and paste annotation objects within and between screenshots (`copiedString`, `copiedType`) | **missing** | Med |
| 18 | **Continuous creation**: draw several objects of the same tool without re-selecting it | present (Skreener keeps the tool after drawing) | — |
| 19 | Undo/redo with labeled states, including crop and backdrop | present (`undoStack`/`redoStack` snapshots incl. crop and background) | — |
| 20 | Tool single-key shortcuts (A T R D M H B S C O L, ruler 1/2, backdrop K) and Draw menu | present, with a different letter map (no D, M, K; C = crop in Skreener vs. counter in Shottr) | Low |
| 21 | Zoom menu: In/Out (⌘+/⌘-), Fit (⌘1), 100% (⌘0), **Zoom to Selection (⌘2)**, Selection Top Left/Bottom Right (Q/W) | partial (zoom popup, wheel/pinch; no ⌘1/⌘0/⌘2 menu items) | Low |
| 22 | **Rasterize (Merge) Image**: flatten objects into the base | **missing** (Skreener flattens only on export) | Low |
| 23 | Rotate/flip | Skreener **has more** (Shottr has no rotate strings) | — |
| 24 | Spotlight, Highlighter, Text, Line, Arrow, Rectangle, Oval, Counter, Blur/Pixelate | present (see per-feature notes for differences) | — |
| 25 | Esc copies (or saves) and closes the editor (`setting-copyOnEsc`/`saveOnEsc`); "Copy (Esc or ⌘C)" | **missing** (also listed in the prefs report, #11) | Med |
| 26 | Imprint Selection Size (stamp a W×H label onto the image) | **missing** (cross-area: measure) | Low |
| 27 | Print (⌘⇧P) and Upload from the editor | missing (cross-area: output) | — |

Cross-area items seen in the editor but owned by other researchers: Ruler (1/2), color picker helpers (pixel/text/average color, WCAG/APCA contrast), OCR (⌘O), Pin (⌘P), Upload (⌘E), Add Capture (append a second capture).

---

## Shottr editor structure (observed)

**Tool table** (strings ~5555-5660; id | tooltip | icon):
- arrow | Arrow (A)
- text | Text (T)
- ruler | Ruler (1 or 2)
- rectangle | Rectangle (R)
- backdrop | Backdrop (K)
- freehand | Freehand Drawing (D)
- magnifier | Magnifier (M)
- append (Add Capture)
- blur | Blur/Erase (B)
- highlighter | Highlighter (H)
- spotlight | Spotlight (S)
- counter | Counter (C)
- oval | Oval (O)
- line | Line (L)
- image

**Draw menu** (MainMenu.nib, plain-key equivalents):
- Arrow a, Text t, Rectangle r, Freehand Drawing d, Magnifier m, Highlighter h, Blur b, Spotlight s, Counter c, Oval o, Line l
- Add Capture
- Snap to Objects, Snap to Similar Objects

**Other menus:**
- File: Copy Image ⌘⇧C, Save ⌘S, Save As ⌘⇧S, Upload ⌘E, Pin ⌘P, Print ⌘⇧P, Open File ⌘⇧O, Open From Clipboard ⌘⇧V, Close ⌘W.
- Edit: Undo/Redo, Reset Crop, Rasterize (Merge) Image, Cut/Copy/Paste/Delete/Select All.
- Zoom: In ⌘+, Out ⌘-, To Fit ⌘1, To 100% ⌘0, To Selection ⌘2, Selection Top Left q, Selection Bottom Right w, Full Screen ⌃⌘F.

**Attribute bar outlets** (fields.txt, editor view controller; `editorSet*` actions in editor_nib):
- `sliderSize` (size slider)
- `scLineType` (16-line / 16-dash)
- `scArrowType` (arrow-shape / arrow-handdrawn / arrow-line / arrow-double), `btnArrowStyle` (16-toggle)
- `scConcealType` (Blur / Blur Text / Erase / Erase Text)
- `scFill` (objfill handdrawn / transparent / translucent / opaque)
- `scShape` (rect / oval)
- `scText` (text-sans / text-goofy)
- `scShapeCorrection` (shape-blob and others)
- `btnTransparency` (16-transparency), `btnGIF` (16-gif)
- `scRulerPixels` (PX/PT), `swPixelsPoints`
- `txtWidth`/`txtHeight` + Resize button + `scSizes`
- `colorPicker` / `btnColor`

**Selection segment tooltips** (editor_nib):
- "Autoadjust (A)", "Resize ( ⇧+] )", "Recognize Text or QR (⌘O)", "Imprint Selection Size", "Erase (Del)", "Cut Out", "Reset Selection (Esc)".
- Export segment: "Copy (Esc or ⌘C)", "Save (⌘S)", "Pin to Screen (⌘P)", plus "Drag'n'Drop Image".

**Object model** (fields.txt). Every object has `rect, size, color`, `knobs`, `preferredPalette` and `wantsSpotlight`, and serializes as a Codable `Dump`:
- ObjArrow `type, style, midpa, midpd, seed`: type = head shape, style = handdrawn, midp = curve control.
- ObjLine `startCap, endCap, dotted`.
- Rect/Oval base `showBorder, showBackground, backgroundAlpha, shape, handdrawn, seed`.
- ObjText `nobg, style (pointy|goofy), text, maxWidth, pPerc, pDist, pSide`.
- ObjCounter `style, count`.
- ObjConceal `fillMode` (rect|oval|pixelate|pixelate-text|erase|erase-text|line|dash).
- ObjMagnifier `factor, lensX, lensY, shape, showBorder, showBackground`.
- ObjImage `imageHash`.
- ObjFreehand `resolution, smoothing, capStyle, shapeCorrection, rawRect, pointsHash`, with `Point{weight, speed, width}`.
- ObjHighlighter `baseColor`; ObjSpotlight; ObjRuler.

Undo `State` is `{objects (JSON), selectedObj, selectionRect, cropRect, counterCount, backdropConfig}`, with labeled, debounced states.

---

## 1. Smart Erase, Erase Text, Blur Text — MISSING (High)

**Shottr.** The Blur/Erase tool (B) has a segmented mode: **Blur | Blur Text | Erase | Erase Text** (observed, editor_nib labels). Conceal fill modes are observed as `pixelate, pixelate-text, erase, erase-text`. The binary also has the strings `scanline floodfill`, `postReconceal(ctx:)` and `textRects(cgImage:onReady:)`.
- Inferred: "Erase" paints the box with the dominant surrounding/background color (flood-fill style), so it looks as if the content was never there. That is cleaner than a mosaic for UI screenshots.
- Inferred: the "…Text" variants run Vision text detection inside the drawn box and conceal only the detected glyph rects, leaving the surrounding UI intact.
- The selection-bar "Erase (Del)" applies Erase to the current selection rectangle (observed tooltip).

**Skreener.** It has `.pixelate` (X) and `.blur` (B) boxes (`AnnotationEditor.swift` renderShape `.pixelate`/`.blur`). OCR-based Redact via `TextRecognizer.Sensitive` (`redact(_:)` ~line 680) creates pixelate boxes per text line for the whole image. There is no erase or background fill, and no per-box text-only mode.

**Approach.**
- Add `Tool.erase` (or a `concealMode` on Style: blur, pixelate, erase, plus a `textOnly` flag).
- Erase: sample the 1-px border ring of the rect in `baseCG`, take the most frequent color (quantize to 5 bits per channel) and fill the rect with it. Optionally, where the ring is not uniform, fill per row/column by interpolating left/right edge colors.
- Text-only: on mouse-up, run `VNRecognizeTextRequest` (already used by `TextRecognizer`) on the cropped region. Store the returned observation rects in the annotation (`subRects`) and render the conceal only inside them, padded by 2 px.

**Acceptance.**
- On a solid-color UI, Erase leaves no visible seam.
- Erase Text over a paragraph inside a card blurs only the text lines, not the card's border.
- Both stay editable (move/resize) and are undoable.
- Resizing a text-only box re-runs detection.

## 2. Magnifier — MISSING (High)

**Shottr.** Magnifier (M) is observed in the tool table and Draw menu. `ObjMagnifier` has `factor, lensX, lensY, lensRect, shape, showBorder, showBackground`, with layers `lmagnifier, lmagborder, lmagline` (observed).
- Inferred: you draw the source area, and a lens (circle or rect, by `shape`) shows it enlarged by `factor`. The lens is placed at an offset (`lensX/lensY`) and can be dragged separately. A connector line joins the source to the lens.

**Skreener.** None.

**Approach.**
- Add `Tool.magnifier`. The annotation holds `start/end` (the source rect) plus a `lensCenter` and `factor` (default 2×; popup 1.5/2/3/4).
- Render by clipping to the lens path (oval or rounded rect) and drawing `baseCG` with a transform that maps the source rect, scaled by the factor, onto the lens. Then stroke the border in the style color and draw a line between the nearest edges.
- Two drag targets: the source rect handles, and the lens body.

**Acceptance.**
- Drawing a small rect creates a lens showing that area at 2× nearby.
- The lens and the source move independently.
- The export matches the canvas.
- Changing the factor, color or shape works on a selected magnifier.

## 3. Arrow variants (hand-drawn, curved, line/shape types) — PARTIAL (Med)

**Shottr.**
- Observed: `scArrowType` icons are arrow-shape, arrow-handdrawn, arrow-line and arrow-double, plus a `btnArrowStyle` toggle.
- Observed: `ObjArrow` stores `type, style, midpa, midpd, center, radius, reversed, arrProfiles(w1,w2,h), seed, rnd`.
- Inferred: `midpa`/`midpd` are the angle/distance of a midpoint handle that bends the arrow into an arc (center/radius), and `seed`/`rnd` give a stable hand-drawn wobble. "shape" is a tapered filled arrow (profiles w1→w2), and "line" is a stroke with a chevron head.

**Skreener.** `ArrowStyle` is filled, open or double, and arrows are straight only (`AnnotationEditor.swift` ~41, renderShape `.arrow`).

**Approach.**
- Add a `curve: CGFloat` (signed perpendicular offset of the midpoint) and a third handle at the midpoint. Build a quadratic Bezier, and take the head angle from the tangent at the end.
- Add `ArrowStyle.tapered`: a filled polygon whose width grows from 0.3·w to w along the shaft.
- Add a `handDrawn: Bool` with a stored `seed`. Perturb path points with seeded noise (`GKMersenneTwisterRandomSource(seed:)`) so the shape is stable across redraws.

**Acceptance.**
- Dragging the mid handle bends the arrow, and the head follows the tangent.
- The hand-drawn look is identical after save/undo/redo.
- Hit-testing follows the curve.

## 4. Freehand smoothing and shape correction — MISSING (Med)

**Shottr.**
- Observed: `ObjFreehand` fields `smoothing, variability, resolution, capStyle, shapeCorrection, lockDirection, realtimeShape`, with `Point{weight, speed, width}`.
- Observed: `scShapeCorrection` segment (icons include 16-shape-blob) and action `editorSetCorrection:`.
- Inferred: strokes are smoothed, and their width varies with drawing speed. With correction on, a roughly closed stroke becomes a clean oval or rect, and a near-straight stroke becomes a line (`lockDirection`).

**Skreener.** `.pen` strokes a raw point list (`outline` for `.pen`).

**Approach.**
- On mouse-up, simplify the points (Ramer-Douglas-Peucker, ε = 1.5/zoom) and fit Catmull-Rom curves.
- Shape correction: compare the fitting error of a line, an ellipse (least squares on the points) and an axis-aligned rect. If the best error is below about 6% of the bounding diagonal, replace the stroke with that tool's annotation.
- Holding Shift while drawing locks to a straight line.

**Acceptance.**
- A shaky circle becomes an editable ellipse when correction is on, and stays a smooth stroke when it is off.
- Strokes look smooth at 400% zoom.

## 5. Fill modes for shapes — PARTIAL (Med)

**Shottr.**
- Observed: `scFill` with transparent / translucent / opaque / hand-drawn.
- Observed: rect/oval fields `showBorder, showBackground, backgroundAlpha`.
- Observed: `scShape` (rect | oval) inside the same tool, so Rectangle and Oval share fill options.

**Skreener.**
- `.rect`, `.filledRect` (F) and `.ellipse` are separate tools.
- There is no filled or translucent ellipse, and no translucent rect.
- The corner radius popup applies to rects (`hasCorners`).

**Approach.**
- Replace `filledRect` with `Style.fill: none / translucent (alpha 0.3) / solid`, applied to rect and ellipse. Keep F as a shortcut that selects Rectangle with solid fill.
- Add a fill pill to the attributes bar when the tool is rect or ellipse.

**Acceptance.**
- All three fills work on both shapes and apply to a selected shape.
- Old documents open with the same appearance (filledRect maps to solid).

## 6. Dashed lines — MISSING (Low-Med)

**Shottr.** Observed: `scLineType` (16-line / 16-dash), `ObjLine.dotted`, and the conceal list includes `line` and `dash`.

**Skreener.** None.

**Approach.** Add `Style.dashed: Bool` and use `NSBezierPath.setLineDash([lw*3, lw*2])` for line, arrow shaft, rect and ellipse. Add a pill toggle.

**Acceptance.** A dashed line exports identically and can be toggled on a selected object.

## 7. Text styles: callout tail, background box, hand-written font, wrapping — PARTIAL (Med)

**Shottr.**
- Observed: `ObjText` has `nobg, style: AnnotationStyles{pointy, goofy}, maxWidth, pPerc, pDist, pSide, sharpTip, fontsizes`, with layers `lbox` (background box) and `lpointer`.
- Observed: `scText` icons text-sans / text-goofy. The storyboard references the fonts `ChalkboardSE-Light`, `HelveticaNeue` and `Helvetica`.
- Inferred: by default, text sits on a colored rounded box, with the text in a contrasting color; `nobg` turns the box off. "Pointy" adds a speech-bubble tail whose side, position along the side (percent) and length are draggable. `maxWidth` wraps the text by dragging the box's width.

**Skreener.** `.text` has font choices (System, Helvetica Neue, Avenir Next, Georgia, Menlo, Marker Felt, Chalkboard SE), a size popup and bold (`EditorWindow.swift` ~279, 706, 721). Text draws as plain glyphs with no box, no tail and no wrap width.

**Approach.**
- Add `Style.textBox: none / solid / outline`. Draw a rounded rect (radius 0.3·fontSize, padding 0.4·fontSize) in the style color, with the text in black or white by luminance (the same rule `drawCounter` uses).
- Add an optional `tail: (side, t, length)` and a tail knob drawn as a triangle merged into the box path.
- Add `maxWidth` and draw with `NSString.draw(in:)` plus a word-wrapping paragraph style; an edge handle changes the width.

**Acceptance.**
- A text label with a box is legible on any background.
- Dragging the tail knob moves the pointer.
- Wrapped text re-flows while resizing.
- The inline editor matches the rendered layout.

## 8. Counter styles and start number — PARTIAL (Low)

**Shottr.**
- Observed: `ObjCounter.style: Int`, `count: Int`, `diameters`; the undo state keeps `counterCount`.
- Inferred: counters number sequentially from a global counter, with more than one badge style (filled circle or outlined). Each counter's `count` is stored.

**Skreener.** A single filled-circle style, numbered by creation order; deleting one renumbers the rest (`drawCounter`).

**Approach.**
- Add a `counterStyle` (filled, outline, square) and an optional "Start at" field.
- Optionally offer letters (A, B, C) or Roman numerals.

**Acceptance.** Styles apply to a selection, and the start number shifts every counter.

## 9. Image overlay transparency and a Before/After GIF — PARTIAL (Low-Med)

**Shottr.**
- Observed: `ObjImage(imageHash)`, "Paste Image (", and "Image overlay takes the image from the clipboard…".
- Observed: `btnTransparency` (editorSetTransparency:) and `btnGIF` (editorGIF:).
- Observed string: ""Before/After" Gif generation — This feature creates an animation of two alternating frames: the image overlay, and the screenshot under the overlay." There is also a hint to align the overlay using transparency mode, and `saveGIF(img1:img2:delay:)`.

**Skreener.** Add Image (file, history, capture, clipboard) as a movable layer that keeps its proportions (`insertImage`, `EditorWindow` add-image menu). It has no opacity and no GIF. GIF export code exists for recordings (`GIFExporter.swift`).

**Approach.**
- Add an "Overlay opacity 50%" toggle for a selected image layer, used while aligning it.
- Add "Export Before/After GIF…": render frame 1 with the image visible and frame 2 without it, then write both with `GIFExporter`, looping with a 1 s delay.

**Acceptance.**
- With an image layer selected, the GIF alternates between the two states.
- The opacity toggle doesn't affect the normal export.

## 10. Cut Out (remove a strip) — MISSING (Med)

**Shottr.**
- Observed: the selection-bar "Cut Out" (20-scissors) and `cutterMoveResize`. Truncated menu strings "Add Brea…"/"Cut Brea…" are inferred to be "Add Break"/"Cut Break".
- Inferred: you select a horizontal or vertical band, and Cut Out removes it, shifting the rest of the image together. This shortens tall scrolling captures.

**Skreener.** None.

**Approach.**
- A Cut Out mode: drag a horizontal band (or a vertical one with ⌥).
- Build a new base image from the parts above and below the band. Shift annotations below the band by its height, and delete those wholly inside it.
- Optionally draw a zig-zag "tear" line at the join.
- Record it as a Snapshot, so it is undoable.

**Acceptance.**
- Removing a band joins the image seamlessly, and annotations below it keep their relative position.
- Undo restores everything.

## 11. Resize image — MISSING (Med)

**Shottr.**
- Observed: the "Resize ( ⇧+] )" tooltip, `txtWidth`/`txtHeight`, the "Resize" button, "px", `scSizes`, `clickResize:`, `changeWidth:`/`changeHeight:`.
- Observed errors: "New size is too large" / "New size is too small".
- Inferred: proportional resizing to pixel dimensions, with preset size buttons.

**Skreener.** None. Retina captures can be saved at 1× (Settings), but there is no resize in the editor.

**Approach.**
- Add a "Resize…" popover with W/H fields (aspect lock), percent presets (25/50/75/200) and a px/pt toggle.
- Resample the base with Core Image Lanczos (`CILanczosScaleTransform`), and scale annotation geometry, line widths and font sizes by the same factor.
- Record it as a Snapshot.

**Acceptance.**
- Resizing to 50% halves the exported pixel size, and annotations stay aligned.
- Undo works.
- The fields reject values below 8 px or above 16k px.

## 12. Crop extras — PARTIAL (Low-Med)

**Shottr.**
- Observed: `CropTool.suggestion` and `suggestionTimer`, "Hit Enter to crop", `cropToSelection`, `uncrop`, Edit → Reset Crop, "Autoadjust (A)".
- Observed: the `backdrop:autocrop` setting and `isEdgeTransparent(img:)`.
- Inferred: while hovering, Shottr suggests a crop that snaps to a detected UI region. A sets the selection to the content box.

**Skreener.** Crop mode (C) has eight handles, draggable sides, Return/Esc and Reset (`beginCrop`/`applyCrop`/`resetCrop`). It has no suggestions.

**Approach.**
- "Auto-crop to content": trim uniform-color borders by scanning rows and columns of `baseCG` for pixels within a tolerance of the corner color.
- Optionally snap crop edges to strong edges near the pointer (shares code with #13).

**Acceptance.** Auto-crop on a window screenshot with a flat margin removes the margin exactly.

## 13. Snap to Objects / Similar Objects — MISSING (Med)

**Shottr.**
- Observed: Draw menu "Snap to Objects" and "Snap to Similar Objects" (`menuSnap:`, `menuSnapSimilar:`), `ObjectHandlers.lsnap`, `setting-snappingMode`.
- Inferred: when drawing a rect, spotlight or blur box, the box snaps to the edges of detected UI elements in the screenshot. "Similar" probably creates boxes around every element similar to the one drawn (for example, blur all avatars).

**Skreener.** None.

**Approach.**
- Detect candidate rects with `VNDetectRectanglesRequest`, or simpler, by edge detection: Sobel via Core Image, then connected components for flat-filled regions.
- While dragging, if an edge of the draft is within 6/zoom pt of a candidate edge, snap it and show a guide.
- "Similar": compare candidate rect sizes (±10%) and mean color to the drawn box, then add matching boxes.

**Acceptance.**
- With snapping on, drawing roughly around a button yields its exact bounds.
- Holding ⌘ (or a setting) turns snapping off.

## 14. Backdrop depth — PARTIAL (Med)

**Shottr.**
- Observed: `Backdrop.Config{mode, colors, stops, gradStart, gradEnd, gradType, meshType, noise, padding, inset, innerRadius, outerRadius, ratio, minWidth, seed, shadowIntensity, filepath, blur}`.
- Observed UI:
  - Tabs: Solid / Colormix / Image.
  - Gradient types: Vertical, Diagonal, Radial, Mesh.
  - Sliders: Padding, Shadow, Inset, Outer Radius, Inner Radius, Image Blur.
  - Randomize, gradient from/to pickers, Recenter/Reset/Remove.
  - Aspect presets: 1:1, 4:3, 3:2, 16:9, Twitter, Facebook, LinkedIn, YouTube, Pinterest.
  - Load Backdrop File, saved custom gradients/colors/images.
  - Many built-in multi-stop gradient templates.
- Observed: the window backdrop is disabled when the capture already has a background ("Window already has backdrop").

**Skreener.** `Background{fill (8 presets + wallpaper), padding (popup 16-128), cornerRadius (popup 0-24), shadow on/off}` (`AnnotationEditor.swift` 76-131; `EditorWindow.buildBackgroundBar` ~766).

**Approach, in order of value:**
1. Aspect-ratio presets: pad the canvas to the target ratio, centering the screenshot.
2. Custom image background (file) with blur.
3. Custom 2-color gradient pickers, gradient angle/type, and a few multi-stop templates.
4. Inset (inner padding with a solid frame) and a shadow intensity slider.

**Acceptance.**
- Choosing 16:9 gives an exported image whose W:H is exactly 16:9 and which contains the full screenshot with at least the configured padding.
- Settings persist as the last-used backdrop.

## 15. Color palettes and per-tool color memory — PARTIAL (Low-Med)

**Shottr.**
- Observed: the drawing palette `#00A490,#00AFEE,#1C2B41,#F7F4E7,#FF0C01,#7758EF,#FFDC2C,#FA3C63`.
- Observed: the highlighter palette `#ADF6FF,#C2EAFE,#E6E6FF,#FFDAEF,#FFF68D,#F2FE01,#D8FF55,#DDF5C6`.
- Observed: `customDrawingColor`, `customHighlighterColor`, `customBackdropColor`, and `preferredPalette` per object.
- Inferred: the highlighter uses its own pastel palette and remembers its color separately from the other tools.

**Skreener.** A single `Style.color` (default systemRed) for all tools, in a `ColorPill` with presets plus More Colors.

**Approach.**
- Keep a per-tool last color (at least separate for the highlighter), and show the highlighter palette when it is active.
- Persist colors in `Preferences`.

**Acceptance.** Switching between the arrow and the highlighter restores each one's own color.

## 16. Size slider — PARTIAL (Low)

**Shottr.**
- Observed: `sliderSize` (`editorSetSize:`), the custom `cellSliderSize`, `labelSize`/`labelSizeDescription`.
- Observed: objects store `size: Int`, an index into per-type tables (`widths`, `fontsizes`, `diameters`).
- Inferred: one slider controls stroke width, font size, counter diameter and blur strength. Notches are per tool.

**Skreener.** Separate popups for stroke (1-12 pt), font size (12-72), strength and corners.

**Approach.** Optional: replace the popups with one stepped NSSlider bound to a per-tool table. Add ⌘[ / ⌘] or -/+ keys to step the size of the selection.

**Acceptance.** The slider changes the selection's size live and is undoable as a single step.

## 17. Copy and paste annotations — MISSING (Med)

**Shottr.** Observed: `ObjectHandlers.copiedString, copiedType`, and the objects are Codable (`Dump`). Inferred: ⌘C/⌘V on a selected object duplicates it, including into another screenshot.

**Skreener.** ⌘V pastes clipboard images as image layers (`paste(_:)`). Annotations can't be copied or duplicated.

**Approach.**
- Make `Annotation` Codable (colors as sRGB components, images as PNG data). Write a private pasteboard type `com.skreener.annotation` on ⌘C while a selection exists. On ⌘V, prefer that type and offset the pasted copy by 10 pt.
- Add ⌘D to duplicate.

**Acceptance.**
- Copying an arrow and pasting it into another editor tab gives an identical, editable arrow.
- Image pasting still works when no annotation is on the clipboard.

## 18. Continuous creation — PRESENT

**Shottr:** `continuousCreation`, `createOnClick`, `prevCreated` (observed). **Skreener:** the tool stays active after drawing (`CanvasView.tool`).

## 19. Undo/redo — PRESENT

**Shottr:**
- Observed: `Undo{states(label, full, comparable), position, tmDebounce}`. The state includes objects, selection, crop, counterCount and backdropConfig.

**Skreener:**
- `undoStack`/`redoStack` of `Snapshot{base, items, crop, background}` (AnnotationEditor ~254-270, 473-492), with ⌘Z/⇧⌘Z.
- Optional: label states for Edit menu titles ("Undo Move").

## 20. Tool shortcuts — PRESENT (different mapping)

**Shottr:** A arrow, T text, R rect, D freehand, M magnifier, H highlighter, B blur, S spotlight, C counter, O oval, L line, K backdrop, 1/2 ruler.

**Skreener** (`Tool.shortcuts`): V select, A, R, F filled rect, O, L, P pen, H, T, N counter, X pixelate, B, S, C crop.
- Consider adding D as an alias for the pen, and M for the magnifier once it exists.

## 21. Zoom commands — PARTIAL (Low)

**Shottr** (observed): Zoom In/Out ⌘+/⌘-, Fit ⌘1, 100% ⌘0, Zoom To Selection ⌘2, plus Selection Top Left (Q) / Bottom Right (W) to jump the view.

**Skreener:** the footer zoom popup (Fit/25-400%), ⌘-wheel and pinch (`EditorWindow` ~567, 604-633). There are no menu key equivalents.

**Approach.**
- Add a View menu with ⌘+, ⌘-, ⌘0 (100%), ⌘9 or ⌘1 (Fit) and "Zoom to Selection" (`magnify(toFit:)` on the selected annotation's bounds).

**Acceptance.** The shortcuts work while the canvas is first responder, and the zoom label updates.

## 22. Rasterize (Merge) — MISSING (Low)

**Shottr:** observed Edit → "Rasterize (Merge) Image".

**Approach:** set `base = flattened()` (without the background) and clear `items`, recorded as a Snapshot. This is useful before a crop or resize when you want objects baked in.

**Acceptance:** after merging, the objects can no longer be selected, and undo restores them.

## 23. Rotate/flip — Skreener ahead

Shottr has no rotate strings or menu items (observed absence in MainMenu.nib and the strings). Skreener's `reorient` (AnnotationEditor ~603-668) is extra.

## 24. Tools at parity (with notes)

- **Highlighter.** Shottr uses `ObjHighlighter.baseColor` with a pastel palette. Skreener uses a multiply blend at alpha 0.45. Parity.
- **Spotlight.** Shottr has `ObjSpotlight`, and any object can set `wantsSpotlight` (inferred: other shapes can act as spotlight cut-outs). Skreener supports rect spotlights with rounded corners only. Possible gap: an oval spotlight.
- **Line.** Shottr's `ObjLine.startCap/endCap` suggest per-end caps (arrow, dot, bar). Skreener lines have round caps and no end decorations. Minor gap.
- **Blur/pixelate.** Both have them. Shottr's blur strength comes from the shared size slider; Skreener uses a Strength popup.
- **Shadow on annotations.** Skreener has `Preferences.annotationShadow`. No Shottr equivalent was found besides the backdrop shadow.

## 25. Esc to copy and close — MISSING (Med; also in the prefs report)

**Shottr:** observed "Copy (Esc or ⌘C)" and the settings `setting-copyOnEsc` / `setting-saveOnEsc`. Pressing Esc in the editor with no selection copies the image (or saves it) and closes the window.

**Skreener:** Esc only clears the selection or cancels crop (`keyDown` ~426-436).

**Approach.** Add a Settings option, Esc with nothing selected: Do nothing / Copy & close / Save & close.

**Acceptance.** With "Copy & close" set, pressing Esc twice (once to deselect, once more) copies and closes the editor tab.

## 26. Imprint Selection Size — MISSING (Low; cross-area: measure)

Observed tooltip and `imprintSelectionSize`. Inferred: it stamps a "W × H" text annotation onto the selection. If added, it would reuse the text annotation.

---

## Open questions (not confirmed without running Shottr)

- The exact behavior of Erase (a solid fill vs. content-aware) and whether the Text variants use Vision rects. Function names to decompile: `postReconceal(ctx:)`, `textRects(cgImage:onReady:)`.
- Whether "Snap to Similar Objects" creates several objects or only snaps.
- What Autoadjust (A) does.

---

## Addendum: extra string evidence (observed, from `allstrings.txt` ~1636-1668, 2150-2165)

These function names sit next to the conceal and selection code:
- `detectBG(rect:maxSamples:)` and `avgColorFast(selection:mode:)`
- `scanline floodfill`, `floodfill-select`
- `checkHomogeneitySide(selection:start:stop:inc:vertical:ortFrom:ortTo:)`, `scout(sx:sy:vertical:persistence:)`
- `VNGenerateForegroundInstanceMaskRequest`, `CIBlendWithAlphaMask`
- `textRects(cgImage:onReady:)`, `postReconceal(ctx:)`

What they imply (inferred):
- **Erase (#1) samples the background.** `detectBG` samples the rect's surroundings for the background color and fills the rect with it. This confirms the approach in #1: sample the border ring and fill with the dominant color.
- **Autoadjust (A) (#12) trims the selection to content.** It walks each side of the selection inward (`scout`/`checkHomogeneitySide`) until the pixels stop being uniform, tightening the box to the content. Skreener could do the same for crop and for its selection rectangles. Acceptance: pressing A on a loose selection around a button tightens it to the button's edges, within 1 px.
- **Flood-fill select (#12/#13).** `floodfill-select` likely means clicking selects a uniform-color region's bounds. It may be part of the snapping feature.
- **Background removal (#10).** `VNGenerateForegroundInstanceMaskRequest` (macOS 14+) with `CIBlendWithAlphaMask` means Shottr can lift the foreground subject and make the rest transparent. This is most likely what "Cut Out" (scissors) does.
  - Skreener approach: an Image → "Remove Background" command. On macOS 14+, run `VNGenerateForegroundInstanceMaskRequest` on `baseCG`, then `generateMaskedImage(ofInstances:from:croppingToInstances:false)`. Replace the base, recorded as a Snapshot. Hide the command on older systems.
  - Acceptance: a photo of an object on a background exports as PNG with a transparent background, and undo restores the original.
  - The strip-removal idea (`cutterMoveResize`) remains a separate, still useful feature for tall scrolling captures. Its existence in Shottr is less certain.

## Open questions (still unconfirmed; REA had no binary open)

- Whether "Snap to Similar Objects" creates several objects or only snaps.
- Which of the two readings of "Cut Out" is the shipped behavior. The Vision strings make background removal the likelier one.
