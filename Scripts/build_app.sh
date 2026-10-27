#!/bin/bash
# Builds Skreener.app (macOS only). Usage: Scripts/build_app.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."
# Shortcuts actions (#274): Shortcuts finds them in the bundle's Metadata.appintents, which Xcode generates with
# appintentsmetadataprocessor and SwiftPM doesn't, so this script runs that tool itself (below). It reads what the
# compiler knows about the App Intents types (constant values for the protocols listed here, like Xcode's list) and
# the linker's dependency info, and skips an app that doesn't link AppIntents.framework there.
INTENTS="$PWD/.build/appintents"
mkdir -p "$INTENTS"
echo '["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider",
"AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider","_IntentValueRepresentable","IntentValueQuery"]' \
  > "$INTENTS/protocols.json"
FLAGS=(-Xswiftc -emit-const-values-path -Xswiftc "$INTENTS/Skreener.swiftconstvalues"
  -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$INTENTS/protocols.json"
  -Xlinker -dependency_info -Xlinker "$INTENTS/link_dependency_info.dat")
# SKREENER_STRICT=1 (set in CI) turns compiler warnings into errors so none slip through.
if [ "${SKREENER_STRICT:-}" = "1" ]; then FLAGS+=(-Xswiftc -warnings-as-errors); fi
swift build -c release "${FLAGS[@]}"
APP=build/Skreener.app
# Version info comes from git, so it changes on its own with every commit and release (#135); nothing to edit by hand.
# Marketing version (About, Finder): SKREENER_VERSION (release.sh sets it from --version or the tag), else the newest
# vX.Y.Z tag this commit descends from, without the "v", else version.txt. release-please moves both on when its
# release PR is merged (.github/workflows/release-please.yml).
TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
VERSION="${SKREENER_VERSION:-${TAG#v}}"
VERSION="${VERSION:-$(tr -d '[:space:]' < version.txt)}"
# Build number: the count of commits up to this one, so it goes up with every commit (CI needs the full history).
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
# Shown in About Skreener next to the version, so you can tell which commit is actually running. "+" marks a build
# with uncommitted changes.
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo dev)
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then COMMIT="$COMMIT+"; fi
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
  <key>SkreenerCommit</key><string>$COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.skreener.app</string>
    <key>CFBundleURLSchemes</key><array><string>skreener</string></array>
  </dict></array>
  <key>NSScreenCaptureUsageDescription</key><string>Skreener needs screen recording access to take screenshots and record the screen.</string>
  <key>NSAppleEventsUsageDescription</key><string>Skreener asks your browser for the address of the page you capture, so you can get back to it from Saved Files, and asks Notes and Reminders to add a capture when you pick them in Send To.</string>
  <key>NSMicrophoneUsageDescription</key><string>Skreener records your microphone in screen recordings when you turn that on in Settings.</string>
</dict></plist>
PLIST
# Metadata.appintents for the Shortcuts actions (see the top). The tool may write to the dependency file it is given,
# so it gets a copy: the linker only writes the original when it links again.
if xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  cp "$INTENTS/link_dependency_info.dat" "$INTENTS/dependency_info.dat"
  find "$PWD/Sources/Skreener" -name '*.swift' > "$INTENTS/sources.txt"
  echo "$INTENTS/Skreener.swiftconstvalues" > "$INTENTS/constvalues.txt"
  : > "$INTENTS/metadata.txt"
  TOOLCHAIN="$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")"
  xcrun appintentsmetadataprocessor --toolchain-dir "$TOOLCHAIN" --module-name Skreener \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
    --platform-family macOS --deployment-target 14.0 --target-triple "$(uname -m)-apple-macos14.0" \
    --bundle-identifier com.skreener.app --output "$APP/Contents/Resources" --binary-file "$APP/Contents/MacOS/Skreener" \
    --dependency-file "$INTENTS/dependency_info.dat" --stringsdata-file "$INTENTS/ExtractedAppShortcutsMetadata.stringsdata" \
    --source-file-list "$INTENTS/sources.txt" --swift-const-vals-list "$INTENTS/constvalues.txt" \
    --metadata-file-list "$INTENTS/metadata.txt" --static-metadata-file-list "$INTENTS/metadata.txt" \
    --compile-time-extraction --deployment-aware-processing --no-app-shortcuts-localization
  [ -d "$APP/Contents/Resources/Metadata.appintents" ] || { echo "error: no Metadata.appintents in $APP" >&2; exit 1; }
else
  echo "warning: appintentsmetadataprocessor not found (it comes with Xcode); Skreener's actions won't show up in Shortcuts." >&2
fi
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
echo "Built $APP $VERSION ($BUILD, $COMMIT) (signed with $SIGNED)"
# Pass --run to launch it right away.
if [ "${1:-}" = "--run" ]; then open "$APP"; fi
