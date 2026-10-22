#!/bin/bash
# Builds Skreener.app (macOS only). Usage: Scripts/build_app.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."
# SKREENER_STRICT=1 (set in CI) turns compiler warnings into errors so none slip through.
if [ "${SKREENER_STRICT:-}" = "1" ]; then
  swift build -c release -Xswiftc -warnings-as-errors
else
  swift build -c release
fi
APP=build/Skreener.app
# Shown in About Skreener, so you can tell which commit is actually running.
BUILD=$(git rev-parse --short HEAD 2>/dev/null || echo dev)
# Marketing version (About, Finder). Scripts/release.sh sets it from --version or the git tag.
VERSION="${SKREENER_VERSION:-0.1.0}"
# A running copy keeps the old code (and its hotkeys), so quit it before replacing the bundle.
pkill -x Skreener 2>/dev/null && sleep 0.5 || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Skreener "$APP/Contents/MacOS/Skreener"
# App icon and menu bar template image (regenerate with Scripts/make_icons.py).
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Skreener</string>
  <key>CFBundleIdentifier</key><string>com.skreener.app</string>
  <key>CFBundleExecutable</key><string>Skreener</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Skreener needs screen recording access to take screenshots and record the screen.</string>
  <key>NSMicrophoneUsageDescription</key><string>Skreener records your microphone in screen recordings when you turn that on in Settings.</string>
</dict></plist>
PLIST
# Ad-hoc signing ("-") changes the app's identity on every build, so macOS forgets the
# Screen Recording grant. Sign with a stable certificate instead: SKREENER_SIGN_IDENTITY if set,
# otherwise "Skreener Dev" when it exists (create it once with Scripts/make_dev_cert.sh).
has_identity() { security find-identity -v -p codesigning | grep -q "\"$1\""; }
if [ -n "${SKREENER_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SKREENER_SIGN_IDENTITY"
  if [ "$IDENTITY" != "-" ] && ! has_identity "$IDENTITY"; then
    echo "warning: signing identity \"$IDENTITY\" not found; falling back to ad-hoc (Screen Recording will be re-requested)." >&2
    echo "         Create it once with Scripts/make_dev_cert.sh" >&2
    IDENTITY="-"
  fi
elif has_identity "Skreener Dev"; then
  IDENTITY="Skreener Dev"
else
  echo "note: no \"Skreener Dev\" certificate; signing ad-hoc (Screen Recording will be re-requested)." >&2
  echo "      Run Scripts/make_dev_cert.sh once to keep the permission across builds." >&2
  IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"
[ "$IDENTITY" = "-" ] && SIGNED="ad-hoc" || SIGNED="\"$IDENTITY\""
echo "Built $APP $VERSION at $BUILD (signed with $SIGNED)"
# Pass --run to launch it right away.
if [ "${1:-}" = "--run" ]; then open "$APP"; fi
