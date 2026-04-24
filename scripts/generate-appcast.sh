#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
GITHUB_REPO="kartikk-k/Echotype-Mac"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST_FILE="$PROJECT_DIR/appcast.xml"

# ─── Check gh CLI ────────────────────────────────────────────────
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is required. Install with: brew install gh"
    exit 1
fi

echo "Fetching releases from $GITHUB_REPO..."

# ─── Generate appcast XML ───────────────────────────────────────
cat > "$APPCAST_FILE" << 'HEADER'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Echotype Mac</title>
    <link>https://github.com/kartikk-k/Echotype-Mac</link>
    <description>Echotype Mac updates</description>
    <language>en</language>
HEADER

# Fetch releases and generate items
gh release list --repo "$GITHUB_REPO" --limit 10 --json tagName,publishedAt,name,isDraft,isPrerelease | \
    python3 -c "
import json, sys, subprocess, os

releases = json.load(sys.stdin)
repo = '$GITHUB_REPO'

for release in releases:
    if release['isDraft']:
        continue

    tag = release['tagName']
    name = release['name'] or tag
    date = release['publishedAt']

    # Get release assets
    assets_json = subprocess.run(
        ['gh', 'release', 'view', tag, '--repo', repo, '--json', 'assets'],
        capture_output=True, text=True
    ).stdout

    assets = json.loads(assets_json).get('assets', [])

    dmg_asset = None
    for asset in assets:
        if asset['name'].endswith('.dmg'):
            dmg_asset = asset
            break

    if not dmg_asset:
        continue

    # Extract version from tag (strip 'v' prefix if present)
    version = tag.lstrip('v')

    url = dmg_asset['url']
    size = dmg_asset['size']

    print(f'''    <item>
      <title>{name}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <enclosure
        url=\"{url}\"
        length=\"{size}\"
        type=\"application/octet-stream\"
        sparkle:os=\"macos\" />
    </item>''')
"

cat >> "$APPCAST_FILE" << 'FOOTER'
  </channel>
</rss>
FOOTER

echo "Appcast generated at: $APPCAST_FILE"
echo ""
echo "Next steps:"
echo "  1. Commit and push appcast.xml to the main branch"
echo "  2. Sparkle will check: https://raw.githubusercontent.com/$GITHUB_REPO/main/appcast.xml"
