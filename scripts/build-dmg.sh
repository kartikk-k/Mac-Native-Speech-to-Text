#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
APP_NAME="Echotype Mac"
SCHEME="Mac native speech to text"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/ Echotype Mac.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_OUTPUT="$BUILD_DIR/$APP_NAME.dmg"

# ─── Clean previous build ───────────────────────────────────────
echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── Resolve Swift packages ─────────────────────────────────────
echo "Resolving Swift packages..."
xcodebuild -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -resolvePackageDependencies \
    -quiet

# ─── Archive (universal: arm64 + x86_64) ────────────────────────
echo "Archiving universal binary (arm64 + x86_64)..."
xcodebuild archive \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    -quiet

# ─── Export archive ──────────────────────────────────────────────
echo "Creating export options plist..."
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>HXV2NNGP22</string>
</dict>
</plist>
PLIST

echo "Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -quiet

APP_PATH="$EXPORT_PATH/ $APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    # Try without leading space
    APP_PATH="$EXPORT_PATH/$APP_NAME.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Could not find exported .app bundle"
    echo "Contents of export dir:"
    ls -la "$EXPORT_PATH/"
    exit 1
fi

# ─── Verify universal binary ────────────────────────────────────
echo "Verifying architectures..."
ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/"* 2>/dev/null | head -1)
echo "  Architectures: $ARCHS"

# ─── Create DMG ─────────────────────────────────────────────────
echo "Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to DMG staging
cp -R "$APP_PATH" "$DMG_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_DIR/Applications"

# Create the DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

echo ""
echo "DMG created at: $DMG_OUTPUT"
echo "Size: $(du -h "$DMG_OUTPUT" | cut -f1)"

# ─── Extract version info ───────────────────────────────────────
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
echo "Version: $VERSION (build $BUILD)"
echo ""
echo "Done! You can now:"
echo "  1. Notarize:  xcrun notarytool submit \"$DMG_OUTPUT\" --apple-id YOUR_APPLE_ID --team-id HXV2NNGP22 --password APP_SPECIFIC_PASSWORD --wait"
echo "  2. Staple:    xcrun stapler staple \"$DMG_OUTPUT\""
echo "  3. Upload to GitHub Releases and run: ./scripts/generate-appcast.sh"
