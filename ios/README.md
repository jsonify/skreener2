# Skreener for iOS

An app and a Share Extension for iPhone (#396, #408). The editor puts a screenshot in a device frame on a background,
covers private parts (a dragged area, or emails, phone numbers, links and typed text found by on-device OCR) with
pixelate, blur or solid black, checks each screenshot as it opens for things not to share (Safe Check: emails,
phone numbers, links, one-time codes, card numbers, API keys and faces, all on the device), marks it up with arrows, rectangles, text and highlights, then saves it to Photos,
copies it or shares it at full size.

There are two ways in. Open the **Skreener** app: its home screen shows the screenshots taken since you last left it,
and has keys for the latest screenshot and for choosing any image. Or, in Photos (or any app), tap Share and choose
**Skreener**. Both open the same editor.

- `Skreener/`: the app (SwiftUI, the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit)): the home screen
  with the inbox of new screenshots, which opens the editor full screen. It reads the Photos Screenshots album and
  asks for that access only when you tap Show my screenshots or Latest screenshot. Its icon, `Skreener/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, is the Mac app's icon as an opaque
  full-bleed square (iOS rounds the corners), drawn by `Scripts/make_icons.py` with the Mac one: change it there.
- `SkreenerEditor/`: the editor as a framework: the screens, redact and draw canvases, rendering and export. It draws
  with `SkreenerCore`, the library shared with the Mac app. The app embeds it; the extension uses it. Both hand it an
  `ImageSource` (the extension's items, or image bytes), which it loads again for each export.
- `SkreenerShare/`: the Share Extension. Only its view controller, which hosts the editor.
- `project.yml`: the [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Bundle IDs are `com.skreener.ios` and
  `com.skreener.ios.share` (the framework is `com.skreener.ios.editor`); iOS 17 or later, iPhone only.

The `.xcodeproj` is generated and not committed (it is in `.gitignore`). The Info.plists are
generated from `project.yml`'s `info:` sections and ignored too: change them there. So are the `.entitlements` files
(`entitlements:`).

## Setup (once)

```
brew install xcodegen
```

The app and the extension share the editor's last look (frame, background, sliders) through the App Group
`group.com.skreener.ios`, which must exist for your team. Xcode's automatic signing registers it on the first build to
a device. If signing fails over it, select each of the `Skreener` and `SkreenerShare` targets, open Signing &
Capabilities, and add the App Groups capability with `group.com.skreener.ios` ticked.

## Build and run

```
cd ios
xcodegen generate
open Skreener.xcodeproj
```

1. Signing, once: copy `Local.xcconfig.example` to `Local.xcconfig` and put your Team ID in it
   (`cp Local.xcconfig.example Local.xcconfig`, then edit). The Team ID is the 10-character code under Membership
   details at developer.apple.com/account, or in Xcode under Settings > Accounts > your Apple ID > the team.
   `Local.xcconfig` is gitignored and both targets read it through `Signing.xcconfig`, so the Team survives every
   `xcodegen generate`. Run `xcodegen generate` again after pulling changes.
2. Connect an iPhone (iOS 17 or later), choose it as the run destination and press Run with the `Skreener` scheme.
   On first install the phone may ask you to trust the developer under Settings > General > VPN & Device Management.

## Try the app

1. Take two or three screenshots on the phone first (side button and volume up).
2. Open **Skreener** from the Home Screen. Nothing asks for Photos access. The LCD reads "TAP SHOW MY SCREENSHOTS",
   the tray says "Your new screenshots show here", and there are **Show my screenshots** (orange), **Latest
   screenshot** and **Choose screenshot** keys. The hint at the bottom says Skreener is in the share sheet too.
3. Tap **Show my screenshots**. iOS asks for Photos access, with "Skreener shows your recent screenshots so you can
   edit them."
   - **Allow Full Access**: the newest 12 screenshots appear as a grid, newest first, and the LCD reads "12 NEW" (or
     fewer if you have fewer). The Show my screenshots key goes away.
   - **Limit Access...**: pick one or two screenshots and tap Done. Only those appear; the LCD reads "N SELECTED"
     and a **Select more** key appears. Tap it, add another screenshot, tap Done: it joins the grid. With none
     selected, the LCD reads "NO SCREENSHOTS SELECTED" and the hint points to Select more and Choose screenshot.
   - **Don't Allow**: the LCD reads "PHOTOS ACCESS IS OFF" and the hint says to allow Skreener in Settings > Privacy &
     Security > Photos. Choose screenshot still works. Turning access on in Settings and coming back shows the grid.
4. With full access, go to the Home Screen, take two new screenshots, and open Skreener again: the grid shows only
   those two and the LCD reads "2 NEW". Go to the Home Screen and come back without taking any: "NO NEW
   SCREENSHOTS". A screenshot taken while Skreener is open shows up straight away.
5. Tap a screenshot in the grid. The LCD reads "OPENING…" (longer if it is in iCloud only), then the editor fills the
   screen with that screenshot.
6. Safe Check: under the preview, the readout first says "SAFE CHECK…", then what it found, as in the extension's
   step 4 below. Try it here with a screenshot of a message that has a 6-digit code and a phone number: "SAFE CHECK ·
   2 FOUND", the lamp beside it lit orange, "1 phone number · 1 code" under it. **Review 2**, untick one, **Redact 1**:
   "SAFE CHECK · 1 LEFT". A screenshot with nothing private reads "SAFE CHECK · CLEAR".
7. In the editor, pick a frame (say Browser, Dark on) and a background, move the Padding slider, cover an area in **Redact** and draw an arrow in **Draw**, as in
   the extension steps below.
8. Tap **Save**. The first time, iOS asks to add to Photos: allow it. The readout says "Saved to Photos" and the
   edited PNG is in Photos. **Copy** and **Share** work as in the extension; Share shows the system share sheet with
   `Skreener.png`.
9. Tap **Close**: the home screen is back.
10. Tap **Latest screenshot**: the newest screenshot opens in the editor. (If Photos access was never asked, this key
    asks first, like Show my screenshots.) Close.
11. Tap **Choose screenshot**: the system photo picker opens, showing only images, without asking for any access.
    Pick one: it opens in the editor. Close.
12. The editor starts with the style you used last: open any screenshot again and the frame, Dark, background and
    sliders are as you left them (redactions and drawings start empty). Now set a different frame and background,
    Close, and share a screenshot from Photos to Skreener (see below): the extension starts with that same look.

## Try the extension

1. Take a screenshot on the phone and open it in Photos. For Safe Check, use a message that shows a 6-digit code
   and a phone number (e.g. a sign-in text); also have a screenshot with nothing private on it.
2. Tap Share. If Skreener is not in the app row, scroll to its end, tap More, and turn Skreener on (or use
   Edit Actions... in the share sheet).
3. Choose Skreener. Switch the frame and background. The Dark switch is there for every frame but None; Browser also
   has an address field. With a background chosen, the Padding, Corners and Shadow sliders appear (scroll the controls
   if they do not fit; the preview stays put).
4. Safe Check: under the preview, the readout says "SAFE CHECK…" for a moment, then "SAFE CHECK · 2 FOUND", the
   small lamp to its left lit orange and "1 phone number · 1 code" under it (it also finds emails, links, card
   numbers, API keys and faces). Nothing is sent anywhere. Tap **Review 2**: the editor switches to Redact and both
   have an orange outline; the key beside the readout is now **Redact 2**. Tap the phone number's outline: it turns
   dashed and the key reads **Redact 1**. Tap **Redact 1**: the code is covered with the current Cover style
   (Pixelate unless changed) and the readout says "SAFE CHECK · 1 LEFT", lamp still lit, with **Review 1**. Review
   it and Redact 1 again: "SAFE CHECK · COVERED", lamp off. **Undo** takes back that last cover (the readout says
   1 left again). A face in the screenshot is found and covered the same way. Open a screenshot with nothing
   private: the readout says "SAFE CHECK · CLEAR" with the lamp off and no Review key. After Save or Copy (step 12),
   the readout shows "Saved to Photos" or "Copied" for a few seconds, then the Safe Check line again.
5. Switch **Mode** to **Redact**. The preview shows the screenshot alone. Drag across some text: an orange dashed band
   follows your finger, and on release the area is pixelated. Pick **Blur** or **Solid** under Cover and drag again;
   that area is blurred or black. **Undo** takes back the last area, **Clear** all of them.
6. Tap **Emails** (or **Phones**, **Links**): the readout says "Reading text…", then "N matches · N selected" and each
   match has an orange outline. Tap one: its outline turns dashed and the count drops. Or type a word into the Text
   field (several separated by commas). **Redact N** covers the selected matches with the current Cover style.
7. Switch **Mode** to **Draw**. The preview shows the screenshot with its redactions. With **Arrow** (and the red
   swatch on), drag from a spot to what it points at: a red arrow follows your finger, its head at the finger, and stays
   on release. A very short drag draws nothing.
8. Pick **Rect** and drag: a red rounded outline. Pick **Highlight**, pick the yellow swatch and drag across a line of
   text: a translucent yellow band, the text still readable through it.
9. Pick **Text** and tap the picture: a small orange ring marks the spot, a Text field appears at the top of the
   controls with the keyboard up (the Mode switch and the output keys step aside meanwhile). Type a word: it shows on
   the picture as you type, its left end at the ring. **Done** (or the keyboard's Done) keeps it; **Cancel**, or Done
   with nothing typed, adds nothing. Tapping elsewhere on the picture while typing moves the label.
10. **Undo** takes back the last drawing, **Clear** all of them; the redactions stay. Undo in Redact still takes back
    only areas.
11. Switch back to **Style**: the frame and background return, with the redactions and drawings on the screenshot
    (drawings over redactions). They are in every export too, at full size.
12. Tap **Save**. The first time, iOS asks to add to Photos: allow it. The readout says "Saved to Photos" and the
    full-resolution PNG is in the Photos library. If you deny, the sheet says to allow "Add Photos Only" for Skreener
    in Settings > Privacy & Security > Photos.
13. Tap **Copy** and paste into Notes or Messages. Tap **Share** for the system share sheet with `Skreener.png`.
14. **Close** (top left) ends the sheet.
15. Open the share sheet again: the frame, Dark, background and sliders are as you left them. Change them, Close,
    and open the Skreener app and a screenshot: the app's editor shows the look you just set in the extension. A fresh
    install starts with iPhone frame, Dark off, the first background and Padding 48, Corners 10, Shadow 50%.

## Privacy manifest

The app has `Skreener/PrivacyInfo.xcprivacy`: it stores when it was last sent to the background in `UserDefaults`,
to know which screenshots are new (reason `CA92.1`, the app's own defaults), and the editor's last look in the shared
App Group defaults (reason `1C8F.1`), so the manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with both.
The extension has its own `SkreenerShare/PrivacyInfo.xcprivacy`, copied as a resource the same way, declaring the same
category with `1C8F.1`: the editor framework runs inside it and reads and writes the shared defaults. Both declare no
tracking and no collected data. The framework, `SkreenerCore` and SK1Kit use none of Apple's other required-reason APIs
(file timestamps, system boot time, disk space, active keyboards). Add an entry, to the target that makes the call, if
that changes.

## Upload to TestFlight

1. Bump `MARKETING_VERSION` in `project.yml` when the build is a new version (testers see it as 0.1.0, 0.2.0...).
2. `xcodegen generate`, always, right before archiving: it stamps a fresh build number, the UTC time as YYMMDD.HHMM
   without leading zeros in the second part (2026-11-04 09:05 is `261104.905`), into the gitignored
   `BuildNumber.xcconfig`; the command prints it. App Store Connect rejects an upload whose build number is not
   higher than the last one's, so archiving from a project generated before the last upload fails there: generate
   again and re-archive. Both targets get the same number, as App Store Connect requires.
3. In Xcode, run destination **Any iOS Device (arm64)**, **Product > Archive**, then in the Organizer **Distribute App >
   App Store Connect > Upload**. The build appears under TestFlight in App Store Connect after processing.

## Upload from GitHub Actions

`.github/workflows/testflight.yml` archives and uploads without a Mac. It runs by itself on every merge to `main` that
changes `ios/`, `Sources/SkreenerCore/` or `Package.swift` (a Mac-only or docs-only merge uploads nothing). To upload
another branch, or `main` again: Actions tab > **TestFlight** > **Run workflow**, pick the branch, **Run workflow**. It stamps its own build number and signs with Xcode's cloud-managed certificates
through an App Store Connect API key, so no certificate or profile is kept in the repository. The run's summary names the
uploaded version and build; it appears under TestFlight after processing.

Setup, once:

1. In App Store Connect, **Users and Access > Integrations > App Store Connect API > Team Keys** (the first time, request
   access and accept the terms). Click **+** (Generate API Key), name it "GitHub Actions" and give it **Admin** access:
   cloud-managed signing needs it. **Download** the `AuthKey_<Key ID>.p8` file (Apple offers it only once) and note
   the **Key ID** next to the key and the **Issuer ID** above the list.
2. In GitHub, the repository's **Settings > Secrets and variables > Actions > New repository secret**, four times:
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8`: the whole text of the `.p8` file, from `-----BEGIN PRIVATE KEY-----` to `-----END PRIVATE KEY-----`
   - `APPLE_TEAM_ID`: the Team ID from `Local.xcconfig`

   Then delete the downloaded `.p8` or keep it somewhere private: whoever has it can upload builds for the team.

To revoke CI's access, revoke the key on the same App Store Connect page.

CI builds the project for the iOS Simulator in `.github/workflows/ios.yml` on every change, with warnings as errors.
