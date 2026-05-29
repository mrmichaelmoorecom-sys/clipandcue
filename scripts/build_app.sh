#!/usr/bin/env bash
# Build clipandcue and assemble a runnable, ad-hoc-signed .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG="${1:-release}"
APP_NAME="clipandcue"
APP="$ROOT/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Bundle every resource (icons, menu bar template image, etc.).
if [[ -d "$ROOT/Resources" ]]; then
    cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
fi

# Register the app icon if present.
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "==> codesign (Developer ID, hardened runtime)"
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ROOT/entitlements.plist" \
        --sign "$CODESIGN_IDENTITY" "$APP"
else
    echo "==> ad-hoc codesign"
    codesign --force --deep --sign - "$APP"
fi

echo "==> done: $APP"
echo "    Move it to /Applications and launch, or run: open \"$APP\""
