# Skreener for iOS

A Share Extension for iPhone (#396). Take a screenshot, open it in Photos, tap Share and choose **Skreener** to put it
in a device frame on a background, cover private parts (a dragged area, or emails, phone numbers, links and typed text
found by on-device OCR) with pixelate, blur or solid black, mark it up with arrows, rectangles, text and highlights,
then save it to Photos, copy it or share it at full size. The container app, also called Skreener, only says how to
use it.

- `Skreener/`: the container app (SwiftUI, the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit)).
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

1. No signing team is in the repo. In Xcode select the project, then for **both** targets (`Skreener` and
   `SkreenerShare`) open Signing & Capabilities and pick your Team. Run `xcodegen generate` again after pulling
   changes; set the Team again if Xcode forgets it (or set `DEVELOPMENT_TEAM` locally, without committing it).
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

CI builds the project for the iOS Simulator in `.github/workflows/ios.yml`, with warnings as errors.
