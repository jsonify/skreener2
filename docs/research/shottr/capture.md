# Shottr 1.9.3 vs Skreener: Capture modes and triggers

Sources: binary strings/field dumps from the earlier extract (`allstrings.txt`, `fields.txt`),
Preferences storyboard NIB strings (`/Applications/Shottr.app/Contents/Resources/Preferences.storyboardc`), shottr.cc home
page and /kb/faq (fetched 2026-10-22). REA session was not used (no binary re-open). Shottr was not launched.
URL scheme, after-capture chooser, hotkey reassign guide and scrolling prefs are covered in detail by the prefs report
(`prefs.md` #1, #2, #6, #14); they are only cross-referenced here.

## Gaps summary

| # | Feature | Skreener | Priority |
|---|---------|----------|----------|
| 1 | Area selection stays adjustable after the drag, then Enter/double-click to capture (Shottr's crop-style area capture) | **partial** (only in the Record Screen picker; plain Capture Area captures on mouse-up) | High |
| 2 | Area keyboard modifiers: Shift = square; arrows move the selection 1/10 px; ⌘+arrows resize 1/10 px; `[` `]` grow/shrink all sides | **partial** (arrows nudge the pointer, Space moves; no square lock, no resize keys) | High |
| 3 | "A" = auto-fit the selection to content (⌥ previews the fit) | **missing** | Med |
| 4 | Capture Active Window (frontmost window, no click; falls back to picking) | **missing** | Med |
| 5 | Fullscreen-then-crop workflow (fullscreen opens straight into crop; editor at 80 %/100 % zoom) | partial | Low-Med |
| 6 | Editor/preview opens on the display the capture came from | **partial** (editor uses `NSScreen.main`) | Med |
| 7 | Dimensions readout in logical vs physical pixels (click to toggle) | partial (points only) | Low |
| 8 | Scrolling capture upward (separate "Scrolling Capture (Up)" item and URL `grab/scrolling/reverse`) | **missing** | Low-Med |
| 9 | Scrolling: speed, max height (default 20,000, up to 200,000 px), reverse auto-scroll | partial (fixed 30,000 px) — see prefs #14 | Low |
| 10 | Capture cursor: Auto / Include / Exclude | partial (on/off) | Low |
| 11 | Explanatory errors instead of a beep ("No area to repeat…", "No windows are present, try fullscreen", "Shottr wasn't able to scroll…") | **missing** (beep + NSLog) | Med |
| 12 | Repeat Area Capture | **present** (in memory only, not kept across relaunch) | Low |
| 13 | Capture Any Window (interactive) | **present** (Space toggles area/window) | — |
| 14 | Delayed screenshot | **present** (Skreener stronger: 3/5/10 s for area/window/fullscreen; Shottr only fullscreen 3 s) | — |
| 15 | Crosshair + magnifier + W×H label, freeze screen | **present** (Shottr's custom grabber has full-screen guide lines; freeze is "experimental" there) | — |
| 16 | Fullscreen capture of the display under the pointer | **present** | — |
| 17 | Global hotkeys (Shottr default only ⌘⇧2 area; others unset) | **present** (Skreener has defaults for all, rebindable) | — |
| 18 | Menu-bar items | mostly present; missing Active Window, Scrolling (Up), Manual Scrolling toggle | Low |
| 19 | URL scheme capture triggers (`shottr://grab/area?then=…`) | **missing** — see prefs #1 | High |
| 20 | Append a capture to the current screenshot (`grab/append`) | **present** (editor Add Image → Capture Area) | — |
| 21 | Choice of area grabber: native `screencapture -i` vs custom | n/a (not recommended) | — |

---

## 1. Adjustable area selection before capture — PARTIAL (High)

**Shottr:** area selection works like a crop: after the drag the rectangle stays on screen and can be refined with keys
(#2, #3) before it is taken. The FAQ says it was "built around the fullscreen cropping workflow": it shoots the whole
screen, then you crop (observed, shottr.cc/kb/faq). `CropTool` fields `selection, suggestion, mmode, mouseDownSelection`
and `CurtainWindowController`/`winOverlay` (observed, fields.txt) support this; General prefs "After Area Crop, show:
Thumbnail / Editor" (`rbAreaPreview`/`rbAreaEditor`, observed NIB).
**Skreener:** `SelectionOverlay.swift` `mouseUp` (~line 226) captures right away. The adjustable rectangle (8 handles,
move, arrows, typed W×H, presets, mode bar with Area/Fullscreen/Window/Timer/OCR) exists only in
`RecordAreaPicker.swift` (~lines 82, 643–760), which Record Screen opens.
**Implementation:** add `Preferences.adjustAreaBeforeCapture` (default on, matching CleanShot/Shottr). When it is on,
`captureArea` uses the `RecordAreaPicker` selection view in screenshot mode: Return or a double-click inside captures,
Esc cancels. Or factor its `SelectionView` (handles, drag kinds) out into a shared type that `SelectionOverlay` uses
after mouse-up. Keep the frozen snapshot so the crop comes from the frozen frame.
**Acceptance:** drag → the rectangle stays with handles; dragging a handle resizes; Return captures exactly the shown
rect (verified against the W×H label); Esc cancels with nothing captured; with the pref off, behavior is unchanged.

## 2. Area selection keyboard modifiers — PARTIAL (High)

**Shottr (observed, shottr.cc):** Shift while dragging = square; arrows move the selection 1 px, Shift+arrows 10 px;
⌘+arrows resize 1 px, ⌘⇧+arrows 10 px; `[` / `]` grow the selection by 1 px per side (Shift: 10 px). The string
`Sb5shift_Sb7commandSb6optionSb7control` (observed) shows a modifier tuple in the selection code.
**Skreener:** `SelectionOverlay.swift` `keyDown` (~231–243): arrows move the *pointer* 1/10 pt (`nudgePointer`), and
holding Space moves the selection. There is no Shift square lock, ⌥ from-center, or resize keys. RecordAreaPicker has
arrow keys (~733) and aspect presets.
**Implementation:** in `mouseDragged`, if `.shift` is held, set `current` so that |dx| = |dy| = max (keep the signs);
if `.option` is held, keep `start` as the center. With #1 in place, map keys on the adjustable selection:
arrows → offset rect; ⌘+arrows → change width/height (right/bottom edge); `[`/`]` → `insetBy(-1)` / `insetBy(1)`;
Shift ×10. Clamp to the screen. Put the rect math in a pure helper (`SelectionGeometry.apply(key:mods:to:bounds:)`)
so `swift test` covers it.
**Acceptance:** Shift-drag gives an exact square in the label; ⌘→ grows width by 1; `]` grows both sides by 1 (W and H +2);
the rect never leaves the screen; unit tests cover each key.

## 3. Auto-fit selection to content ("A") — MISSING (Med)

**Shottr (observed site):** after selecting, "A" shrinks the selection to the content; holding ⌥ previews the result.
Evidence: `CropTool.suggestion`, `suggestionTimer`, `lsuggestion` layer, `contrast` (observed fields.txt). Inferred: it trims
uniform-colored borders inside the rect.
**Skreener:** none.
**Implementation:** in a pure function on the frozen `CGImage` crop, find the uniform border color (the corner pixel),
then scan rows and columns inward until a pixel differs by more than a tolerance (e.g. ΔRGB > 12). Return the tight rect.
Bind A to apply and ⌥ (flagsChanged) to draw a dashed preview. Unit-test with synthetic images.
**Acceptance:** select a button with margins on a flat background, press A → the rect hugs the button (±1 px); on a
uniform image nothing changes; ⌥ shows the preview without applying it.

## 4. Capture Active Window — MISSING (Med)

**Shottr (observed):** menu items "Capture Active Window" and "Capture Any Window" are separate. Methods `grabWindow`
vs `grabWindowInteractive`; hotkey holders `vWindowHolder` / `vAnyWindowHolder`; URL `grab/window/active`. Errors:
"Window grab failed, frontmost window: ", "No windows are present, try taking a fullscreen screenshot instead".
The site says that when the active window can't be found, you pick it manually.
**Skreener:** only interactive `captureWindow` (`AppDelegate.swift` ~468) using `CaptureService.onScreenWindows()`.
**Implementation:** new `HotKeyAction.captureActiveWindow` (no default, or ⌃⇧9) with a menu item. Take
`NSWorkspace.shared.frontmostApplication?.processIdentifier` from *before* Skreener is activated (the menu-bar click
activates Skreener, so record the frontmost app in `menuWillOpen`). Pick the first `SCWindow` in
`onScreenWindows()` (already frontmost-first) whose `owningApplication?.processID` matches, with layer 0 and
`isOnScreen`. Hand it to `CaptureService.captureWindow`. If none matches, fall back to the interactive picker.
**Acceptance:** with Safari frontmost, the hotkey captures Safari's front window with the configured shadow/background
and no picker; from the menu it still captures the previously frontmost app; with only the desktop showing, the picker opens.

## 5. Fullscreen-then-crop workflow — PARTIAL (Low-Med)

**Shottr:** fullscreen capture opens the editor where you crop. Advanced "Prefer 100 %" (`cbLargerWindow`,
`setting-preferLargeWindow`): "Area Capture will open the editor at 100 % zoom when possible, and Fullscreen Capture will
open the editor at 80 % zoom" (observed). `KeyToRenderFullscreen` (observed).
**Skreener:** Capture Fullscreen → editor (zoom-to-fit) and crop tool C exist (`EditorWindow.swift`); no "open in crop mode"
option.
**Implementation:** optional `Preferences.fullscreenOpensCrop`: after a fullscreen capture, open the editor with the crop
tool active and the canvas at 80 % zoom. Low priority, since #1 covers the main need.
**Acceptance:** with the option on, fullscreen capture → the editor opens with crop handles ready; Return crops.

## 6. Editor opens on the capture's display — PARTIAL (Med)

**Shottr (observed site):** "the editor opens on the screen where the screenshot was taken"; it keeps `lastActiveScreen`
and `lastActiveTime` (observed fields).
**Skreener:** `EditorWindow.swift` ~296 centers on `NSScreen.main`. QuickAccess uses the screen under the pointer
(`QuickAccess.swift` ~39), which is close.
**Implementation:** pass the source `NSScreen` (it is known in `handle(_:)`/`captureFullscreen`) through `finish(_:)` into
`EditorWindowController.present(on:)`, and center on that screen's `visibleFrame`. Use the pointer's screen for opened files.
**Acceptance:** with two displays, capturing on the secondary opens the editor there, even when the menu bar/key
screen is the primary.

## 7. Logical vs physical pixel readout — PARTIAL (Low)

**Shottr (observed site):** Retina sizes show in logical px by default; clicking the size box shows physical px. Setting
`setting-realPixels` (observed). DPI detection for mixed Retina/non-Retina setups.
**Skreener:** the selection label shows points (`SelectionOverlay.swift` ~280). Capture is per-screen at `backingScaleFactor`,
so mixed DPI already works.
**Implementation:** show `W × H` plus a dimmer `(2W × 2H px)` when `screen.backingScaleFactor > 1`, or toggle with Tab.
**Acceptance:** on Retina, a 100×50 pt drag shows "100 × 50 (200 × 100 px)".

## 8. Upward scrolling capture — MISSING (Low-Med)

**Shottr (observed):** menu "Scrolling Capture (Up)", `grabScrollingUp`, `grabScrolling(direction:method:then:)`, URL
`grab/scrolling/reverse`; manual mode "Start Scrolling (Up or Down)" and "Manual Scrolling Capture" item
(`itemScrollingManual`, `setting-scrollingManualEnabled`). Autoscroll banner: "Select the area and let Shottr scroll
automatically… press Escape" (observed).
**Skreener:** `ScrollCapture.swift` auto-scroll only goes down (doc comment ~389); the stitcher follows scrolling back up but
does not build upward (`ScrollStitcher.add`, ~55–100). It starts manual, with an Auto-Scroll button, so the manual/auto split
is already covered.
**Implementation:** add `direction` to `ScrollStitcher`. For upward capture, either flip frames vertically before matching
and flip the result back (the simplest reuse of the matcher), or prepend instead of append. Add an Auto-Scroll Up
action posting negative wheel deltas. **Acceptance:** start at the bottom of a long page, Auto-Scroll Up → the stitched image
matches a downward capture of the same page (unit test with flipped synthetic frames).

## 9. Scrolling speed / max height / reverse — PARTIAL (Low)
See prefs report #14. Observed extra: site says max height defaults to 20,000 px, adjustable up to 200,000; the error
"You can change scrolling height limit in the app preferences"; and "Shottr wasn't able to scroll… If you're running a
scroll-modificator app (MOS, Scroll Reverser, Smooze, etc), try setting Reverse Scrolling Capture direction…".
Skreener: `ScrollStitcher.maxHeight = 30_000` (`ScrollCapture.swift:23`). Suggest a Settings field and a "limit reached" message.

## 10. Capture cursor: Auto / Include / Exclude — PARTIAL (Low)

**Shottr (observed):** URL `settings/capturecursor/auto|include|exclude`, `setting-captureCursor`. Inferred: Auto includes
the cursor in fullscreen/delayed captures and leaves it out of area/window captures.
**Skreener:** `Preferences.showCursor` bool (`Preferences.swift:49`) applied in `CaptureService.makeConfig`.
**Implementation:** make it an enum `CursorMode { auto, always, never }`, migrating the bool (true → always). Pass
`showsCursor` per capture type in `AppDelegate` (fullscreen and timers: auto → true; area/window: auto → false).
**Acceptance:** Auto: a fullscreen capture shows the pointer and an area capture does not; Always/Never apply everywhere.

## 11. Explanatory capture errors — MISSING (Med)

**Shottr (observed strings):** "No area to repeat — Repeat Area Capture takes a screenshot of the previously captured area.
You need to perform the area capture first."; "No windows are present, try taking a fullscreen screenshot instead";
"Area capture failed"; "Selected area seems to be empty"; "Shottr needs permission to record the screen" + steps;
"Scrolling Capture requires accessibility permissions. Go to System Preferences…"; "Shottr wasn't able to scroll".
**Skreener:** `capturePreviousArea` and `run(_:)` just `NSSound.beep()` + `NSLog` (`AppDelegate.swift` ~268, ~520).
**Implementation:** a small `CaptureMessage.show(title:detail:)` HUD (the same dark capsule style as the scroll bar) near the
pointer for 3 s. Use it for no previous area, capture failure (with a Screen Recording hint when
`!CGPreflightScreenCaptureAccess()`), no window under the click, and scroll limit reached.
**Acceptance:** fresh launch → Capture Previous Area shows "Capture an area first" instead of a silent beep; with
permission revoked, a capture shows a message with an "Open Privacy Settings" hint.

## 12. Repeat Area Capture — PRESENT
Shottr: `grabAreaRepeat`, menu "Repeat Area Capture", `interactive-repeat`, hotkey `vRepeatHolder`, URL `grab/repeat`;
`interactive(…repeatArea:dontRememberArea:…)` (observed). Skreener: `capturePreviousArea` ⌃⇧1, `lastArea` in memory
(`AppDelegate.swift:10, 267`). Optional: persist `lastArea` (display ID + rect) in UserDefaults so it survives a relaunch.

## 13. Capture Any Window — PRESENT
Shottr: `grabWindowInteractive`, `interactive-window`; inferred: uses `/usr/sbin/screencapture` (strings "screencapture
returned weird data", "Can't create temp directory", regex "capture window.+0x([0-9a-f]+)"). Window background
Wallpaper / Solid / Transparent / Trim shadow → prefs report #13. Skreener: `captureWindow` + Space toggle in `SelectionOverlay`.

## 14. Delayed screenshot — PRESENT (Skreener stronger)
Shottr: `grabDelayed`, menu "Delayed Screenshot (3s)" (fullscreen only; URL `grab/delayed=10` per docs). Skreener:
`SelfTimer.swift`, Self-Timer submenu (area/window/fullscreen, 3/5/10 s).

## 15. Overlay visuals (crosshair, magnifier, size label, freeze) — PRESENT
Shottr custom grabber `RegionSelector` has `lguideH1/H2/V1/V2` guide lines, a size text layer, `screenFreeze`/`frozenImg`,
and state `selectingScreen/dragging/scrolling`; the default area grabber may be macOS's (`setting-areaCustomGrabber`,
"experimental screen-freezing area capture" per FAQ). Skreener: `SelectionOverlay.swift` crosshair (~291), loupe (~303),
W×H label, `Preferences.freezeScreen`. Shottr's Magnifier (`ObjMagnifier`) is an editor annotation (cross-area: editor).

## 16. Fullscreen — PRESENT
Shottr `fullscreen14(cursor:screen:)` with "No matching display found" (observed): the display under the cursor. Skreener
`captureFullscreen` uses the screen under `NSEvent.mouseLocation`. Neither offers an "all displays stitched" mode.

## 17. Global hotkeys — PRESENT
Shottr uses the KeyboardShortcuts package. Recorders: Fullscreen, Area, Repeat area, Active window, Any window, Scrolling,
Instant OCR, Show Shottr (observed NIB). The only documented default is ⌘⇧2 = area (site). The others are inferred unset,
plus a guide to move macOS ⇧⌘3/⇧⌘4 into Shottr (prefs #6). Skreener: `Shortcuts.swift` `defaultCombo` (~214) gives
⌃⇧1–8, H for all capture actions. Rebinding and conflict warnings already exist.

## 18. Menu-bar menu — mostly PRESENT
Shottr items (observed): Fullscreen Screenshot, Area Capture, Repeat Area Capture, Capture Active Window, Capture Any Window,
Scrolling Capture, Scrolling Capture (Up), Manual Scrolling Capture, Delayed Screenshot (3s), Recognize Text/QR, Load From
Clipboard, Launch at Startup, plus links. Skreener (`AppDelegate.buildMenu`, ~74–125) has the equivalents except Active
Window (#4) and Scrolling Up (#8).

## 19. URL scheme triggers — MISSING (see prefs #1)
Capture commands (docs + strings): `grab/fullscreen`, `grab/area`, `grab/repeat`, `grab/window`, `grab/window/active`,
`grab/scrolling`, `grab/scrolling/reverse`, `grab/delayed[=N]`, `grab/append`, `ocr`, each with `?then=copy,save,edit,pin,thumbnail`.

## 20. Append capture — PRESENT (cross-area: editor)
Shottr `grab/append` ("Take a screenshot before adding a capture to it"). Skreener: the editor's Add Image → Capture Area
(`EditorWindowController.captureArea`, `AppDelegate.swift` ~67, ~488).

## 21. Native vs custom area grabber — not recommended
Shottr appears to let you choose macOS's `screencapture -i` or its own selector (`areaCaptureMode`, `areaCustomGrabber`,
`scrollingCustomGrabber`; inferred). Skreener's own overlay is already the better option; no action.

---

## Manual test plan (for implemented gaps)
1. Build: `Scripts/build_app.sh --run`.
2. #1/#2: press ⌃⇧4, drag a rect, release → the rect stays with handles. Hold Shift while dragging → the label shows equal W and H.
   Press → → the rect moves 1 pt; ⌘→ → width +1; `]` → W and H +2. Press Return → the editor shows exactly that area.
3. #3: select around a button on a flat background, press A → the rect tightens to the button.
4. #4: click into Safari, press the Active Window hotkey → Safari's window is captured with no picker.
5. #6: with two displays, capture on the secondary → the editor opens on the secondary.
6. #11: relaunch, press ⌃⇧1 → a HUD says to capture an area first.
