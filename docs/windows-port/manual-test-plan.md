# Skreener for Windows: Manual Test Plan

Use this plan to test the Windows port of Skreener on a Windows 11 virtual machine or PC. Work top to bottom. Mark each case Pass or Fail. If a case cannot be run on your setup, mark it "Needs real PC or Parallels" and skip it.

Parts:

1. Set up a Windows test machine
2. Get the build
3. Test cases
4. Reporting a problem

---

## Part 1: Set up a Windows test machine

Your Mac uses Apple Silicon (M1, M2, M3 or M4), so the Windows VM must be **Windows 11 ARM64**.

### 1.1 Install UTM

1. On your Mac, open a browser and go to **getutm.app**. Click **Download**.
   (You can also install UTM from the Mac App Store. The free download from getutm.app is the same app.)
2. Open the downloaded file and drag **UTM** to **Applications**.
3. Open **UTM** from Applications.
4. **Expected:** The UTM window opens with a **+** (Create a new virtual machine) button.

### 1.2 Get a Windows 11 ARM64 image

Use only Microsoft's own download pages. Do not use third-party sites.

**Option A: Windows 11 ARM64 ISO (recommended)**

1. In a browser, go to **microsoft.com/software-download** and search for **Windows 11 ARM64**. Choose the **Windows 11 disk image (ISO) for ARM64 devices** download.
2. Save the ISO to your Mac (for example, Downloads).
3. **Expected:** You have a file ending in `.iso` for ARM64.

**Option B: Windows Insider Preview (ARM64 VHDX)**

1. Sign in with a free Microsoft account and join the Windows Insider Program on Microsoft's Insider page.
2. Download the Windows 11 ARM64 Insider Preview build as a virtual hard disk (VHDX) from Microsoft's Insider download page.
3. Note: Insider builds are preview builds. Write the build number in your report.

**UTM guide:** UTM has a step-by-step **Windows** guide in its documentation at **docs.getutm.app** (search for "Windows"). Use it if a step below does not match what you see.

### 1.3 Create the VM

1. In UTM, click **+** (Create a new virtual machine).
2. Choose **Virtualize** (not Emulate).
3. Choose **Windows**.
4. Tick **Boot from ISO image**, click **Browse**, and select the Windows 11 ARM64 ISO. (For Option B, skip the ISO and attach the VHDX as the disk.)
5. Leave the Windows options UTM shows at their defaults. They cover the settings Windows 11 Setup checks.
6. Set **Hardware**:
   - CPU cores: **4** or more
   - Memory: **8192 MB** (8 GB) or more
7. Set **Storage** to **64 GB** or more.
8. Skip shared directories.
9. Name the VM **Windows 11 Skreener** and click **Save**.
10. Click the play button to start the VM.
11. Go through Windows 11 Setup. To skip the Microsoft account sign-in, choose **Offline account** and create a local account.
12. **Expected:** Windows 11 desktop appears.

### 1.4 Install the SPICE guest tools

These tools enable copy/paste between Mac and VM and let the VM window resize with the UTM window.

1. In the Windows VM, open **File Explorer**.
2. Open the drive labelled as the guest tools or SPICE drive (a CD drive in This PC).
3. Double-click the installer (its name contains **spice** or **utm-guest-tools**). Click through the installer, then **Restart** when it asks.
   If no drive appears, get the Windows guest tools installer from the UTM docs and run it from a folder in the VM.
4. After the restart, on the Mac, copy some text (for example, select text in a Mac app and press Command+C).
5. In the VM, open **Notepad**, press **Ctrl+V**.
6. **Expected:** The text from the Mac appears in Notepad. Resize the UTM window; the Windows display follows.

### 1.5 Set display scaling

1. In the VM, right-click the desktop, choose **Display settings**.
2. Under **Scale**, choose **100%** for the default tests.
3. Later, for mixed-DPI tests, set **150%**.
4. **Expected:** The text and icons change size. Scale setting shows the chosen value.

### 1.6 Multiple displays

UTM can show only one display per VM in normal use. Multi-monitor and mixed-DPI testing needs a real Windows PC or **Parallels Desktop** (which supports multiple displays for a VM).

Mark the Multi-monitor and mixed DPI cases (in Part 3) as **Needs real PC or Parallels** unless you have one of those.

---

## Part 2: Get the build

Skreener is a plain folder. There is no installer.

### 2.1 Download the build from GitHub

1. Open the pull request on GitHub.
2. Click the **Checks** tab.
3. Click the **Windows** workflow run.
4. Scroll to **Artifacts**.
5. Download the file for your machine:
   - **Skreener-windows-ARM64** for the Windows 11 ARM VM on Apple Silicon
   - **Skreener-windows-x64** for an Intel or AMD PC
6. **Expected:** A `.zip` file downloads.

### 2.2 Unzip and run

1. Copy the `.zip` into the VM (drag and drop from Mac, or download it in the VM's browser).
2. Right-click the `.zip` and choose **Extract All**. Extract to a new folder, for example `C:\Skreener`.
3. Open the folder and double-click **Skreener.exe**.
4. **Expected:** SmartScreen warns, because builds are not signed. See 2.3.

### 2.3 Get past SmartScreen

1. A blue window says **Windows protected your PC**.
2. Click **More info**.
3. Click **Run anyway**.
4. **Expected:** Skreener starts and a tray icon appears in the notification area (near the clock; it may be under the **^** arrow).

### 2.4 Where things live

- Settings: `%APPDATA%\Skreener\settings.json`
  (Paste `%APPDATA%\Skreener` into the File Explorer address bar.)
- Screenshots: `Pictures\Skreener` in your user folder.

---

## Part 3: Test cases

**Columns:** Steps are exactly what to click or press. Expected result is what you should see. Mark Pass or Fail.

"Tray icon" means the Skreener icon in the notification area near the clock.

### Launch and single instance

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 1 | Double-click `Skreener.exe`. | A tray icon appears. No error dialog. | [ ] / [ ] |
| 2 | With Skreener already running, double-click `Skreener.exe` again. | Still only one tray icon. Open Task Manager, Details tab: only one `Skreener.exe` process. | [ ] / [ ] |

### Tray menu

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 3 | Right-click the tray icon. (If hidden, click **^** first.) | A menu opens with the capture actions, **Launch at login**, and **Quit**. | [ ] / [ ] |
| 4 | Right-click the tray icon. Click **Area**. | The area selection overlay appears (same as Ctrl+Alt+4). | [ ] / [ ] |

### Hotkeys

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 5 | Click on the desktop. Press **Ctrl+Alt+4**. | The area selection overlay appears. | [ ] / [ ] |
| 6 | Press **Ctrl+Alt+3**. | The screen is captured at once with no overlay. A save or clipboard result follows (see Output). | [ ] / [ ] |
| 7 | Press **Ctrl+Alt+5**. | Window mode starts: hovering a window highlights it. | [ ] / [ ] |
| 8 | Setup: start another app that already uses **Ctrl+Alt+4** (for example, an AutoHotkey script containing `^!4::return`). Then start Skreener. Press **Ctrl+Alt+4**. | A toast says the hotkey is in use or conflicts. Skreener keeps running. | [ ] / [ ] |

### Area capture

Start each case with **Ctrl+Alt+4**.

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 9 | Press and hold the left mouse button. Drag to make a rectangle. Keep holding. | The rectangle follows the mouse. A label shows **W x H** (width by height) and updates as you drag. | [ ] / [ ] |
| 10 | Finish case 9 with a click to confirm (Enter). Open the saved file in Paint (see Output). Read the size in the Paint status bar at the bottom. | The label's W x H matches the image size in pixels. The label uses physical pixels, so it matches the file, not the logical size. | [ ] / [ ] |
| 11 | Press and hold the left mouse button. Hold **Shift**. Drag. Release. | The selection is a square. | [ ] / [ ] |
| 12 | Press and hold the left mouse button at a point. Hold **Alt**. Drag outward from that point. | The selection grows from the centre (the first point is the centre), not from a corner. | [ ] / [ ] |
| 13 | Start a selection. While holding or after the drag, press the **Left**, **Right**, **Up** and **Down** arrow keys. | The selection edge nudges a small amount with each arrow press. | [ ] / [ ] |
| 14 | Drag a rectangle, release the mouse button. Look at the corners and edge midpoints. | Small handles appear on the corners and edge midpoints. | [ ] / [ ] |
| 15 | After release (case 14), press and hold a handle and drag it. | The edge or corner follows the mouse. The rectangle resizes. | [ ] / [ ] |
| 16 | After release, hold **Ctrl** and press **Right**, then **Left**, then **Down**, then **Up**. | The selection resizes in each direction. | [ ] / [ ] |
| 17 | After release, move the mouse over the selection and scroll the wheel **up** (away from you) several notches. | The selection grows. | [ ] / [ ] |
| 18 | After release, scroll the wheel **down** (toward you) several notches. | The selection shrinks. | [ ] / [ ] |
| 19 | Make a selection. Press **Enter**. | The capture completes: the overlay closes and the image is saved and copied (see Output). | [ ] / [ ] |
| 20 | Make a selection. Double-click inside the selection. | The capture completes and the overlay closes. | [ ] / [ ] |
| 21 | Start **Ctrl+Alt+4**. Make a selection. Press **Esc**. | Nothing is saved. No toast. All overlays close. | [ ] / [ ] |
| 22 | Start **Ctrl+Alt+4**. Make a selection. Right-click. | Nothing is saved. All overlays close. | [ ] / [ ] |
| 23 | Start **Ctrl+Alt+4**. Press **Space**. | Mode switches to window mode: hovering a window highlights it. | [ ] / [ ] |
| 24 | In window mode (case 23), press **Space** again. | Mode switches back to area selection. | [ ] / [ ] |

### Window capture

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 25 | Press **Ctrl+Alt+5**. Move the mouse over an open window (for example, Notepad). | The window is highlighted. | [ ] / [ ] |
| 26 | Open Notepad and move a second window (Paint) over part of it so Notepad is partly covered. Press **Ctrl+Alt+5**. Hover over the visible part of Notepad (or over the covered area, if the highlight allows). Click. Open the saved file in Paint. | The capture contains the whole Notepad window, including the parts hidden behind Paint. | [ ] / [ ] |
| 27 | Repeat case 26 with any window. Look at the highlight and the saved image's edges. | There is no yellow border on the highlight or in the saved image. | [ ] / [ ] |
| 28 | **[verify]** Capture a Windows 11 window that has rounded corners (for example, File Explorer, using window mode). Open the file in Paint. Zoom in on one corner (View > Zoom, or Ctrl+mouse wheel). | Record what you see: the corner is either **transparent** (checkerboard or see-through) or **filled** with a solid colour. Write the result in your report. This is a record, not a pass/fail check. | Record only |

### Fullscreen

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 29 | Make sure the display is at 100% scale (see 1.5). Open **Settings > System > Display** and note the resolution. Press **Ctrl+Alt+3**. Open the file in Paint and read the status bar. | The image is the full screen at native resolution (matches the resolution in Settings). It is not a smaller or blurred image. | [ ] / [ ] |

### Previous Area

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 30 | Press **Ctrl+Alt+4**. Make a selection and confirm with Enter. Press **Ctrl+Alt+1**. | The same area is captured again straight away, with no overlay. The new file shows what is on screen now. | [ ] / [ ] |
| 31 | Quit Skreener (see Quit). Start it again. Press **Ctrl+Alt+1** before any capture. | A "No area to repeat" toast appears. Nothing crashes, and Skreener keeps running. | [ ] / [ ] |

### Output

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 32 | Capture with **Ctrl+Alt+3**. Open **Paint**. Press **Ctrl+V**. | The screenshot appears in Paint. | [ ] / [ ] |
| 33 | Open File Explorer, go to `Pictures\Skreener`. | A new file named `Skreener yyyy-mm-dd at hh.mm.ss.png` exists, with today's date and the time of the capture (for example, `Skreener 2026-10-25 at 14.03.22.png`). | [ ] / [ ] |
| 34 | Capture with **Ctrl+Alt+3**. Watch the bottom-right corner of the screen. | A **"Saved to..."** toast appears. | [ ] / [ ] |
| 35 | Click the "Saved to..." toast. | File Explorer opens with the new file selected. | [ ] / [ ] |

### Quick Access

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 36 | Capture with **Ctrl+Alt+3**. Look at the bottom-right of the screen. | A thumbnail of the capture appears in the bottom-right corner. | [ ] / [ ] |
| 37 | Open **Notepad** and click in it. Type a few words. Capture with **Ctrl+Alt+3** while typing. | The thumbnail appears but does not take focus. Typing continues in Notepad. Notepad stays the active window. | [ ] / [ ] |
| 38 | When the thumbnail is showing, move the mouse over it. | **Copy**, **Save**, **Edit** and **Close** buttons appear on the thumbnail. | [ ] / [ ] |
| 39 | Keep the mouse over the thumbnail for at least 15 seconds. | The thumbnail stays open while the mouse is over it. | [ ] / [ ] |
| 40 | Move the mouse away from the thumbnail. Do not touch it. Count to 10. | The thumbnail closes after about 6 seconds. | [ ] / [ ] |
| 41 | Capture. Hover the thumbnail, click **Copy**. Open Paint, press **Ctrl+V**. | The captured image is pasted. | [ ] / [ ] |
| 42 | Capture. Hover the thumbnail, click **Save**. Open `Pictures\Skreener` in File Explorer. | A new `Skreener ...png` file is there for this capture. | [ ] / [ ] |
| 43 | Capture. Hover the thumbnail, click **Close**. | The thumbnail closes immediately. | [ ] / [ ] |
| 44 | Capture with **Ctrl+Alt+3** (thumbnail appears). Before it closes, capture again with **Ctrl+Alt+3**. Open the second capture in Paint. | The second capture does not contain a Quick Access thumbnail. | [ ] / [ ] |

### Editor

Cases are numbered E1, E2, … so the numbers of the cases after this section stay the same.

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| E1 | Press **Ctrl+Alt+4** and drag over part of a window with text. Release, press **Enter**. Hover the thumbnail and click **Edit**. | The thumbnail closes. A **Skreener Editor** window opens in the middle of the screen the capture came from, showing the capture at 100 % (or shrunk to fit if it is big), on a dark grey background. **Arrow** is highlighted in the toolbar. | [ ] / [ ] |
| E2 | Drag across the image. | A red arrow follows the pointer while you drag: a line with a filled head at the point where you release. After release it has a white dot with a blue ring at each end. | [ ] / [ ] |
| E3 | Click **Rect**, drag a box. Click **Ellipse**, drag another. Click **Line**, drag. | Each tool draws its shape in red while you drag. The tool you clicked is highlighted. Rectangles and ellipses get four corner dots when finished. | [ ] / [ ] |
| E4 | Click **Pen** and scribble. Then draw a second stroke holding **Shift**. | The first stroke follows the pointer freely. The Shift stroke is a straight line from where you pressed to where you released. A finished pen stroke shows a dashed blue frame instead of dots. | [ ] / [ ] |
| E5 | Click **Pixelate** and drag over some text. | The text inside the box turns into coarse blocks. The color dots and the width box are replaced by a **Blocks 10 px** box. | [ ] / [ ] |
| E6 | With the pixelate box selected, choose **Blocks 24 px**. | The blocks in the selected box get bigger. | [ ] / [ ] |
| E7 | Click **Select**. Click on the line of a rectangle and drag it. Then drag one of its corner dots. | The rectangle moves with the pointer. Dragging a corner resizes it while the opposite corner stays put. | [ ] / [ ] |
| E8 | Click **Arrow**. Press on the middle of an existing arrow's line and drag. | The arrow moves; no new arrow is drawn (a press on a shape grabs it with any tool). | [ ] / [ ] |
| E9 | Click inside a rectangle (not on its line) with **Rect** selected, and drag. | A new rectangle is drawn inside it. The first rectangle doesn't move. | [ ] / [ ] |
| E10 | Select a shape (click its line). Click the blue color dot, then choose **12 px** in the width box. | The selected shape turns blue and gets thicker. The blue dot has a ring around it. The next shape you draw is blue and 12 px too. | [ ] / [ ] |
| E11 | Select a shape. Press the **arrow keys**, then **Shift+arrow keys**. | It moves 1 pixel per press, 10 pixels with Shift. | [ ] / [ ] |
| E12 | Select a shape and press **Delete**. | It disappears. | [ ] / [ ] |
| E13 | Press **Ctrl+Z** several times, then **Ctrl+Y** several times. Also try the **Undo** and **Redo** buttons. | Each Ctrl+Z takes back one step (a drawn shape, a move, a delete, a color change); Ctrl+Y redoes it. A whole drag is one step. Undo is greyed out when there is nothing left to undo, Redo when there is nothing to redo. | [ ] / [ ] |
| E14 | Press **V**, **A**, **R**, **O**, **L**, **P**, **X** one at a time. | The highlighted tool changes to Select, Arrow, Rect, Ellipse, Line, Pen, Pixelate in turn. | [ ] / [ ] |
| E15 | Start dragging a new rectangle and press **Esc** before releasing. Then select a shape and press **Esc**. | The rectangle being drawn disappears. The second Esc deselects the shape (its dots go away). | [ ] / [ ] |
| E16 | Click **Copy** (or press **Ctrl+C**). Open Paint and press **Ctrl+V**. | The screenshot is pasted with all the shapes drawn in, at the full capture size, with no selection dots. | [ ] / [ ] |
| E17 | Click **Save** (or press **Ctrl+S**). Open `Pictures\Skreener`. | A new file with the shapes drawn in is there, and a "Screenshot saved" toast appears. | [ ] / [ ] |
| E18 | Draw a new shape. Close the editor with the **X** button. | A dialog asks **Save your changes?** with **Save**, **Don't Save** and **Cancel**. **Cancel** keeps the editor open. **Don't Save** closes it. **Save** saves a file (as E17) and closes it. | [ ] / [ ] |
| E19 | Open an editor, Copy or Save, then close it without drawing anything more. | It closes without asking. | [ ] / [ ] |
| E20 | Make the editor window smaller and bigger by dragging its edge. | The image shrinks to fit and grows back, never past 100 %. Shapes stay on the same spot of the image. Drawing still lands exactly under the pointer. | [ ] / [ ] |
| E21 | Capture a window with **Ctrl+Alt+5** and open it in the editor. Open two editors at once from two captures. | Both editors work on their own. | [ ] / [ ] |
| E22 | At 150 % display scaling (see 1.5), repeat E1, E2 and E16. | The image is sharp at 100 % (one capture pixel per screen pixel). The pasted image has the full capture size. | [ ] / [ ] |

### Capture Text

Capture Text is **Ctrl+Alt+2** or the tray menu's **Capture Text**. It needs a Windows OCR language: English is installed on most PCs (Settings > Time & Language > Language & region). Prepare a Notepad window with a few lines of large, plain text, for example "Skreener reads this line" on one line and "and this one too" on the next, at normal zoom. Cases T1 to T16.

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| T1 | Press **Ctrl+Alt+2**. | The area selection overlay appears, the same as for Ctrl+Alt+4. | [ ] / [ ] |
| T2 | Right-click the tray icon. Click **Capture Text**. | The tray menu closes, then the area selection overlay appears. The menu is not in the way of what you select. | [ ] / [ ] |
| T3 | Press **Ctrl+Alt+2**. Press **Esc**. Open `Pictures\Skreener`. | The overlay closes. No window and no toast appear. No new file in the folder. | [ ] / [ ] |
| T4 | Press **Ctrl+Alt+2**. Drag a rectangle around the text in Notepad. Press **Enter**. | A window titled **Captured Text** opens in the middle of the display the pointer is on, in front of other windows. It holds the text you selected, one recognized line per line, all selected. At the bottom: **Join Lines**, a line and character count, and **Copy to Clipboard**. | [ ] / [ ] |
| T5 | After T4, look at `Pictures\Skreener` and the bottom-right corner. Open Paint and press **Ctrl+V**. | No new screenshot file, no Quick Access thumbnail, and no image on the clipboard: Capture Text does not save, copy or show the capture. | [ ] / [ ] |
| T6 | Click on the Notepad window, then press **Ctrl+Alt+2** and select an empty (blank) part of the screen, such as an empty part of the desktop or a plain white area. Press **Enter**. | A **No text found** toast appears. No window opens. | [ ] / [ ] |
| T7 | Setup: in Notepad type "The screen-" on one line and "shot tool works. Jean-" on the next, then "Paul agrees" on a third (use a large font). Capture that text with **Ctrl+Alt+2**. In the **Captured Text** window click **Join Lines**. | The three lines become one: "The screenshot tool works. Jean- Paul agrees". "screen-" and "shot" are mended into "screenshot". "Jean-" and "Paul" keep their hyphen (capital letter after it). | [ ] / [ ] |
| T8 | In the Captured Text window, select only the first two lines with the mouse. Click **Join Lines**. | Only the selected lines are merged. The lines after them stay as they were. | [ ] / [ ] |
| T9 | Type a few extra words in the text box. Click **Copy to Clipboard**. Open Notepad, click in it and press **Ctrl+V**. | The pad closes. A toast says "Copied N lines of text". Notepad receives the exact text from the pad, as plain text, with your extra words. | [ ] / [ ] |
| T10 | Capture text again. In the pad, press **Ctrl+Enter**. Paste in Notepad. | Same as T9: the text is copied, the pad closes, and the toast appears. | [ ] / [ ] |
| T11 | Capture text again. Press **Esc** in the pad. Paste in Notepad (after copying something else first, for example the word "marker"). | The pad closes. The clipboard still holds "marker". No toast. | [ ] / [ ] |
| T12 | Capture text and leave the pad open. Press **Ctrl+Alt+2** again and capture different text. | The same pad window takes the new text (no second window opens). Pressing the close button of the pad closes it without copying. | [ ] / [ ] |
| T13 | Open a long web page or document so that text fills a tall area. Press **Ctrl+Alt+2** and select a tall area (the full height of the screen, or taller by nudging the selection). Press **Enter**. | The text of the whole area is recognized, from top to bottom, with no error toast. (Images over 10,000 px per side are scaled down to fit the OCR engine, so only extreme areas lose accuracy.) | [ ] / [ ] |
| T14 | Set the display to **150 %** (see 1.5). Repeat T4. | The text is recognized as in T4. The pad opens fully on screen and its text and buttons are sharp and not cut off. | [ ] / [ ] |
| T15 | **Needs another OCR language.** Add a language in Settings > Time & Language > Language & region (for example Japanese or German; its optional "Optical character recognition" feature must install). Show text in that language and capture it with **Ctrl+Alt+2**. | The text is recognized when that language is in your language list. For Chinese or Japanese the words come out without stray spaces between characters. | [ ] / [ ] |
| T16 | **Needs a PC with no OCR language** (remove the OCR feature of every language under Settings > Time & Language > Language & region > the language's options; this is rare). Capture text. | A toast "No OCR language installed" says to add one in Settings > Time & Language > Language & region. No crash. | [ ] / [ ] |

### Settings

Before starting, quit Skreener from the tray (see Quit) if it is running, then reopen it.

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 45 | Open File Explorer. Paste `%APPDATA%\Skreener` into the address bar and press Enter. Open `settings.json` in Notepad. | The file exists and opens in Notepad. | [ ] / [ ] |
| 46 | Copy some text in Notepad (Ctrl+C) so you know what the clipboard holds. In `settings.json`, set `"Format": "Jpeg"` and `"CopyToClipboard": false`. Save. Do **not** restart Skreener. Press **Ctrl+Alt+3**. Open `Pictures\Skreener`, then open the newest file. Then, in Paint, press **Ctrl+V**. | The newest file is a JPEG (`.jpg` or `.jpeg`). Paint's Ctrl+V pastes the old text or nothing, not the new screenshot. The new setting applied with no restart. | [ ] / [ ] |
| 47 | Set `"CopyToClipboard"` back to `true` and `"Format"` back to `"Png"`. Save. Press **Ctrl+Alt+3**. | The newest file is a PNG. The screenshot is on the clipboard (Ctrl+V in Paint shows it). | [ ] / [ ] |

### Launch at login

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 48 | Right-click the tray icon. Click **Launch at login** to turn it on. | The **Launch at login** item shows as checked (on). | [ ] / [ ] |
| 49 | Open Task Manager (Ctrl+Shift+Esc). Click the **Startup apps** tab. Find **Skreener**. | Skreener is listed and its status is **Enabled**. | [ ] / [ ] |
| 50 | Sign out of Windows (Start > your user icon > Sign out). Sign back in. Wait about 30 seconds. | The Skreener tray icon appears without you starting it. | [ ] / [ ] |
| 51 | Right-click the tray icon. Click **Launch at login** to turn it off. Open Task Manager > **Startup apps**. | Skreener is no longer Enabled (not listed, or Disabled). | [ ] / [ ] |

### Quit

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 52 | Right-click the tray icon. Click **Quit**. | The tray icon disappears. In Task Manager Details, no `Skreener.exe` remains. Pressing **Ctrl+Alt+4** does nothing. | [ ] / [ ] |

### Multi-monitor and mixed DPI

**Needs real PC or Parallels** for all cases in this section. Set up two monitors before starting.

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 53 | **Needs real PC or Parallels.** Set both monitors to **100%** (Settings > System > Display). Press **Ctrl+Alt+4**. | The overlay covers each monitor exactly. No gap at the edges and no overflow onto other areas. | [ ] / [ ] |
| 54 | **Needs real PC or Parallels.** Set monitor 1 to **100%** and monitor 2 to **150%**. Press **Ctrl+Alt+4**. | The overlay covers each monitor exactly, on both. | [ ] / [ ] |
| 55 | **Needs real PC or Parallels.** Keep the mixed setup (case 54). Put the mouse on monitor 2. Press **Ctrl+Alt+4**. Drag a rectangle entirely on monitor 2 and confirm with Enter. Open the file in Paint. | The saved image shows the area you selected on monitor 2, cropped correctly with no offset. | [ ] / [ ] |
| 56 | **Needs real PC or Parallels.** Keep the mixed setup. Repeat case 55 on monitor 1. | The saved image shows the area you selected on monitor 1, cropped correctly with no offset. | [ ] / [ ] |
| 57 | **Needs real PC or Parallels.** Keep the mixed setup. Put a window on monitor 2. Press **Ctrl+Alt+5**, hover the window, click. Open the file in Paint. | The window is captured completely and at the right size (no cut-off edges, not stretched). | [ ] / [ ] |
| 58 | **Needs real PC or Parallels.** Keep the mixed setup. Put the mouse on monitor 2. Press **Ctrl+Alt+3**. Open the file in Paint and read the status bar. | The capture is of monitor 2 at its native resolution. | [ ] / [ ] |
| 59 | **Needs real PC or Parallels.** Keep the mixed setup. Put the mouse on monitor 1. Press **Ctrl+Alt+3**. | The capture is of monitor 1, not monitor 2. | [ ] / [ ] |

### Explorer restart

| # | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| 60 | Press the **Start** button, type `cmd`, press **Enter** (a normal, non-administrator window is fine). Type `taskkill /f /im explorer.exe` and press **Enter**. | The taskbar and desktop icons disappear. The Command Prompt window stays open. | [ ] / [ ] |
| 61 | In the same Command Prompt window, type `start explorer.exe` and press **Enter**. Wait 10 seconds. | The taskbar and desktop return. | [ ] / [ ] |
| 62 | Look for the Skreener tray icon in the notification area. (If hidden, click **^**.) | The Skreener tray icon is back. | [ ] / [ ] |

---

## Part 4: Reporting a problem

When a case fails, or something looks wrong, collect the following and paste it into the Claude session.

1. **Screenshot** of the problem. Use Ctrl+Alt+3 (the Skreener capture) or Windows **Win+Shift+S**.
2. **Steps:** the case number and exactly what you did, in order.
3. **What you expected** and **what happened**.
4. **Windows version:** press **Win+R**, type `winver`, press **Enter**. Copy the version and build shown.
5. **Display scaling:** Settings > System > Display > Scale (for example, 100% or 150%). Note each monitor if you have more than one.
6. **Machine type:** ARM (Windows 11 ARM VM on Apple Silicon) or x64 (Intel or AMD PC). Which artifact did you download: **Skreener-windows-ARM64** or **Skreener-windows-x64**?
7. **Contents of `settings.json`:** open `%APPDATA%\Skreener\settings.json` in Notepad and copy the whole text. Remove anything personal if you have added it.
8. **Rounded-corner result** (case 28), if you ran it.

Paste all of the above into the Claude session in one message.
