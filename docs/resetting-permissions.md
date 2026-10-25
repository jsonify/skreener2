# Resetting permissions

Use this when Skreener's switches in **System Settings > Privacy & Security** look on but the permission doesn't
work: captures come back blank or fail, macOS keeps asking for Screen Recording after every build, or scrolling
capture can't auto-scroll.

## Why it happens

macOS ties each grant (Screen Recording, Accessibility, Microphone) to the app's bundle ID (`com.skreener.app`)
**and its code signature**. A grant made to an ad-hoc build, an older certificate or another copy of the app no
longer matches the build you are running, so macOS ignores it even though the switch is on. Release builds (signed
by CI with the release certificate) and local builds (signed with "Skreener Dev" or ad-hoc) are different
identities, so switching between them resets grants too.

## Steps

1. **Quit Skreener and remove stray copies.** Keep one copy of the app: look in `/Applications`, `build/`,
   `~/Downloads` and any zips you unpacked.

   ```sh
   pkill -x Skreener
   ```

2. **Reset Skreener's grants.**

   ```sh
   tccutil reset ScreenCapture com.skreener.app
   tccutil reset Accessibility com.skreener.app
   tccutil reset Microphone com.skreener.app
   ```

   If a stale "Skreener" entry still shows in Screen Recording or Accessibility, select it and remove it with the
   minus button.

3. **Use one stable signing identity for local builds.** Ad-hoc signing changes the app's identity on every build.

   ```sh
   security find-identity -v -p codesigning   # what is installed
   Scripts/make_dev_cert.sh                   # creates "Skreener Dev" if there is none
   ```

   Delete stale or duplicate certificates with the same name in Keychain Access. To sign with a different
   identity, set `SKREENER_SIGN_IDENTITY` before building.

4. **Rebuild, launch and grant once.**

   ```sh
   Scripts/build_app.sh --run
   ```

   Approve Screen Recording, then Accessibility and Microphone when asked. Quit and reopen Skreener after granting
   Screen Recording. **Settings > General** shows the status of each permission.

Pick one build to test with, release or local, so the grants stay put.
