#!/usr/bin/env bash
set -euo pipefail

# End-to-end App Store Archive script for macOS & iPadOS.
# Usage:
#   ./scripts/archive-appstore.sh macos   [DEVELOPMENT_TEAM_ID]
#   ./scripts/archive-appstore.sh ipados  [DEVELOPMENT_TEAM_ID]

PLATFORM="${1:-macos}"
TEAM_ID="${2:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DIR="$ROOT_DIR/apps/xcode"
ARCHIVE_DIR="$ROOT_DIR/build/archives"
EXPORT_DIR="$ROOT_DIR/build/export"

mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

echo "1/3 Building GalleryFFI.xcframework (macOS + iPadOS + Simulator)..."
"$ROOT_DIR/scripts/build-xcframework.sh"

echo "2/3 Regenerating DigitalGallery.xcodeproj via xcodegen..."
(cd "$XCODE_DIR" && xcodegen generate)

SIGN_ARGS=()
if [ -n "$TEAM_ID" ]; then
  SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates)
else
  echo "No DEVELOPMENT_TEAM passed -> running unsigned validation archive (pass your Apple Team ID to sign for App Store Connect)."
  SIGN_ARGS+=(CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi

if [ "$PLATFORM" = "macos" ]; then
  SCHEME="DigitalGallery-macOS"
  DEST="generic/platform=macOS"
  ARCHIVE_PATH="$ARCHIVE_DIR/DigitalGallery-macOS.xcarchive"
elif [ "$PLATFORM" = "ipados" ]; then
  SCHEME="DigitalGallery-iPadOS"
  DEST="generic/platform=iOS"
  ARCHIVE_PATH="$ARCHIVE_DIR/DigitalGallery-iPadOS.xcarchive"
else
  echo "Unknown platform: $PLATFORM (use 'macos' or 'ipados')"
  exit 1
fi

echo "3/3 Archiving $SCHEME ($DEST)..."
xcodebuild archive \
  -project "$XCODE_DIR/DigitalGallery.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DEST" \
  -archivePath "$ARCHIVE_PATH" \
  "${SIGN_ARGS[@]}"

echo "Archive succeeded: $ARCHIVE_PATH"

if [ -n "$TEAM_ID" ]; then
  echo "Exporting for App Store Connect..."
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR/$PLATFORM" \
    -exportOptionsPlist "$XCODE_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates
  echo "Exported App Store package to: $EXPORT_DIR/$PLATFORM"
fi
