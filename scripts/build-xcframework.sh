#!/usr/bin/env bash
set -euo pipefail

# Builds GalleryFFI.xcframework for macOS (arm64) and, when installed via rustup,
# iPadOS/iOS device (aarch64-apple-ios) and Simulator (aarch64-apple-ios-sim).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

XCFRAMEWORK_OUT="$ROOT_DIR/apps/apple/Libs/GalleryFFI.xcframework"
HEADERS_DIR="$ROOT_DIR/apps/apple/Sources/CGalleryFFI/include"

# Ensure headers and macOS release binary are fresh
"$ROOT_DIR/scripts/build-swift-bridge.sh"

INSTALLED_TARGETS="$(rustup target list --installed 2>/dev/null || echo "aarch64-apple-darwin")"
XCF_ARGS=()

# 1. macOS slice (always built on Apple Silicon host)
MACOS_LIB="$ROOT_DIR/target/release/libgallery_ffi.a"
XCF_ARGS+=(-library "$MACOS_LIB" -headers "$HEADERS_DIR")

# 2. iPadOS / iOS device slice (if aarch64-apple-ios is installed)
if echo "$INSTALLED_TARGETS" | grep -q "^aarch64-apple-ios$"; then
  echo "Building iPadOS/iOS device slice (aarch64-apple-ios)..."
  cargo build --offline --release -p gallery-ffi --target aarch64-apple-ios
  XCF_ARGS+=(-library "$ROOT_DIR/target/aarch64-apple-ios/release/libgallery_ffi.a" -headers "$HEADERS_DIR")
else
  echo "Note: aarch64-apple-ios target not installed (install with: rustup target add aarch64-apple-ios)"
fi

# 3. iPadOS / iOS Simulator slice (if aarch64-apple-ios-sim is installed)
if echo "$INSTALLED_TARGETS" | grep -q "^aarch64-apple-ios-sim$"; then
  echo "Building iPadOS/iOS Simulator slice (aarch64-apple-ios-sim)..."
  cargo build --offline --release -p gallery-ffi --target aarch64-apple-ios-sim
  XCF_ARGS+=(-library "$ROOT_DIR/target/aarch64-apple-ios-sim/release/libgallery_ffi.a" -headers "$HEADERS_DIR")
else
  echo "Note: aarch64-apple-ios-sim target not installed (install with: rustup target add aarch64-apple-ios-sim)"
fi

rm -rf "$XCFRAMEWORK_OUT"
xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "$XCFRAMEWORK_OUT"

echo "Created XCFramework: $XCFRAMEWORK_OUT"
