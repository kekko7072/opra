#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, and publish a new Opra release with a
# Sparkle-signed appcast for the in-app auto-updater.
#
# Usage:
#   ./release.sh <version> [build-number]
#   e.g. ./release.sh 1.2.0
#
# Prerequisites (one-time):
#   1. Developer ID Application certificate in your keychain (team P8WULW25UZ).
#   2. Sparkle EdDSA private key in your keychain (created via Sparkle's generate_keys;
#      the matching public key is already in Info.plist as SUPublicEDKey).
#   3. A notarytool keychain profile for notarization:
#        xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#          --apple-id "you@example.com" --team-id P8WULW25UZ --password "app-specific-pw"
#
# Env overrides:
#   NOTARY_PROFILE       notarytool keychain profile name        (default: OpraNotary)
#   DEVELOPER_ID         signing identity                        (default: Developer ID Application: Francesco Vezzani (P8WULW25UZ))
#   SPARKLE_BIN          dir containing generate_appcast          (default: auto-located in DerivedData)
#   DOWNLOAD_URL_PREFIX  base URL where the .zip will be hosted   (default: GitHub release assets for the tag)
#   SKIP_NOTARIZE=1      skip notarization (for local test builds)
#
set -euo pipefail

VERSION="${1:-}"
BUILD_NUMBER="${2:-$VERSION}"
if [[ -z "$VERSION" ]]; then
  echo "error: version required.  usage: ./release.sh <version> [build-number]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/Opra.xcodeproj"
SCHEME="Opra"
INFO_PLIST="$ROOT/Opra/Info.plist"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Opra.xcarchive"
EXPORT_DIR="$OUT/export"
UPDATES_DIR="$ROOT/updates"
APP_NAME="Opra.app"
ZIP_NAME="Opra-$VERSION.zip"

NOTARY_PROFILE="${NOTARY_PROFILE:-OpraNotary}"
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Francesco Vezzani (P8WULW25UZ)}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/kekko7072/Opra/releases/download/v$VERSION/}"

PB=/usr/libexec/PlistBuddy

echo "==> Releasing Opra $VERSION (build $BUILD_NUMBER)"

# --- Locate Sparkle's generate_appcast ---------------------------------------
if [[ -z "${SPARKLE_BIN:-}" ]]; then
  SPARKLE_BIN="$(dirname "$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)" 2>/dev/null || true)"
fi
if [[ -z "$SPARKLE_BIN" || ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "error: could not locate Sparkle's generate_appcast. Build the app once, or set SPARKLE_BIN." >&2
  exit 1
fi
echo "==> Sparkle tools: $SPARKLE_BIN"

# --- Bump version in Info.plist ----------------------------------------------
echo "==> Setting version $VERSION / build $BUILD_NUMBER in Info.plist"
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
"$PB" -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

# --- Archive -----------------------------------------------------------------
echo "==> Archiving (Release, Developer ID)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
  DEVELOPMENT_TEAM=P8WULW25UZ \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

# --- Export ------------------------------------------------------------------
echo "==> Exporting signed .app"
EXPORT_OPTIONS="$OUT/ExportOptions-developerid.plist"
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>P8WULW25UZ</string>
  <key>signingStyle</key><string>manual</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/$APP_NAME"
[[ -d "$APP_PATH" ]] || { echo "error: exported app not found at $APP_PATH" >&2; exit 1; }

# --- Notarize + staple -------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "==> Notarizing (this can take a few minutes)"
  NOTARIZE_ZIP="$OUT/notarize.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket"
  xcrun stapler staple "$APP_PATH"
  rm -f "$NOTARIZE_ZIP"
else
  echo "==> SKIP_NOTARIZE=1 — skipping notarization (not for public releases)"
fi

# --- Package for Sparkle -----------------------------------------------------
echo "==> Packaging $ZIP_NAME"
mkdir -p "$UPDATES_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$UPDATES_DIR/$ZIP_NAME"

# --- Generate / update the appcast (signs with EdDSA key from keychain) ------
echo "==> Generating appcast (EdDSA-signed)"
"$SPARKLE_BIN/generate_appcast" "$UPDATES_DIR" --download-url-prefix "$DOWNLOAD_URL_PREFIX"
cp -f "$UPDATES_DIR/appcast.xml" "$ROOT/appcast.xml"

echo ""
echo "✅ Done."
echo "   App:     $APP_PATH"
echo "   Archive: $UPDATES_DIR/$ZIP_NAME"
echo "   Appcast: $ROOT/appcast.xml (also in $UPDATES_DIR/)"
echo ""
echo "Next steps:"
echo "  1. Create GitHub release tag v$VERSION and upload $UPDATES_DIR/$ZIP_NAME as an asset"
echo "     (must match DOWNLOAD_URL_PREFIX=$DOWNLOAD_URL_PREFIX)."
echo "  2. Commit & push appcast.xml so it is served at the SUFeedURL in Info.plist:"
echo "     https://raw.githubusercontent.com/kekko7072/Opra/main/appcast.xml"
echo "  3. Existing users will be offered the update automatically."
