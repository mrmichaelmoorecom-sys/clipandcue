#!/usr/bin/env bash
# Build, Developer ID-sign, notarize, and staple clipandcue.dmg.
#
# Prereqs (one-time, once your paid membership is active):
#   1. A "Developer ID Application" cert in your login keychain (Xcode →
#      Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. A notarytool keychain profile, e.g.:
#        xcrun notarytool store-credentials "clipandcue-notary" \
#          --apple-id "you@email.com" --team-id "5Q26YV5NG4" --password "<app-specific-pw>"
#
# Usage:
#   CODESIGN_IDENTITY="Developer ID Application: Michael Moore (5Q26YV5NG4)" \
#   NOTARY_PROFILE="clipandcue-notary" ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your 'Developer ID Application: …' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-clipandcue-notary}"
APP="clipandcue.app"
DMG="clipandcue.dmg"

echo "==> build + Developer ID sign the app"
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" ./scripts/build_app.sh release
codesign --verify --strict --verbose=2 "$APP"

echo "==> notarize the app (zip → submit → staple)"
ZIP="$(mktemp -d)/clipandcue.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "==> build dmg (now contains the stapled app)"
./scripts/make_dmg.sh

echo "==> sign + notarize + staple the dmg"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> verify"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true
echo "==> done: notarized $DMG"
