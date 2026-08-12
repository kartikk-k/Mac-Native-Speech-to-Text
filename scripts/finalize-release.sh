#!/bin/bash
set -euo pipefail

# Finalize a release AFTER the DMG has been notarized + stapled.
#
# Steps performed:
#   1. Sparkle-sign the (stapled) DMG with the EdDSA key from the Keychain.
#   2. Create the GitHub release and upload the DMG.
#   3. Write appcast.xml with the real URL, length, and edSignature.
#   4. Commit the appcast + version bump.
#
# Prereqs (do these first — they need your secrets):
#   xcrun notarytool submit "build/Echotype Mac.dmg" --apple-id YOU --team-id HXV2NNGP22 --password APP_PW --wait
#   xcrun stapler staple    "build/Echotype Mac.dmg"

VERSION="1.2"
TAG="v${VERSION}"
REPO="kartikk-k/Echotype-Mac"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$PROJECT_DIR/build/Echotype Mac.dmg"
APPCAST="$PROJECT_DIR/appcast.xml"
NOTES="$PROJECT_DIR/scripts/release-notes-${VERSION}.md"
SIGN_UPDATE="$HOME/Library/Developer/Xcode/DerivedData/_Echotype_Mac-fsahskvqitevgeemsbgtqbuwxfmp/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

[ -f "$DMG" ] || { echo "Error: DMG not found at $DMG"; exit 1; }

# Sanity: confirm the DMG has been stapled (notarization ticket present).
if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
  echo "WARNING: $DMG does not appear to be stapled/notarized."
  echo "Run notarytool + stapler first (see header of this script). Continue anyway? [y/N]"
  read -r ans; [ "$ans" = "y" ] || exit 1
fi

# ─── 1. Sparkle-sign the stapled DMG ────────────────────────────
echo "Signing DMG with Sparkle EdDSA key..."
SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG")"
echo "  $SIGN_OUTPUT"
ED_SIG="$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIG" ] && [ -n "$LENGTH" ] || { echo "Error: could not parse signature/length"; exit 1; }

# ─── 2. Create GitHub release + upload DMG ──────────────────────
echo "Creating GitHub release $TAG..."
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "  Release $TAG already exists — uploading DMG (clobber)."
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$DMG" --repo "$REPO" \
    --title "Echotype Mac $TAG" \
    --notes-file "$NOTES"
fi

PUB_DATE="$(gh release view "$TAG" --repo "$REPO" --json publishedAt -q .publishedAt)"
DMG_URL="$(gh release view "$TAG" --repo "$REPO" --json assets \
  -q '.assets[] | select(.name|endswith(".dmg")) | .url' | head -1)"

# ─── 3. Write appcast.xml ───────────────────────────────────────
echo "Writing appcast.xml..."
NOTES_HTML="$(python3 -c "import sys,html; print(html.escape(open('$NOTES').read()))")"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Echotype Mac</title>
    <link>https://github.com/${REPO}</link>
    <description>Echotype Mac updates</description>
    <language>en</language>
    <item>
      <title>Echotype Mac ${TAG}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <description><![CDATA[
${NOTES_HTML}
      ]]></description>
      <enclosure
        url="${DMG_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIG}"
        sparkle:os="macos" />
    </item>
  </channel>
</rss>
XML

echo "Appcast written: $APPCAST"

# ─── 4. Commit ──────────────────────────────────────────────────
echo "Committing appcast..."
git -C "$PROJECT_DIR" add appcast.xml
git -C "$PROJECT_DIR" commit -m "release: v${VERSION} appcast (signed enclosure)"

echo ""
echo "Done. Push the branch to publish the update to existing users:"
echo "  git push origin \$(git -C \"$PROJECT_DIR\" branch --show-current)"
