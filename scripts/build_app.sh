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
mkdir -p "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Bundle every resource (icons, menu bar template image, etc.).
if [[ -d "$ROOT/Resources" ]]; then
    cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
fi

# Embed Sparkle.framework from the SPM artifact so the auto-updater
# (Autoupdate helper + Installer XPCs) ships inside the bundle. Without
# this the app would crash on launch with "Library not loaded: Sparkle".
SPARKLE_FW="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    echo "==> embedding Sparkle.framework"
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
    # Add the conventional @executable_path/../Frameworks rpath so the
    # dyld loader actually finds the embedded framework at runtime.
    # SPM doesn't set this for us when shipping a CLI-style executable.
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

# Register the app icon if present.
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Embed the Developer ID provisioning profile if present — required so the
# Developer-ID-signed app is authorized to use the iCloud/CloudKit container.
PROFILE="$ROOT/clipandcue.provisionprofile"
if [[ -f "$PROFILE" ]]; then
    echo "==> embedding provisioning profile"
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "==> codesign (Developer ID, hardened runtime)"
    # Sparkle's nested helpers (Updater.app, Downloader.xpc, Installer.xpc)
    # each need their own Developer ID signature from the inside out. We
    # re-sign them WITHOUT the app's entitlements file — they ship their
    # own entitlements baked in via their Info.plist.
    SPARKLE_BASE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    if [[ -d "$SPARKLE_BASE" ]]; then
        # Standalone Mach-O helper — must be Developer-ID signed with a
        # secure timestamp on its own. Notarization rejects the bundle
        # otherwise (Autoupdate is treated as a separately validatable
        # binary, not part of the parent framework's signature).
        if [[ -f "$SPARKLE_BASE/Autoupdate" ]]; then
            codesign --force --options runtime --timestamp \
                --sign "$CODESIGN_IDENTITY" "$SPARKLE_BASE/Autoupdate"
        fi
        for helper in \
            "$SPARKLE_BASE/XPCServices/Downloader.xpc" \
            "$SPARKLE_BASE/XPCServices/Installer.xpc" \
            "$SPARKLE_BASE/Updater.app"; do
            if [[ -d "$helper" ]]; then
                codesign --force --options runtime --timestamp \
                    --sign "$CODESIGN_IDENTITY" "$helper"
            fi
        done
        codesign --force --options runtime --timestamp \
            --sign "$CODESIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    fi
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT/entitlements.plist" \
        --sign "$CODESIGN_IDENTITY" "$APP"
else
    echo "==> ad-hoc codesign"
    codesign --force --deep --sign - "$APP"
fi

echo "==> done: $APP"
echo "    Move it to /Applications and launch, or run: open \"$APP\""
