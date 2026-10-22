# Shottr 1.9.3 vs Skreener: Output, upload, pins, library

Evidence sources: REA had no binary open (`list_documents` -> target_unavailable), so per the brief no `open_binary` was attempted. Evidence comes from the earlier shell extracts (`allstrings.txt`, `fields.txt` = Swift reflection field lists per class) and `strings` on `/Applications/Shottr.app/Contents/Resources/{Library,Pin,Preferences}.storyboardc/*.nib`. "Observed" = literal string / IB label / field name seen; "inferred" = behaviour deduced from names. Shottr was not launched. Skreener file refs are under `Sources/Skreener/`.

Items already covered by the prefs report (`prefs.md`): Auto PNG/JPEG format, downscale 1x, save folder, thumbnail close mode, Esc-copy/save, URL scheme `then=` actions, Keychain for secrets. Only referenced here where they touch output.

## Gaps summary

| # | Feature | Skreener | Priority |
|---|---------|----------|----------|
| 1 | Image upload + link: S3-compatible (AWS, R2, B2...), presigned or public-bucket URL, key prefix, expiry, Test Connection; URL copied to clipboard | **missing** (TODO #33) | High |
| 2 | Upload size fallback ladder (PNG full -> JPEG full -> PNG reduced -> JPEG reduced under a MB cap) | **missing** | Med (with #1) |
| 3 | Upload history ("Go to uploads" menu item) and delete-uploaded-object | **missing** | Low-Med |
| 4 | Pin: hover toolbar (close, drag-out, edit, copy, zoom %) | **partial** (gestures only) | Med |
| 5 | Pin: context menu (50/100/200%, Copy, Edit, Close, Semi-transparent toggle) | **missing** | Med |
| 6 | Pin: retina-correct 100% size (dpr) and zoom % readout | **partial** (fits to 60% of screen, no % shown) | Low-Med |
| 7 | Pin: drag the pinned image out as a file | **missing** | Med |
| 8 | Library: indexed browser of the *save folder* (not a private cache), incl. pre-existing screenshots | **partial** (history = private 100-PNG cache) | Med |
| 9 | Library: search + filters (month, app, domain, has-drawings, file type) | **missing** | Med |
| 10 | Library: layouts (large/medium/small tiles, file list), resizable popover | **partial** (one strip layout) | Low |
| 11 | Library: multi-select, Copy Files, Delete, Open in Default App, Show in Finder, file-promise drag | **partial** (single item; drag/delete/copy image yes; no Finder/Default App/Copy Files/multi-select) | Low-Med |
| 12 | Library: capture-tool toolbar inside the library popover | **missing** (menu only) | Low |
| 13 | Library limit + enable/disable | **partial** (on/off toggle; limit fixed at 100) | Low |
| 14 | Screenshot metadata written to saved files (`kMDItemIsScreenCapture`, `kMDItemScreenCaptureGlobalRect`) | **missing** | Low-Med |
| 15 | Re-save edits over the same file (`autosaveOverwrite`) | **missing** (each save is a new file) | Med |
| 16 | Copy also puts a file on the pasteboard ("Copy Files", `NSFilenamesPboardType`) | **partial** (image only from editor/QA; file from recording QA) | Low |
| 17 | Print | **missing** | Low |
| 18 | Animated 2-frame GIF export (overlay) | missing (cross-area: editor; Skreener has GIF only for recordings) | Low |
| 19 | Drag-out from Quick Access thumbnail | **missing** (TODO #32) — editor Drag Me and history drag present | Med |
| 20 | Filename template | **present** (Skreener stronger: user-editable tokens) | — |
| 21 | PNG/JPEG, 1x downscale, save folder, Save As | **present** (Auto format missing, see prefs report) | — |
| 22 | Share sheet | **present** (Shottr has none observed; Skreener ahead) | — |
| 23 | Pin opacity, zoom, move, Esc/double-click close, all Spaces | **present** | — |

---

## 1. Image upload and link sharing — MISSING (High)

**Shottr (observed):** `PrefUploadViewController` pane titled "Image Uploading & Link Sharing". Dropdown `ddlUploadMode`: "Disable Uploading" / "Shottr Cloud" / "S3 (Amazon, Cloudflare, Backblaze, etc.)". S3 box: "Access key", "Secret key" (`NSSecureTextField`), "Bucket", radio "Region" vs "Endpoint" (`radioS3HaveRegion/Endpoint`), "Key prefix (path)", "Link sharing" dropdown "Generate Presigned URL" / "Generate Public Bucket URL", "Link Expiration" slider ("N days", "Presigned URLs are only valid for up to 7 days"), "Public bucket URL" ("Will only work if your bucket is public"), "Test Connection" button with spinner/label. Own SigV4 implementation (class `S3Lean`; strings `AWS4-HMAC-SHA256`, `x-amz-content-sha256`, `SignedHeaders=`, `generateDownloadURL(bucket:key:expiration:)`, `upload(data:bucket:key:attempt:completion:)`, retry on clock skew `Failed S3 uploading. clockSkew:`). Friendly error mapping: 403 "Are Secret Key and Bucket correct?", 404 "Object key or bucket name/path is wrong", 301/307 wrong region/endpoint, 409 conflict, 401; warns on "Uppercase Bucket Name"; `cloudflarestorage.com` special-cased; "Region is required when no endpoint is provided." Success: "URL copied to the clipboard", "Upload Succeeded". Triggers: editor toolbar `toolbar:uploadImage`, menu `menu:uploadImage`, "Upload and Get Link (" shortcut hint, thumbnail `btnUpload`, URL-scheme `then=` (`AfterGrab.upload` field). Shottr Cloud: token ("Get a Token", `https://shottr.cc/get_token.html`), posts to `https://shottr.cc/api/upload.php`; settings pref keys `setting-uploadMode`, `setting-uploadS3SharingMode`, `uploadS3Endpoint`, `uploadS3PublicUrl`, `uploadS3PresignExpiration`; secrets in Keychain ("Failed to save to keychain"). S3 is license-gated ("S3 uploading is only available after the license activation").
**Inferred:** key = prefix + generated filename; public URL = publicURL + "/" + key.

**Skreener:** missing (TODO.md "Upload to S3-compatible / custom endpoint + copy link — M (#33)"). No networking code in `Output.swift`.

**Suggested approach:** new `Uploader.swift`: `struct S3Config { accessKey, bucket, region?, endpoint?, prefix, linkMode (.presigned(days) | .publicBase(URL)) }`, secret in Keychain (`SecItemAdd`, service "Skreener Upload"), rest in UserDefaults. Implement SigV4 PUT (CryptoKit HMAC-SHA256, `URLSession.upload`), path-style URLs when an endpoint is set (R2/B2/MinIO), virtual-host for AWS. Presign GET with `X-Amz-Expires` <= 604800. Add Settings pane "Upload" (`SettingsWindow.swift`) with Test Connection (PUT then DELETE a tiny object). Add "Upload" to Quick Access corner/center, editor footer, history hover, and an After Capture option. On success copy URL as `.string` (+ `.URL`) to pasteboard and show the existing toast. Pure functions (canonical request, signing key, presigned URL) are unit-testable on Linux-free test target.
**Acceptance:** with valid R2 / AWS creds Test Connection reports OK; Upload from Quick Access puts a working https link on the clipboard within a few seconds; presigned link expires after configured days; wrong secret shows a readable 403 message; secret never appears in UserDefaults plist; SigV4 test vectors from AWS docs pass in `swift test`.

## 2. Upload size fallback ladder — MISSING

**Shottr (observed):** `getImgDataBelow(image:limitMB:)` with log strings "Attempt 1, PNG fullsize", "Attempt 2, JPEG fullsize", "Attempt 3, PNG reduced", "Attempt 4, JPEG reduced", "Image is too large", `resize(image:width:height:)`. **Inferred:** for Shottr Cloud (size cap), tries progressively smaller encodings.
**Skreener:** missing; `Output.fileData` encodes once.
**Approach:** `Output.fileData(_:maxBytes:)` that loops over (png,1.0),(jpeg q0.9,1.0),(png,0.5),(jpeg,0.5). Only needed if a capped destination exists; for S3 skip. **Acceptance:** a 6K screenshot with a 5 MB cap yields data <= 5 MB; unit test.

## 3. Upload history / delete — MISSING (Low-Med)

**Shottr (observed):** status menu `itemGoToUploads`, `gotoUploads(method:)` opens `https://shottr.cc/gallery.html?code=` (Cloud only); "Can't open past uploads"; S3 "Delete failed with status:". **Approach:** keep a local JSON log (date, key, URL, thumbnail path) and show it in the history panel with "Copy Link" / "Delete from Bucket" (SigV4 DELETE). **Acceptance:** uploaded items show a link badge in history; Delete removes the object (GET then 404).

## 4. Pin hover toolbar — PARTIAL (Med)

**Shottr (observed):** `PinViewController` fields `viewToolbar` (NSVisualEffectView), `btnClose`, `btnDragger` (class `CtrlDragOut`), `btnEdit`, `btnCopy`, `viewZoom`/`textZoom`, `tmrHideToolbar`, `viewToolbarCurtain`; nib actions `close:`, `clickEdit:`, `clickCopy:`. **Inferred:** a translucent strip appears on hover and auto-hides on a timer.
**Skreener:** `PinnedScreenshot.swift` — borderless floating panel, drag to move, scroll = opacity (0.1..1), ⌘-scroll/pinch = zoom, double-click/Esc closes. No buttons, no way to edit or copy from a pin.
**Approach:** add a tracking area on `PinnedView`; on hover fade in an `NSVisualEffectView` bar (top) with PillButton-style icons: close (xmark), copy, edit (opens `EditorWindow` with the image), drag handle, and a zoom % label; hide 1.5 s after exit. **Acceptance:** hovering a pin shows the bar; Copy puts the image on the clipboard; Edit opens it as an editor tab; the bar is never included in Copy/drag output; leaving the pin hides the bar.

## 5. Pin context menu — MISSING (Med)

**Shottr (observed):** Pin nib menu items "50%", "100%", "200%", "Copy", "Edit", "Close", "Semi-transparent" (`menuTransparency:`, `miTransparency`, pref-like key `pin:transparency`). **Approach:** `PinnedView.menu(for:)` returning those items plus "Save…" and "Share…" (reuse `Output.saveAs`/`Output.share`); Semi-transparent toggles alpha 0.5/1 with a checkmark. **Acceptance:** right-click shows the menu; 100% sizes the window to the image's point size; Semi-transparent toggles and shows a checkmark.

## 6. Pin size and zoom readout — PARTIAL

**Shottr (observed):** `PinWindowController` fields `dpr`, `width`, `height`, `currentZoom`, `pinTime`. **Inferred:** pins open at true 100% (pixels / backing scale) and show zoom %. **Skreener:** opens fit to 60% of the main screen at center (`PinnedScreenshot.swift` `show`), no % shown, not placed at the captured location. **Approach:** for Capture Area & Pin pass the capture rect and open the pin exactly over it at 100%; show zoom % briefly while zooming. **Acceptance:** ⌃⇧6 pin appears exactly where the area was, same size; zooming shows "150%" etc.

## 7. Drag out of a pin — MISSING

**Shottr (observed):** `btnDragger` of class `CtrlDragOut` (fields `holdImage`, `holdName`), `FileDraggOut`. **Approach:** make the toolbar drag handle an `NSDraggingSource` writing `Output.temporaryFile(image)` as `NSURL` (same as `HistoryCell.mouseDragged` in `CaptureHistory.swift:401`). Window drag stays on the image body. **Acceptance:** dragging the handle into Finder/Slack drops a named PNG; dragging the image still moves the pin.

## 8. Library over the save folder — PARTIAL (Med)

**Shottr (observed):** `ScreenLib` (records, filenames, `topColors`), `IndexMachine` (filesQueue, queued/processed counts, "Preparing to index your files...", "Finishing indexing"), "Every time you save a screenshot with Shottr, it will appear here.", "Pick a folder for your screenshots.", "N pre-existing screenshots found. Do you want to add them to the library?" (`libAllowPreexisting`), "Reindexing file, url doesn't match (different folder?)", "Can't change folder while indexing", security-scoped `defaultFolderBookmark`; `GrabData._libObject`. Library is a popover from the status item (`StatusMenu.libPopover`). Pref keys `setting-libEnabled`, `setting-libLimit`, `setting-libLayout`, `setting-libPopoveerSize`.
**Skreener:** `CaptureHistory.swift` keeps every capture (flattened PNG) in `~/Library/Application Support/Skreener/History`, newest 100, shown in a slide-down panel (⌃⇧H). Files saved to the save folder are not indexed; pre-existing screenshots are not shown.
**Approach:** keep the history cache but add an index of the save folder: on launch and on `DispatchSource`/FSEvents changes, list image files (png/jpg/gif/mp4) with creation date into an in-memory model (persist a small JSON cache with per-file metadata). Offer "Show saved files" in the history panel. **Acceptance:** a file saved to the folder appears without relaunch; deleting it in Finder removes it; 2,000 files index in < 2 s without blocking the UI.

## 9. Library search and filters — MISSING (Med)

**Shottr (observed):** `LibViewController` fields `tbSearch` (NSSearchField), `filterMonths`, `filterDomains`, `filterDrawings`, `filterTypes`, `filterApps` (each `[(count, value)]`); URL-detecting regex in strings (domain filter, inferred from OCR'd text or the frontmost browser); "N images selected". **Inferred:** search matches OCR text; facets show counts.
**Skreener:** history panel has no search. OCR exists (`TextRecognizer.swift`).
**Approach:** at add time store sidecar metadata `{date, frontmostAppBundleID, ocrText (background, low QoS), hasAnnotations, type}`; add an `NSSearchField` and a filter popup (Month, App, Type) to the history panel; search on OCR text + app name. **Acceptance:** typing a word visible in a screenshot finds it; App filter lists apps with counts; clearing the field restores all.

## 10. Library layouts — PARTIAL (Low)

**Shottr (observed):** `ddlLayout` "Large Tiles" / "Medium Tiles" / "Small Tiles" / "File List" (icons `16-lib-layout-*`), `btnPopoverSize` collapse/expand, `GalleryDelegate.itemsPerRow`, QuickLook thumbnails (`QLThumbnailGenerator`). **Skreener:** single horizontal strip of cells (`CaptureHistory.swift`). **Approach:** NSCollectionView with a flow layout and a size popup; list mode = NSTableView with name/date/size. **Acceptance:** switching layout persists across launches.

## 11. Library item actions — PARTIAL

**Shottr (observed):** `GalleryItemView.menuDelete`, `menuCopyFiles`, "Open in Default App", "lib:action-finder" / "Click to open in Finder", file-promise drag (`com.apple.NSFilePromiseItemMetaData`), multi-selection. **Skreener:** hover edit/copy/save/share/pin/delete, double-click edit, drag-out file (`CaptureHistory.swift` HistoryCell), Clear History. Missing: Show in Finder, Open in Default App, multi-select + Copy Files. **Approach:** right-click menu on HistoryCell with Show in Finder (`NSWorkspace.activateFileViewerSelecting`), Open With default (`NSWorkspace.open`), Copy File (write `NSURL` to pasteboard). **Acceptance:** each menu item works on one and on several selected items.

## 12. Capture toolbar inside the library — MISSING (Low)
**Shottr (observed):** library toolbar icons `lib-tool-28-{fullscreen,area,repeat,window,scrolldown,scrollup,clipboard,more}` with tooltips/hotkeys ("Repeat Area Capture", "Load From Clipboard"). **Approach:** small icon row at the top of the history panel calling the existing AppDelegate actions. **Acceptance:** clicking Area in the panel closes it and starts area capture.

## 13. Library limit — PARTIAL
**Shottr (observed):** `setting-libLimit`, URL scheme `settings/library/limit`, enable/disable. **Skreener:** `CaptureHistory.limit = 100` constant; toggle `Preferences.keepHistory`. **Approach:** Settings stepper (25/100/500/unlimited). **Acceptance:** lowering the limit prunes oldest immediately.

## 14. Screen-capture metadata on saved files — MISSING (Low-Med)
**Shottr (observed):** `com.apple.metadata:kMDItemIsScreenCapture`, `com.apple.metadata:kMDItemScreenCaptureGlobalRect`, `getXattrRect(url:)` (reads the rect back, e.g. for re-capture/library). **Skreener:** none (`Output.save`). **Approach:** after write, `setxattr` binary-plist-encoded `true` and `[x,y,w,h]` (as macOS screencapture does), so Spotlight "kind:screenshot" and Finder smart folders pick them up. **Acceptance:** `mdls -name kMDItemIsScreenCapture file.png` = 1 after mdimport; unit test reads the xattr back.

## 15. Re-save over the same file — MISSING (Med)
**Shottr (observed):** `autosaveOverwrite`, `saveImgToFolder(image:name:url:overwrite:)`, `backgroundSaveProcess(url:scopedURL:quiet:)`, `openedURL`. **Inferred:** once a screenshot is saved (or opened from a file), later saves write the edited version over that file instead of making "name 2". **Skreener:** `Output.save` always makes a unique new name; editor only has Save as… panel. **Approach:** store the saved URL per editor document; ⌘S overwrites it (atomic write), ⇧⌘S = Save as. **Acceptance:** auto-save on capture, annotate, ⌘S -> same file updated, no duplicate.

## 16. Copy as file — PARTIAL (Low)
**Shottr (observed):** `NSFilenamesPboardType`, "Copy Files" in library. **Skreener:** `Output.copy` writes only `NSImage` (`Output.swift`); recordings copy as file (`QuickAccess.swift`). **Approach:** also write a temp file URL item alongside the image so pasting into Finder makes a file and into Slack keeps the name. **Acceptance:** ⌘V in Finder after Copy creates the PNG; pasting into Preview still pastes the image.

## 17. Print — MISSING (Low)
**Shottr (observed):** `menuPrint:`, `printOperationWithView:printInfo:`, `printOrientation`. **Approach:** editor File > Print (⌘P) with `NSPrintOperation(view: NSImageView)`, auto orientation from aspect. **Acceptance:** ⌘P opens the print panel with the flattened image fit to page.

## 18. Two-frame GIF (cross-area, editor) — brief
Observed `saveGIF(img1:img2:delay:urlFolder:)`, "To create GIF with two frames, position overlay image on top of the original screenshot." Editor researcher's area.

## 19. Quick Access drag-out — MISSING (TODO #32)
Shottr's thumbnail is `PreviewViewController` (buttons copy/save/edit/OCR/upload/pin/close, `viewGrip`) plus drag out (inferred from `CtrlDragOut`). Skreener: `QuickAccess.swift` has no `mouseDragged`. **Approach:** reuse HistoryCell drag code on the preview image. **Acceptance:** dragging the thumbnail into Finder drops the file; QA closes after a successful drop.

## 20-23. Present
- Filename template: Skreener `Output.filename` with `%Y %y %m %d %H %M %S`, default "Skreener %Y-%m-%d at %H.%M.%S", unique " 2" suffix (`Output.swift`, `Preferences.swift:35`). Shottr has a `fileNameTemplate` key and an illegal-char sanitizer regex but no template field in the prefs nib (inferred: fixed/hidden). Skreener ahead.
- Format/1x/folder/Save As: `Output.fileData`, `Preferences.imageFormat`, `downscaleRetina`, `saveDirectory`. Shottr extras: Auto format (prefs report #13), security-scoped folder bookmark (only needed if sandboxed).
- Share sheet: `Output.share` (NSSharingServicePicker) — no share-service strings found in Shottr. Skreener ahead.
- Pin basics: `PinnedScreenshot.swift` (floating level, all Spaces, opacity, zoom, close).

## Test notes for the owner
None of the above is implemented in this research task, so there is nothing to test yet.

## Raw Shottr evidence collected (run 2)
REA session had no binary open, so all evidence is from shell extracts (allstrings.txt, fields.txt = Swift field metadata) and strings of the Library/Pin/Preferences storyboard nibs.

- Upload prefs pane (PrefUploadViewController, nib PA4-Wk-i8P): dropdown "Disable Uploading / Shottr Cloud / S3 (Amazon, Cloudflare, Backblaze, etc.)"; S3 fields Access key, Secret key (NSSecureTextField), Bucket, Region-or-Endpoint radio, Key prefix (path), Link sharing = "Generate Presigned URL" / "Generate Public Bucket URL", Link Expiration slider "N days" ("Presigned URLs are only valid for up to 7 days"), Public bucket URL, Test Connection button + spinner + label; Shottr Cloud "Token" + "Get a Token". Observed.
- Pin (PinWindowController/PinViewController, Pin.storyboardc): hover toolbar (btnClose, btnDragger, btnEdit, btnCopy, zoom %), context menu 50%/100%/200%, Copy, Edit, Close, Semi-transparent; fields transparency, totalScrollDelta, currentZoom, dpr, pinTime. Observed.
- Library (LibViewController, Library.storyboardc): status-bar popover with NSCollectionView, layouts Large/Medium/Small Tiles/File List, search field, filters months/domains/drawings/types/apps, capture-tool toolbar, indexing of pre-existing images, file-promise drag, Delete / Copy Files / Open in Default App / Show in Finder. Observed.
