#!/bin/bash
# Builds Skreener.app (macOS only). Usage: Scripts/build_app.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Skreener.app
# A running copy keeps the old code (and its hotkeys), so quit it before replacing the bundle.
pkill -x Skreener 2>/dev/null && sleep 0.5 || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/Skreener "$APP/Contents/MacOS/Skreener"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Skreener</string>
  <key>CFBundleIdentifier</key><string>com.skreener.app</string>
  <key>CFBundleExecutable</key><string>Skreener</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Skreener needs screen recording access to take screenshots.</string>
</dict></plist>
PLIST
# Ad-hoc signing ("-") changes the app's identity on every build, so macOS forgets the
# Screen Recording grant. Set SKREENER_SIGN_IDENTITY to a stable certificate name to keep it.
IDENTITY="${SKREENER_SIGN_IDENTITY:--}"
if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "warning: signing identity \"$IDENTITY\" not found; falling back to ad-hoc (Screen Recording will be re-requested)." >&2
  echo "         Create it once with Scripts/make_dev_cert.sh" >&2
  IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with ${IDENTITY/#-/ad-hoc})"
# Pass --run to launch it right away.
if [ "${1:-}" = "--run" ]; then open "$APP"; fi
