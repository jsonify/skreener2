# Skreener for iOS

A Share Extension for iPhone (#396). Take a screenshot, open it in Photos, tap Share and choose **Skreener** to put it
in a device frame on a background. For now the sheet previews the result; Save, Copy, redaction and annotation come in
later steps. The container app, also called Skreener, only says how to use it.

- `Skreener/`: the container app (SwiftUI, the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit)).
- `SkreenerShare/`: the Share Extension. It draws with `SkreenerCore`, the library shared with the Mac app.
- `project.yml`: the [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Bundle IDs are `com.skreener.ios` and
  `com.skreener.ios.share`; iOS 17 or later, iPhone only.

The `.xcodeproj` is generated and not committed (it is in `.gitignore`). Info.plists are generated too, but are
committed so changes to them show in review.

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
3. Choose Skreener. Switch the frame and background; Cancel or Done closes the sheet.

CI builds the project for the iOS Simulator in `.github/workflows/ios.yml`, with warnings as errors.
