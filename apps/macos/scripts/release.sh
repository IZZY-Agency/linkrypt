#!/bin/bash
# Build a Developer ID-signed, notarized, stapled Linkrypt DMG for direct
# distribution (outside the Mac App Store).
#
# Usage (from anywhere):
#   apps/macos/scripts/release.sh                  # full release
#   apps/macos/scripts/release.sh --skip-notarize  # signed only, for a local smoke test
#   apps/macos/scripts/release.sh --allow-dirty    # build from an uncommitted tree
#
# Notarization needs a notarytool keychain profile for team VHZR49D9QB. Any
# profile name works: pass it via NOTARY_PROFILE (default linkrypt-notary).
# One-time setup, stores the notary credentials in the login Keychain:
#   xcrun notarytool store-credentials linkrypt-notary \
#     --apple-id <apple-id> --team-id VHZR49D9QB
# It prompts for an app-specific password (account.apple.com > Sign-In and
# Security > App-Specific Passwords). An App Store Connect API key works too:
#   xcrun notarytool store-credentials linkrypt-notary \
#     --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
# Env overrides: DEVELOPER_DIR (default /Applications/Xcode.app/...),
#                NOTARY_PROFILE (default linkrypt-notary; any notarytool
#                keychain profile for team VHZR49D9QB).
# Output: one new directory per run, never overwritten or deleted:
#   apps/macos/Linkrypt/build/release/<version>-b<build>-<commit>[-dirty][-unnotarized]-<UTC time>/
#   with Linkrypt-<version>.dmg + .sha256 and Linkrypt.xcarchive (keep it: dSYMs).
# After a successful run the final DMG and its .sha256 are also copied to a
# stable path (overwritten on each run; the per-run directory is untouched):
#   apps/macos/Linkrypt/build/Linkrypt-<version>.dmg(.sha256)
#   (Linkrypt-<version>-unnotarized.dmg with --skip-notarize).
#   build/ is gitignored; prune old runs by hand.
#
# Bash 3.2-compatible (macOS /bin/bash).
set -euo pipefail

TEAM_ID="VHZR49D9QB"
SIGN_IDENTITY="Developer ID Application: IZZY Agency (${TEAM_ID})"
BUNDLE_ID="sh.linkrypt.mac"
NOTARY_PROFILE="${NOTARY_PROFILE:-linkrypt-notary}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

NOTARIZE=1
ALLOW_DIRTY=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) NOTARIZE=0 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h|--help) sed -n '2,/^# Bash 3.2/p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg (see --help)" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJ_DIR="$MAC_DIR/Linkrypt"
RELEASES="$PROJ_DIR/build/release"

step() { printf '\n==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Captured into variables before grepping: `cmd | grep -q` under pipefail can
# report a false "no match" when grep exits early and cmd gets SIGPIPE.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# $1 = build setting key in project.yml (quoted or bare scalar value).
yml_value() {
  sed -n "s/^[[:space:]]*$1:[[:space:]]*\"\{0,1\}\([^\"[:space:]#]*\).*/\1/p" "$PROJ_DIR/project.yml"
}

# $1 = signed path. Fails unless it carries our Developer ID signature with a
# secure timestamp (a notarization requirement).
verify_signature() {
  local target="$1" info
  if [ -d "$target" ]; then
    codesign --verify --deep --strict --verbose=2 "$target"
  else
    codesign --verify --strict --verbose=2 "$target"
  fi
  info="$(codesign -dvv "$target" 2>&1)"
  contains "$info" "Authority=$SIGN_IDENTITY" || die "$target is not signed by $SIGN_IDENTITY"
  contains "$info" "TeamIdentifier=$TEAM_ID"  || die "$target has the wrong team identifier"
  contains "$info" $'\nTimestamp='           || die "$target has no secure timestamp"
}

# $1 = file to submit (zip or dmg). Waits for the verdict; prints the notary
# log and fails on anything but Accepted.
notarize() {
  local file="$1" name json id status
  name="$(basename "$file")"
  json="$OUT/notary-$name.json"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" \
    --wait --timeout 30m --output-format json > "$json" || true
  id="$(plutil -extract id raw -o - "$json" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$json" 2>/dev/null || true)"
  if [ "$status" != "Accepted" ]; then
    cat "$json" >&2 || true
    if [ -n "$id" ]; then
      xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    die "notarization of $name failed (status: ${status:-unknown})"
  fi
  echo "notarized $name (submission $id)"
}

# $1 = path, $2 = spctl --type. Prints the verdict; fails unless it is
# "accepted" with source=Notarized Developer ID.
assess_notarized() {
  local verdict
  if [ "$2" = "open" ]; then
    verdict="$(spctl --assess --type open --context context:primary-signature -vv "$1" 2>&1 || true)"
  else
    verdict="$(spctl --assess --type "$2" -vv "$1" 2>&1 || true)"
  fi
  echo "$verdict"
  contains "$verdict" ": accepted" && contains "$verdict" "source=Notarized Developer ID" \
    || die "Gatekeeper does not accept $1 as notarized"
}

# ---------------------------------------------------------------------------
step "Preflight"
[ -d "$DEVELOPER_DIR" ] || die "Xcode not found at $DEVELOPER_DIR (set DEVELOPER_DIR)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"

identities="$(security find-identity -v -p codesigning)"
contains "$identities" "\"$SIGN_IDENTITY\"" \
  || die "signing identity not found in the Keychain: $SIGN_IDENTITY"
echo "identity: $SIGN_IDENTITY"

dirty="$(git -C "$MAC_DIR" status --porcelain -- .)"
if [ -n "$dirty" ] && [ "$ALLOW_DIRTY" -eq 0 ]; then
  die "apps/macos has uncommitted changes (commit them, or pass --allow-dirty)"
fi
COMMIT="$(git -C "$MAC_DIR" rev-parse --short HEAD)"

YML_VERSION="$(yml_value MARKETING_VERSION)"
YML_BUILD="$(yml_value CURRENT_PROJECT_VERSION)"
[ -n "$YML_VERSION" ] && [ -n "$YML_BUILD" ] \
  || die "cannot read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml"

if [ "$NOTARIZE" -eq 1 ]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notary profile '$NOTARY_PROFILE' is missing or invalid (setup: $0 --help)"
  echo "notary profile: $NOTARY_PROFILE"
else
  echo "notarization: SKIPPED (--skip-notarize), the DMG will not open on other Macs"
fi

# A fresh directory per run: a smoke test or a failed run never destroys an
# earlier release's archive (its dSYMs symbolicate that release's crashes).
run_name="$YML_VERSION-b$YML_BUILD-$COMMIT"
[ -z "$dirty" ] || run_name="$run_name-dirty"
[ "$NOTARIZE" -eq 1 ] || run_name="$run_name-unnotarized"
run_name="$run_name-$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$RELEASES/$run_name"
ARCHIVE="$OUT/Linkrypt.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/Linkrypt.app"
mkdir -p "$RELEASES"
mkdir "$OUT"   # fails if it already exists; nothing is ever overwritten
echo "output: $OUT"

# ---------------------------------------------------------------------------
step "Archive (Release)"
xcodebuild -project "$PROJ_DIR/Linkrypt.xcodeproj" -scheme Linkrypt \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -quiet archive

step "Export (Developer ID)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$PROJ_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" -quiet
[ -d "$APP" ] || die "export produced no Linkrypt.app in $EXPORT_DIR"

plist="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
[ "$APP_BUNDLE_ID" = "$BUNDLE_ID" ] || die "unexpected bundle id $APP_BUNDLE_ID"
[ "$VERSION" = "$YML_VERSION" ] && [ "$BUILD" = "$YML_BUILD" ] \
  || die "app $VERSION ($BUILD) != project.yml $YML_VERSION ($YML_BUILD); run xcodegen generate in apps/macos/Linkrypt"
echo "Linkrypt $VERSION (build $BUILD), commit $COMMIT, archs: $(lipo -archs "$APP/Contents/MacOS/Linkrypt")"

step "Verify app signature"
verify_signature "$APP"
cd_info="$(codesign -dvv "$APP" 2>&1)"
contains "$cd_info" "(runtime)" || die "hardened runtime is not enabled on the app"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if contains "$entitlements" "get-task-allow"; then
  die "app carries com.apple.security.get-task-allow (debug entitlement); notarization would reject it"
fi
echo "signature OK: Developer ID, team $TEAM_ID, hardened runtime, secure timestamp"

# ---------------------------------------------------------------------------
if [ "$NOTARIZE" -eq 1 ]; then
  step "Notarize app"
  zip="$OUT/Linkrypt-notarize.zip"
  ditto -c -k --keepParent "$APP" "$zip"
  notarize "$zip"
  rm -f "$zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

step "Build DMG"
if [ "$NOTARIZE" -eq 1 ]; then
  DMG="$OUT/Linkrypt-$VERSION.dmg"
else
  DMG="$OUT/Linkrypt-$VERSION-unnotarized.dmg"
fi
stage="$OUT/dmg-root"
mkdir -p "$stage"
ditto "$APP" "$stage/Linkrypt.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Linkrypt $VERSION" -srcfolder "$stage" \
  -format UDZO -ov -quiet "$DMG"
rm -rf "$stage"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
verify_signature "$DMG"

if [ "$NOTARIZE" -eq 1 ]; then
  step "Notarize DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  step "Gatekeeper assessment"
  assess_notarized "$APP" execute
  assess_notarized "$DMG" open
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

# Stable copy for tooling that wants a fixed path (e.g. a release upload). The
# .sha256 names the DMG by basename, so it verifies in either directory.
STABLE_DIR="$PROJ_DIR/build"
STABLE_DMG="$STABLE_DIR/$(basename "$DMG")"
cp -f "$DMG" "$STABLE_DMG"
cp -f "$DMG.sha256" "$STABLE_DMG.sha256"
(cd "$STABLE_DIR" && shasum -a 256 -c "$(basename "$STABLE_DMG").sha256" >/dev/null) \
  || die "stable copy $STABLE_DMG does not match its checksum"

step "Done"
echo "version:   $VERSION (build $BUILD), commit $COMMIT"
echo "dmg:       $DMG"
echo "sha256:    $(cut -d' ' -f1 < "$DMG.sha256")"
echo "stable:    $STABLE_DMG (+ .sha256)"
echo "archive:   $ARCHIVE (keep it: dSYMs for crash symbolication)"
if [ "$NOTARIZE" -eq 1 ]; then
  echo "notarized: yes, ticket stapled to the app and the DMG"
else
  echo "notarized: NO (--skip-notarize); Gatekeeper will block this DMG on other Macs"
fi
