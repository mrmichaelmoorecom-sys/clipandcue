#!/usr/bin/env bash
# Prepend a new <item> entry to appcast.xml for the just-notarized DMG.
#
# Usage:
#   ./scripts/update_appcast.sh <version> "<release-notes>"
#
# Reads the Sparkle signature line written by notarize.sh from
# .build/last-sparkle-signature.txt (format:
# `sparkle:edSignature="..." length="..."`).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: update_appcast.sh <version> '<release notes>'}"
NOTES="${2:-Auto-update through Sparkle.}"
DMG="clipandcue.dmg"
APPCAST="appcast.xml"
SIG_FILE=".build/last-sparkle-signature.txt"

if [[ ! -f "$SIG_FILE" ]]; then
    echo "error: $SIG_FILE missing — run scripts/notarize.sh first" >&2
    exit 1
fi
SPARKLE_LINE="$(cat "$SIG_FILE")"

PUBDATE="$(LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S +0000')"
URL="https://github.com/mrmichaelmoorecom-sys/clipandcue/releases/download/v${VERSION}/clipandcue.dmg"

NEW_ITEM=$(cat <<EOF
        <item>
            <title>v${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description><![CDATA[${NOTES}]]></description>
            <enclosure
                url="${URL}"
                type="application/octet-stream"
                ${SPARKLE_LINE} />
        </item>
EOF
)

if [[ -f "$APPCAST" ]]; then
    # Prepend new item right after the <language>en</language> line.
    python3 - "$APPCAST" <<PY
import sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
marker = "<language>en</language>"
new_item = """$NEW_ITEM"""
if marker not in text:
    raise SystemExit("appcast.xml missing <language>en</language> marker")
text = text.replace(marker, marker + "\n" + new_item, 1)
path.write_text(text)
PY
else
    cat > "$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>clipandcue</title>
        <link>https://clipandcue.com/appcast.xml</link>
        <description>Auto-update feed for clipandcue.</description>
        <language>en</language>
${NEW_ITEM}
    </channel>
</rss>
EOF
fi

echo "==> updated $APPCAST with v${VERSION}"
