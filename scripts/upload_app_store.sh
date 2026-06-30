#!/usr/bin/env bash
# Upload clipandcue.pkg to App Store Connect via iTMSTransporter (Apple's
# command-line tool — same backend as the Transporter.app GUI, but gives
# us real error output if processing fails). Use this when the GUI's
# upload sits stuck for hours with no email, or for CI.
#
# Auth — supply ONE of the two paths via env vars:
#
# A) App Store Connect API key (recommended):
#      ASC_API_KEY_ID="ABC123XYZ"
#      ASC_API_KEY_ISSUER="69a6de7f-..." (your issuer ID)
#    Plus the .p8 file at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
# B) Apple ID + app-specific password:
#      ASC_APPLE_ID="mike@mrmichaelmoore.com"
#      ASC_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#    Generate the ASP at appleid.apple.com → Sign-In and Security →
#    App-Specific Passwords.
#
# Usage: ./scripts/upload_app_store.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PKG="$(pwd)/clipandcue.pkg"
[[ -f "$PKG" ]] || { echo "error: $PKG not found — run scripts/archive_app_store.sh first" >&2; exit 1; }

ITMS="/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter"
[[ -x "$ITMS" ]] || ITMS="/Applications/Transporter.app/Contents/Resources/itms/bin/iTMSTransporter"
[[ -x "$ITMS" ]] || { echo "error: iTMSTransporter not found — install Transporter from the Mac App Store" >&2; exit 1; }

if [[ -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_KEY_ISSUER:-}" ]]; then
    echo "==> upload via App Store Connect API key ($ASC_API_KEY_ID)"
    "$ITMS" -m upload -assetFile "$PKG" \
        -apiKey "$ASC_API_KEY_ID" \
        -apiIssuer "$ASC_API_KEY_ISSUER" \
        -v eXtreme
elif [[ -n "${ASC_APPLE_ID:-}" && -n "${ASC_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "==> upload via Apple ID + app-specific password ($ASC_APPLE_ID)"
    "$ITMS" -m upload -assetFile "$PKG" \
        -u "$ASC_APPLE_ID" \
        -p "$ASC_APP_SPECIFIC_PASSWORD" \
        -v eXtreme
else
    cat >&2 <<EOF
error: no credentials supplied. Set one of:
  A) ASC_API_KEY_ID + ASC_API_KEY_ISSUER (+ .p8 file in ~/.appstoreconnect/private_keys/)
  B) ASC_APPLE_ID + ASC_APP_SPECIFIC_PASSWORD
See script header for details.
EOF
    exit 1
fi
