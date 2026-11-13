# Skreener for iOS

An app and a Share Extension for iPhone (#396, #408). The editor puts a screenshot in a device frame on a background,
covers private parts (a dragged area, or emails, phone numbers, links and typed text found by on-device OCR) with
pixelate, blur or solid black, checks each screenshot as it opens for things not to share (Safe Check: emails,
phone numbers, links, one-time codes, card numbers, API keys and faces, all on the device), marks it up with arrows, lines, rectangles, ellipses, freehand pen strokes, text and highlights, in five colours
and five sizes, then saves it to Photos
or shares it at full size (the share sheet's Copy Photo copies it).

There are two ways in. Open the **Skreener** app: its home screen shows the screenshots taken since you last left it,
and has keys for the latest screenshot and for choosing any image. Or, in Photos (or any app), tap Share and choose
**Skreener**. Both open the same editor.

**Long screenshots** (#456): the app's **Long screenshot** key stitches a page taller than the screen into one image,
as the Mac's Scrolling capture does. iOS lets no app capture other apps or scroll them, so the frames come from a
screen recording made while scrolling (Control Centre > Screen Recording), or from several screenshots that overlap
by a few lines. The status, navigation and tab bars are kept once; the result opens in the editor like any picture.
`Skreener/LongScreenshot.swift` reads the recording (about ten frames a second, retrying the frames in between after a
fast flick) and feeds `ScrollStitcher` from `SkreenerCore`.

- `Skreener/`: the app (SwiftUI, the SK-1 look from [SK1Kit](https://github.com/jsonify/SK1Kit)): the home screen
  with the inbox of new screenshots, which opens the editor full screen. It reads the Photos Screenshots album and
  asks for that access only when you tap Show my screenshots or Latest screenshot. Its icon, `Skreener/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, is the Mac app's icon as an opaque
  full-bleed square (iOS rounds the corners), drawn by `Scripts/make_icons.py` with the Mac one: change it there.
- `SkreenerEditor/`: the editor as a framework: the screens, redact and draw canvases, rendering and export. It draws
  with `SkreenerCore`, the library shared with the Mac app. The app embeds it; the extension uses it. Both hand it an
  `ImageSource` (the extension's items, or image bytes), which it loads again for each export.
- `SkreenerShare/`: the Share Extension. Only its view controller, which hosts the editor.
- `SkreenerBroadcast/`: the Broadcast Upload Extension for live scrolling capture (see below). It links only
  `SkreenerCore`, for the stitcher.
- `SkreenerControls/`: the widget extension with the **Frame Latest** control for Control Center and the Action
  button (#439; iOS 18 and later, the app stays on 17). `Shared/` holds the control's intent, which is in the app too;
  it is a `LiveActivityIntent` so that iOS runs it in the app, not in the extension.
- `project.yml`: the [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Bundle IDs are `com.skreener.ios`,
  `com.skreener.ios.share`, `com.skreener.ios.broadcast` and `com.skreener.ios.controls` (the framework is `com.skreener.ios.editor`); iOS 17 or
  later, iPhone only.

The `.xcodeproj` is generated and not committed (it is in `.gitignore`). The Info.plists are
generated from `project.yml`'s `info:` sections and ignored too: change them there. So are the `.entitlements` files
(`entitlements:`).

## Setup (once)

```
brew install xcodegen
```

The app and the extension share the editor's last look (frame, background, sliders) through the App Group
`group.com.skreener.ios`, which must exist for your team. Xcode's automatic signing registers it on the first build to
a device. If signing fails over it, select each of the `Skreener`, `SkreenerShare` and `SkreenerBroadcast` targets,
open Signing & Capabilities, and add the App Groups capability with `group.com.skreener.ios` ticked. The broadcast
extension (#456) is a new App ID, `com.skreener.ios.broadcast`, which automatic signing registers the same way; it
uses the group to hand its long screenshots to the app. The controls extension (#439), `com.skreener.ios.controls`, is one more App ID,
registered the same way; it needs no App Group.

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
2. Open **Skreener** from the Home Screen. Nothing asks for Photos access. At the top, "SK-1 SKREENER" and a small
   speaker grille; the LCD reads "TAP SHOW MY SCREENSHOTS", the tray says "Your new screenshots show here", and
   there are **Show my screenshots** (orange, full width) and, in a tray captioned OPEN, **Latest screenshot** and
   **Choose screenshot** keys. The hint at the bottom says Skreener is in the share sheet too.
3. Tap **Show my screenshots**. iOS asks for Photos access, with "Skreener shows your recent screenshots so you can
   edit them."
   - **Allow Full Access**: the newest 12 screenshots appear as a grid, newest first, and the LCD shows "12" in
     seven-segment digits with "NEW" and "Tap one to edit it" beside it, the INBOX lamp lit (or fewer if you have
     fewer). The Show my screenshots key goes away and **Latest screenshot** turns orange.
   - **Limit Access...**: pick one or two screenshots and tap Done. Only those appear; the LCD reads "N" "SELECTED"
     and a **Select more** key appears. Tap it, add another screenshot, tap Done: it joins the grid. With none
     selected, the LCD reads "NO SCREENSHOTS SELECTED" and the hint points to Select more and Choose screenshot.
   - **Don't Allow**: the LCD reads "PHOTOS ACCESS IS OFF" and the hint says to allow Skreener in Settings > Privacy &
     Security > Photos. Choose screenshot still works. Turning access on in Settings and coming back shows the grid.
4. With full access, go to the Home Screen, take two new screenshots, and open Skreener again: the grid shows only
   those two and the LCD reads "2" "NEW". Go to the Home Screen and come back without taking any: "NO NEW
   SCREENSHOTS". A screenshot taken while Skreener is open shows up straight away.
5. Tap a screenshot in the grid. The LCD reads "OPENING…" (longer if it is in iCloud only), then the editor fills the
   screen with that screenshot. At the top, the same header as the home screen ("SK-1 SKREENER" at the left, the
   speaker grille at the right); under it a row of keys: **Close** and **Undo** (greyed out) at the left, a
   **Share** key (the share icon) and the orange **Save** key, its label dark, at the right. All of them sit
   below the status bar and the Dynamic Island, easy to tap; the cream (or charcoal) chassis still fills the screen
   to its edges. There is no Copy key. Under them, a slim LCD strip; then the picture, as big as it fits; then the
   bottom row, above the home indicator: a tray of four tool keys, **Frame** (lit), **Draw** (an arrow with a small
   ▴ at its corner), **Text** and **Redact**, and a round key showing a red dot. Nothing in the bottom row scrolls
   sideways, even on a 375 pt wide iPhone (SE, mini): a sideways swipe along the bottom edge switches apps as usual,
   and a swipe up from the home indicator goes home on the first try.
6. Safe Check: the strip first says "SAFE CHECK…", then what it found, as in the extension's step 4 below. Try it
   here with a screenshot of a message that has a 6-digit code and a phone number: "SAFE CHECK · 2 FOUND  1 phone
   number · 1 code", the lamp at its left lit orange, and a **Review 2** key beside the strip. **Review 2**, untick
   one, **Redact 1**: "SAFE CHECK · 1 LEFT". A screenshot with nothing private reads "SAFE CHECK · CLEAR" for a few
   seconds, then the strip shows the tool: "FRAME  iPhone · Sky · Padding 48" (your frame and background).
7. In the editor, tap **Frame** again for its options, pick a frame (say Browser) and, with **More**, Dark and a
   background, move the Padding slider, cover an area with **Redact** and draw an arrow with **Draw**, as in the
   extension steps below.
8. Tap **Save**. The first time, iOS asks to add to Photos: allow it. The strip says "Saved to Photos" and the
   edited PNG is in Photos. **Share** works as in the extension: the system share sheet with `Skreener.png`, whose
   **Copy Photo** copies it.
9. Tap **Close**: the home screen is back.
10. Tap **Latest screenshot**: the newest screenshot opens in the editor. (If Photos access was never asked, this key
    asks first, like Show my screenshots.) Close.
11. Tap **Choose screenshot**: the system photo picker opens, showing only images, without asking for any access.
    Pick one: it opens in the editor. Close.
12. The editor starts with the style you used last: open any screenshot again and the frame, Dark, background and
    sliders, and the drawing size in the colour key, are as you left them (redactions and drawings start empty). Now set a different frame and background,
    Close, and share a screenshot from Photos to Skreener (see below): the extension starts with that same look.
13. Dark mode: in Control Centre (or Settings > Display & Brightness) choose Dark and open the editor: the chassis
    turns charcoal, the keys dark grey with light symbols, the LCD glass a little dimmer; Save stays orange with its
    dark label. Undo (top left) with nothing to undo is greyed out. The Draw key's shapes stand on a charcoal plate.
   The home screen turns charcoal too.

## Try long screenshots

1. Make a recording: open Control Centre, tap Screen Recording (add it in Settings > Control Centre if missing), wait
   for the countdown, close Control Centre, and in Settings (or Safari, Mail, any long list) scroll steadily down for
   five to ten seconds. Stop the recording from the red pill at the top (or Control Centre). It is in Photos.
2. Open Skreener. The tray captioned OPEN has a full-width **Long screenshot** key under Latest screenshot and Choose
   screenshot. Tap it: a menu with **From a screen recording** and **From screenshots**.
3. **From a screen recording**: the photo picker shows only videos. Pick the recording. A panel covers Home with
   "READING THE RECORDING…", then "STITCHING THE RECORDING…" and a bar filling, and a **Cancel** key. Then the editor
   opens on one tall picture: the status bar and the navigation bar once at the top, the page scrolled through without
   repeats or gaps, the tab bar (if any) once at the bottom. Control Centre at the start and end is not in it.
4. Again, but with Cancel during the stitching: the panel goes and Home is as before, the LCD clear.
5. Fast flick: record a page and flick it hard once or twice in the middle. It still stitches in one piece if the
   frames in between overlap. If a flick is too fast to follow, the editor opens on the longest part that stitched, and
   a banner over the picture for eight seconds says scrolling went too fast, with the time span used (a tap hides it).
6. A recording where nothing scrolls (record the Home Screen for a few seconds): no editor; the LCD reads "NOTHING
   SCROLLED IN THIS RECORDING" with a hint about recording while scrolling.
7. **From screenshots**: take three screenshots of a long page, scrolling down between them so each shares a few lines
   with the one before. Pick them (the picker numbers them in the order tapped; with Photos access they are put in the
   order they were taken). The editor opens on one tall picture. Picked bottom to top, they still stitch.
8. Pick two screenshots of different pages: the LCD reads "SCREENSHOT 2 DOESN’T OVERLAP", the hint "Screenshot 2
   doesn’t overlap the one before it. Take screenshots that share a few lines." Pick three where only the first two
   overlap: the editor opens on those two, with a banner saying screenshot 3 doesn't overlap and is left out.
9. Pick a screenshot and a photo of another size: "SCREENSHOTS MUST BE THE SAME SIZE". Pick just one: "PICK TWO OR
   MORE SCREENSHOTS".
10. In the editor, Save: Photos has the full-width tall PNG (up to 30 000 px tall).

## Try the extension

1. Take a screenshot on the phone and open it in Photos. For Safe Check, use a message that shows a 6-digit code
   and a phone number (e.g. a sign-in text); also have a screenshot with nothing private on it.
2. Tap Share. If Skreener is not in the app row, scroll to its end, tap More, and turn Skreener on (or use
   Edit Actions... in the share sheet).
3. Choose Skreener. The editor opens as in the app's step 5, with **Frame** lit and the screenshot in its frame. The
   strip reads "FRAME" and the frame, background and padding. Tap **Frame** again: the bottom row becomes Frame's
   options: four frame keys (None, iPhone, Browser, macOS Window; the current one lit), a round key with the
   background's colours, **More** (sliders icon) and **✕**. Pick each frame: the preview follows. Tap the
   background key or **More**: a sheet rises from the bottom, on the same cream (or charcoal) chassis, with a grabber,
   "FRAME OPTIONS" and a ✕. In it: the backgrounds as round keys (the current one pressed in), and with a background
   chosen, **Padding**, **Corners** and **Shadow** sliders, each with its value in a small LCD chip ("48", "10",
   "50%"); with no background, a hint to pick one. **Dark** is there for every frame but None; Browser also has an
   **Address** field. The preview stays visible above the sheet and changes as you drag. Drag the sheet up for all of
   it; ✕ or a drag down closes it. ✕ on the bottom row brings the tools back.
4. Safe Check: the strip says "SAFE CHECK…" for a moment, then "SAFE CHECK · 2 FOUND" with "1 phone number · 1 code"
   after it, the small lamp at its left lit orange (it also finds emails, links, card numbers, API keys and faces).
   Nothing is sent anywhere. Tap **Review 2** beside the strip: the editor switches to Redact (the Redact key lights)
   and both have an orange outline; the key beside the strip is now **Redact 2**. Tap the phone number's outline: it
   turns dashed and the key reads **Redact 1**. Tap **Redact 1**: the code is covered with the current Cover style
   (Pixelate unless changed) and the strip says "SAFE CHECK · 1 LEFT", lamp still lit, with **Review 1**. Review it
   and Redact 1 again: "SAFE CHECK · COVERED", lamp off, and a few seconds later the strip shows the tool again.
   **Undo** takes back that last cover (the strip says 1 left again). A face in the screenshot is found and covered
   the same way. Open a screenshot with nothing private: the strip says "SAFE CHECK · CLEAR" with the lamp off and no
   Review key, then the tool. After Save (step 15), the strip shows "Saved to Photos" for a few seconds, then its
   line again.
5. Tap **Redact** in the tray. The preview shows the screenshot alone and the strip reads "REDACT  Pixelate · drag
   to cover". Drag across some text: an orange dashed band follows your finger, and on release the area is
   pixelated. Tap **Redact** again for its options: the lit Redact key, a **Pixelate / Blur / Solid** switch, **Find**
   (magnifier) and **✕**. Pick **Blur** or **Solid** and drag again; that area is blurred or black. To cover small
   text, pinch on the picture to zoom in (up to 600%, about the pinch), drag with two fingers to move around, and
   drag with one finger to cover as before; a chip in the preview's corner reads the zoom (e.g. "250%"). Double-tap
   zooms to 250% at the tap; double-tap again, or tap the chip, to see the whole picture. A pinch never leaves a band
   behind. Draw tools zoom the same way (the zoom carries over between Redact and them), and Frame shows the whole
   picture again.
6. Tap **Find**: a sheet rises with "FIND", **Emails**, **Phones** and **Links** keys, a text field, **Redact 0**
   (orange), **Undo** and **Clear**, and a hint. The picture stays usable above it. Tap **Emails** (or **Phones**,
   **Links**): a readout says "Reading text…", then "N matches · N selected" and each match has an orange outline.
   Tap one on the picture: its outline turns dashed and the count drops. Or type a word into the field (several
   separated by commas). **Redact N** covers the selected matches with the current Cover style. The sheet's **Undo**
   takes back the last covered area (or a whole Redact N), **Clear** all of them. Close the sheet with its ✕.
7. Tap **✕** on the bottom row, then **Draw** in the tray (the arrow key with the small ▴). It lights, the preview
   shows the screenshot with its redactions and the strip reads "ARROW · DRAG TO DRAW". Drag from a spot to what it
   points at: a red arrow follows your finger, its head at the finger, and stays on release. A very short drag draws
   nothing. **Undo**, at the top left next to Close, is no longer grey.
8. Tap the lit **Draw** key again: a column of six shape keys fans upward above it on a small chassis plate with a
   soft shadow, top to bottom **Arrow** (lit), **Line**, **Rectangle**, **Ellipse**, **Pen** and **Highlight**. On a
   667 pt iPhone SE it still sits between the top bar and the Draw key, covering neither. Tap **Rectangle**: the
   column closes, the Draw key now shows a rectangle (still with its ▴) and the strip reads "RECTANGLE · DRAG TO
   DRAW"; drag on the picture for a red rounded outline. **Line** ("LINE · DRAG TO DRAW") draws a straight stroke
   with round ends and no head; **Ellipse** ("ELLIPSE · DRAG TO DRAW") an outlined oval in the dragged box; both
   follow the finger. Open the column again and close it without choosing: tap the picture (nothing is drawn), or
   tap Draw again. Tap **Frame**, then **Draw**: it picks the last shape used. With VoiceOver, the Draw key reads
   "Draw, Rectangle", and the open column reads as "Shapes" with each shape (the current one selected); a two-finger
   scrub closes it.
9. Pick **Pen**: the strip reads "PEN · DRAW FREELY". Draw a loop or a signature: a smooth red line follows the
   finger and stays on release. A tap draws a dot. Pinch to zoom in and draw again: the stroke lands exactly under
   the finger. Start a stroke and put a second finger down mid-way: the stroke vanishes and the pinch zooms.
10. Tap the round colour key: a small popover with five round colour keys (red, yellow, green, blue, black; the
    current one pressed in); under them a **Size** row: a short line in the colour showing the size, a slider with
    five stops (0.5×, 1×, 2×, 3×, 4×; it snaps) and the size in an LCD chip ("1×"); then **Clear drawings** (all the
    drawings; the redactions stay; greyed out with none). Pick yellow: the popover closes and the key shows a yellow
    dot. Drag a rectangle: yellow. Open the popover, slide to 4×: the preview line thickens and the chip reads "4×";
    draw an arrow, a line, an ellipse and a pen stroke: all thick (the arrowhead grows too), while the earlier
    rectangle keeps its size. With **Text** the size sets the text size. Choose **Highlight** from Draw's column and
    drag across a line of text: a translucent yellow band, the text still readable through it; its popover greys
    the Size row out, with "Highlights have one size." under it. The size is part of the last look, like the frame:
    the next editor, in the app or the extension, starts with it.
11. Tap **Text** and tap the picture: a small orange ring marks the spot and the bottom row becomes a text field,
    **Done** and **✕**, with the keyboard up and the row riding above it (Share, Save and Undo grey out meanwhile).
    Type a word: it shows on the picture as you type, its left end at the ring; the strip reads "TEXT · TAP WHERE IT
    GOES". **Done** (or the keyboard's Done) keeps it; **✕**, or Done with nothing typed, adds nothing. Tapping
    elsewhere on the picture while typing moves the label. Tap the lit **Text** key for its options: the lit Text
    key, the colour key, **Clear** and **✕**.
12. **Undo** (top left) takes back the newest edit, a drawing or a redaction, whichever came last: draw an arrow,
    cover an area, then tap Undo twice: the area goes, then the arrow. A line, ellipse, pen stroke or dot is one
    step each, the same way. With nothing left, Undo greys out.
13. Drawings and covered areas stay editable, as in the system's Markup. In Draw, tap a drawing: it gets an orange
    dashed box (an arrow or line gets a round handle at each end, a rectangle, ellipse or highlight one at each
    corner), the strip reads "… · SELECTED · DRAG TO MOVE", and a dark menu above it offers **Duplicate** and
    **Delete** (and **Edit** for text). Drag the drawing to move it; drag a handle to move an arrow's head or tail or
    resize a box. Drag an arrow, line, rectangle, ellipse or label directly to move it without tapping first (a
    highlight, and anything while Pen is picked, is tapped first). With a drawing selected, the colour key shows its
    colour and size: pick another colour or slide the size and that drawing changes. Tap a selected label, or
    **Edit**, to retype it in the text field; **Done** keeps the change, **✕** leaves it as it was, and Done with the
    text emptied deletes it. **Delete** removes the drawing; a tap on nothing deselects. In Redact, tap a covered
    area to select it: corner handles and **Duplicate** / **Delete**; drag it to move it, drag a corner to resize it,
    and Pixelate, Blur or Solid change its cover. Each move, resize, change or delete is one Undo step, as are
    **Clear** and **Clear drawings**.
14. Tap **Frame**: the frame and background return, with the redactions and drawings on the screenshot (drawings
    over redactions). They are in every export too, at full size.
15. With a full iPhone screenshot, Frame's **More** sheet has a **Clean bar** switch next to Dark (it is absent for a
    photo, an iPad or a cropped screenshot). Turn it on: the bar at the top repaints with the time reading 9:41, full
    signal bars, full Wi-Fi and a full battery, and no carrier, notification icons or real time. It stays on in
    Redact and the draw tools, and in Save and Share at full size. Turn it off to get the original bar back. The
    app's own editor has the same switch.
16. Tap **Save**. The first time, iOS asks to add to Photos: allow it. The strip says "Saved to Photos" and the
    full-resolution PNG is in the Photos library. If you deny, the strip says "No access to Photos" with, under it,
    to allow "Add Photos Only" for Skreener in Settings > Privacy & Security > Photos.
17. Tap **Share** (the icon left of Save) for the system share sheet with `Skreener.png`. Tap **Copy Photo** and
    paste into Notes or Messages: the edited picture.
18. **Close** (top left) ends the sheet.
19. Open the share sheet again: the frame, Dark, background, sliders, Clean bar and drawing size are as you left
    them. Change them, Close, and open the Skreener app and a screenshot: the app's editor shows the look you just set in the
    extension. A fresh install starts with iPhone frame, Dark off, the first background, Padding 48, Corners 10,
    Shadow 50%, Clean bar off and size 1×.

## Try the shortcuts

The app gives Shortcuts, Siri and Spotlight two actions (#439), with no setup: they show under Skreener in the
Shortcuts app's gallery and in Spotlight once the app has been opened.

- **Frame Latest Screenshot** frames the newest screenshot in your last look (frame, background, sliders, Clean bar)
  without opening Skreener, and returns the PNG, so it chains with other actions. Its **Then** choice does one more
  thing with it: **Copy** (the default), **Save to Photos**, **Share** (Skreener comes to the front with the share
  sheet) or **Nothing**. Siri: "Frame my latest screenshot with Skreener".
- **Open Latest Screenshot in Skreener** opens the app with the newest screenshot in the editor. Siri: "Open my
  latest screenshot in Skreener".

**Safe Check gate.** Frame Latest Screenshot first runs Safe Check on the screenshot. If it finds anything (a code,
card number, email, phone number, link, key or face), nothing is copied, saved, shared or returned: it asks "Safe
Check found 2 things to cover. Open in Skreener?" and opens the editor on that screenshot with the findings showing.
A clean screenshot goes straight through.

Neither action asks for Photos access. Until Skreener can see your screenshots, they stop with "Open Skreener and tap
Show my screenshots to let it see your screenshots" (or say to allow access in Settings, or to Select more).

**Back Tap.** In the Shortcuts app, tap **+**, add the Frame Latest Screenshot action (search for Skreener) and name
the shortcut, say "Frame latest". Then Settings > Accessibility > Touch > Back Tap > Double Tap > the shortcut. Take a screenshot, double-tap
the back of the phone and paste in Messages: the framed screenshot.

**Control Center and the Action button** (iOS 18 and later). Skreener has a **Frame Latest** control: one tap does
what Frame Latest Screenshot does with Then = Copy, Safe Check gate included, without opening Skreener (a screenshot
with something to cover opens in the editor instead). Add it: open Control Center, tap **+** (top left), **Add a
Control**, search for Skreener and tap **Frame Latest**. On an iPhone with an Action button: Settings > Action Button,
swipe to **Controls**, choose Skreener > Frame Latest. The control shows nothing when it is done: paste to see the
framed screenshot. It frames the newest screenshot saved in Photos: dismiss iOS's screenshot preview first (swipe the
thumbnail away, or tap ✓ > Save to Photos), or it frames the one before.

## Live scrolling capture

The home screen's **Scroll capture** key captures a long screenshot of any app (#456), like the Mac's scrolling
capture, except that you scroll by hand: iOS lets no app scroll another. The key starts a screen broadcast to
Skreener's Broadcast Upload Extension (`SkreenerBroadcast`); iOS shows the red recording button in the status bar while
it runs. The extension takes about 10 frames a second and stitches them with `ScrollStitcher` from `SkreenerCore`,
keeping the status bar, navigation bar and tab bar once. Until something scrolls, it starts again from whatever is on
screen whenever the screen changes, so Skreener, the countdown and the switch to the other app don't end up in the
picture. A broadcast extension may use only about 50 MB, so the finished strips go to disk as PNGs as you scroll, in
the App Group container (`LiveCaptures/<id>/`), with a `manifest.json` once the broadcast stops; nothing leaves the
phone. It then posts a notification. When Skreener comes back to the front (from the notification or any other way),
the home screen joins the strips into one PNG, removes the folder and opens it in the editor, as a picked image opens.
With an editor already open, it waits until you close it; with several finished captures, the newest (or the one
whose notification you tapped) opens first and each of the others opens when you close the editor. The capture stops
at 30,000 pixels, the Mac's limit too.

## Try live scrolling capture

1. On first launch after this change, the home screen has a **Scroll capture** key above the OPEN tray, and under it
   "Start, then switch to any app and scroll slowly. Stop from the red status-bar button."
2. Tap **Scroll capture**. The first time, iOS asks to allow notifications: tap Allow. Then the system's Screen
   Broadcast sheet rises with **Skreener** chosen and no microphone switch. (If instead a small round record button
   appears next to the key with "Tap the round button, then Start Broadcast.", tap that button.)
3. Tap **Start Broadcast**. After the 3-2-1 countdown, the status bar's clock turns into a red pill. Close the sheet
   (tap above it or swipe it down).
4. Go to Safari (a long article) or Messages (a long conversation). Wait a moment, then scroll down slowly with
   short, steady swipes; don't fling. You may pause and carry on.
5. Tap the red pill in the status bar, then **Stop**. Within a second or two a notification says "Long screenshot
   ready" / "Tap to edit it in Skreener."
6. Tap the notification. Skreener opens; the LCD reads "OPENING…" briefly, then the editor shows one tall image: the
   page from where you started to where you stopped, the status bar and Safari's toolbar (or Messages' header and
   input bar) once each, no repeated lines. Save it: Photos has the long PNG. Close: the home screen is back, and the
   explainer under the key is gone.
7. Nothing scrolled: start again, open an app, don't scroll, stop. The notification says "Nothing scrolled" /
   "Scroll slowly in the app you want to capture." Opening Skreener opens nothing.
8. Maximum length: start, open a very long page (a long Wikipedia article) and keep scrolling slowly for a minute or
   two. At 30,000 pixels (roughly 12 screens on a 3x iPhone) the broadcast stops by itself with an alert
   "Reached the maximum length. Your long screenshot is saved: tap the Skreener notification to edit it.", and
   a "Long screenshot ready (maximum length)" notification; tapping it opens the capture as in step 6.
9. Without opening the notification: make a capture, stop, and open Skreener from the Home Screen instead: it opens
   the capture the same way. With an editor open when a capture finishes (stop from Control Centre while Skreener
   is in front), the banner shows and the capture opens when you tap Close.

## Privacy manifest

The app has `Skreener/PrivacyInfo.xcprivacy`: it stores when it was last sent to the background in `UserDefaults`,
to know which screenshots are new (reason `CA92.1`, the app's own defaults), and the editor's last look in the shared
App Group defaults (reason `1C8F.1`), so the manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with both.
The extension has its own `SkreenerShare/PrivacyInfo.xcprivacy`, copied as a resource the same way, declaring the same
category with `1C8F.1`: the editor framework runs inside it and reads and writes the shared defaults. Both declare no
tracking and no collected data. The framework, `SkreenerCore` and SK1Kit use none of Apple's other required-reason APIs
(file timestamps, system boot time, disk space, active keyboards). Add an entry, to the target that makes the call, if
that changes. The broadcast extension uses none of them (no `UserDefaults`, no file timestamps), so it has no
manifest; the app's Scroll capture key remembers in its own defaults that its explainer was seen, covered by `CA92.1`.

## Upload to TestFlight

1. Bump `MARKETING_VERSION` in `project.yml` when the build is a new version (testers see it as 1.1.0, 1.2.0...). It must stay above 1.0: a build uploaded from Xcode on 2026-11-03 is 1.0 (1), and TestFlight offers the highest version.
2. `xcodegen generate`, always, right before archiving: it stamps a fresh build number, the UTC time as YYMMDD.HHMM
   without leading zeros in the second part (2026-11-04 09:05 is `261104.905`), into the gitignored
   `BuildNumber.xcconfig`; the command prints it. App Store Connect rejects an upload whose build number is not
   higher than the last one's, so archiving from a project generated before the last upload fails there: generate
   again and re-archive. Both targets get the same number, as App Store Connect requires.
3. In Xcode, run destination **Any iOS Device (arm64)**, **Product > Archive**, then in the Organizer **Distribute App >
   App Store Connect > Upload**. The build appears under TestFlight in App Store Connect after processing.

## Upload from GitHub Actions

`.github/workflows/testflight.yml` archives and uploads on the owner's Mac, registered as a self-hosted runner (see
**Self-hosted runner** below), with that Mac's selected Xcode. It runs by itself on every merge to `main` that
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

### Self-hosted runner

The TestFlight job asks for a runner labelled `self-hosted` and `macOS`; every other workflow stays on GitHub's runners.
While no such runner is online (the Mac is off, asleep or the runner is stopped), uploads wait in the queue, for up to
a day, then fail.

Setup, once, on the Mac:

1. Ideally make a separate standard macOS user for the runner (System Settings > Users & Groups), so builds can't
   reach your own files and keychain. Install Xcode (signed in to nothing is fine: signing uses the API key) and
   Homebrew, run `xcode-select -p` to check the Xcode it uses, and `brew install xcodegen`.
2. On GitHub: the repository's **Settings > Actions > Runners > New self-hosted runner**, choose macOS and the Mac's
   architecture, and run the commands shown, in that user's account. Accept the default labels (they include
   `self-hosted` and `macOS`).
3. Install it as a service so it starts at login: `./svc.sh install && ./svc.sh start` in the runner folder.
4. The repository is public, so in **Settings > Actions > General > Approval for running fork pull request
   workflows from contributors**, choose **Require approval for all external contributors**. A pull request from a
   fork runs its own copy of the workflows, and one that changed `runs-on` could otherwise run code on this Mac.

Check: Actions tab > **TestFlight** > **Run workflow** on `main`. The run's job page names the Mac's runner, and the
build appears under TestFlight after processing.

CI builds the project for the iOS Simulator in `.github/workflows/ios.yml` on every change, with warnings as errors.

## Simulator screenshots

`.github/workflows/ios-screens.yml` builds the app (Debug) for the Simulator and screenshots Home, the editor and the
Draw key's open shapes on the newest "iPhone N Pro" (Dynamic Island), and on a 375 pt iPhone SE when the runner can
make one. It runs on pull requests and pushes to `claude/` branches that change `ios/`, or from the Actions tab
(**iOS screens** > **Run workflow**, once the workflow is on `main`). The PNGs are the run's `ios-screens` artifact
(`pro-home.png`, `pro-editor.png`, `pro-shapes.png`, and `se-*.png`).

Debug builds take launch arguments that open screens without Photos access (`Skreener/DemoLaunch.swift`; Release
builds, TestFlight's, have none of it):

- `-SKDemoEditor`: opens the editor full screen from Home, as a pick does, on a generated phone screenshot with an
  email and a 6-digit code (Safe Check finds 2).
- `-SKDemoTool frame|draw|text|redact`: starts the editor with that tool lit.
- `-SKDemoShapes`: starts it with the Draw key's shapes fanned out.

Locally: `xcrun simctl launch booted com.skreener.ios -SKDemoEditor -SKDemoTool redact`, or add them in Xcode under
Product > Scheme > Edit Scheme > Run > Arguments.
