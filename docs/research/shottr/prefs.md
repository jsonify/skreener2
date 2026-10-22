# Shottr 1.9.3: Preferences and app-level UX vs. Skreener

Researcher: shottr-prefs. Sources: decoded `Preferences.storyboardc` nibs (6 nibs, decoded with `tools/nib.py`), Shottr `Info.plist`,
`tools/allstrings.txt` / `sFXfy/all.txt` string extracts, shottr.cc/kb/urlschemes (fetched 2026-10-22).
Skreener refs are relative to the repo root. Shottr was not launched; defaults it sets in code
could not be read (prefs plist sandboxed, checkbox states are not stored in the nibs), so default values are marked **inferred**.

## Gaps summary

| # | Feature | Skreener | Priority |
|---|---------|----------|----------|
| 1 | URL scheme / automation API (`shottr://grab/area?then=copy,save`), with opt-in toggle and a first-use confirm prompt | **missing** | High |
| 2 | After-capture action per trigger (`then=` param); first-run "Preview or Editor?" chooser | partial (global toggles only) | Med |
| 3 | Notification style: None / System Notification / Custom (in-app HUD) | **missing** (sounds and a few toasts only) | Med |
| 4 | Hide menu-bar icon (app reachable by re-launch / hotkeys / URL) | **missing** | Low-Med |
| 5 | Dock-icon / quit behaviour chooser ("If you quit, shortcuts stop working; close window instead?") | partial (accessory app, policy switches for editor) | Low |
| 6 | Reassign macOS ⇧⌘3/⇧⌘4 guide (steps + Open System Settings button, reads symbolic hotkeys) | partial (warns only) | Med |
| 7 | Hotkey for "Show app / reopen last screenshot" | **missing** | Low |
| 8 | Update check (version.json poll + in-app download & reinstall) | **missing** (TODO #34) | Med |
| 9 | Launch at login | **present** | — |
| 10 | Rebindable shortcuts (KeyboardShortcuts recorder) | **present** (stronger than Shottr) | — |
| 11 | Esc-to-close action (copy / save on Esc) | **missing** (cross-area: editor) | Med |
| 12 | Editor window: always on top, prefer 100% zoom, zoom with wheel, reverse scroll | partial (cross-area: editor) | Low |
| 13 | Screenshot settings in General: save format Auto(PNG/JPEG), downscale 1×, folder, window background (Wallpaper/Solid/Transparent/Trim shadow), thumbnail auto/manual close | mostly present; missing Auto format, Solid-color window bg, thumbnail close mode (cross-area) | Low |
| 14 | Scrolling capture speed slider + max height + reverse auto-scroll (Settings) | partial (fixed constants) (cross-area: capture) | Low |
| 15 | Diagnostics/telemetry opt-in | missing (not recommended to add) | — |
| 16 | License / trial / nag UX | n/a (Skreener is free) | — |
| 17 | Splash/intro window on launch, "What's new" intro | **missing** (Skreener: silent start) | Low |
| 18 | Permission prompts: Screen Recording explainer, Accessibility for scrolling, deep link to Privacy panes | partial | Med |
| 19 | Open images via Finder ("Open With", drag on Dock icon): CFBundleDocumentTypes png/jpeg/gif | **missing** | Low-Med |
| 20 | Reset all settings | **missing** | Low |
| 21 | Help/feedback links in menu (Suggest feature, Report bug, Twitter) | missing (About pane only) | Low |
| 22 | Localization | Shottr UI English only (KeyboardShortcuts bundle has de/es/hu/ru/zh-Hans/zh-TW) | — (parity) |
| 23 | Sensitive settings in Keychain (upload secrets) | n/a until upload exists (cross-area: output) | — |

---

## Shottr preferences window structure (observed)

`NSWindowController-3cz-fX-Ya1.nib`: an NSTabView window with tabs **General, Hotkeys, Uploading, Advanced, License**.

- **General** (`vXi-bH-nTd`): Autostart → "Launch at startup"; "After screenshot" → Show / Copy / Save checkboxes (`cbAfterGrabShow/Copy/Save`);
  "After Area Crop, show" → Thumbnail / Editor radios (`rbAreaPreview`/`rbAreaEditor`); "Hide preview thumbnail" popup →
  "Automatically (click outside)" / "Manually (close button)" (`ddlThumbnailClosing`); "Screenshots folder" + Select Folder;
  "Save format" Auto (PNG/JPEG) / PNG + help button; "Resize retina screenshots" → "Downscale to 1× when saving";
  "Window Screenshot Background" radios Wallpaper / Solid Color (`#C4C6C8` field) / Transparent / Trim shadow + help;
  "Scrolling screenshot speed" slider (0–3, nib value 2); "Scrolling screenshot max height" (px field).
- **Hotkeys** (`6sQ-om-XCe`): recorders for Fullscreen, Area, Repeat area, Active window, Any window, Scrolling, Instant Text/QR
  Recognition, Show Shottr; plus a "Reassign default shortcuts" section (see #6).
- **Uploading** (`PA4-Wk-i8P`): Disable / Shottr Cloud (token) / S3 (cross-area: output agent).
- **Advanced** (`NTL-U4-RCY`): Main window → Always on top; Default zoom level → Prefer 100%; Zoom with mouse wheel / Reverse scroll
  direction; Scrolling capture → Reverse scroll direction (auto-scroll); "Action when hiding with Esc" → Copy Image / Save Image;
  Menubar icon → Hide menubar icon (+help); Splash window (`cbHideSplash`); "Confirmation style" popup → None / System Notification /
  Custom Notification; Primary OCR language popup; OCR line breaks → Remove line breaks; URL Scheme API → Enable deep links;
  Diagnostics information → Allow collection.
- **License** (`YPR-Ju-4pY`): license number field, Activate, Purchase, Restore License, "Explore hidden features" (Friends Club).

Defaults keys (observed strings, prefix `setting-`): afterGrabSave, afterGrabCopy, afterGrabShow, saveOnEsc, copyOnEsc,
preferLargeWindow, ocrRemoveBreaks, showIntro, showMenubarIcon, alwaysOnTop, snappingMode, areaCustomGrabber,
scrollingCustomGrabber, scrollingManualEnabled, scrollingReverseAutoscroll, scrollingSpeed, scrollingMax, downscaleOnSave,
saveFormat, contrastType, colorFormat, windowSolidColor, windowShadow, thumbnailClosing, areaCaptureMode, captureCursor,
primaryOCRLang, uploadS3SharingMode, uploadMode, cmdQAction, altZoomDirection, defaultFolder (+ `defaultFolderBookmark`),
autostart, allowDeeplinks, notificationType, allowTelemetry, realPixels, libEnabled, libLimit, libLayout, libPopoveerSize.
Bookkeeping keys: everScrollingCapture, everHidMainWindow, everVisitedHotkeys, activeAppVersion, latestVersionCode/URL/PackageUrl,
customBackdropColor/HighlighterColor/DrawingColor.

---

## 1. URL scheme / automation API — MISSING (High)

**Shottr (observed):** `CFBundleURLTypes` registers scheme `shottr`. Command strings in binary: `grab/window/active`,
`grab/scrolling/reverse`, `settings/license`, `settings/scrolling/manual/enable|disable`, `settings/areacustomgrabber/`,
`settings/capturecursor/auto|include|exclude`, `settings/library/enable|disable|limit`. Errors: "Shottr: command is not recognized",
"Unrecognized "then" parameter … Available options: "copy", "save", "edit", "pin", or a comma-separated combination".
Gate: "Enable deep links" checkbox (`setting-allowDeeplinks`); when off and a link arrives, an alert asks
"Some app, perhaps on your behalf, tries to execute deep link shottr://… Do you want to enable deep links in Shottr?".
**Docs (observed, shottr.cc/kb/urlschemes):** `show`, `grab/fullscreen`, `grab/area`, `grab/repeat`, `grab/window`,
`grab/scrolling`, `grab/scrolling/reverse`, `grab/delayed`, `grab/delayed=10`, `grab/append`, `ocr`, `load/clipboard`,
`load/file`, `uploads`, `settings`; every `grab/*` takes `?then=copy,save,edit,pin,thumbnail`. Used for Raycast/Alfred/Shortcuts.
**Default (inferred):** deep links off until first confirm.

**Skreener:** no `CFBundleURLTypes` in `Scripts/build_app.sh` Info.plist heredoc; no Apple-event URL handler in
`Sources/Skreener/AppDelegate.swift`.

**Implementation:** add `CFBundleURLTypes` (scheme `skreener`) to the Info.plist in `Scripts/build_app.sh`. In
`AppDelegate.applicationDidFinishLaunching` (or implement `application(_:open urls:)`), parse with `URLComponents`:
host + path → command enum mapping onto existing `HotKeyAction` handlers (`ShortcutCenter.shared.handlers`), so
`skreener://capture/area`, `/capture/previous`, `/capture/fullscreen`, `/capture/window`, `/capture/scrolling`, `/capture/text`,
`/record`, `/timer/area?delay=5`, `/open/clipboard`, `/pin/clipboard`, `/history`, `/settings`. Add `then=` (copy,save,edit,pin,
quickaccess) as a per-call override of the After Capture prefs (needs a capture-options struct passed into the capture
pipeline instead of reading `Preferences` globals directly). New `Preferences.allowURLScheme` (default false) + Settings →
General "Allow URL scheme (for Raycast, Alfred, Shortcuts)"; when off, first incoming URL shows an NSAlert naming the
command with Enable / Cancel. Put the parser in a pure type (`URLCommand.parse(URL) -> URLCommand?`) so `swift test` covers it.
**Acceptance:** `open "skreener://capture/area?then=copy"` starts area selection and only copies; unknown command or bad `then`
shows an alert listing valid options; with the toggle off nothing runs until the user confirms; unit tests cover parsing.

## 2. After-capture action chooser — PARTIAL

**Shottr (observed):** General → "After screenshot": Show / Copy / Save (independent checkboxes) and "After Area Crop, show":
Thumbnail vs Editor. First-run modal (observed string): "Show small Preview or open the Editor? We will remember your choice.
You can always change it in preferences Later." Per-invocation override via URL `then=`.
**Skreener:** Settings → After Capture: Copy / Save / Open in editor / Show Quick Access toggles
(`Sources/Skreener/SettingsWindow.swift` ~251–266, `Preferences.copyToClipboard/autoSave/openEditorAfterCapture/showQuickAccess`).
Missing: one-time first-capture chooser and per-trigger overrides.
**Implementation:** on first successful capture with `Preferences.didChooseAfterCapture == false`, show an NSAlert with
"Quick Access preview" / "Open Editor" buttons, set the prefs and the flag. Per-trigger override comes with #1.
**Acceptance:** fresh defaults → first capture asks once; the choice is reflected in Settings → After Capture; never asked again.

## 3. Confirmation / notification style — MISSING

**Shottr (observed):** Advanced → "Confirmation style": None / System Notification / Custom Notification (`setting-notificationType`).
Uses `UNUserNotificationCenter` (delegate, `addNotificationRequest`), click handling ("Click to open in Finder" after save,
"URL copied to the clipboard"); falls back with "P.S. Shottr doesn't have permission to show System Notifications". Custom style
is an in-app popover HUD (`viewNotification`, `24-notification-logo/warning`). **Default (inferred):** Custom.
**Skreener:** no notifications; uses `NSSound` cues (`QuickAccess.swift:194`, `AppDelegate.swift:458`, `SelfTimer.swift:66`) and
editor toasts (`EditorWindow.swift` `showToast`). Background actions (auto-save with Quick Access off, OCR copy) give only a sound.
**Implementation:** `enum ConfirmationStyle { none, system, hud }` in `Preferences`; a `Notifier.confirm(title:, body:, fileURL:)`
used by save/copy/OCR/recording-saved paths. `.system` → `UNUserNotificationCenter` (request authorization lazily, on click
`NSWorkspace.activateFileViewerSelecting`). `.hud` → a small non-activating `NSPanel` near the menu bar for ~1.5 s (reuse the
editor toast view). Add a "Play sounds" toggle too, since Skreener's sounds are unconditional.
**Acceptance:** with Quick Access off and auto-save on, a capture shows the chosen confirmation; clicking a system notification
reveals the file; None shows nothing; denied notification permission falls back to the HUD.

## 4. Hide menu-bar icon — MISSING

**Shottr (observed):** Advanced → "Hide menubar icon" (`setting-showMenubarIcon`, `helpHideMenubar:`); Shottr is a regular app
(`LSUIElement` false), so it stays reachable via Dock/re-launch and the "Show Shottr" hotkey.
**Skreener:** status item always created (`AppDelegate.swift:30`); accessory app (`main.swift:6`), so hiding it would strand the
user unless re-open works.
**Implementation:** `Preferences.showMenuBarIcon` (default true); toggle `statusItem.isVisible`. Implement
`applicationShouldHandleReopen(_:hasVisibleWindows:)` to open Settings when the user launches Skreener again from Finder/Spotlight;
confirm with an alert explaining how to get it back (relaunch, or `skreener://settings`).
**Acceptance:** toggling off removes the icon immediately, hotkeys still work, launching the app again opens Settings, icon state
survives relaunch.

## 5. Dock icon / ⌘Q behaviour — PARTIAL

**Shottr (observed):** `setting-cmdQAction`; dialog "Red pill or blue pill?" — "If you quit the app, shortcuts will stop working.
If you close the window, dock icon will go away, but the app will stay in the menu bar. We will remember your choice."
**Skreener:** accessory app that switches activation policy when editor windows are open (`AppDelegate.swift:550`). ⌘Q in the
editor quits the whole app.
**Implementation:** intercept ⌘Q while an editor is key (`applicationShouldTerminate` when termination came from the main menu
with editors open): ask once "Quit Skreener / Close windows", store the choice in `Preferences.cmdQClosesWindows`.
**Acceptance:** first ⌘Q in the editor asks; choosing Close keeps hotkeys working and the menu-bar icon present.

## 6. Reassign macOS screenshot shortcuts — PARTIAL

**Shottr (observed):** Hotkeys pane "Reassign default shortcuts" section: steps "1. Go to System Settings → Keyboard → Keyboard
Shortcuts", "2. Select "Screenshots" and uncheck checkboxes for system shortcuts", "3. Put ⌘⇧3 into Fullscreen and ⌘⇧4 into Area
fields below", button "Open System Settings" (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts`),
"Reassign Default" button; reads `kHISymbolicHotKeyEnabled/Code/Modifiers` (inferred: checks whether the system shortcuts are
still enabled to show/hide the section). Keys `settings-reassignInitiated(-pref)`.
**Skreener:** `Shortcuts.swift:61,124–150` warns when a combo collides with a macOS shortcut; no guide or deep link.
**Implementation:** in `ShortcutRecorder.swift`'s Shortcuts pane add a group "Use ⇧⌘3 / ⇧⌘4 for Skreener" with the three steps,
an "Open Keyboard Shortcuts" button (same URL), and an "Assign ⇧⌘3/⇧⌘4/⇧⌘5" button that sets Capture Fullscreen/Area/Window.
Detect system state via `UserDefaults(suiteName: "com.apple.symbolichotkeys")?["AppleSymbolicHotKeys"]` ids 28–31 `enabled`
(read only); hide the steps when they are already off. Registration of ⇧⌘4 fails while macOS owns it, so show that result.
**Acceptance:** button opens Keyboard Shortcuts; after disabling macOS's ones and clicking Assign, ⇧⌘4 starts a Skreener area capture.

## 7. "Show app" hotkey — MISSING

**Shottr (observed):** hotkey "Show Shottr" (`vReopenHolder`) reopens the last screenshot / main window.
**Skreener:** no action for it in `HotKeyAction` (`Shortcuts.swift:155–158`).
**Implementation:** add `HotKeyAction.showLastCapture` (no default) that re-opens the newest editor tab or the newest
`CaptureHistory` entry in the editor. **Acceptance:** after closing the editor, the hotkey reopens the last capture.

## 8. Update check — MISSING (TODO #34)

**Shottr (observed):** `Updater` class; polls `https://shottr.cc/api/version.json?anticache=…`, stores latestVersionCode/URL/
PackageUrl; `suggestAutoupdate` dialog "Shottr will download the new version and re-install it. The app will restart…"; downloads
with URLSession and reinstalls, falls back to opening `https://shottr.cc/newversion.html`; events autoupdate:confirmed/rejected/
failed/canceled. `btnUpdate` / `introNewVersion` show a "new version" banner.
**Skreener:** none; About pane shows version/build only (`SettingsWindow.swift` ~369–390).
**Implementation:** simplest: Sparkle 2 via SwiftPM with an appcast on GitHub Releases (`Scripts/release.sh` already exists);
"Check for Updates…" menu item + "Automatically check" toggle in General. Lighter alternative: query the GitHub Releases API,
compare `CFBundleShortVersionString`, show an alert with a Download button.
**Acceptance:** with an older build, Check for Updates offers the new version; with the latest says up to date; no network → error alert.

## 9. Launch at login — PRESENT

**Shottr (observed):** General → "Launch at startup" (`setting-autostart`), sindresorhus LaunchAtLogin helper in
`Contents/Library/LoginItems`, also a status-menu item "Launch at Startup".
**Skreener:** `Sources/Skreener/LaunchAtLogin.swift` (SMAppService, handles requiresApproval) and Settings → General
(`SettingsWindow.swift:238`). Optional parity: a menu item. Nothing else needed.

## 10. Shortcut customization — PRESENT

**Shottr (observed):** sindresorhus KeyboardShortcuts `RecorderCocoa`, localized en/de/es/hu/ru/zh-Hans/zh-TW; strings
`keyboard_shortcut_used_by_system`, `..._used_by_menu_item`. 8 actions.
**Skreener:** `Shortcuts.swift`, `ShortcutRecorder.swift`, `HotKeys.swift`: 17 actions, grouped, conflict + system warnings,
reset per row and Restore Defaults. Skreener is ahead; only #6/#7 missing.

## 11. Esc action — MISSING (cross-area: editor)

**Shottr (observed):** Advanced → "Action when hiding with Esc": Copy Image / Save Image (`setting-copyOnEsc`, `setting-saveOnEsc`);
toolbar tooltip "Copy (Esc or …". **Default (inferred):** Copy on Esc on.
**Skreener:** not found in `EditorWindow.swift` prefs. **Implementation:** two toggles under Settings → Annotate → Editor Window;
in the editor's `cancelOperation(_:)`, when no tool/text edit is active, copy and/or save the rendered image, then close.
**Acceptance:** Esc with copy on closes the editor and the clipboard holds the annotated image.

## 12. Editor window prefs — PARTIAL (cross-area: editor)

**Shottr (observed):** Always on top (`setting-alwaysOnTop`); Prefer 100% ("When selected, Area Capture will open the editor at
100% zoom when possible, and Fullscreen Capture will open the editor at 80% zoom."); Zoom with mouse wheel + Reverse scroll
direction (`altZoomDirection`, `enableMagicMouseZoom`).
**Skreener:** editor has ⌘+wheel zoom (TODO #63) and tab prefs; no always-on-top or initial-zoom setting.
**Implementation:** `Preferences.editorAlwaysOnTop` → `window.level = .floating`; `editorPreferActualSize` → initial zoom 1.0 if it
fits the screen. **Acceptance:** toggles apply to newly opened editors.

## 13. Screenshot output prefs — mostly PRESENT (cross-area: output/capture)

Skreener has format PNG/JPEG, 1× downscale, filename template, folder, window shadow/transparent/padding
(`SettingsWindow.swift:271–321`). Missing vs Shottr: **Auto (PNG/JPEG)** format (JPEG for photographic content: "If the screenshot
has gradients, noise or photographs, it'll be saved as Jpeg…"), window background **Solid color** (`#C4C6C8` default observed in nib)
and **Wallpaper**, Quick Access "Hide preview: automatically (click outside) / manually (close button)". Leave detail to output/capture agents.

## 14. Scrolling capture prefs — PARTIAL (cross-area: capture)

Shottr: speed slider (0–3, nib value 2), max height px, reverse auto-scroll direction (for MOS/Scroll Reverser users), manual mode
toggle via URL. Skreener: fixed 30,000 px max and fixed speed (`ScrollCapture.swift`). Suggest exposing max height and speed in
Settings → Screenshots.

## 15. Telemetry — not recommended

Shottr: "Diagnostics information → Allow collection" (`setting-allowTelemetry`, posts to `tel.shottr.cc/telemetry.php`). Skreener has
none; keep it that way unless crash reporting is wanted (then opt-in, off by default).

## 16. License / trial — n/a

Shottr: License tab (activate, restore, purchase), "Regular tier … get rid of the Annoying Fellow" nag with probability params
(`startNagAfter`, `maxNagProb`), feature gates ("…only available after the license activation"), Friends Club experimental features,
keychain-stored license. Not applicable to Skreener.

## 17. Splash / intro window — MISSING (low value)

Shottr: "Splash window" toggle (`setting-showIntro`, `cbHideSplash`), intro views for standard / new version / purchase.
Skreener starts silently, only calling `CGRequestScreenCaptureAccess()`. Suggest a one-time welcome window instead (see #18).

## 18. Permission prompts — PARTIAL

**Shottr (observed):** Screen Recording: "Shottr needs permission to record the screen … Go to System Settings → Privacy & Security
→ Screen Recording, and check the checkbox next to the Shottr app." Accessibility for scrolling: "Scrolling Capture requires
accessibility permissions" with retry attempts and deep link
`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
**Skreener:** `AppDelegate.swift:71` calls `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess` at launch; Accessibility via
`AXIsProcessTrustedWithOptions` prompt in `RecordingEffects.swift:13–17` (also used by auto-scroll). No explanatory UI when capture
fails due to missing permission, no Settings section showing status.
**Implementation:** a "Permissions" group in Settings → General showing Screen Recording / Accessibility / Microphone status with
"Open System Settings" buttons (`…?Privacy_ScreenCapture`, `…?Privacy_Accessibility`, `…?Privacy_Microphone`), refreshed on window
activation; on first launch without screen access, a one-time welcome window explaining it instead of the bare system prompt; when
a capture comes back blank/denied, an alert with the same button.
**Acceptance:** with Screen Recording revoked, Settings shows "Not allowed" with a working button; capture shows the explainer.

## 19. Open images from Finder — MISSING

**Shottr (observed):** `CFBundleDocumentTypes` Editor role for public.png / public.jpeg / public.compuserve.gif; `openImage(file:)`,
`droppedImageAt(file:x:y:)`.
**Skreener:** Open… exists (`AppDelegate.openFile`), but no document types, so no "Open With → Skreener" or drop on Dock icon.
**Implementation:** add `CFBundleDocumentTypes` (LSHandlerRank `Alternate`, types public.png, public.jpeg, public.heic, public.tiff)
in `Scripts/build_app.sh`; implement `application(_:open urls:)` (shared with #1, distinguish file URLs) to open each in the editor.
**Acceptance:** right-click a PNG → Open With → Skreener opens it in the editor.

## 20. Reset all settings — MISSING

Shottr: "Reset all settings" string (location inferred: Advanced/debug). Skreener: only shortcut Restore Defaults.
**Implementation:** button in Settings → General ("Reset All Settings…", confirm alert) →
`UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)`, re-register shortcuts, rebuild Settings.

## 21. Help / feedback links — MISSING

Shottr: menu items "Shottr Help", suggestion/bug-report URLs with version param, "Shottr on Twitter". Skreener: About pane only.
Suggest "Report an Issue…" in the About pane / status menu opening the GitHub issues page with version prefilled.

## 22. Localization — parity

Shottr UI strings are English-only (Base.lproj only; `CFBundleDevelopmentRegion` en); only the KeyboardShortcuts bundle carries
de, en, es, hu, ru, zh-Hans, zh-TW. Skreener is English-only too. No gap.
