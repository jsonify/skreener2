#!/bin/bash
# Builds a distributable Skreener: Developer ID signature with the hardened runtime, notarised by
# Apple, ticket stapled, packaged as a DMG and a zip in build/release/ (macOS only).
# Run Scripts/release.sh --help for usage and the credentials it needs.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: Scripts/release.sh [options]

Builds build/Skreener.app (via Scripts/build_app.sh), signs it with a Developer ID Application
certificate (hardened runtime, Resources/Skreener.entitlements, secure timestamp), notarises it
with notarytool, staples the ticket, and writes to build/release/:
  Skreener-<version>.dmg   signed, notarised and stapled disk image (app + Applications link)
  Skreener-<version>.zip   the stapled app, zipped with ditto
  SHA256SUMS               checksums of the above

Options:
  --version X.Y.Z     Marketing version (CFBundleShortVersionString). Default: $SKREENER_VERSION,
                      else the current commit's tag without the leading "v" (v1.2.0 -> 1.2.0),
                      else build_app.sh's default.
  --format F          dmg, zip or both (default: both).
  --skip-notarize     Sign and package only; no Apple credentials needed. Outputs are named
                      *-unnotarized and Gatekeeper will still block them on other Macs.
  --self-signed       Release without a paid Apple Developer account: sign with a self-signed
                      certificate (SKREENER_SIGN_IDENTITY, default "Skreener Dev" from
                      Scripts/make_dev_cert.sh); no notarisation or hardened runtime. The same certificate on every
                      release keeps the Screen Recording permission across updates, but Gatekeeper
                      calls a browser download "damaged": people install with Scripts/install.sh or
                      the in-app updater, which skip it. The DMG is left unsigned: Gatekeeper rejects a disk image
                      signed with a self-signed certificate outright. With SKREENER_SIGN_P12
                      (the certificate as a .p12 file) and
                      SKREENER_SIGN_P12_PASSWORD_FILE, it signs with rcodesign instead of codesign,
                      which doesn't need the certificate trusted on this Mac (used on CI).
  -h, --help          Show this help.

Signing identity (from your keychain, never the repo):
  SKREENER_DEVELOPER_ID   "Developer ID Application: Your Name (TEAMID)" or its SHA-1 hash.
                          If unset, the only Developer ID Application identity in the keychain is used.
  SKREENER_KEYCHAIN       Optional keychain file to search (used by CI's temporary keychain).

Notarisation credentials (first set that is complete wins):
  1. SKREENER_NOTARY_PROFILE    A notarytool keychain profile, created once with
                                  xcrun notarytool store-credentials skreener-notary \
                                    --apple-id you@example.com --team-id TEAMID
                                (asks for an app-specific password from appleid.apple.com)
  2. SKREENER_NOTARY_KEY        Path to an App Store Connect API key (.p8), with
     SKREENER_NOTARY_KEY_ID     its key ID and
     SKREENER_NOTARY_ISSUER     its issuer ID (Users and Access -> Integrations -> Team Keys)
  3. SKREENER_NOTARY_APPLE_ID   Apple ID email, with
     SKREENER_NOTARY_TEAM_ID    the 10-character team ID and
     SKREENER_NOTARY_PASSWORD   an app-specific password

Other environment: SKREENER_STRICT=1 builds with warnings as errors (as CI does).

Example:
  SKREENER_NOTARY_PROFILE=skreener-notary Scripts/release.sh --version 0.2.0
EOF
}

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

VERSION="${SKREENER_VERSION:-}"
FORMAT=both
NOTARIZE=1
SELF_SIGNED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || die "--version needs a value, e.g. --version 0.2.0"; VERSION="$2"; shift 2 ;;
    --version=*) VERSION="${1#*=}"; shift ;;
    --format) [ $# -ge 2 ] || die "--format needs dmg, zip or both"; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --skip-notarize|--skip-notarise) NOTARIZE=0; shift ;;
    --self-signed) SELF_SIGNED=1; NOTARIZE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; echo >&2; die "unknown option: $1" ;;
  esac
done
case "$FORMAT" in dmg|zip|both) ;; *) die "--format must be dmg, zip or both (got \"$FORMAT\")" ;; esac

# ---- Checks first, so a missing credential fails in seconds rather than after the build. ----
[ "$(uname -s)" = "Darwin" ] || die "release.sh needs macOS (codesign, notarytool, hdiutil)."
for tool in codesign security ditto hdiutil plutil; do
  command -v "$tool" >/dev/null || die "$tool not found."
done

if [ -z "$VERSION" ]; then
  TAG=$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)
  VERSION="${TAG#v}"
fi
if [ -n "$VERSION" ] && ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  die "version \"$VERSION\" must look like 1, 1.2 or 1.2.3 (Apple's CFBundleShortVersionString format)."
fi

KEYCHAIN="${SKREENER_KEYCHAIN:-}"
KEYCHAIN_ARGS=()
if [ -n "$KEYCHAIN" ]; then
  [ -f "$KEYCHAIN" ] || die "SKREENER_KEYCHAIN=\"$KEYCHAIN\" is not a file."
  KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
fi
# find-identity takes the keychain as a trailing argument; codesign takes --keychain.
IDENTITIES=$(security find-identity -v -p codesigning ${KEYCHAIN:+"$KEYCHAIN"} || true)
P12="${SKREENER_SIGN_P12:-}"
if [ "$SELF_SIGNED" = 1 ] && [ -n "$P12" ]; then
  [ -f "$P12" ] || die "SKREENER_SIGN_P12=\"$P12\" is not a file."
  [ -f "${SKREENER_SIGN_P12_PASSWORD_FILE:-}" ] || die "SKREENER_SIGN_P12_PASSWORD_FILE must name the file holding the .p12's password."
  command -v rcodesign >/dev/null || die "rcodesign not found (github.com/indygreg/apple-platform-rs); it signs from SKREENER_SIGN_P12."
  IDENTITY="$(basename "$P12") (rcodesign)"
elif [ "$SELF_SIGNED" = 1 ]; then
  # A self-signed certificate may not be trusted on this Mac, and then find-identity's code-signing policy leaves
  # it out: look among all identities and certificates (by name or SHA-1 hash) and let codesign be the judge.
  IDENTITY="${SKREENER_SIGN_IDENTITY:-Skreener Dev}"
  ALL_IDENTITIES=$( (security find-identity ${KEYCHAIN:+"$KEYCHAIN"}; security find-certificate -a -Z ${KEYCHAIN:+"$KEYCHAIN"}) 2>/dev/null || true)
  printf '%s\n' "$ALL_IDENTITIES" | grep -qF "$IDENTITY" \
    || die "signing identity \"$IDENTITY\" not found. Create it once with Scripts/make_dev_cert.sh, or name yours
       with SKREENER_SIGN_IDENTITY."
else
  IDENTITY="${SKREENER_DEVELOPER_ID:-}"
  if [ -z "$IDENTITY" ]; then
    DEV_IDS=$(printf '%s\n' "$IDENTITIES" | grep -o '"Developer ID Application: [^"]*"' | tr -d '"' | sort -u || true)
    COUNT=$(printf '%s' "$DEV_IDS" | grep -c . || true)
    if [ "$COUNT" -eq 0 ]; then
      die "no \"Developer ID Application\" certificate in the keychain.
       Create one at developer.apple.com -> Certificates (type: Developer ID Application) or in
       Xcode -> Settings -> Accounts -> Manage Certificates, then run this again.
       (\"Skreener Dev\" from make_dev_cert.sh is for local builds only; Apple won't notarise it.)"
    elif [ "$COUNT" -gt 1 ]; then
      die "several Developer ID Application identities found; pick one with SKREENER_DEVELOPER_ID:
$(printf '%s\n' "$DEV_IDS" | sed 's/^/         /')"
    fi
    IDENTITY="$DEV_IDS"
  elif ! printf '%s\n' "$IDENTITIES" | grep -qF "$IDENTITY"; then
    die "signing identity \"$IDENTITY\" (SKREENER_DEVELOPER_ID) is not a valid code-signing identity in the keychain.
       Valid identities:
$(printf '%s\n' "$IDENTITIES" | sed 's/^/         /')"
  fi
  if ! [[ "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] && [[ "$IDENTITY" != "Developer ID Application:"* ]]; then
    die "\"$IDENTITY\" is not a Developer ID Application identity; notarisation would reject it."
  fi
fi

NOTARY_ARGS=()
NOTARY_DESC=""
if [ "$NOTARIZE" = 1 ]; then
  xcrun --find notarytool >/dev/null 2>&1 || die "notarytool not found; install Xcode 13 or later and run xcode-select."
  xcrun --find stapler >/dev/null 2>&1 || die "stapler not found; install Xcode and run xcode-select."
  if [ -n "${SKREENER_NOTARY_PROFILE:-}" ]; then
    NOTARY_ARGS=(--keychain-profile "$SKREENER_NOTARY_PROFILE")
    [ -n "$KEYCHAIN" ] && NOTARY_ARGS+=(--keychain "$KEYCHAIN")
    NOTARY_DESC="keychain profile \"$SKREENER_NOTARY_PROFILE\""
  elif [ -n "${SKREENER_NOTARY_KEY:-}${SKREENER_NOTARY_KEY_ID:-}${SKREENER_NOTARY_ISSUER:-}" ]; then
    for v in SKREENER_NOTARY_KEY SKREENER_NOTARY_KEY_ID SKREENER_NOTARY_ISSUER; do
      [ -n "${!v:-}" ] || die "$v is not set; the API-key method needs SKREENER_NOTARY_KEY, _KEY_ID and _ISSUER."
    done
    [ -f "$SKREENER_NOTARY_KEY" ] || die "SKREENER_NOTARY_KEY=\"$SKREENER_NOTARY_KEY\" is not a file (expected the .p8 key)."
    NOTARY_ARGS=(--key "$SKREENER_NOTARY_KEY" --key-id "$SKREENER_NOTARY_KEY_ID" --issuer "$SKREENER_NOTARY_ISSUER")
    NOTARY_DESC="API key $SKREENER_NOTARY_KEY_ID"
  elif [ -n "${SKREENER_NOTARY_APPLE_ID:-}${SKREENER_NOTARY_TEAM_ID:-}${SKREENER_NOTARY_PASSWORD:-}" ]; then
    for v in SKREENER_NOTARY_APPLE_ID SKREENER_NOTARY_TEAM_ID SKREENER_NOTARY_PASSWORD; do
      [ -n "${!v:-}" ] || die "$v is not set; the Apple ID method needs SKREENER_NOTARY_APPLE_ID, _TEAM_ID and _PASSWORD."
    done
    NOTARY_ARGS=(--apple-id "$SKREENER_NOTARY_APPLE_ID" --team-id "$SKREENER_NOTARY_TEAM_ID" --password "$SKREENER_NOTARY_PASSWORD")
    NOTARY_DESC="Apple ID $SKREENER_NOTARY_APPLE_ID"
  else
    die "no notarisation credentials. Set SKREENER_NOTARY_PROFILE (recommended; see --help to create one),
       or the SKREENER_NOTARY_KEY/_KEY_ID/_ISSUER or SKREENER_NOTARY_APPLE_ID/_TEAM_ID/_PASSWORD variables.
       To sign and package without notarising, pass --skip-notarize."
  fi
fi

ENTITLEMENTS=Resources/Skreener.entitlements
[ -f "$ENTITLEMENTS" ] || die "$ENTITLEMENTS is missing."
plutil -lint -s "$ENTITLEMENTS" || die "$ENTITLEMENTS is not a valid plist."

APP=build/Skreener.app
OUT=build/release
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Submits a file, waits for Apple's verdict, and prints the log when it isn't accepted.
notarize() {
  local file="$1" result status id
  result="$WORK/notary-$(basename "$file").plist"
  echo "Submitting $(basename "$file") with $NOTARY_DESC (usually a few minutes)..."
  if ! xcrun notarytool submit "$file" "${NOTARY_ARGS[@]}" --wait --output-format plist > "$result"; then
    cat "$result" >&2 || true
    die "notarytool submit failed (check the credentials above and your network)."
  fi
  status=$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)
  id=$(plutil -extract id raw -o - "$result" 2>/dev/null || echo "")
  echo "Notarisation status: $status${id:+ (submission $id)}"
  if [ "$status" != "Accepted" ]; then
    if [ -n "$id" ]; then
      echo "Apple's log for this submission:" >&2
      xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" >&2 || true
    fi
    die "notarisation of $(basename "$file") was not accepted (status: $status)."
  fi
}

# ---- Build ----
step "Building"
# Ad-hoc here (no keychain prompt for the dev cert); the Developer ID signature below replaces it.
SKREENER_SIGN_IDENTITY="-" SKREENER_VERSION="$VERSION" Scripts/build_app.sh
[ -d "$APP" ] || die "build_app.sh did not produce $APP."
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")
if [ "$NOTARIZE" = 1 ] || [ "$SELF_SIGNED" = 1 ]; then NAME="Skreener-$VERSION"; else NAME="Skreener-$VERSION-unnotarized"; fi
# A self-signed build isn't notarised, which is the only reason for the hardened runtime and Apple's timestamp (whose
# service only signs for Apple-issued certificates anyway), so it gets neither.
if [ "$SELF_SIGNED" = 1 ]; then
  SIGN_ARGS=(--timestamp=none); RUNTIME_NOTE=""
else
  SIGN_ARGS=(--timestamp --options runtime); RUNTIME_NOTE=" (hardened runtime)"
fi

# ---- Sign ----
step "Signing with \"$IDENTITY\"$RUNTIME_NOTE"
# Nested code is signed inside-out; today the bundle has only the main executable.
# rcodesign signs straight from the .p12, without the keychain or trust (CI); otherwise codesign.
rsign() { rcodesign sign --p12-file "$P12" --p12-password-file "$SKREENER_SIGN_P12_PASSWORD_FILE" "$@"; }
if [ -n "$P12" ]; then
  # The entitlements option has been renamed between rcodesign versions; use whichever this one has.
  ENT_FLAG=$(rcodesign sign --help 2>&1 | grep -o -- '--entitlements-xml-[a-z]*' | head -1 || true)
  rsign ${ENT_FLAG:+"$ENT_FLAG" "$ENTITLEMENTS"} "$APP"
else
  codesign --force "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
fi
if [ -n "$P12" ]; then
  # codesign --verify also checks the certificate against macOS's code-signing policy, which a self-signed
  # certificate only passes where it's trusted (your Mac), not here ("Invalid Extended Key Usage for policy").
  # Check the signature itself instead.
  rcodesign verify "$APP/Contents/MacOS/Skreener"
else
  codesign --verify --deep --strict --verbose=2 "$APP"
fi
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Authority|TeamIdentifier|Timestamp|flags|Identifier)=' || true
# What macOS keys the Screen Recording permission to: the same certificate in every release keeps it.
codesign --display --requirements - "$APP" 2>&1 | grep designated || true
if [ "$SELF_SIGNED" = 0 ]; then
  codesign --display --verbose=2 "$APP" 2>&1 | grep -q 'flags=.*runtime' || die "hardened runtime flag missing from the signature."
fi

# ---- Notarise the app, staple it ----
if [ "$NOTARIZE" = 1 ]; then
  step "Notarising the app"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/Skreener-notarize.zip"
  notarize "$WORK/Skreener-notarize.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

# ---- Package ----
rm -rf "$OUT"; mkdir -p "$OUT"
ARTIFACTS=()
if [ "$FORMAT" != dmg ]; then
  step "Packaging $NAME.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"
  ARTIFACTS+=("$NAME.zip")
fi
if [ "$FORMAT" != zip ]; then
  step "Packaging $NAME.dmg"
  STAGE="$WORK/dmg"; mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Skreener.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Skreener $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/$NAME.dmg" >/dev/null
  # Gatekeeper checks a signed disk image when it is opened, and rejects one signed with a certificate Apple didn't
  # issue ("Move to Trash", with no Open Anyway) (#151). Left unsigned it just mounts, and the app inside gets the usual
  # Open Anyway prompt.
  if [ "$SELF_SIGNED" = 1 ]; then
    echo "Leaving the DMG unsigned (self-signed release)."
  else
    codesign --force "${SIGN_ARGS[0]}" --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$OUT/$NAME.dmg"
  fi
  if [ "$NOTARIZE" = 1 ]; then
    step "Notarising the DMG"
    notarize "$OUT/$NAME.dmg"
    xcrun stapler staple "$OUT/$NAME.dmg"
    xcrun stapler validate "$OUT/$NAME.dmg"
  fi
  ARTIFACTS+=("$NAME.dmg")
fi
(cd "$OUT" && shasum -a 256 "${ARTIFACTS[@]}" > SHA256SUMS)

# ---- Gatekeeper check (what a downloaded copy will go through) ----
if [ "$NOTARIZE" = 1 ]; then
  step "Gatekeeper assessment"
  spctl --assess --type execute --verbose=2 "$APP"
  if [ "$FORMAT" != zip ]; then
    spctl --assess --type open --context context:primary-signature --verbose=2 "$OUT/$NAME.dmg"
  fi
fi

echo
echo "Release $VERSION (build $BUILD) in $OUT/:"
for a in "${ARTIFACTS[@]}"; do echo "  $a"; done
echo "  SHA256SUMS"
if [ "$SELF_SIGNED" = 1 ]; then
  echo "note: self-signed, not notarised: install with Scripts/install.sh; a browser download needs xattr -dr com.apple.quarantine." >&2
elif [ "$NOTARIZE" = 0 ]; then
  echo "note: not notarised (--skip-notarize); other Macs will refuse to open these." >&2
fi
