# Skreener -> Windows: feature inventory and port analysis

Author: Port Analyst. Stack-agnostic: nothing here assumes C++/C#/Rust/Electron/Tauri. Source of truth is the code in
`Sources/Skreener` (17,475 LOC, 51 files) and `Tests/SkreenerTests` (25 files); `README.md` was used as the checklist.
Windows API facts are from general knowledge and were NOT verified in this Linux session (no Windows, no web): anything
marked **[verify]** needs a spike before it is relied on.

Caveats about the source itself:
- `TODO.md` marks 97 of 103 items `[~]` ("written, not yet compiled/tested on macOS"), only 6 `[x]`. The macOS code is the
  spec but much of it has never been confirmed on a Mac, so "does what the code says" is not proof of "works".
- Not implemented anywhere (TODO `[ ]`): Do-Not-Disturb while recording (#23), Studio Mode (#24), webcam overlay (#25),
  live stitched preview (#28), upload to S3/custom endpoint (#33), CleanShot-style default hotkeys (#35). Out of scope here.
- Complexity key (re-implementing on Windows, one competent dev, assuming the UI toolkit/2D engine is chosen):
  **S** <= 2 days, **M** ~ 1 week, **L** 1-3 weeks, **XL** > 3 weeks or research-grade risk.
- LOC are physical lines of the listed files (some files are shared across features, so rows overlap).

---------------------------------------------------------------------------------------------------------------------

## 1. Feature inventory

### 1.1 Capture (screenshots)

| Feature | Source files (LOC) | Complexity | Notes |
|---|---|---|---|
| Fullscreen capture (per display) | `CaptureService.swift` 151 (`captureScreenImage` :32-54), `AppDelegate.swift` 796 (`captureFullscreen` :395) | M | Mixed-DPI + multi-monitor is the cost, not the grab itself. |
| Area capture (drag, then capture) | `SelectionOverlay.swift` 623, `SelectionGeometry.swift` 106, `CaptureService.swift`, `AppDelegate.swift` (`captureArea` :613, `handle(_ sel:)` :673, `run` :733, `finish` :750) | L | See 1.2 for the overlay. |
| Capture Previous Area | `AppDelegate.swift` `capturePreviousArea` :383-394, `lastArea` | S | Stores (screen, rect); must survive monitor changes (:384 checks `NSScreen.screens.contains`). |
| Window capture (hover tint, click captures whole window even if covered) | `CaptureService.swift` `captureWindow` :92-105, `onScreenWindows` :133-150; `SelectionOverlay.swift` `drawWindowHighlight` :550-575; `AppDelegate.swift` `pickWindow` :636 | XL | Z-order hit-testing + occluded-window capture + alpha corners. See 4.2. |
| Window capture options: shadow, transparent/white background, padding | `CaptureService.swift` `decorateWindow` :108-129; `Preferences.swift` :319-343 | M | Pure image compositing; needs a shadow blur primitive. |
| Capture Active Window (no picking) | `AppDelegate.swift` `captureActiveWindow` :648-672, `lastOtherApp` tracking :92-99 | M | Windows: `GetForegroundWindow`, but must remember "previous foreground" when the tray menu itself took focus. |
| Freeze screen while picking | `SelectionOverlay.swift` `begin` :48-66 (grabs every display first), `CaptureService.crop` :79-83, `pixelRect` :86-90 | M | Overlay shows a still; final crop comes from the still. |
| Self-timer 3/5/10 s (area/window/fullscreen) | `SelfTimer.swift` 82, `AppDelegate.swift` `timedArea` :557, `timedWindow` :570, `timedFullscreen` :552 | S | Countdown window + temporary global Esc (`SelfTimer.swift:48`). |
| Capture Area & Pin | `AppDelegate.swift` `captureAreaAndPin` :400-417 | S | Composition of area capture + pin. |
| Cursor in capture toggle | `CaptureService.swift` :11-17 (`showsCursor`), `Preferences.swift` :71 | S | WGC cursor flag **[verify]** (`IsCursorCaptureEnabled`, Win10 2004+). |
| Hide desktop icons (toggle, or only while capturing) | `ImageSource.swift` `DesktopIcons` :22-39 (shells out to `defaults`/`killall Finder`), `AppDelegate.swift` `prepareCapture` :364-380, `toggleDesktopIcons` :327 | S | Windows: toggle via the shell's icon visibility (`SHGetSetSettings`/registry `HideIcons` + refresh, or a `SysListView32` show/hide) **[verify]**. macOS waits a fixed 1.0 s (:368). |
| Open image / Open from Clipboard / Pin file / Pin clipboard | `ImageSource.swift` :5-20, `AppDelegate.swift` :335-362 | S | File dialog + clipboard bitmap (CF_DIB(V5)/PNG). |
| "All-in-One" picker (choose action after selection) | `AppDelegate.swift` `allInOne` :456, `RecordAreaPicker.swift` (shared with record) | L | Shares the Record picker UI; not in README but in menu (`AppDelegate.swift:111`). |
| Save/copy pipeline: filename template, unique names, PNG/JPEG, Retina->1x | `Output.swift` 126 (`filename` :36-59, `uniqueURL` :61-69, `copy` :71, `save` :78, `saveAs` :95), `Preferences.swift` :41-70 | S | Mostly pure; encode/clipboard are the platform parts. |
| Share sheet | `Output.swift` `share` :116-125 (`NSSharingServicePicker`) | M | Windows Share contract (`IDataTransferManagerInterop`) needs a window handle; unpackaged apps are awkward **[verify]**. |

### 1.2 Area selection overlay

| Feature | Source (LOC) | Complexity | Notes |
|---|---|---|---|
| One borderless overlay per display, crosshair cursor, dimming, hint banner | `SelectionOverlay.swift` 623 (panels :63-90, `drawHintBanner` :4-16) | L | Layered/topmost per-monitor windows, mixed DPI. |
| Pixel magnifier + live size readout | `SelectionOverlay.swift` (uses snapshot taken at `begin` :55-65), `Preferences.swift` :81 | M | Needs a pre-grab of each display (an extra full capture per display on every hotkey press). |
| Arrow-key nudge (Shift = 10), Space = move selection, Shift = square, Option = from centre | `SelectionGeometry.swift` `apply` :24-48, `dragRect` :67-86 | S (logic done) / M (input plumbing) | Option -> Alt on Windows; Alt key handling in a topmost window needs care. |
| Adjust before capture: handles, move, Cmd+arrows resize, wheel grows/shrinks, Return/double-click capture, Esc cancel | `SelectionGeometry.swift` `resize` :90-98, `move` :101-105, `resizeAllSides` :52-56, `rounded` :60-63; `SelectionOverlay.swift` handles ~:578+ | M | Cmd+arrows -> Ctrl+arrows. |
| Mode cycle (Space: area -> window -> scrolling) | `SelectionOverlay.swift` `Mode.next(in:)` :33-36 | S | Pure. |
| Selection survives across screens ("new selection on another screen replaces") | `SelectionOverlay.swift` `selectionStarted` :117 | S | |

### 1.3 Scrolling capture

| Feature | Source (LOC) | Complexity | Notes |
|---|---|---|---|
| Manual scroll capture: dashed frame, control panel, grab ~8 fps, stitch | `ScrollCapture.swift` 627 (`ScrollStitcher` :11-163, `ScrollCaptureController` :166-627), `ScrollMatcher.swift` 163 | L | Algorithms portable (section 3); frame loop :238-268; max stitched height 30,000 px (:27). |
| Auto-Scroll (inject scroll events, adaptive speed, overshoot take-back, end detection) | `ScrollCapture.swift` `toggleAutoScroll` :331-371, `scrollTick` :382-393, `autoScrollStep` :395-471, `post` :504-519 | XL | Event injection is the hard part (4.3). State machine is ~140 lines of tuning heuristics. |
| Sticky header/footer de-duplication | `ScrollStitcher.add` :55-103, `ScrollMatcher` header/footer :82-97 | M | Pure logic, tests cover only the matcher (no `ScrollStitcher` test exists). |
| Overlay scroll-bar tolerance (ignore right 16 px) | `ScrollCapture.swift` :257 (`16 * backingScaleFactor`), `ScrollStitcher.init(ignoreRight:)` :43 | S | Scale factor assumption: integer Retina. |

### 1.4 Recording and GIF

| Feature | Source (LOC) | Complexity | Notes |
|---|---|---|---|
| Record area / window / fullscreen to H.264 MP4, 30/60 fps, bitrate heuristic, <= 4096x2304 clamp | `ScreenRecorder.swift` 241 (config :58-75, writer :79-101, clamp :18/:52-56), `RecordingController.swift` 272 | XL | WGC/DXGI + Media Foundation; see 4.5. |
| Pause / resume (retimes later samples) | `ScreenRecorder.swift` `setPaused` :134-147, `retimed` :193-210 | M | Timestamp rebasing is portable logic. |
| System audio and microphone, mixed to one AAC track | `ScreenRecorder.swift` :71-75, :93-101, :158-166, `AudioMixer.swift` 102 | XL | WASAPI loopback + capture, drift/silence handling, mux. |
| Record GIF (MP4 -> 15 fps, <= 960 px wide, looping) | `GIFExporter.swift` 32 (:10-31), `RecordingController.swift` | M | Needs a GIF encoder with good quantization (ImageIO does it for free on Mac; WIC GIF encoder is weak **[verify]**). |
| Record picker (area/window/fullscreen, size entry, aspect presets, mode bar, Record GIF / Video, OCR/screenshot/timer from the same bar) | `RecordAreaPicker.swift` 876 | L | Largest single UI file after the editor; reuses overlay patterns. |
| Recording options (countdown, dim screen, cursor, frame rate, time in menu bar, remember last selection) | `RecordingController.swift` (dim :162-180, frame :181-198, HUD :199-251), `Preferences.swift` :236-318 | M | "Time in menu bar" (`AppDelegate.swift:76`) has no Windows tray equivalent (4.8). |
| Click highlight rings and keystroke display baked into the video | `RecordingEffects.swift` 180 | L | Needs global input hooks + an overlay that IS captured while other UI is not (4.4). |
| Recording HUD (timer, pause, stop; dashed frame) and menu-bar stop button | `RecordingController.swift` :199-251, `AppDelegate.swift` `recordingChanged` :527-548 | M | |
| Trim (no re-encode, GIF rebuilt from trimmed MP4) | `RecordingTrimmer.swift` 155 (`keptRange` :12-21, export :24-, `AVPlayerView` trim UI :65-103) | L | Need a player with a trim bar (none built into most Windows UI stacks) and lossless cut on keyframes **[verify]**; the macOS passthrough export may snap to keyframes too. |

### 1.5 Annotation editor

All of the following are in `AnnotationEditor.swift` (2,497 LOC, the `CanvasView`) unless noted; windowing/toolbar/footer in
`EditorWindow.swift` (1,602), tabs/dock in `EditorTabs.swift` (401), pill controls in `PillButton.swift` (326).

| Feature | Source | Complexity | Notes |
|---|---|---|---|
| Document model: `Tool` (17 cases :4-8), `Style` (:74-135), `Annotation` (:175-260); select/move/resize/recolor/duplicate/reorder; undo/redo (:826-860) | `AnnotationEditor.swift` | L | Model is mostly data; entangled with `NSColor/NSImage/NSBezierPath`. |
| Drawing tools: arrow (filled/open/double/tapered, bendable), rect, filled rect, ellipse, line, pen, highlighter (multiply), counter, text (solid/outlined/bubble, inline editing :1620-1738) | `AnnotationEditor.swift` Drawing :1950-2257, Inline text :1620; `StrokeShapes.swift` 176; `ArrowLabel.swift` 19 | XL | 2D engine with beziers, blend modes, rich text layout; hand-drawn style (`StrokeShapes.handDrawn` :88). |
| Pen smoothing and shape recognition (stroke -> ellipse/rect/line) | `StrokeShapes.swift` `simplify` :14, `smoothPath` :35, `fit` :61 | M | `fit`/`simplify` are pure (CGPoint); `smoothPath/handDrawn` return `NSBezierPath`. |
| Pixelate, blur (Gaussian via CoreImage), erase, spotlight, magnifier | `AnnotationEditor.swift` blur cache :2452-2466; Erase :2291; Magnifier :2310; spotlight in Drawing | L | Blur = need a Gaussian (Direct2D effect / Skia / custom). |
| Text Only mode for pixelate/blur/erase (OCR finds the lines in the box) | `AnnotationEditor.swift` :2258-2290, `TextRecognizer.lineBoxes` :61-85 | M | Depends on OCR line boxes. |
| Smart Erase (fill with ring's dominant colour) | `SmartErase.swift` 58 | S | Pure. |
| Snap to objects, Repeat on Similar Objects | `AnnotationEditor.swift` :650-740, `ObjectSnap.swift` 186, `PixelBuffer.swift` 133 | M | Pure image-processing; the similar-search is O(W*H*w*h) on a downscale, perf-sensitive. |
| Pixel ruler (hold 1/2/arrows), measure, colour picker, copy colours in HEX/CSS/RGB/UIColor/Android/OKLCH..., contrast WCAG2/APCA | `AnnotationEditor.swift` :1311-1521, `RulerScanner.swift` 48, `ColorFormat.swift` 74, `Contrast.swift` 70, `PixelBuffer.swift` | M | Pure math; "UIColor" format is iOS-specific but trivial to keep. |
| Crop (8 handles), rotate/flip, resize to exact px, Cut Out strip | `AnnotationEditor.swift` Crop :1522-1619, Rotate :1011-1086, Resize/CutOut :1087-1197; `ImageOps.swift` 102; `ResizeForm.swift` 120 | M | `ImageOps` limits (8..16384 px) and cut maths are pure. |
| Remove Background | `ImageOps.swift` `removingBackground` :78-92 (Vision `VNGenerateForegroundInstanceMaskRequest`) | XL | No OS equivalent on most Windows machines (see 2, 4.9). |
| Background tool (gradients, solid, wallpaper, custom image + blur, aspect presets incl. social sizes, padding, inset, radii, shadow) | `Background.swift` 244 (`canvas(around:)` :90, wallpaper :163-170, blur :185-198) | M | Aspect/canvas maths pure; wallpaper lookup differs. |
| Add Image layer (capture area, history, file, paste) | `EditorWindow.swift` :1385-1420 | S | |
| Copy/paste annotations between screenshots | `AnnotationClipboard.swift` 47 | S | Uses a token on the pasteboard + in-memory store; trivially portable. |
| Document persistence (annotations stay editable per history capture) | `EditorDocument.swift` 109 (JSON + `base.png` + `img-<id>.png` in a `<capture>.skreener` folder) | M | JSON schema should be frozen and shared across platforms if cross-OS docs matter. |
| Tabs, dock of thumbnails, move tab to new window, merge windows | `EditorTabs.swift` 401, `EditorWindow.swift` | L | Custom tab row; "dock" can be left of the canvas or right (`Preferences.swift:172`). |
| Zoom/pan (wheel, Shift-wheel, Cmd-wheel, middle-drag, pinch) | `AnnotationEditor.swift` Mouse :427-649 | M | Pinch -> touchpad precision gestures (WM_GESTURE/pointer API) **[verify]**. |
| Drag Me (drag exported file out; app hides during drag) | `EditorWindow.swift` `DragPill` :88-160 (hides app :114) | M | OLE `DoDragDrop` with `CF_HDROP`/virtual files from a temp file (`Output.temporaryFile` :105). |
| Esc-with-nothing-selected action, per-tool single-key shortcuts | `Preferences.swift` :190, `AnnotationEditor.swift` :12-13 (`V A R F O L P H T N X B E S M`) | S | |
| Export: Save, Save As, copy, drag, overwrite-keeps-format | `Output.swift`, `EditorWindow.swift` | S | |

### 1.6 OCR

| Feature | Source (LOC) | Complexity | Notes |
|---|---|---|---|
| Capture Text (area -> OCR -> scratch pad) | `TextRecognizer.swift` 106 (`recognize` :7-22), `TextScratchPad.swift` 145 (Join Lines :98-124), `AppDelegate.swift` `captureText` :585-612 | M | Windows.Media.Ocr is available but lower quality; language packs. |
| Editor Copy Text (all or dragged area) | `AnnotationEditor.swift` :1229-1310 | S | |
| Redact (all text / emails / phones / links -> pixelate boxes) | `TextRecognizer.boxes` :24-59 + `matches` :87-102, `AnnotationEditor.swift` :1198-1228 | M | `NSDataDetector` phone/link detection has no Windows built-in (use regex + a phone lib). |
| Search-by-text index of the save folder | `Library.swift` `recognizeText` :204-214 | M | Background OCR of every image; perf and battery. |

### 1.7 Quick Access overlay

| Feature | Source (LOC) | Complexity | Notes |
|---|---|---|---|
| Stacked thumbnail previews in a screen corner (220 pt wide), hover buttons (copy, save, edit, pin, share, close), 65 % resting alpha, suspend while capturing | `QuickAccess.swift` 495 (panel :119-125, `QuickAccessCard` :328+, `suspend/resume` :86-100, `PreviewHover` :317-326) | L | Topmost non-activating layered windows; position vs taskbar/work area (`visibleFrame` :171). |
| Swipe-to-dismiss vs drag-file-out classification | `QuickAccessGesture` :293-315 | S | Pure. |
| Recording preview (first frame via `AVAssetImageGenerator` :69; Open/Show in Finder/Trim) | `QuickAccess.swift` :53-84, :214 | M | Thumbnail extraction via Media Foundation / Shell thumbnail. |
| Drag preview to another app as a file | `QuickAccess.swift` :481 | M | OLE drag-drop. |

### 1.8 Pinned screenshots

`PinnedScreenshot.swift` 340: borderless always-on-top (`.floating` :36), drag to move, wheel = opacity (:103), pinch/Cmd+wheel = zoom (:112), toolbar on hover, right-click menu (50/100/200 %, copy, edit, save, share), pin at exact captured rect (:21-24), drag handle (:298-336). **Complexity M.** Topmost layered window, per-pixel alpha + opacity; trivial once the overlay window primitive exists.

### 1.9 History / library

| Feature | Source (LOC) | Complexity |
|---|---|---|
| Capture History panel (slides from top, History + Saved Files views, hover actions, multi-select, drag-out, context menu, tile size) | `CaptureHistory.swift` 816 (`CaptureHistoryPanel` :151+, panel level :242-246, dismissal monitors :622-631, drag :663/784) | L |
| History store (PNG in Application Support, limit/prune, per-capture editor document) | `CaptureHistory.swift` `CaptureHistory` enum :12-149 | S |
| Thumbnails (ImageIO downsample; Quick Look for video/other) | `CaptureHistory.swift` :101-135 (`QLThumbnailGenerator` :121) | M (Windows Shell thumbnail provider `IShellItemImageFactory`) |
| Saved-files index with search/filters (app, month, kind, edited), FS watcher, JSON meta in Application Support | `Library.swift` 236 (watcher `DispatchSource` :78/:112, filter :217-229, counts :231) | M |
| Which app was in front when saved (search facet) | `AppDelegate.swift` :758, `lastOtherApp` :27 | S (needs process name/exe description on Windows) |

### 1.10 Settings, preferences, permissions

| Feature | Source (LOC) | Complexity |
|---|---|---|
| Settings window (General, After Capture, Shortcuts, Screenshots, Screen Recording, Annotate, About) | `SettingsWindow.swift` 717 (panes :23-47), `Preferences.swift` 347 (~55 prefs, `UserDefaults` :39) | L |
| Permissions status panel (Screen Recording, Accessibility, Microphone, with "Open System Settings") | `Permissions.swift` 54, `AppDelegate.swift:104` | S -> mostly N/A (4.7) |
| After-capture actions: copy / save / editor / Quick Access / pin; sounds; confirmation none/notification/HUD | `AppDelegate.swift` `finish` :750-788, `Notifier.swift` 225, `Preferences.swift` :63-70,:152-160,:185 | M |
| Menu bar item with full command menu, per-action key equivalents | `AppDelegate.swift` `buildMenu` :107-168, `updateMenuShortcuts` :227 | M |
| App menu bar (Edit/Image/Window menus for editor) | `AppDelegate.swift` `buildMainMenu` :251-326 | M (Windows editor needs its own menu or ribbon) |

### 1.11 Shortcuts

| Feature | Source (LOC) | Complexity |
|---|---|---|
| Global hotkeys (Carbon), rebindable, reports "unavailable" if taken | `HotKeys.swift` 97 (`RegisterEventHotKey` :19, `UnregisterEventHotKey` :28, handler :35-42), `ShortcutCenter` :48-96 | M |
| Shortcut model/store/defaults/conflict rules (`KeyCombo`, `HotKeyAction`, `ShortcutStore`, `problem(with:)` :284) | `Shortcuts.swift` 335 | M (model portable, key-code table and modifier semantics are macOS-specific) |
| Shortcut recorder UI, suspends registration while listening (`ShortcutCenter.suspended` :59) | `ShortcutRecorder.swift` 374 | M |
| macOS-system-shortcut conflict list and "hand over Shift-Cmd-3/4" wizard (reads `com.apple.symbolichotkeys`) | `Shortcuts.swift` :124-148, :300-335 | N/A -> replace with a Windows reserved-hotkey list (PrintScreen, Win+Shift+S, etc.) |
| Default bindings: Ctrl+Shift+1..9, H | `Shortcuts.swift` :221-230 | S (Ctrl+Shift+digit may collide with IME/layout switch on Windows **[verify]**) |

### 1.12 URL scheme (automation)

`URLCommand.swift` 151 (grammar :35-80, `parse` :82-121), dispatch `AppDelegate.swift` :174-220 (`openLink`, first-use allow prompt :193, `perform` sets `linkActions`/`linkDelay` then calls the hotkey handler), registration `Scripts/build_app.sh:45-47` (`CFBundleURLTypes`). **Complexity S** for the parser (pure), **M** for registration + single-instance hand-off + running as an unpackaged vs packaged app.

### 1.13 Updater

`Updater.swift` 256: GitHub "latest release" JSON (:51-64), numeric version compare (:33-47), SHA256SUMS check (:66-80), daily timer (:91-100), prompt/Later/Release Notes (:130-148), download+verify+swap+relaunch (:160-255). **Complexity L** on Windows, mostly because of signing/replacement (4.10).

### 1.14 Notifications

`Notifier.swift` 225: `UNUserNotificationCenter` toast with click -> reveal file (:42-57, delegate :88-105), in-app `MessageHUD` (:108-225, panel :179-185), error messages with "Open System Settings" (`Notifier.problem`/`captureFailed`). **Complexity M**: unpackaged apps need an AppUserModelID + Start-menu shortcut for toasts **[verify]**; HUD is just an overlay window.

### 1.15 Launch at login

`LaunchAtLogin.swift` 28: `SMAppService.mainApp` register/unregister/status incl. `.requiresApproval` (:7-26). **Complexity S**: `HKCU\...\Run` value or MSIX `StartupTask`; handle the user-disabled-in-Task-Manager state (`StartupApproved`).

### 1.16 Packaging / infra (not user features but needed)

`Scripts/build_app.sh` (Info.plist `LSUIElement` :44), `release.sh`, `install.sh` (curl|bash installer), `make_dev_cert.sh`, `.github/workflows/*.yml`. Windows needs its own build/sign/package/release pipeline and a replacement for `install.sh` (winget / MSI / MSIX / `irm | iex` is not recommended). **Complexity L**.

### 1.17 Rough totals

| Area | LOC (approx) | Share |
|---|---:|---:|
| Editor (canvas, window, tabs, pills, bg, doc, image ops, color tools) | ~6,400 | 37 % |
| Capture + selection + app glue (`AppDelegate`, `SelectionOverlay`, `CaptureService`, ...) | ~1,900 | 11 % |
| Recording (+picker, effects, trim, mixer, GIF) | ~1,860 | 11 % |
| History/library/quick access/pins | ~1,890 | 11 % |
| Settings/prefs/shortcuts/recorder | ~1,900 | 11 % |
| Scrolling capture | ~790 | 5 % |
| OCR + scratch pad | ~250 | 1 % |
| Updater/notifier/URL/login/permissions | ~740 | 4 % |

Roughly 45 % of LOC is AppKit view/window code that must be rewritten from scratch; about 10 % (about 1,500 LOC) is pure logic that ports nearly line-for-line.

---------------------------------------------------------------------------------------------------------------------

## 2. Platform API map

Port risk: **low** = direct, well-known equivalent; **med** = equivalent exists but behaviour/limits differ; **high** = no
clean equivalent, or core to the product and uncertain.

| macOS API | Where used (file:line) | Windows equivalent(s) | Risk | Reason |
|---|---|---|---|---|
| ScreenCaptureKit `SCScreenshotManager.captureImage` + `SCContentFilter(display:)` + `sourceRect` | `CaptureService.swift:34-54`, `:58-76` (`AreaGrabber`), `SelectionOverlay.swift:60-64` | Windows.Graphics.Capture (WGC) single-frame via `Direct3D11CaptureFramePool` with `GraphicsCaptureItem.CreateFromMonitor` (Win10 1903+/2004+ for cursor) ; or DXGI Desktop Duplication; or GDI `BitBlt` fallback | med | No one-shot screenshot API: you start a session, wait for the first frame, copy a sub-rect from the GPU texture to CPU. Latency matters for scrolling capture (`AreaGrabber.grab()` ~8x/s, comment at :56-57). DXGI DD is faster for repeated sub-rect grabs but has per-process limits and DRM black frames. |
| SCK window capture `SCContentFilter(desktopIndependentWindow:)`, `ignoreShadowsSingleWindow`, `backgroundColor=.clear`, `shouldBeOpaque=false`, BGRA | `CaptureService.swift:92-105` | WGC `CreateFromWindow(HWND)`; `PrintWindow(PW_RENDERFULLCONTENT)` as fallback; `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` for true bounds | high | Occluded-window capture works in WGC, but minimized windows do not, and whether rounded-corner pixels arrive with alpha=0 is **[verify]** (see 4.2). Win10 windows have square corners; Win11 has ~8 px rounded corners. |
| `SCShareableContent` + `CGWindowListCopyWindowInfo` for front-to-back window list, layer 0 filter, alpha filter | `CaptureService.swift:133-150`; `ScrollCapture.swift:486-501` | `EnumWindows` (already top-to-bottom z-order) + `IsWindowVisible`, `DwmGetWindowAttribute(DWMWA_CLOAKED)`, `GetWindowLong(WS_EX_TOOLWINDOW/NOACTIVATE)`, `WindowFromPoint`/`ChildWindowFromPoint`; UI Automation for sub-element picking (optional) | med | Must filter cloaked UWP windows, tool windows, own overlays; no "layer" concept. |
| SCStream (screen + audio + microphone outputs), `minimumFrameInterval`, `queueDepth`, `excludingApplications`, `exceptingWindows`, `excludesCurrentProcessAudio`, `captureMicrophone` (macOS 15) | `ScreenRecorder.swift:44-109`, `:158-166` | WGC frame pool (video) + WASAPI loopback (`AUDCLNT_STREAMFLAGS_LOOPBACK`, or process-loopback `AUDIOCLIENT_ACTIVATION_PARAMS` with `PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE`, Win10 2004+/Win11 **[verify]**) + WASAPI capture (mic) | high | Three independent clocks to align. WGC only delivers frames when content changes (same as SCK idle frames, see `ScreenRecorder.swift:176`), so constant-fps needs frame duplication. WGC cannot exclude "my other windows" selectively on monitor capture except via `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` **[verify]**. |
| `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` | `AppDelegate.swift:104`, `Permissions.swift:27` | None needed for desktop apps (no capture consent prompt; WGC yellow border can be disabled via `IsBorderRequired=false` on newer builds **[verify]**) | low | Concept mostly disappears. |
| Carbon `RegisterEventHotKey` / `InstallEventHandler` | `HotKeys.swift:19-42` | `RegisterHotKey` + `WM_HOTKEY` (thread message loop), `UnregisterHotKey`; optional `WH_KEYBOARD_LL` for keys `RegisterHotKey` cannot take (e.g. Win+Shift+S is reserved) | low-med | Straight mapping, incl. no-modifier Esc used as a temporary global key (`SelfTimer.swift:48`, `ScrollCapture.swift:233`); PrintScreen/Win-combos may be owned by the shell. Failure detection (`return nil` :20) maps to `RegisterHotKey` returning FALSE. |
| `NSEvent.addGlobalMonitorForEvents` (mouse down, keyDown) | `RecordingEffects.swift:43-51`; `CaptureHistory.swift:622-631` | `SetWindowsHookEx(WH_MOUSE_LL / WH_KEYBOARD_LL)` or Raw Input (`RegisterRawInputDevices` with `RIDEV_INPUTSINK`) | med | Low-level hooks work without special permission but run on the installing thread's message loop, can be flagged by AV/EDR as keylogger behaviour, and are skipped for elevated apps (UIPI). |
| Accessibility trust `AXIsProcessTrusted` (gate for keystroke display and scroll posting) | `RecordingEffects.swift:13-18`, `ScrollCapture.swift:338-346` | No equivalent grant; UIPI (integrity level) is the analogous limit | low | Permission UX disappears but replace with "target app is elevated" detection. |
| `CGEvent(scrollWheelEvent2Source:units:.pixel)` + `postToPid` / `.cghidEventTap`, window-under-pointer fields | `ScrollCapture.swift:504-519` | `SendInput(MOUSEEVENTF_WHEEL)` (cursor position decides target); `PostMessage(hwnd, WM_MOUSEWHEEL, ...)` to the window under the area; UI Automation `ScrollPattern.Scroll`/`SetScrollPercent` for native controls | high | macOS posts to a specific PID without moving the pointer. Windows `SendInput` goes to whatever is under the cursor (so the pointer must sit over the area); `PostMessage` is ignored by Chromium/Electron/UWP surfaces **[verify]**; UIA only works for controls that implement ScrollPattern (not browsers' page content). Pixel-precise deltas: wheel delta is 120/notch; sub-120 "precision" deltas are app-dependent. |
| `CGWindowListCopyWindowInfo(kCGWindowBounds, kCGWindowOwnerPID)` | `ScrollCapture.swift:486-501` | `WindowFromPoint` + `GetAncestor(GA_ROOT)` + `GetWindowThreadProcessId` | low | |
| Vision `VNRecognizeTextRequest` (accurate, language correction on/off, regionOfInterest, per-range `boundingBox`) | `TextRecognizer.swift:12-16`,`:33-37`,`:70-74`; `Library.swift:207-209` | `Windows.Media.Ocr.OcrEngine` (`OcrLine`/`OcrWord.BoundingRect`); alternatives: Tesseract, Windows 11 on-device AI text recognition (Copilot+ PCs **[verify]**), PaddleOCR/ONNX | med | Word rects are easier than Vision sub-range boxes, but accuracy on small UI text is lower, max image dimension is ~10,000 px (tile tall scrolling captures), languages depend on installed packs, no "correction" switch. |
| Vision `VNGenerateForegroundInstanceMaskRequest` + CoreImage mask apply | `ImageOps.swift:78-92` | None built-in for desktop apps (Windows AI Imaging "Object Erase/Background removal" APIs exist only on Copilot+ PCs **[verify]**); ship an ONNX model (U2-Net / RMBG / SAM-class) via ONNX Runtime/DirectML | high | Model size/licensing/quality choice; falls to an optional download. |
| AVAssetWriter/AVAssetWriterInput (H.264 + AAC, real-time, `startSession(atSourceTime:)`) | `ScreenRecorder.swift:79-101`, `:177-187`,`:207-` | Media Foundation Sink Writer (`IMFSinkWriter`, H.264 MFT hardware/software, AAC MFT) or FFmpeg/libav; NVENC/QSV/AMF direct | med-high | Hardware encoder availability and colour conversion (BGRA -> NV12) on GPU; MP4 muxing fine. Packaging FFmpeg has licence implications (GPL/LGPL, patents). |
| AVAssetReader/Writer audio mix, `AVAssetReaderAudioMixOutput` | `AudioMixer.swift:23-80` | Mix PCM yourself before encoding (simpler: mix live into one stream) or MF transcode | low-med | On Windows it is easier to mix before the encoder than post-hoc; the existing "mix after stop" design can be dropped. |
| AVAssetExportSession passthrough trim | `RecordingTrimmer.swift:24-40` | MF `IMFMediaSource` + Sink Writer with samples copied (no re-encode), or FFmpeg `-c copy` | med | Cut points snap to keyframes (encoder uses max keyframe interval `fps*2`, `ScreenRecorder.swift:87`) **[verify]** whether macOS does too. |
| AVKit `AVPlayerView` trim bar | `RecordingTrimmer.swift:65-103` | MediaPlayerElement/own timeline widget; no built-in trim UI | med | Build a player + two-handle timeline. |
| AVAssetImageGenerator (frame grab for GIF & thumbnails) | `GIFExporter.swift:13-27`, `QuickAccess.swift:69` | MF `IMFSourceReader` frame seek; Shell thumbnail (`IShellItemImageFactory`) | med | Frame accurate seek speed for 15 fps x duration. |
| ImageIO `CGImageDestination` GIF + `CGImageSourceCreateThumbnailAtIndex` | `GIFExporter.swift:21-30`; `CaptureHistory.swift:132-136` | WIC (`GUID_ContainerFormatGif` encoder, thumbnail via `IWICBitmapScaler`) or a library (gifski, giflib, ImageMagick) | med | WIC GIF has limited palette control (global palette dithering) so quality is poor without a dedicated quantizer. |
| ImageIO PNG/JPEG encode via `NSBitmapImageRep` | `Output.swift:7-34` | WIC encoders / library | low | Test `OutputTests` pins behaviour (alpha kept for PNG, JPEG flattens on white). |
| CoreImage `CIGaussianBlur`, `clampedToExtent`, `CIContext` | `AnnotationEditor.swift:2452-2466`, `Background.swift:181-198`, `ImageOps.swift:86` | Direct2D `ID2D1Effect` (CLSID_D2D1GaussianBlur), Skia `SkImageFilters::Blur`, or own box-blur | low | |
| Core Graphics / AppKit drawing (`CGContext`, `NSBezierPath`, `NSAttributedString`, `NSFont`, shadows, transparency layers, `setBlendMode(.clear)`) | `AnnotationEditor.swift` (67 NSBezierPath/NSFont/NSColor refs), `CaptureService.swift:108-129`, `SelectionOverlay.swift:550-575`, `SmartErase.swift:209-230`, `ImageOps.swift:27-33,52-75` | Direct2D/DirectWrite, Skia, Cairo/Pango, or the toolkit's canvas | med | Coordinate origin flips (CG bottom-left vs most Windows engines top-left) permeate geometry code (see 4.1, 4.11). |
| `QLThumbnailGenerator` (video/any file thumbnails) | `CaptureHistory.swift:121-123` | `IShellItemImageFactory::GetImage` / `IThumbnailCache` | low | |
| UserNotifications (`UNUserNotificationCenter`) with click action | `Notifier.swift:42-57`, `:88-105` | Toast notifications (`ToastNotificationManager`; Windows App SDK `AppNotificationManager`) with activation handler | med | Unpackaged apps need AUMID + shortcut registration **[verify]**; "Focus Assist" suppresses toasts. |
| `SMAppService.mainApp` | `LaunchAtLogin.swift:7-26` | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, or MSIX `StartupTask` | low | |
| CryptoKit `SHA256` | `Updater.swift:78-80` | `BCryptHashData` / BCL / OpenSSL | low | `UpdaterTests.testSHA256` pins vectors. |
| Security.framework code-signature check against own designated requirement (`SecCodeCopySelf`, `SecStaticCodeCheckValidity`, "cdhash" detection) | `Updater.swift:213-239` | Authenticode: `WinVerifyTrust` + compare signer cert thumbprint/subject with the running exe's signer; MSIX/AppInstaller handles this natively | med | Needs a stable signing identity (4.10). |
| `Process` -> `/usr/bin/ditto`, `/bin/sh` swap script, `open`, `kill -0` wait | `Updater.swift:198-207`, `:243-255` | Zip extraction in-process; a small updater helper exe that waits on PID then replaces files/launches installer; or MSIX AppInstaller / Squirrel-style | med | A running exe cannot overwrite itself on Windows; needs helper + elevation if installed per-machine. |
| `URLSession` HTTPS | `Updater.swift:111-113`,`:190-196` | WinHTTP/`HttpClient`/libcurl | low | |
| `NSStatusItem` + `NSMenu` (icon, menu, title text, tooltip, swap to stop button, tint) | `AppDelegate.swift:40-43`, `:76`, `:527-548` | `Shell_NotifyIcon` (+ `NOTIFYICON_VERSION_4`), popup menu (`TrackPopupMenu`) | med | No text next to the tray icon (recording timer is shown there: `AppDelegate.swift:76`); icons hide in overflow by default on Win11; high-DPI icon sizes; left-click vs right-click semantics. |
| `NSPasteboard` (image, string, custom type `com.skreener.annotation`, file URLs) | `Output.swift:71-76`, `ImageSource.swift:6-8`, `AnnotationClipboard.swift:6-22`, `QuickAccess.swift:214`, `AnnotationEditor.swift:1384` | Win32 clipboard: `CF_DIB`/`CF_DIBV5` + registered "PNG" format (alpha), `CF_UNICODETEXT`, `CF_HDROP`, `RegisterClipboardFormat` | med | Transparent PNG paste targets are inconsistent; write multiple formats. |
| Drag and drop out (`NSDraggingItem`, `beginDraggingSession`) | `EditorWindow.swift:102-107`, `QuickAccess.swift:481`, `CaptureHistory.swift:784-786`, `PinnedScreenshot.swift:331-336` | OLE `DoDragDrop` + `IDataObject` (`CF_HDROP` or `CFSTR_FILEDESCRIPTOR`) with a drag image (`IDragSourceHelper`) | med | OLE in a custom-window stack is fiddly; many UI toolkits wrap it. |
| `NSSharingServicePicker` | `Output.swift:116-125` | Windows Share UI (`DataTransferManager`, needs HWND interop) or "Open with / Share" fallbacks | med | |
| Borderless `NSPanel`s: `.screenSaver`/`.statusBar`/`.floating` levels, `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `ignoresMouseEvents`, `nonactivatingPanel`, `isOpaque=false` | `SelectionOverlay.swift:76-84`, `QuickAccess.swift:119-125`, `PinnedScreenshot.swift:36-43`, `RecordAreaPicker.swift:125-131,175-181`, `RecordingController.swift:165-232`, `RecordingEffects.swift:32-37`, `ScrollCapture.swift:532-571`, `SelfTimer.swift:26-29`, `Notifier.swift:179-185`, `CaptureHistory.swift:242-246` | `WS_POPUP` + `WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`, per-pixel alpha via `UpdateLayeredWindow` or DirectComposition; `SetWindowPos(HWND_TOPMOST)` | med-high | 4.1. |
| `NSScreen.screens`, `frame`, `visibleFrame`, `backingScaleFactor`, mouse-location -> screen | 40+ sites, e.g. `CaptureService.swift:27,42,94`, `ScrollCapture.swift:257,275,481`, `ScreenRecorder.swift:52`, `QuickAccess.swift:41,171`, `SelectionOverlay.swift:63,299,488` | `EnumDisplayMonitors`/`GetMonitorInfo` (rcWork = visibleFrame), `GetDpiForMonitor(MDT_EFFECTIVE_DPI)`, per-monitor-v2 DPI awareness manifest, `WM_DPICHANGED` | high | 4.1: fractional scales (125/150/175 %), negative virtual-desktop coords, top-left origin. |
| `NSVisualEffectView` materials (HUD blur) | `SelfTimer.swift:78`, `CaptureHistory.swift:249`, `EditorTabs.swift:171`, `EditorWindow.swift:713,737`, `RecordAreaPicker.swift:69` | Acrylic/Mica (`DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)`, Win11) or plain translucent fills | low | Aesthetic only. |
| `NSWorkspace` (frontmost app, activation notifications, open URL, `desktopImageURL`, reveal in Finder) | `AppDelegate.swift:92-99,649`, `Background.swift:163-166`, `Updater.swift:144` | `GetForegroundWindow` + `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)`; `SystemParametersInfo(SPI_GETDESKWALLPAPER)` / `IDesktopWallpaper`; `ShellExecute`, `SHOpenFolderAndSelectItems` | low | Wallpaper may be slideshow/Spotlight (non-file) like the macOS "dynamic aerial" case (`Background.swift:166`). |
| `UserDefaults` | `Preferences.swift:39`, `Shortcuts.swift:250-283`, `CaptureHistory.swift:188` | Registry, JSON/TOML file in `%APPDATA%`, or toolkit settings | low | `ShortcutTests` store round-trip via a swappable `UserDefaults` (:255 `in defaults:`), so keep storage injectable. |
| `NSOpenPanel/NSSavePanel/NSAlert` | `ImageSource.swift:10-17`, `Output.swift:95`, `Updater.swift:132-155`, `AppDelegate.swift:178-205` | `IFileOpenDialog/IFileSaveDialog`, `TaskDialog`/`MessageBox` | low | |
| `NSSound` / `NSSound.beep` | `Notifier.swift:20-23`, `AnnotationEditor.swift:235,699,...` | `PlaySound`/`MessageBeep` | low | |
| `NSApp.hide` during drag; `setActivationPolicy(.accessory)`, `LSUIElement` | `EditorWindow.swift:114`, `main.swift:6`, `AppDelegate.swift:793`, `build_app.sh:44` | Tray-only process: hide all top-level windows; no Dock/taskbar entry via `WS_EX_TOOLWINDOW`/skip-taskbar; editor window shows in taskbar | low | |
| Finder `defaults write com.apple.finder CreateDesktop` + `killall Finder` | `ImageSource.swift:24-30` | Shell icon-visibility toggle **[verify]** (no restart needed) | low-med | |
| Info.plist URL scheme `skreener` | `Scripts/build_app.sh:45-47` | `HKCU\Software\Classes\skreener\shell\open\command`, or MSIX `uap:Protocol`; second-instance forwards argv to first | low-med | Need single-instance mutex + IPC. |
| FS watch `DispatchSourceFileSystemObject` | `Library.swift:78,112` | `ReadDirectoryChangesW` / `FileSystemWatcher` | low | |
| Application Support dirs | `CaptureHistory.swift:22`, `Library.swift:85` | `%LOCALAPPDATA%\Skreener` | low | |

---------------------------------------------------------------------------------------------------------------------

## 3. Portable logic and executable specs

The pieces below have no Apple UI dependency in their algorithm. Several still `import CoreGraphics` for `CGImage`/`CGRect`
(trivial to replace) and several tests build fixtures with AppKit (`TestImages.swift`, `ColorToolsTests.image` :8-22). On
Windows these become: a pixel-buffer type (RGBA8, top-left origin), a rect type, and synthetic-fixture builders. The test
cases (inputs and expected values) are the acceptance criteria; port them as table-driven tests.

### 3.1 Pure and directly portable

**SelectionGeometry** (`SelectionGeometry.swift:5-106`; rects in bottom-left-origin points)
- `apply` moves by 1/10 pt; Cmd/Ctrl+arrows grow/shrink the right/bottom edge (top edge fixed for down/up) and finally clamp into `bounds`; `resizeAllSides` grows/shrinks every side (clamped / min 1 pt); `rounded` rounds edges, not size; `dragRect` handles Shift-square and Option-from-center clamped to room in bounds; `resize(handle:)` uses handle index 0..7 CCW from bottom-left and flips on crossing; `move` clamps.
- Windows note: the whole file assumes bottom-left origin and 1-pt steps. Decide the Windows convention (top-left, device pixels or DIPs) up front and port the tests with flipped Y.
- Executable spec: `SelectionGeometryTests` (14 tests: `testKeyMapping`, `testArrowsMoveOneOrTenPoints`, `testMovesStopAtTheScreenEdge`, `testCommandArrowsResizeTheRightAndBottomEdges`, `testCommandArrowsStayOnScreenAndKeepAPoint`, `testScrollGrowsAndShrinksEverySide`, `testGrowStopsAtTheScreenAndShrinkKeepsAPoint`, `testRoundingKeepsTheSizeOfAFractionalPosition`, `testPlainDragSpansStartAndCurrent`, `testShiftDragMakesASquareOnTheLongerSide`, `testShiftDragStaysSquareAtTheScreenEdge`, `testOptionDragGrowsAroundTheStart`, `testResizeByHandles`, `testMoveStaysOnScreen`) + `SelectionModeTests` (mode cycle `SelectionOverlay.Mode.next`, `:33-36`: area->window->scrolling wraps, skips unavailable). `key(keyCode:)` maps macOS key codes 123-126; replace with VK_LEFT.. (37-40).

**ScrollMatcher / ScrollRows** (`ScrollMatcher.swift:1-163`)
- Each frame row is squeezed to 96 gray bins, reduced to "detail" (value minus neighbour mean + change from row above, around 128) and flagged flat if range <= 4. `match(prev,new,hint,bridgeBlank)`: find static header/footer rows (row diff < 2/bin), cap each at h/4, then search shift in `-band/2 ... band-minOverlap` (hint first, step 2 rows, refine +/-2 at step 1) minimizing mean abs diff while ignoring blank-on-both rows; accept if cost < 6 and < 0.5x the "no move" cost; else try a blank-bridging guess; else `.lost`.
- Executable spec: `ScrollMatcherTests` (6): `testSameFrameIsUnchanged`, `testScrollDown` (shift 37), `testScrollBackUp` (-30), `testHintGivesTheSameAnswer`, `testStickyHeaderStaysPut` (header 20..21, shift 40), `testUnrelatedContentIsLost`. Fixtures use a fixed LCG (`state*1664525+1013904223`), which makes them exactly reproducible on any language: keep it.
- **Gap**: `ScrollStitcher` (`ScrollCapture.swift:11-163`, ~150 LOC of header/footer/tail bookkeeping) has no test at all (`grep` finds no references in `Tests/`). The Windows suite should add stitching tests (known page -> frames -> reassembled image equals the page) before porting, written against the macOS build first if possible.
- The row-reduction step `ScrollStitcher.rows` (:147-163) uses CoreGraphics gray down-sampling (`interpolationQuality=.medium`, 96 bins); a different resampler will shift costs slightly, so the `maxCost=6`/`sameRow=2` thresholds must be re-validated on real pages.

**ObjectSnap** (`ObjectSnap.swift:170-349`; pixels, top-left origin)
- `snap`: for each side of a box, scan +/-`reach` px for the boundary where neighbouring pixels differ (> 16 per channel) along >= 45 % of the side; strongest wins, nearest on ties (within 0.1); degenerate pairs revert. `similar`: grayscale template matching at ~10 px across the short side (SAD, threshold `3*10*sw*sh`), refine at full-res, non-overlap by 20 % core inset, max 60, rejects flat templates (mean abs deviation < 6).
- Spec: `ObjectSnapTests` (5): `testABoxDrawnRoughlyAroundAButtonGetsItsExactBounds`, `testABoxDrawnJustInsideSnapsOutToTheEdges`, `testNothingNearbyLeavesTheBoxAlone`, `testSimilarObjectsAreFound`, `testAFlatBoxMatchesNothing`. Perf is unspecified by tests; add a time budget.

**PixelBuffer** (`PixelBuffer.swift:29-133`)
- RGBA8 premultiplied-in, `rgba(x,y)`, `color`, `darkest(radius 10)` for text colour near the pointer, `average(in:)`, `dominantColors(in:)` (background vs foreground). `RGBColor` has WCAG relative luminance (:22). Spec: `ColorToolsTests` `testPixelColorIsReadTopLeft`, `testDarkestNearbyFindsTheTextColor`, `testAverageOfHalfBlackHalfWhiteIsMidGray`, `testDominantColorsOfTextOnABackground`, `testDominantColorsOfOneColor`. Windows images are BGRA and often straight (non-premultiplied) alpha: define the buffer contract explicitly (the translucent-colour tests will expose mistakes).

**ColorFormat** (`ColorFormat.swift:5-74`): HEX, CSS, RGB, UIColor, Android, OKLCH ... formatting plus `oklchComponents` (sRGB -> linear -> OKLab -> LCH). Spec: `ColorToolsTests.testEveryFormat`, `testTranslucentFormats`, `testOKLCHOfGraysHasNoHue`. Locale: uses `String(format:"%.2f")`, force invariant culture on Windows.

**Contrast** (`Contrast.swift:4-70`): `wcag` ratio and rating thresholds; `apca` (Lc) with soft-clamp 0.022/1.414 and rating bands. Spec: `ColorToolsTests.testWCAG` (black/white = 21, gray/white = 4.48 -> "AA Large"), `testAPCA`.

**RulerScanner** (`RulerScanner.swift:1-48`): from a pixel, extend a same-colour run (tolerance 10) both ways; with `outer` also take the neighbouring run if <= 16 px (border). Spec: `ColorToolsTests` `testRulerMeasuresTheInsideOfABox`, `testRulerWithShiftIncludesTheBorder`, `testRulerOuterIgnoresTheBackgroundAroundABorderlessBox`, `testRulerMeasuresTheGapBetweenBoxes`, `testRulerRunsToTheImageEdge`, `testRulerToleratesSlightNoise`.

**SmartErase** (`SmartErase.swift:5-58`): one-pixel ring outside the box, bucket colours at 5 bits/channel, pick the most common bucket and average its members (un-premultiply), nil if the ring is entirely outside. Spec: `SmartEraseTests` (5): black square, covering square -> white, most-common-wins, box past edge uses inside ring, box covering everything -> nil.

**ArrowLabel** (`ArrowLabel.swift:5-19`): label box placed `gap` past the arrow tail away from the head; side chosen by direction components vs 0.38 lean (about 22 degrees). Spec: `AnnotationStyleTests.testArrowLabelSitsPastTheTailAwayFromTheHead`, `testArrowLabelNeverCoversTheTail`, `testArrowLabelIsOnByDefault`.

**URLCommand** (`URLCommand.swift`): grammar `skreener://<group>/<action>[?then=copy,save,edit,pin,quickaccess][&delay=1..60]`, `capture/` alias of `grab/`, tolerant of case, slashes, missing `//` and trailing slash; unknown path/param/then/delay -> typed errors with messages listing options. Depends on `HotKeyAction` (pure enum in `Shortcuts.swift:154-`), which should move to a shared "actions" module. Spec: `URLCommandTests` (10): `testAreaWithThen`, `testCaptureIsAnAliasForGrab`, `testWithoutSlashesCaseAndTrailingSlash`, `testActiveWindow`, `testEveryCommandParses`, `testSettingsAndOtherCommands`, `testEveryThenOption`, `testDelay`, `testErrors`, `testErrorMessagesListTheOptions`. On Windows `skreener://grab/area` arrives as argv/protocol activation with the full URL: same parser.

### 3.2 Pure logic embedded in otherwise platform files (extract and port)

| Logic | Location | Spec tests |
|---|---|---|
| Filename template (`%Y %y %m %d %H %M %S %%`, `/`->`-`, `:`->`.`, leading dot, empty fallback), unique-name numbering | `Output.swift:36-69` | `OutputTests` `testDefaultTemplate`, `testEveryToken`, `testPercentSigns`, `testFolderAndColonCharactersAreReplaced`, `testEmptyNameFallsBack`, `testLeadingDotIsNotHidden`, `testTakenNamesGetANumber`. Windows must also strip `\ * ? " < > |` and reserved names (CON, NUL...) which the Mac code does not. |
| Image encode semantics: PNG keeps alpha, JPEG flattens on white, "save at 1x" downscale, format from extension, overwrite keeps format | `Output.swift:7-34,86-93` | `OutputTests` `testPNGKeepsTransparency`, `testJPEGFlattensOntoWhite`, `testRetinaKeepsFullResolutionByDefault`, `testRetinaSavedAt1x`, `testFormatFromExtension`, `testOverwriteKeepsTheFilesFormat` (need re-expression: they build `NSImage` fixtures) |
| Screen-rect -> pixel-rect (integral rounding, multi-display offsets) | `CaptureService.swift:86-90` | `CaptureServiceTests` `testRetinaMainScreen`, `testSecondScreenToTheRightAndLower`, `testScreenAboveTheMainOne`, `testFractionalPointsCoverWholePixels`. Re-spec for top-left virtual-desktop pixels and fractional DPI. |
| Window decoration compositing (margin = (shadow?40:0 + padding) * scale; transparent vs white fill; shadow offset (0,-10), blur 30, alpha .45) | `CaptureService.swift:108-129` | `WindowDecorationTests` (`CaptureServiceTests.swift:37-`) `testTransparentPaddingStaysClear`, `testTransparentWithoutPaddingKeepsTheCorner`, `testShadowAreaIsTransparentPastTheShadow`, `testOpaqueFillsWithWhite`. |
| Background canvas maths (padding vs aspect ratio, odd ratios within 1 pt) and persistence round-trip | `Background.swift:90-139,235-244` | `BackgroundTests` (6) |
| Image ops limits and cut maths (`resizeProblem`, `proportional`, `removing(band:)`, `afterCut`) | `ImageOps.swift:5-75` | `ImageOpsTests` `testSizeLimits`, `testProportionalSide`, `testResizeHalvesPixelsAndKeepsDensity`, `testRemovingRowsJoinsTheRest`, `testRemovingColumns`, `testCannotRemoveEverything`, `testCoordinatesAfterACut` |
| Stroke simplification and shape recognition; seeded hand-drawn wobble is deterministic | `StrokeShapes.swift:14-176`, `SeededRandom` :159 | `StrokeShapesTests` (6): `testShakyCircleBecomesAnEllipse`, `testBoxBecomesARectangle`, `testNearlyStraightStrokeBecomesALine`, `testScribbleStaysAStroke`, `testSimplifyDropsPointsOnAStraightRun`, `testHandDrawnWobbleIsTheSameEachTime` (the last needs the same PRNG, :159-176, to be bit-identical, otherwise only "stable per seed" is testable) |
| Annotation/Style model and (de)serialisation, text-on-solid contrast, speech-bubble tail in outline, scaled font size rules | `AnnotationEditor.swift:74-260`, `EditorDocument.swift` | `AnnotationStyleTests` (8), `EditorDocumentTests` (7: round trips, newer-version -> nil, document folder naming, removal), `AnnotationClipboardTests` (3) |
| Library search/filter/counts, media-kind by extension, listing newest first | `Library.swift:30-45,146,217-236` | `LibraryTests` `testSearchFindsTextInTheScreenshot`, `testFilters`, `testCountsForTheFilterMenus`, `testListsMediaInTheFolderNewestFirst` |
| Quick Access stack placement and gesture classification | `QuickAccess.swift:161-176,293-315` | `QuickAccessTests` `testBottomLeftAndBottomRight`, `testSecondScreenToTheLeft`, `testSwipeTowardTheEdgeTheStackSitsOn`, `testOtherDirectionsDragTheFileOut`, `testSmallMovementIsStillAClick`, `testDismissNeedsDistanceOrAFlick` |
| Version compare, release JSON parsing (draft/prerelease/missing assets -> nil), SHA256SUMS lookup (`*name` binary marker), dev builds never update | `Updater.swift:33-80` | `UpdaterTests` (7), `VersionTests` (3: version/build/commit parsing from Info.plist; Windows analogue = version resource) |
| Trim range from player handles (invalid = untouched, clamped, <= 10 ms slack) | `RecordingTrimmer.swift:12-21` | `RecordingTrimTests` (5), uses `CMTime`: re-express with seconds as doubles/rationals |
| Shortcut model: display strings, storage `"keyCode:mask"`, malformed rejected, defaults don't conflict, needs-modifier rule, taken-by-another-action, set/clear/restore | `Shortcuts.swift:6-80,238-300` | `ShortcutTests` (about 20): the display-string, menu-equivalent and mac-system-warning tests are macOS-specific; the storage/conflict/default tests are the portable spec. Replace the Carbon mask with a Windows modifier set and re-pin key codes (VK_*). |
| Scratch-pad "Join Lines" (mends hyphenation across lines only if previous char is a letter and next starts lowercase) | `TextScratchPad.swift:110-124` | `ScratchPadJoinTests` (`TextRecognizerTests.swift:69-80`) |
| Audio-track count rule: only mix when > 1 audio track; keep originals on failure | `AudioMixer.swift:14-19`, `ScreenRecorder.swift:219-228` | `AudioMixerTests` (2; needs real AAC fixtures) |
| Redact patterns (email regex; phone & link via `NSDataDetector`) | `TextRecognizer.swift:87-102` | `TextRecognizerTests` `testRedactEmailCoversJustTheAddress`, `testRedactLinkAndPhoneNumber` (OCR-dependent; run against the chosen engine, expect threshold tuning) |
| Pure `ScrollStitcher` + auto-scroll controller state machine (velocity, overshoot take-back, fruitless take-back stop at 2) | `ScrollCapture.swift:11-163`, `:395-471` | no tests; write them |

### 3.3 Tests that are NOT portable specs (need OS-specific re-creation)

`TextRecognizerTests` (Vision output), `GIFExporterTests` (AVFoundation fixtures), `AudioMixerTests`, `RecordingTrimTests` (CMTime types only, logic portable), `OutputTests`/`WindowDecorationTests`/`ImageOpsTests`/`BackgroundTests` (AppKit fixture builders), `AnnotationClipboardTests` (NSPasteboard). Their assertions are portable; their harness is not.

---------------------------------------------------------------------------------------------------------------------

## 4. Hard problems and unknowns

### 4.1 Multi-monitor, mixed-DPI selection overlays
- macOS code uses points (`NSScreen.frame`) with a global bottom-left origin that is flipped using the primary display's height in several places (`AppDelegate.swift:686`, `ScrollCapture.swift:481`, `SelectionOverlay.swift:299,488`, and per-display conversion at `CaptureService.swift:47-49`). Windows virtual-screen coordinates are top-left, can be negative on either axis, and each monitor has its own DPI.
- Integer-scale assumption: `Int(width * scale)` (`CaptureService.swift:13-14`), `Int(16 * backingScaleFactor)` (`ScrollCapture.swift:257`), `scale *= sqrt(...)` then `& ~1` (`ScreenRecorder.swift:52-56`). Windows commonly runs 125 %/150 %/175 %: pixel rect rounding (`pixelRect` :86-90 uses `.integral`) needs re-validation, and selections that cross a monitor boundary with different DPI may span two textures.
- Per-monitor DPI v2 awareness is mandatory (manifest) or all coordinates get virtualized. One overlay window per monitor must be positioned in physical pixels; a single window spanning all monitors fails when DPIs differ **[verify]** (the macOS design is already one panel per screen: `SelectionOverlay.swift:63-90`, which is the right model).
- Overlays need to appear above fullscreen apps, the taskbar and UWP; exclusive-fullscreen games/DRM video yield black capture regardless of API.
- Cursor shape management: macOS re-applies the crosshair on every move because other apps reset it (`SelectionOverlay.swift:108-113,287-289`, TODO #161); Windows needs `SetCursor` in `WM_SETCURSOR` plus handling apps that call `SetCursor` globally.
- Keyboard focus: overlay must take keys (Space, arrows, Esc) while being non-activating to avoid dismissing menus in the foreground app; `WS_EX_NOACTIVATE` windows do not receive key events without focus, so a focus strategy or a low-level keyboard hook is needed **[verify]**.

### 4.2 Single-window capture with transparent rounded corners
- macOS needed explicit `pixelFormat=BGRA`, `backgroundColor=.clear`, `shouldBeOpaque=false` and `ignoreShadowsSingleWindow` to keep transparent corners (`CaptureService.swift:96-102`, issue #138). The code then composes its own shadow (`decorateWindow` :108-129) and tests pin transparent corner behaviour (`WindowDecorationTests`).
- Windows: WGC window capture returns the window's surface rectangle; DWM drop shadows are outside the "extended frame bounds"; Win11 corners are DWM-clipped. Whether the corner pixels come back transparent, black, or desktop-through is **[verify - spike first]**. Fallbacks: apply a corner mask manually (Win11 radius about 8 px at 100 %, scaled; `DWMWA_WINDOW_CORNER_PREFERENCE`), or capture the monitor and crop (loses "window even if covered").
- "Even if something covers it" (README) maps to WGC window capture; but minimized windows, windows on other virtual desktops and DRM/protected content fail. Windows with `WS_EX_LAYERED` / acrylic / Mica composite differently.
- Z-order hit test: the macOS code explicitly re-sorts `SCShareableContent` windows with `CGWindowListCopyWindowInfo` because SCK's order is not front-to-back (`CaptureService.swift:131-149`) and drops alpha ~0 windows. Windows `EnumWindows` is z-ordered but includes cloaked UWP/ghost windows and invisible helper windows; hover tint must exclude "windows in front" via region subtraction (`SelectionOverlay.swift:560-570`) - on Windows use `GetWindowRgn`/`GetWindowRect` rect subtraction.
- The window picker also needs to avoid "Program Manager"/desktop, the taskbar and Skreener's own overlays (macOS: `owningApplication.bundleIdentifier != me`, `windowLayer == 0`, size > 40: `CaptureService.swift:136-139`).

### 4.3 Scrolling capture: auto-scroll injection
- The Mac design: post pixel-unit scroll events to a PID without moving the pointer (`ScrollCapture.swift:504-519`), fall back to pointer posting if the app ignores them (`viaPointer`, :191, :433). Speed is calibrated from measured content movement per scrolled point and overshoot is taken back via negative scroll (`autoScrollStep` :395-471, `fruitlessTakeBacks` stop).
- Windows options all have trade-offs: `SendInput` wheel (works almost everywhere but needs the cursor on the target and moves/steals the user's pointer; blocked by UIPI for elevated targets), `PostMessage WM_MOUSEWHEEL` (not honoured by Chromium/Edge/Electron/UWP rendering surfaces and many frameworks **[verify]**), UI Automation `ScrollPattern` (browser page content is usually not exposed; works for native lists/documents), keyboard Page Down (changes selection/caret, jumpy). Smooth-scrolling animations in browsers make per-event deltas non-linear; the existing closed-loop (measure shift, adjust velocity) is the right design but its constants (`rect.height*0.25` start, 60 Hz timer :369-371, x3 / x1.5 ramp :419) were tuned on macOS trackpad semantics and need re-tuning.
- Frame loop currently grabs through the screen-capture API every ~120 ms (:262-266). WGC session start-up per grab is too slow, so a persistent capture session with the latest-frame texture is needed (analogous to the `AreaGrabber` comment about not refetching content: `CaptureService.swift:56-57`).
- Own frame/control windows must be excluded from the grab (macOS: filter out own PID: :67). Windows: `WDA_EXCLUDEFROMCAPTURE` on the frame and control windows **[verify]**, else they pollute stitching.
- Fixed pieces: matcher thresholds depend on the gray down-sampling (3.1); text rendering (ClearType vs macOS grayscale AA) changes `flat`/detail statistics.

### 4.4 Click highlights and keystroke display in recordings
- macOS draws a click-through overlay window that is deliberately included in the video via `exceptingWindows` while all other Skreener windows are excluded (`RecordingEffects.swift:21-37`, `ScreenRecorder.swift:44-49`, `RecordingController.swift:56`). Windows: monitor-level WGC captures every visible window including all our own HUD/dim/frame windows. Choices: (a) mark every non-effects window `WDA_EXCLUDEFROMCAPTURE` (Win10 2004+ **[verify]** - older builds blank the window instead of excluding it), or (b) do not use an overlay at all and composite rings/pills into each frame in the encoder path (more work, but deterministic and works with cursor-less capture).
- Event sources: low-level mouse/keyboard hooks (`SetWindowsHookEx`) or Raw Input; keystrokes need translation from VK + keyboard layout to a label (`RecordingEffects.keyName` :86-115 is Mac key code based) with dead keys/IME handling and modifier-state tracking. Security tools may flag a global keyboard hook; password-field masking is a privacy consideration the Mac code does not address.
- Elevated windows: hooks installed by a non-elevated process do not see input into elevated apps.

### 4.5 Recording with system audio + microphone
- Mac pipeline: one SCStream emits synchronized screen/system-audio/mic buffers on a single clock; writer pauses by dropping and retiming (`ScreenRecorder.swift:134-210`); mic needs macOS 15 and a permission prompt (:71-75, :127-132). Windows has no single synchronized source: WGC frames carry `SystemRelativeTime`, WASAPI loopback and mic have QPC/device positions. Required work: a shared QPC time base, resampling to 48 kHz stereo, drift correction, and **silence insertion** because loopback delivers no packets while nothing plays, which otherwise desynchronizes the audio track **[verify]**.
- System audio without Skreener's own sounds: macOS `excludesCurrentProcessAudio` (:64); Windows needs process-loopback exclusion (new APIs, Win10 2004+/Win11 **[verify]**) else Skreener's own beeps/countdown sounds end up in the file.
- Echo/feedback between mic and speakers is unaddressed even on Mac. Mixed track happens after the fact (`AudioMixer`); on Windows mix live and skip the 2-track-then-remux step (and its failure branch).
- Encoder: bitrate formula `max(2 Mbps, w*h*fps*0.12)` (`ScreenRecorder.swift:80-92`), max keyframe 2 s, H.264 High auto level, 4096x2304 cap, even dimensions (:55). Hardware MFT availability differs per GPU; software x264 fallback has licensing questions; HDR displays (WGC returns scRGB/FP16 on HDR monitors) need tone-mapping **[verify]**, absent from the Mac code.
- Cursor capture and frame pacing: SCK `minimumFrameInterval` drops frames; WGC (`MinUpdateInterval` on newer builds **[verify]**) or manual throttling.
- GIF from MP4 relies on exact-time frame extraction (`GIFExporter.swift:13-27`); consider generating GIF directly from captured frames to avoid decode.

### 4.6 Global hotkeys on Windows
- Defaults `Ctrl+Shift+1..9/H` (`Shortcuts.swift:221-230`): Ctrl+Shift is also the default input-language/keyboard-layout switch for many users and some IMEs **[verify]**; `RegisterHotKey` fails silently for combinations already owned (the code surfaces this as `unavailable`: `HotKeys.swift:20`, `ShortcutCenter.unavailable` :56). Win-key and PrintScreen combos belong to the shell (Snipping Tool). Esc registered as a global hotkey during selection/scroll capture (`ScrollCapture.swift:233`) swallows Esc for every app until released - same on Windows.
- The "hand over system screenshot shortcuts" wizard reads `com.apple.symbolichotkeys` (`Shortcuts.swift:300-335`); Windows has no equivalent store (Snipping Tool is toggled in Settings > Accessibility > Keyboard "Use the Print screen key to open screen capture").

### 4.7 Permissions and elevation model
- All of `Permissions.swift` (Screen Recording / Accessibility / Microphone + deep links `x-apple.systempreferences:` :40-50) collapses: no capture or accessibility grant exists; mic access can be blocked in Settings > Privacy > Microphone ("let desktop apps access"). The new first-class failure modes are UIPI (can't scroll or hook elevated windows), secure desktop/UAC prompts (black capture), DRM-protected surfaces, and policy-blocked WGC. User-facing error copy (`Notifier.captureFailed`, README "Permissions" table) needs a rewrite.

### 4.8 Tray ("menu bar") limitations
- Timer text in the menu bar during recording (`AppDelegate.swift:76`, `Preferences.recordTimeInMenuBar`) and tinted stop button (:527-548) have no equivalent: tray icons cannot show text and Win11 hides new tray icons in overflow. Plan: icon swap + tooltip, plus the always-on HUD (`RecordingController` HUD) as the real control surface.
- Left-click vs right-click behavior, tray DPI icon sets, Explorer restart (`TaskbarCreated` message must re-add the icon).

### 4.9 OCR parity and Remove Background
- Vision "accurate" with language correction (`TextRecognizer.swift:13-14`) vs Windows.Media.Ocr: different accuracy, language-pack dependence, ~10k px dimension limit (scrolling captures can reach 30,000 px: `ScrollStitcher.maxHeight` :27, so tile), and no per-range box API (word rects instead; email/URL regex across word boundaries needs mapping char-offset -> word rects).
- Library full-text search (`Library.swift:204-214`) OCRs every image in the folder in the background: cost scales with the library; needs throttling and idle scheduling.
- `removingBackground` (`ImageOps.swift:78-92`) has no OS-level equivalent on most PCs; shipping a segmentation model (size, licence, DirectML/CPU speed) is a product decision, easy to defer.

### 4.10 Code signing, SmartScreen and the updater trust model
- The Mac design deliberately uses a self-signed certificate (README "Releases are signed with Skreener's own certificate"; `Updater.swift:211-239` pins the update to the running app's designated requirement, refuses ad-hoc builds containing "cdhash" :224) and avoids quarantine by downloading in-process (comment :14-20). Windows analogue: Authenticode with a real OV/EV or Azure Trusted Signing certificate; a self-signed cert triggers SmartScreen "unknown publisher" for downloaded installers (Mark-of-the-Web), and new certs have no reputation. Files downloaded by the app itself with an HTTP client do not get the Zone.Identifier stream, which gives the same escape hatch as the Mac `Updater` but the *first* install still faces SmartScreen **[verify]**.
- Replacing a running exe: needs a helper (`Updater.relaunch` shell script :243-255 -> helper exe that waits on PID), or MSIX/AppInstaller, or Squirrel/Velopack-style framework; per-user install avoids elevation. Verification: `WinVerifyTrust` + pin signer thumbprint/subject. Checksums (`SHA256SUMS`) logic ports as is.
- `install.sh` (curl|bash) has no safe Windows twin; use winget manifest / MSIX / signed MSI.
- Secrets/cert management for CI (README release notes about `SELF_SIGNED_P12_*` secrets) will need rework (HSM/cloud signing).

### 4.11 UI toolkit-level unknowns
- The editor draws everything itself (`CanvasView`, 2,497 LOC) with `NSBezierPath`, `NSAttributedString`, transparency layers and `.clear` blend; hit-testing, handles, text editing (`NSTextViewDelegate`, inline text :1620-1738, `NSTextView` undo), rich text layout, pinch/trackpad gestures. Which 2D stack the Windows version uses determines feasibility of: multiply-blend highlighter, soft shadows, bubble tails, per-annotation blur/pixelate sampling from the base image.
- Coordinate-origin flip (bottom-left in editor, Vision, CG) is baked into data (`Annotation` geometry, `EditorDocument` JSON, Vision rects in `TextRecognizer.swift:42-46`). If saved documents should open on both OSes, freeze the document origin (the JSON has `version = 1`: `EditorDocument.swift:9`).
- Dark mode, `NSColor` semantic colors, and SF Symbols used throughout (toolbar icons, `AppDelegate.swift:539`, `SettingsWindow.swift:39-44`): need an icon set (Segoe Fluent icons / own SVGs).
- Drag-out with app hiding (`EditorWindow.swift:88-160`) depends on Cocoa dragging-session callbacks; OLE gives start/end callbacks too (`IDropSource`), but hiding the whole app during the drag needs explicit window management.
- Unverified Mac behaviours (97 `[~]` TODO items) mean some subtle behaviours (e.g. cursor re-apply #161, drag hide #81) may be untested even on the reference platform; do not treat all code as a verified spec.

---------------------------------------------------------------------------------------------------------------------

## 5. Suggested phasing

### Phase 0 - spikes (1-2 weeks, before committing to a stack)
Each spike answers a **[verify]** from above with a throwaway prototype on Windows 10 22H2 and Windows 11 with 2 monitors at different DPIs (e.g. 100 % + 150 %):
1. Mixed-DPI overlay: borderless per-monitor window, drag-select, correct pixel crop (`pixelRect` equivalence).
2. WGC window capture: occluded window, Win11 rounded corners (alpha?), shadow, cursor.
3. Auto-scroll injection into Chrome/Edge, Word/Notepad, Explorer, UWP (SendInput vs PostMessage vs UIA).
4. Recording: WGC + WASAPI loopback + mic -> MP4, A/V sync with silence, `WDA_EXCLUDEFROMCAPTURE` for self-exclusion.
5. OCR quality sample (Windows.Media.Ocr vs Tesseract) on UI screenshots and the `TextRecognizerTests` fixture strings.
6. Signing/updating: Authenticode cert option, SmartScreen behaviour for an unsigned vs signed installer, MSIX vs installer + helper.
7. Pick the 2D/UI stack against editor requirements (blend modes, blur, text editing, hit testing, per-pixel-alpha topmost windows).

### Phase 1 - MVP: "a useful Windows screenshot tool" (target: first public preview)
Scope: tray app (single instance), rebindable global hotkeys (area, fullscreen, window, previous area, history), area selection overlay incl. magnifier, size readout, adjust handles (port `SelectionGeometry` + tests), fullscreen/area/window capture (window with shadow/padding options, even if corners are approximate), freeze screen optional, copy/save pipeline (`Output` template + PNG/JPEG), Quick Access preview (corner thumbnail, copy/save/edit/close), minimal editor (select/move/delete, arrow, rect, filled rect, ellipse, line, pen, highlighter, text, counter, pixelate, blur, crop, undo/redo, save/copy, zoom), Capture Text (OCR + scratch pad), pin to screen, settings (folder, format, hotkeys, after-capture, launch at login), `skreener://` parsing deferred, installer + auto-update by "download and run installer" only.
Why: this is the core loop; ~35-40 % of total effort but covers the main user value. It exercises every portable-logic test already (SelectionGeometry, ColorFormat, Output, SmartErase optional).
Acceptance: SelectionGeometry/SelectionMode/Output/pixelRect-equivalent tests green; manual matrix on 1 and 2 monitors with mixed DPI.

### Phase 2 - capture parity and recording
- Self-timer, capture active window, hide desktop icons, All-in-One picker, Capture Area & Pin.
- Screen recording MP4 (area/window/fullscreen, cursor, 30/60 fps, pause), HUD, tray stop, recording Quick Access preview, **video only first**, then microphone, then system audio (+ mix).
- GIF export, trim (basic start/end cut).
- Capture History panel + history store + editor documents (`EditorDocument` JSON), drag-out.
- URL scheme registration + single-instance forwarding (`URLCommand` + 10 tests).
- Updater with signature verification (once signing is settled).

### Phase 3 - scrolling capture and editor depth
- Manual scrolling capture (port `ScrollMatcher` + `ScrollStitcher` and add stitcher tests), then Auto-Scroll with whichever injection method Phase 0 validates, with a clear "scroll by hand" fallback.
- Click highlights and keystroke display in recordings.
- Editor: backgrounds (gradient/wallpaper/image + aspect presets), snap to objects, repeat on similar objects, pixel ruler, colour tools + contrast, magnifier, spotlight, smart erase, resize, cut out, rotate/flip, Add Image, annotation copy/paste, pen shape recognition, hand-drawn style, tabs/dock, Drag Me, redact, Copy Text.

### Phase 4 - library, polish, optional
- Saved Files view with OCR index/search/filters, FS watching, thumbnails.
- Remove Background (optional model download), social-size presets polish, sounds, notifications styles, mica/acrylic polish, accessibility pass, localization, winget/MSIX distribution.
- Longer term (not in macOS app either): Studio mode, webcam overlay, upload targets - roadmap items #23-#25, #33.

### Cross-cutting rules for the whole port
- Extract the pure logic (3.1/3.2) into a shared library with its own tests first; the Windows test suite's initial milestone is "all ported tests green on synthetic fixtures", before any OS API work.
- Decide the coordinate convention (top-left, device pixels) once; keep conversion at the OS boundary only.
- Keep settings and the editor document JSON schemas versioned and OS-neutral if cross-platform document sharing is wanted (`EditorDocument.version`, `Preferences` keys).
- Do not copy the Mac "[weak self]" Swift concerns or the Swift warning policy from `CLAUDE.md`; but do mirror the "give the owner step-by-step manual test instructions for anything the tests don't cover" rule, since most of the Windows risk is in non-unit-testable behaviour.
