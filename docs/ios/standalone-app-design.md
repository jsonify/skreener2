# Skreener for iPhone: standalone app design (#408)

A proposal for what the standalone app should be, beyond "the Share Extension with a picker in front". It keeps
#408's v1 scope (shared editor framework, picker, Latest screenshot, full-screen editor) and adds a few product
decisions on top. Each idea below says what it reuses and what it costs. The owner picks; nothing here is built yet.

## What the research says

- **Screenshots pile up, and most are never shared.** About one in four camera-roll images is a screenshot
  ([The Conversation](https://theconversation.com/i-studied-5-000-phone-images-objects-were-more-popular-than-people-but-women-took-way-more-selfies-150080)).
  In Mottelson's study of why people take them, only about a quarter were taken to share
  ([ITU Copenhagen](https://pure.itu.dk/en/publications/why-do-people-take-screenshots-on-their-smartphones/)).
  The rest are notes to self: a recipe, a ticket, an address, a code. A 2025 Memory & Cognition study put
  "cognitive offloading" behind about 31% of screenshots, and people then remember those images worse.
- **The market is split in two.** Editors (Picsew for stitching, Shareshot for frames, Annotable for markup) make one
  screenshot look good. Cleaners (Screeny, Sardis) bulk-delete the pile. No app handles a screenshot from the moment
  it is taken to the moment it is shared, filed or gone.
- **Speed is what people praise.** Shareshot's best-reviewed feature is a Shortcuts action that frames the last
  screenshot with no app UI ([MacStories](https://www.macstories.net/reviews/shareshot-1-0-pixel-perfect-screenshots-beautifully-presented/)).
  iOS 26's full-screen screenshot preview drew complaints for slowing people down, and many turned it off
  ([9to5Mac](https://9to5mac.com/2025/09/18/ios-26-iphone-screenshot-changed-setting-full-screen/)).
- **The system won't tell us a screenshot was taken.** PhotoKit sends no system-wide "new photo" event, and a
  suspended or killed app gets nothing ([Apple Developer Forums](https://developer.apple.com/forums/thread/696678)).
  So the app learns about new screenshots when it comes to the front, or when the user triggers it (share sheet,
  Shortcut, Control Center, Action button).
- **New system surfaces are open to apps.** App Intents feed Shortcuts, Siri, Spotlight and (iOS 18+) Control Center
  controls, which the Action button can run. iOS 26 adds Visual Intelligence integration and on-device Foundation
  Models with image input on Apple Intelligence devices
  ([Apple](https://developer.apple.com/foundation-models-framework/)). Our deployment target is iOS 17, so anything
  newer is availability-gated.

## The idea in one line

**Skreener is the darkroom for your screenshots: every new screenshot comes in, gets made safe and good-looking in
one or two taps, and then goes out (shared), gets filed, or gets thrown away.**

The Share Extension stays the "I'm already looking at it" path. The app becomes the "what about all the others" path.

## Proposals

Ordered by value per effort. "Reuses" names existing code.

### 1. Home is an inbox, not a picker (recommended for v1)

The home screen shows the screenshots taken since you last opened Skreener as a contact sheet on the SK-1 chassis.
The LCD reads `3 NEW`. Tap one to open it in the editor. **Choose screenshot** (PhotosPicker) stays as a key for
anything older.

- Needs Photos read access, which #408 already asks for **Latest screenshot**. The inbox is the same permission
  with a much better reason to grant it, so it answers the issue's open question: ask once, on the first tap of
  **Show my screenshots**, never at launch.
- Limited access shows only the screenshots the user selected. Denied falls back to the picker, with the LCD
  saying why.
- "Since last opened" is a date in `UserDefaults` (add the privacy manifest entry, `CA92.1`).
- Reuses: `PHAssetCollectionSubtype.smartAlbumScreenshots` fetch from #408 step 4; SK1UI wells and LCD.

### 2. Safe Check: a leak scan when a screenshot opens (recommended for v1)

On open, run the OCR the editor already has and light a lamp on the LCD: `SAFE CHECK · 2 FOUND`. One tap selects
what was found in Redact mode, a second covers it. Finds emails, phone numbers and links (as today), plus one-time
codes, card numbers (Luhn-checked), API-key-shaped strings and faces (Vision). The Mac has the same idea filed as
#258; on iPhone it matters more, because the most shared screenshots are chats and receipts.

- Reuses: `TextFinder`, `TextRecognizer`, `RedactText`, the Redact canvas. New: a few matchers in `SkreenerCore`
  (unit-tested on the Mac like the rest of Core), and `VNDetectFaceRectanglesRequest`.
- Runs on the downscaled image already in memory; no network, nothing stored.

### 3. Clean status bar (recommended for v1)

A **Clean bar** switch in Style replaces the status bar with a tidy one: 9:41, full signal, full battery, no
notification icons. It hides low battery, carrier and time, and makes screenshots look like Apple's marketing
images.

- Reuses: `SmartErase` (fills the strip with the color around it), the Mac's text drawing for the time. New:
  status-bar height per screen size (a small table, unit-tested) and three SF Symbols drawn on the right.
- Only offered when the image is an iPhone screenshot of a known size, so photos are never touched.

### 4. One gesture from screenshot to framed (strongly suggested, small follow-up)

#408 lists Shortcuts as out of scope. They are the cheapest way past the competition, and the app target is where
they have to live, so plan for them now even if they ship in a follow-up PR.

- **App Intents**: "Open latest screenshot in Skreener", "Frame latest screenshot" (uses your last style, returns
  the image, so it chains in Shortcuts). Siri and Spotlight get them for free.
- **Control Center control and Action button** (iOS 18+, a small widget extension): one press opens the newest
  screenshot in the editor. With Back Tap (Settings > Accessibility > Touch) running the Shortcut, it's two taps on
  the back of the phone.
- **Last look**: the editor remembers the last frame, background, padding and corners and starts with them. This is
  what makes "Frame latest screenshot" useful, and it needs an App Group only when the extension should share it.

### 5. Out: share, file or toss (v2)

After **Save**, **Copy** or **Share**, the readout offers **Toss original**: deletes the unedited screenshot (iOS
shows its own confirmation, and it goes to Recently Deleted). In the inbox, a swipe tosses or keeps without opening.
This is the "cleaner" half of the market, done one screenshot at a time instead of as a bulk purge.

- Needs full (not limited) Photos access for the delete. `PHAssetChangeRequest.deleteAssets`.

### 6. Remind me: screenshots as notes to self (v2)

For the screenshots taken to remember something: **Remind me** (tonight, tomorrow, next week) schedules a local
notification with the screenshot attached (`UNNotificationAttachment`), and the inbox keeps it until then. Smart
actions from the OCR text go with it: a date offers **Add to Calendar**, an address **Open in Maps**, a URL
**Open**, a QR code its payload, a block of text **Copy text**.

- Reuses: the Mac's `SmartActionDetector` idea (move the detection, not the AppKit UI, into Core), `TextRecognizer`.
- Notification permission asked on first **Remind me** only.

### 7. Show someone how (v2)

A **Guide** tool: tap points in order and get numbered circles, each with an optional short caption, plus a dimmed
spotlight on the first one. For helping a parent find a setting, or writing a support reply. The Mac has counters
and Step Guide; this is the phone-sized version.

### 8. Describe it (v2, iOS 26+, Apple Intelligence devices)

**Copy with description**: Foundation Models writes a one-sentence alt text from the image and its OCR text, so a
screenshot shared to a group chat or a docs page is readable with VoiceOver. Also names saved files from their
content (as the Mac's `ContentNaming` does). Hidden on devices without Apple Intelligence; the OCR text is the
fallback.

## Recommended v1

#408's scope as written, plus:

| Add | Why in v1 | Size |
|---|---|---|
| Inbox home (1) | Turns the permission ask into a feature; gives the app a reason to be opened | S on top of step 4 |
| Safe Check (2) | Clearest "Markup can't do this" moment, mostly reuse | M |
| Clean status bar (3) | Visible, fun, mostly reuse | S-M |
| Last look (part of 4) | Two-tap edits; prerequisite for the Shortcuts follow-up | S |

App Intents, the Control Center control, Toss, Remind me, Guide and Describe become their own issues after v1.

## Decisions for the owner

1. Which of the recommended v1 additions to take (inbox, Safe Check, clean status bar, last look).
2. Read access: with the inbox, ask on the first tap of **Show my screenshots** (recommended), or keep v1
   picker-only and ship the inbox later.
3. Safe Check: run automatically on open (recommended, it's on-device and quick) or only when a key is tapped.
4. Should Safe Check and the clean status bar also come to the Share Extension in the same release, or app only?
   They live in the shared editor framework either way.
