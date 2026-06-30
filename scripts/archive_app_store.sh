#!/usr/bin/env bash
# Build clipandcue.pkg for Mac App Store submission.
#
# Produces a signed installer package ready to upload to App Store Connect
# via Transporter. Mirrors scripts/build_app.sh but with:
#   - the App Store provisioning profile (vs. the Developer ID one)
#   - the "3rd Party Mac Developer Application" codesigning identity
#   - a productbuild step that wraps the .app in a .pkg signed by
#     "3rd Party Mac Developer Installer"
#
# Prereqs (one-time):
#   - Both 3rd Party Mac Developer certs imported into Keychain
#   - clipandcue_Mac_App_Store.provisionprofile in the project root
#
# Usage:
#   ./scripts/archive_app_store.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG="${1:-release}"
APP_NAME="clipandcue"
APP="$ROOT/$APP_NAME.app"
PKG="$ROOT/$APP_NAME.pkg"

APP_IDENTITY="${APP_STORE_APP_IDENTITY:-3rd Party Mac Developer Application: Michael Moore (HA5AB7JS87)}"
INSTALLER_IDENTITY="${APP_STORE_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: Michael Moore (HA5AB7JS87)}"
PROFILE="$ROOT/clipandcue_Mac_App_Store.provisionprofile"

if [[ ! -f "$PROFILE" ]]; then
    echo "error: $PROFILE not found — generate one at developer.apple.com → Profiles → Mac App Store Connect" >&2
    exit 1
fi

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
[[ -f "$BIN" ]] || { echo "error: built binary not found at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

if [[ -d "$ROOT/Resources" ]]; then
    cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
fi

if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> embedding App Store provisioning profile"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Strip com.apple.quarantine xattr from every file in the bundle. App
# Store ingestion rejects packages that contain quarantined files
# (error 91109) — and provisioning profiles downloaded from
# developer.apple.com via Safari carry the attr by default. The
# bounce is silent: Transporter accepts the upload, then the backend
# fails processing with no email.
xattr -cr "$APP"

# Make every file in the bundle world-readable (dirs +rx, files +r).
# Transporter rejects packages that contain root-only-readable files
# because Gatekeeper on the user's machine couldn't verify the signature
# under their non-root account.
chmod -R a+rX "$APP"

echo "==> codesign (Apple Distribution, hardened runtime)"
codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/entitlements.plist" \
    --sign "$APP_IDENTITY" "$APP"

echo "==> productbuild → $PKG"
rm -f "$PKG"
productbuild --component "$APP" /Applications \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG"

echo "==> verify"
codesign --verify --strict --verbose=2 "$APP"
pkgutil --check-signature "$PKG" | head -10

echo "==> done: $PKG"
echo "    Upload to App Store Connect with Transporter (Mac App Store →"
echo "    Apps → clipandcue → + Add Build → drag the .pkg)."
