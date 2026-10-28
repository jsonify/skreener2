# Skreener

A screenshot and screen recording tool for macOS that lives in the menu bar. Skreener captures areas, windows,
full screens and long scrolling pages. It records video and GIFs, reads text from the screen, and opens every
capture in a full annotation editor.

Skreener is a clean-room tool in the style of CleanShot X. It was built only from publicly documented behavior.
No code from CleanShot X was decompiled or copied.

- [Requirements](#requirements)
- [Installation](#installation)
- [Permissions](#permissions)
- [Major features](#major-features)
- [Default shortcuts](#default-shortcuts)
- [Building from source](#building-from-source)
- [Development](#development)
- [Roadmap](#roadmap)

## Requirements

| | |
|---|---|
| macOS | 14 Sonoma or later |
| Recording with the microphone | macOS 15 Sequoia or later |
| Building from source | Xcode 16 or later (Swift 5.9+, macOS 15 SDK) |

## Installation

### From a release

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/jsonify/skreener2/main/Scripts/install.sh | bash
```

It downloads the latest release, checks it against the release's checksums, installs it in **Applications** and
opens it. Its icon shows up in the menu bar, not in the Dock. Run the same command again to update, or use
**Check for Updates…** in Skreener's menu: Skreener also checks once a day and asks before installing.

Releases are signed with Skreener's own certificate, not an Apple Developer ID. Every release has the same
certificate, so the Screen Recording permission you grant once carries over to every update. macOS only checks
apps downloaded in a browser, and calls a browser-downloaded copy "damaged". If you downloaded the DMG or zip from the
[Releases](https://github.com/jsonify/skreener2/releases) page instead, drag Skreener into **Applications** and run
this once before opening it:

```sh
xattr -dr com.apple.quarantine /Applications/Skreener.app
```

### From source

See [Building from source](#building-from-source).

## Permissions

The first time you capture, macOS asks for **Screen Recording**. Grant it in **System Settings > Privacy & Security >
Screen Recording**, then restart Skreener. **Settings > General** shows the status of every permission and links to
the right pane.

| Permission | Needed for |
|---|---|
| Screen Recording | All screenshots and recordings |
| Accessibility | Auto-Scroll in scrolling capture |
| Microphone | Recordings with the microphone turned on (macOS asks the first time) |

Permissions switched on but not working, or asked for again after every build? See
[Resetting permissions](docs/resetting-permissions.md).

A new install opens a short **Welcome Guide** that walks through the permission, the capture shortcut and the
selection keys. After an update, **What's New** lists the changes. Both are also under **Help** in the menu-bar menu.

## Major features

### Screenshots

- **Area, window and full screen**, plus **Previous Area** to repeat the last selection, and **Capture Active
  Window** to grab the front window without picking.
- **Area selection** comes with a pixel magnifier (or the pointer's coordinates when it is off), crosshair lines
  across the screen, and a live size readout. Arrow keys nudge the pointer (Shift
  moves 10 pt). Hold Space to move the selection, Shift for a square, and Option to drag from the center.
- **Adjust before capturing.** After the drag the selection stays on screen. You can drag its handles or move it.
  Arrow keys move it, and Command + arrows resize it. The scroll wheel grows or shrinks every side. Return or a
  double-click takes the capture, and Esc cancels.
- **Window capture.** The visible part of the window under the pointer gets a tint, and a click captures the whole
  window, even if something covers it. You can add a shadow, a transparent or white background, and padding.
- **Freeze screen.** This optionally freezes the screen while you pick, so menus and hover states stay put.
- **Self-timer.** Pick an area, window or the full screen, then wait a 3, 5 or 10 second countdown.
- **Capture Area & Pin.** This captures an area and pins it in place at 100%.
- **Live Pin.** A pin that keeps updating, like picture-in-picture for an area (**Capture Area & Live Pin**, or the
  All-in-One bar) or a window (**Live Pin Window…**, which keeps showing it when other windows cover it). It runs at
  5 fps by default (10 or 15 in Settings or the pin's right-click menu). **Freeze** turns it into a regular pin.
- **Desktop icons.** You can hide them with a toggle, or only while capturing.

### Scrolling capture

- Pick an area, then scroll its content yourself. Or click **Auto-Scroll** and Skreener scrolls to the end for you.
- The frames are stitched into one tall image. Sticky headers and footers appear only once.

### Text recognition (OCR)

- **Smart actions** look through each capture for dates, addresses, phone numbers, links, flights and QR codes or
  barcodes, off the main thread. Quick Access shows buttons for them (Add to Calendar, Open in Maps, Call, Open Link,
  Copy or Open QR content), with more in a menu; the editor's text menu has the same under Smart Actions. Turn it
  off in Settings → After Capture. **Scan QR Code** (no default shortcut, or `skreener://qr`) copies what the codes
  in an area say and offers to open a link.

- **Capture Text** recognizes the text in an area on your Mac, using Apple's Vision framework. The text opens in a
  small scratch pad where you can fix it up or join the lines, then you copy it.
  Capture more text while it is open and it is added on a new line at the cursor.
  **Speak** (Option-Command-S, in the scratch pad) reads the selection, or all the text, aloud in a voice that
  matches its language; it turns into **Stop** until the speech ends.
- **Capture Code** (menu bar or `skreener://ocr/code`) is Capture Text for code on a screen, slide or video: it
  copies the text with its indentation kept and common OCR mistakes fixed (curly quotes, `l`/`O` inside numbers).
  Settings can copy it as a Markdown code block.
- In the editor, **Copy Text** copies the text from the whole screenshot or from a dragged area. **Redact** finds
  text, emails, phone numbers or links and pixelates them. The **Redact Text** tool finds the words you type
  (several at once, with Match Case, Whole Word, Regex and Fuzzy options), highlights every match so you can click
  away false positives, and covers the rest with a solid box, pixelation, blur or erase in one undoable step.

### Watch This Area

- **Watch This Area** checks an area (or the previous area) every 5 s, 30 s, 1 min or 5 min and notifies you when it
  changes (Low, Medium or High sensitivity), or when a text you type appears or disappears (on-device OCR), e.g.
  "Build succeeded". Press Space in the picker to watch a window instead: it keeps working while other windows cover it.
- The notification shows before and after side by side; click it to open both in the editor. While a watch runs the
  menu-bar icon is an eye, and the menu offers **Stop Watching**.

### Screen recording

- Record an area or a window to **MP4** or **GIF** at 30 or 60 fps.
- You can include system audio and the microphone (macOS 15+); with both on, they are mixed into one track.
- Other options: a countdown, dimming the rest of the screen, showing the cursor, click highlighting, keystroke
  display, a cursor spotlight (dims all but a soft circle around the pointer; radius and dim amount are in the
  options, and Control-Shift-S turns it on or off while recording), and the elapsed time in the menu bar.
- A control bar shows the elapsed time, with pause, resume and stop.
- **Trim** cuts the start and end without re-encoding. A trimmed GIF is rebuilt from the trimmed video.
- **Zoom & Draw on Screen** for calls and recordings: draw with a pen, arrows or boxes (P, A, R; colors on 1 to 5,
  Command-Z undoes), scroll or press Command-Plus / Command-Minus to zoom in around the pointer, and move the pointer
  to pan. Esc clears, a second Esc leaves. The marks and the zoom show up in an ongoing recording.

### Annotation editor

- **Tabs.** Each capture opens as a tab, shown as thumbnails in a dock beside the canvas.
- **Tools.** Arrow, rectangle, filled rectangle, ellipse, line, pen, highlighter, text, numbered counter, pixelate,
  blur, erase, spotlight and magnifier. Every tool has a single-key shortcut (V A R F O L P H T N X B E S M).
- **Shortcut list.** Press **?** in the editor, or choose **Help > Keyboard Shortcuts**, for a searchable list of
  every tool, editor key, capture modifier and your own global shortcuts.
- **Variants and right-click.** Hold the Rectangle or Arrow button, or click its corner triangle, for filled, open,
  double or tapered, and hand-drawn. Right-click an annotation to copy and paste its style or turn a rectangle into
  a filled one; right-click the canvas for Paste, Cut Out, Remove Background, Check Contrast and Ask Claude.
- **Styles.** Arrows come filled, open, double-headed or tapered, and they bend. Shapes can look hand-drawn. Text can
  sit on a solid box, an outlined box, or a speech bubble. Pen strokes are smoothed and can turn into clean shapes.
- **Stays editable.** You can select, move, resize, recolor, duplicate and reorder annotations, and copy and paste
  them between screenshots, with full undo and redo.
- **Snap to objects.** Boxes snap to the edges of buttons and shapes in the screenshot. **Repeat on Similar
  Objects** places the same box over every matching element.
- **Image operations.** Crop, rotate, flip, resize to exact sizes, **Cut Out** a strip and join the rest, and
  **Remove Background**. **Balance** (in the Background bar and the Image menu) trims uneven empty margins and centers
  the content by cropping, so you can still adjust it with Crop.
- **Combine Screenshots.** This lays 2 to 9 captures out in a row, column or grid on a new canvas. The captures stay
  movable images. Pick them from the editor tabs or the history.
- **Photos from your iPhone or iPad.** **Add Image > Import from iPhone or iPad** takes a photo, scans documents or
  adds a sketch on a nearby iPhone or iPad (same Apple ID, Wi-Fi and Bluetooth on), and places it as a movable layer.
  The menu-bar menu's **Open from iPhone or iPad** opens the picture in a new tab.
- **Backgrounds.** Gradients, solid colors, your wallpaper or a picture of your own. There are presets for
  common aspect ratios and social media sizes, plus padding, corner radius and shadow.
- **Frames.** Wrap a screenshot in a macOS window, a browser (with an address you can edit), a MacBook, an iPhone
  or an iPad, light or dark. It sits inside the background and is saved with the capture.
- **Measure and pick colors.** Measure runs of color under the pointer, and copy colors in HEX, CSS, RGB,
  UIColor, Android, OKLCH and more. **Check Contrast** shows the WCAG 2 ratio or APCA value.
- **Tips and hints.** A few one-time tips point out shortcuts as you go (one per session at most). A faint line
  under the canvas says what the handle or drag under the pointer does, such as "Drag to bend". A small dot or a
  "New" badge marks features you haven't tried yet. Turn these off, or show them all again with Reset Tips, in
  Settings → General.
- **Export.** Save, Save As, copy, or drag a small preview straight into another app.
- **Compress.** Optionally shrink PNGs (a palette of up to 256 colors, only when it looks the same) and recordings
  (HEVC) when saving, or press Compress in Quick Access or the saved-files menu. It shows the size before and after.
- **Ask Claude.** The sparkles button sends the screenshot to Claude to explain an error, summarize a chart, write
  alt text, or answer your own question, and shows the answer to copy. It uses your own Anthropic API key (Settings →
  Ask Claude, kept in the Keychain), and nothing is sent until you press Ask. With a Claude plan instead of a key,
  **Open in Claude** copies the screenshot and opens Claude in your browser with the question filled in: paste and
  send. (Anthropic doesn't let other apps sign in with a Claude subscription.)

### After capture

- **Quick Access preview.** A thumbnail appears in the corner with buttons to copy, save, edit, pin, share or close.
  Later captures stack above it.
- **Pins.** Float any screenshot above other windows. You can scroll to change opacity and pinch to zoom.
  To check a build against a mockup, pin the mockup over the app and right-click it. **Onion Skin** makes it
  see-through, and **Difference** lights up every pixel that doesn't match the app underneath. **Click-Through**
  lets your clicks reach the app; Control-Shift-0 turns it off again. The arrow keys nudge a pin by 1 pt, or 10 pt
  with Shift.
- **Capture History.** Recent captures slide down from the top of the screen. The **Saved Files** view searches
  everything in your export folder by file name, app, or the text inside the screenshots.
- **Source page.** Captures of Safari, Chrome, Arc, Edge or Brave remember the page's address and title. Saved Files
  and History can open it again, Saved Files searches it and filters by site, and Finder shows it under Where from.
  macOS asks once per browser for Automation access; without it the capture just has no page. A switch in
  Settings → After Capture turns it off.
- **Filing rules.** In **Settings → After Capture → Filing Rules** you send saved captures to their own folders by the
  app they came from or the text in them, e.g. "App name is Figma → ~/Design/Screens" or "Text contains Invoice →
  ~/Receipts". Both ignore case, the first rule that matches wins, and each rule can be switched off. A text rule moves
  the screenshot a moment after saving, once its text has been read. A file is never replaced (a taken name gets a
  number), a missing folder is made, and Saved Files keeps showing and searching moved captures.
- **Finder tags and Spotlight.** Two switches below the rules, off by default: tag saved captures with the app's name
  (e.g. a "Safari" tag in Finder), and put the text read in a screenshot in its Spotlight comment, so Spotlight finds
  it by any word in it.
- You choose what happens to each capture: copy, save, open the editor, or show the preview. You can also play a
  sound or show a notification.

### Send To and custom actions

- **Send To menu.** The paper-plane button in Quick Access and the editor footer, and **Send To** in the right-click
  menu of Capture History, list your own actions. The editor sends the screenshot with its annotations.
- **Custom actions.** In **Settings → Send To** you add a name and a shell command. It runs with `/bin/zsh -lc` (so
  your PATH and Homebrew tools work) for up to 60 seconds, after the capture is saved, and never holds up a capture.
  The capture's path is `$1` and `$SKREENER_FILE`, the app it came from is `$SKREENER_APP`, and the text in it is
  `$SKREENER_TEXT` (only read when your command mentions it). Skreener shows what the command printed, or why it
  failed. Tick **Copy the output to the clipboard** for commands that print a link, and **Run after every capture**
  to run it on each screenshot without picking it.

  ```sh
  rsync "$SKREENER_FILE" server:/shots/
  curl -s -F "file=@$1" https://example.com/upload
  open -a Preview "$SKREENER_FILE"
  ```
- **Notes apps.** Send To also lists the notes apps you have installed: Obsidian, Bear, Apple Notes, Drafts, Things
  and Reminders. **Settings → Send To** picks which show, and whether the text found in the screenshot goes along.
  Bear and Apple Notes get the picture inside the note. Drafts, Things and Reminders only hold text, so they get the
  text and the picture is put on the clipboard to paste. Obsidian can't be handed a file: choose your vault's folder in
  Settings, and Skreener copies the picture into its `Skreener` folder and appends `![[picture]]` and the text to the
  note `Skreener/Captures` (or to today's daily note, if you have the Advanced URI plugin). Apple Notes and Reminders
  ask for permission to be controlled the first time.

### Automation

Skreener answers `skreener://` links, so Raycast, Alfred, Shortcuts or a shell script can drive it:

```sh
open "skreener://grab/area?then=copy,save"
open "skreener://grab/delayed/window?delay=5"
open "skreener://ocr"
```

| Group | Commands |
|---|---|
| Capture | `grab/area`, `grab/previous`, `grab/fullscreen`, `grab/window`, `grab/window/active`, `grab/scrolling`, `grab/delayed[/area\|/window\|/fullscreen]?delay=N` |
| Other actions | `ocr`, `record`, `watch/area`, `history`, `settings` |
| Open and pin | `load/clipboard`, `load/file`, `pin/clipboard`, `pin/file`, `pin/live`, `pin/live/window` |

`then=` (`copy`, `save`, `edit`, `pin`, `quickaccess`) overrides the After Capture settings for that one capture.
Links are off until you allow them in **Settings > General**, or from the prompt the first link shows.

#### Shortcuts actions

The Shortcuts app also lists Skreener's own actions, which take and return images, so you can chain them with other
apps: **Capture Area**, **Capture Window** and **Capture Fullscreen** return the screenshot as an image file
(After Capture steps don't run), **Capture Text** returns the recognized text, **Pin Image** and **Open in Editor**
take an image, and **Record Screen** starts or stops a recording. They work whether or not links are allowed. Siri and Spotlight know phrases like "Capture an
area with Skreener" without any setup.

## Default shortcuts

You can change every shortcut in **Settings > Shortcuts**. Skreener warns you when a combination is already taken
by macOS or by another action. The same pane walks you through handing the system's Shift-Command-3 and
Shift-Command-4 over to Skreener.

| Action | Shortcut |
|---|---|
| Capture Area | Control-Shift-4 |
| Capture Fullscreen | Control-Shift-3 |
| Capture Window | Control-Shift-5 |
| Capture Previous Area | Control-Shift-1 |
| Capture Text (OCR) | Control-Shift-2 |
| Capture Area & Pin | Control-Shift-6 |
| Record Screen (press again to stop) | Control-Shift-7 |
| Capture Scrolling | Control-Shift-8 |
| Capture History | Control-Shift-H |
| Pin Click-Through On / Off | Control-Shift-0 |
| Zoom & Draw on Screen (press again to leave) | Control-Shift-Z |
| Cursor Spotlight (while recording) | Control-Shift-S |

## Building from source

You need a Mac with Xcode 16 or later.

```sh
git clone https://github.com/jsonify/skreener2.git
cd skreener2
Scripts/build_app.sh          # builds build/Skreener.app
open build/Skreener.app
```

macOS ties the Screen Recording permission to the app's signature. To keep the permission across rebuilds, create a
stable local signing certificate once:

```sh
Scripts/make_dev_cert.sh      # creates "Skreener Dev"; build_app.sh then signs with it automatically
Scripts/build_app.sh --run    # quits the running copy, rebuilds and relaunches
```

## Development

### Tests

```sh
swift test
```

The unit tests in `Tests/SkreenerTests` cover the logic that runs without a screen or permissions. CI builds and
tests with warnings treated as errors, so builds must be warning-free.

### Versions and commit messages

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org), such as `fix(editor): ...`,
`feat(capture): ...` or `docs: ...`, and a CI check enforces this on pull requests.
[release-please](https://github.com/googleapis/release-please) uses them to keep a release PR open with the next
version and the changelog:

- `fix` bumps the patch version.
- `feat` bumps the minor version.
- `feat!:` or a `BREAKING CHANGE:` footer bumps the major version. It bumps the minor version while below 1.0.

Merging the release PR tags `vX.Y.Z` and updates `CHANGELOG.md` and `version.txt`. CI then attaches a DMG and zip of the
signed app to the GitHub release.

`build_app.sh` takes the version from the newest `vX.Y.Z` tag, the build number from the commit count, and adds the
short commit hash. The About panel shows all three, for example `0.2.0 (412, 48db438)`.

### Releases

`Scripts/release.sh` builds, signs, packages and (optionally) notarizes the app. It writes a DMG, a zip and
`SHA256SUMS` to `build/release/`. Run `Scripts/release.sh --help` for all options.

- **With an Apple Developer ID.** Signing uses your Developer ID Application certificate with the hardened runtime,
  then notarizes and staples the app. Credentials come from your keychain or environment, never from the repo:

  ```sh
  xcrun notarytool store-credentials skreener-notary --apple-id you@example.com --team-id TEAMID   # once
  SKREENER_NOTARY_PROFILE=skreener-notary Scripts/release.sh --version 0.2.0
  ```

  If you have several Developer ID identities, pick one with `SKREENER_DEVELOPER_ID`.

- **Without a developer account.** Run `Scripts/release.sh --self-signed` to sign the app with the "Skreener Dev"
  certificate instead. macOS calls a browser download of such an app "damaged", so people install with
  `Scripts/install.sh` or the in-app updater, which don't mark the download as quarantined. The DMG stays unsigned,
  because macOS refuses to open a disk image signed with a certificate Apple didn't issue. CI does this automatically
  when the Developer ID secrets are not set. To set it up for CI, export the **Skreener Dev** certificate that
  `Scripts/make_dev_cert.sh` created from Keychain Access as a `.p12`. It is the one that expires 10 years out and lists
  **Code Signing** under Extended Key Usage. A certificate made with Keychain Access's Certificate Assistant is for
  e-mail unless you change its type, and macOS rejects apps signed with it; the release build refuses one. Add the
  `.p12` as the repository secret `SELF_SIGNED_P12_BASE64` (base64-encoded) and its password as
  `SELF_SIGNED_P12_PASSWORD`, then delete the `.p12` file. Keep the certificate itself: a new one would make every user
  grant Screen Recording again.

Merging a release PR or pushing a `v*` tag runs `.github/workflows/release.yml`. The secrets it needs are listed
at the top of that file.

## Roadmap

See [TODO.md](TODO.md) for what is done, in progress and planned, and [CHANGELOG.md](CHANGELOG.md) for released
changes.
