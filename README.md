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

1. Download the latest `Skreener-<version>.dmg` from the [Releases](https://github.com/jsonify/skreener2/releases) page.
2. Open the DMG and drag **Skreener** into **Applications**.
3. Open Skreener from Applications. Its icon shows up in the menu bar, not in the Dock.

Releases are not signed with an Apple Developer ID or notarized, so macOS blocks the first launch. To allow it:

1. Try to open Skreener once and click **Done**.
2. Open **System Settings > Privacy & Security**.
3. Next to the message about Skreener, click **Open Anyway** and confirm.

If macOS refuses to open it, run this once in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Skreener.app
```

After an update, macOS asks for Screen Recording permission again, because it treats each unsigned build as a new app.

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

## Major features

### Screenshots

- **Area, window and full screen**, plus **Previous Area** to repeat the last selection, and **Capture Active
  Window** to grab the front window without picking.
- **Area selection** comes with a pixel magnifier and a live size readout. Arrow keys nudge the pointer (Shift
  moves 10 pt). Hold Space to move the selection, Shift for a square, and Option to drag from the center.
- **Adjust before capturing.** After the drag the selection stays on screen. You can drag its handles or move it.
  Arrow keys move it, and Command + arrows resize it. The scroll wheel grows or shrinks every side. Return or a
  double-click takes the capture, and Esc cancels.
- **Window capture.** The visible part of the window under the pointer gets a tint, and a click captures the whole
  window, even if something covers it. You can add a shadow, a transparent or white background, and padding.
- **Freeze screen.** This optionally freezes the screen while you pick, so menus and hover states stay put.
- **Self-timer.** Pick an area, window or the full screen, then wait a 3, 5 or 10 second countdown.
- **Capture Area & Pin.** This captures an area and pins it in place at 100%.
- **Desktop icons.** You can hide them with a toggle, or only while capturing.

### Scrolling capture

- Pick an area, then scroll its content yourself. Or click **Auto-Scroll** and Skreener scrolls to the end for you.
- The frames are stitched into one tall image. Sticky headers and footers appear only once.

### Text recognition (OCR)

- **Capture Text** recognizes the text in an area on your Mac, using Apple's Vision framework. The text opens in a
  small scratch pad where you can fix it up or join the lines, then you copy it.
- In the editor, **Copy Text** copies the text from the whole screenshot or from a dragged area. **Redact** finds
  text, emails, phone numbers or links and pixelates them.

### Screen recording

- Record an area or a window to **MP4** or **GIF** at 30 or 60 fps.
- You can include system audio and the microphone (macOS 15+); with both on, they are mixed into one track.
- Other options: a countdown, dimming the rest of the screen, showing the cursor, click highlighting, keystroke
  display, and the elapsed time in the menu bar.
- A control bar shows the elapsed time, with pause, resume and stop.
- **Trim** cuts the start and end without re-encoding. A trimmed GIF is rebuilt from the trimmed video.

### Annotation editor

- **Tabs.** Each capture opens as a tab, shown as thumbnails in a dock beside the canvas.
- **Tools.** Arrow, rectangle, filled rectangle, ellipse, line, pen, highlighter, text, numbered counter, pixelate,
  blur, erase, spotlight and magnifier. Every tool has a single-key shortcut (V A R F O L P H T N X B E S M).
- **Styles.** Arrows come filled, open, double-headed or tapered, and they bend. Shapes can look hand-drawn. Text can
  sit on a solid box, an outlined box, or a speech bubble. Pen strokes are smoothed and can turn into clean shapes.
- **Stays editable.** You can select, move, resize, recolor, duplicate and reorder annotations, and copy and paste
  them between screenshots, with full undo and redo.
- **Snap to objects.** Boxes snap to the edges of buttons and shapes in the screenshot. **Repeat on Similar
  Objects** places the same box over every matching element.
- **Image operations.** Crop, rotate, flip, resize to exact sizes, **Cut Out** a strip and join the rest, and
  **Remove Background**.
- **Backgrounds.** Gradients, solid colors, your wallpaper or a picture of your own. There are presets for
  common aspect ratios and social media sizes, plus padding, corner radius and shadow.
- **Measure and pick colors.** Measure runs of color under the pointer, and copy colors in HEX, CSS, RGB,
  UIColor, Android, OKLCH and more. **Check Contrast** shows the WCAG 2 ratio or APCA value.
- **Export.** Save, Save As, copy, or drag a small preview straight into another app.

### After capture

- **Quick Access preview.** A thumbnail appears in the corner with buttons to copy, save, edit, pin, share or close.
  Later captures stack above it.
- **Pins.** Float any screenshot above other windows. You can scroll to change opacity and pinch to zoom.
- **Capture History.** Recent captures slide down from the top of the screen. The **Saved Files** view searches
  everything in your export folder by file name, app, or the text inside the screenshots.
- You choose what happens to each capture: copy, save, open the editor, or show the preview. You can also play a
  sound or show a notification.

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
| Other actions | `ocr`, `record`, `history`, `settings` |
| Open and pin | `load/clipboard`, `load/file`, `pin/clipboard`, `pin/file` |

`then=` (`copy`, `save`, `edit`, `pin`, `quickaccess`) overrides the After Capture settings for that one capture.
Links are off until you allow them in **Settings > General**, or from the prompt the first link shows.

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

- **Without a developer account.** Run `Scripts/release.sh --ad-hoc` to sign ad-hoc instead, with no certificate.
  CI does this automatically when the Developer ID secrets are not set. Not with a self-signed certificate: macOS
  calls a downloaded app signed that way "damaged" and offers no Open Anyway.

Merging a release PR or pushing a `v*` tag runs `.github/workflows/release.yml`. The secrets it needs are listed
at the top of that file.

## Roadmap

See [TODO.md](TODO.md) for what is done, in progress and planned, and [CHANGELOG.md](CHANGELOG.md) for released
changes.
