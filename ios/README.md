# Skreener for iOS

A Share Extension for iPhone (#396). Take a screenshot, open it in Photos, tap Share and choose **Skreener** to put it
in a device frame on a background, cover private parts (a dragged area, or emails, phone numbers, links and typed text
found by on-device OCR) with pixelate, blur or solid black, mark it up with arrows, rectangles, text and highlights,
then save it to Photos, copy it or share it at full size. The container app, also called Skreener, only says how to
use it.

- `Skreener/`: the container app (SwiftUI, the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit)).
  Its icon, `Skreener/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, is the Mac app's icon as an opaque
  full-bleed square (iOS rounds the corners), drawn by `Scripts/make_icons.py` with the Mac one: change it there.
- `SkreenerShare/`: the Share Extension. It draws with `SkreenerCore`, the library shared with the Mac app.
- `project.yml`: the [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Bundle IDs are `com.skreener.ios` and
  `com.skreener.ios.share`; iOS 17 or later, iPhone only.

The `.xcodeproj` is generated and not committed (it is in `.gitignore`). The Info.plists are
generated from `project.yml`'s `info:` sections and ignored too: change them there.

## Setup (once)

```
brew install xcodegen
```

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

## Try the extension

1. Take a screenshot on the phone and open it in Photos.
2. Tap Share. If Skreener is not in the app row, scroll to its end, tap More, and turn Skreener on (or use
   Edit Actions... in the share sheet).
3. Choose Skreener. Switch the frame and background. The Dark switch is there for every frame but None; Browser also
   has an address field. With a background chosen, the Padding, Corners and Shadow sliders appear (scroll the controls
   if they do not fit; the preview stays put).
4. Switch **Mode** to **Redact**. The preview shows the screenshot alone. Drag across some text: an orange dashed band
   follows your finger, and on release the area is pixelated. Pick **Blur** or **Solid** under Cover and drag again;
   that area is blurred or black. **Undo** takes back the last area, **Clear** all of them.
5. Tap **Emails** (or **Phones**, **Links**): the readout says "Reading text…", then "N matches · N selected" and each
   match has an orange outline. Tap one: its outline turns dashed and the count drops. Or type a word into the Text
   field (several separated by commas). **Redact N** covers the selected matches with the current Cover style.
6. Switch **Mode** to **Draw**. The preview shows the screenshot with its redactions. With **Arrow** (and the red
   swatch on), drag from a spot to what it points at: a red arrow follows your finger, its head at the finger, and stays
   on release. A very short drag draws nothing.
7. Pick **Rect** and drag: a red rounded outline. Pick **Highlight**, pick the yellow swatch and drag across a line of
   text: a translucent yellow band, the text still readable through it.
8. Pick **Text** and tap the picture: a small orange ring marks the spot, a Text field appears at the top of the
   controls with the keyboard up (the Mode switch and the output keys step aside meanwhile). Type a word: it shows on
   the picture as you type, its left end at the ring. **Done** (or the keyboard's Done) keeps it; **Cancel**, or Done
   with nothing typed, adds nothing. Tapping elsewhere on the picture while typing moves the label.
9. **Undo** takes back the last drawing, **Clear** all of them; the redactions stay. Undo in Redact still takes back
   only areas.
10. Switch back to **Style**: the frame and background return, with the redactions and drawings on the screenshot
    (drawings over redactions). They are in every export too, at full size.
11. Tap **Save**. The first time, iOS asks to add to Photos: allow it. The readout says "Saved to Photos" and the
    full-resolution PNG is in the Photos library. If you deny, the sheet says to allow "Add Photos Only" for Skreener
    in Settings > Privacy & Security > Photos.
12. Tap **Copy** and paste into Notes or Messages. Tap **Share** for the system share sheet with `Skreener.png`.
13. **Close** (top left) ends the sheet.

## Privacy manifest

There is no `PrivacyInfo.xcprivacy`: neither target, `SkreenerCore` nor SK1Kit uses any of Apple's required-reason
APIs (`UserDefaults`, file timestamps, system boot time, disk space, active keyboards), and nothing collects data or
tracks. Add one, to the target that makes the call, if that changes.

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
