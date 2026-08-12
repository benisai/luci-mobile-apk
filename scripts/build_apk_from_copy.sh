#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="${OPENWALLA_BUILD_DIR:-/tmp/openwalla-apk-build}"
OUTPUT_DIR="${OPENWALLA_APK_OUTPUT_DIR:-$PROJECT_ROOT/dist/apk}"
BUILD_MODE="${1:-release}"

case "$BUILD_MODE" in
  debug|profile|release)
    ;;
  *)
    echo "Usage: $0 [debug|profile|release]" >&2
    exit 2
    ;;
esac

echo "Preparing clean build copy: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git/' \
    --exclude '.dart_tool/' \
    --exclude '.flutter-plugins' \
    --exclude '.flutter-plugins-dependencies' \
    --exclude 'build/' \
    --exclude 'dist/' \
    "$PROJECT_ROOT/" "$BUILD_DIR/"
else
  tar -C "$PROJECT_ROOT" \
    --exclude './.git' \
    --exclude './.dart_tool' \
    --exclude './.flutter-plugins' \
    --exclude './.flutter-plugins-dependencies' \
    --exclude './build' \
    --exclude './dist' \
    -cf - . | tar -C "$BUILD_DIR" -xf -
fi

echo "Resolving dependencies"
flutter pub get --directory "$BUILD_DIR"

echo "Building APK ($BUILD_MODE)"
(
  cd "$BUILD_DIR"
  flutter build apk "--$BUILD_MODE"
)

APK_PATH="$BUILD_DIR/build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
if [[ ! -f "$APK_PATH" ]]; then
  echo "Expected APK was not created: $APK_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_APK="$OUTPUT_DIR/openwalla-$BUILD_MODE.apk"
cp "$APK_PATH" "$OUTPUT_APK"

echo "APK created: $OUTPUT_APK"
