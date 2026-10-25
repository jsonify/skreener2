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
| 38 | When the thumbnail is showing, move the mouse over it. | **Copy**, **Save** and **Close** buttons appear on the thumbnail. | [ ] / [ ] |
| 39 | Keep the mouse over the thumbnail for at least 15 seconds. | The thumbnail stays open while the mouse is over it. | [ ] / [ ] |
| 40 | Move the mouse away from the thumbnail. Do not touch it. Count to 10. | The thumbnail closes after about 6 seconds. | [ ] / [ ] |
| 41 | Capture. Hover the thumbnail, click **Copy**. Open Paint, press **Ctrl+V**. | The captured image is pasted. | [ ] / [ ] |
| 42 | Capture. Hover the thumbnail, click **Save**. Open `Pictures\Skreener` in File Explorer. | A new `Skreener ...png` file is there for this capture. | [ ] / [ ] |
| 43 | Capture. Hover the thumbnail, click **Close**. | The thumbnail closes immediately. | [ ] / [ ] |
| 44 | Capture with **Ctrl+Alt+3** (thumbnail appears). Before it closes, capture again with **Ctrl+Alt+3**. Open the second capture in Paint. | The second capture does not contain a Quick Access thumbnail. | [ ] / [ ] |

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
