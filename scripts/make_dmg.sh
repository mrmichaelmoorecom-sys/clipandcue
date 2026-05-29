#!/usr/bin/env bash
# Build a drag-to-Applications .dmg for clipandcue using only native tools
# (hdiutil + AppleScript/Finder). Run scripts/build_app.sh first.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="clipandcue"
APP="$ROOT/$APP_NAME.app"
VOL="clipandcue"
DMG_FINAL="$ROOT/$APP_NAME.dmg"
BG_SRC="$ROOT/Resources/dmg-background.tiff"

[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/build_app.sh first" >&2; exit 1; }
[[ -f "$BG_SRC" ]] || { echo "error: $BG_SRC not found" >&2; exit 1; }

# Detach any stale mount of the same volume.
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true

WORK="$(mktemp -d)"
STAGING="$WORK/stage"
TMP_DMG="$WORK/rw.dmg"
mkdir -p "$STAGING"

echo "==> staging contents"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp "$BG_SRC" "$STAGING/.background/background.tiff"
[[ -f "$ROOT/dmg/Read Me.txt" ]] && cp "$ROOT/dmg/Read Me.txt" "$STAGING/Read Me.txt"

SIZE_MB=$(( $(du -sk "$STAGING" | cut -f1) / 1024 + 20 ))

echo "==> creating writable image (${SIZE_MB}m)"
hdiutil create -srcfolder "$STAGING" -volname "$VOL" -fs HFS+ \
    -format UDRW -size "${SIZE_MB}m" -ov "$TMP_DMG" >/dev/null

echo "==> mounting"
hdiutil attach "$TMP_DMG" -noautoopen -mountpoint "/Volumes/$VOL" >/dev/null
sleep 1

echo "==> arranging window (Finder)"
osascript <<APPLESCRIPT || echo "WARN: Finder layout step returned an error (above). Grant Automation→Finder if prompted, then re-run."
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 180, 960, 608}
    set theOptions to the icon view options of container window
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 128
    set text size of theOptions to 13
    set background picture of theOptions to file ".background:background.tiff"
    -- Position by name match: the .app extension is hidden, so exact-name lookups miss.
    repeat with anItem in (get items of container window)
      set nm to name of anItem
      if nm contains "clipandcue" then
        set position of anItem to {165, 200}
      else if nm is "Applications" then
        set position of anItem to {495, 200}
      else if nm contains "Read" then
        set position of anItem to {330, 560}
      else
        set position of anItem to {1600, 1600}
      end if
    end repeat
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
echo "==> detaching"
hdiutil detach "/Volumes/$VOL" >/dev/null || hdiutil detach "/Volumes/$VOL" -force >/dev/null

echo "==> compressing to read-only $DMG_FINAL"
rm -f "$DMG_FINAL"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null

rm -rf "$WORK"
echo "==> done: $DMG_FINAL ($(du -h "$DMG_FINAL" | cut -f1))"
