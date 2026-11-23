#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_DIR="$ROOT_DIR/apps/apple"
OUT_TMP="$ROOT_DIR/target/uniffi-swift"

echo "1/3 Building gallery-ffi (release)..."
cargo build --offline --manifest-path "$ROOT_DIR/Cargo.toml" -p gallery-ffi --release

echo "2/3 Generating Swift bindings via uniffi-bindgen..."
rm -rf "$OUT_TMP"
mkdir -p "$OUT_TMP"
cargo run --offline --release --manifest-path "$ROOT_DIR/Cargo.toml" -p gallery-ffi --bin uniffi-bindgen -- \
  generate \
  --library "$ROOT_DIR/target/release/libgallery_ffi.dylib" \
  --language swift \
  --out-dir "$OUT_TMP"

echo "3/3 Syncing headers, Swift bindings, and static library into apps/apple..."
mkdir -p "$APP_DIR/Sources/CGalleryFFI/include"
mkdir -p "$APP_DIR/Sources/GalleryBridge/Generated"
mkdir -p "$APP_DIR/Libs"

cp "$OUT_TMP/gallery_ffiFFI.h" "$APP_DIR/Sources/CGalleryFFI/include/gallery_ffiFFI.h"
cp "$OUT_TMP/gallery_ffiFFI.modulemap" "$APP_DIR/Sources/CGalleryFFI/include/module.modulemap"
cp "$OUT_TMP/gallery_ffi.swift" "$APP_DIR/Sources/GalleryBridge/Generated/gallery_ffi.swift"
cp "$ROOT_DIR/target/release/libgallery_ffi.a" "$APP_DIR/Libs/libgallery_ffi.a"

if [ ! -f "$APP_DIR/Sources/CGalleryFFI/shim.c" ]; then
  echo "/* Empty shim for SwiftPM C target */" > "$APP_DIR/Sources/CGalleryFFI/shim.c"
fi

echo "Done! Swift bindings and libgallery_ffi.a are ready in $APP_DIR"
