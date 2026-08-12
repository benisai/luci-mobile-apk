#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="${OPENWALLA_BUILD_DIR:-/tmp/openwalla-apk-build}"
OUTPUT_DIR="${OPENWALLA_APK_OUTPUT_DIR:-$PROJECT_ROOT/dist/apk}"
BUILD_MODE="release"
UPLOAD_RELEASE=false

usage() {
  echo "Usage: $0 [debug|profile|release] [--upload]" >&2
  echo "Set OPENWALLA_RELEASE_TAG, OPENWALLA_RELEASE_TITLE, or OPENWALLA_RELEASE_NOTES to override GitHub release metadata." >&2
}

find_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return 0
  fi

  local sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk_dir" && -d "$HOME/Library/Android/sdk" ]]; then
    sdk_dir="$HOME/Library/Android/sdk"
  fi

  if [[ -n "$sdk_dir" && -d "$sdk_dir/build-tools" ]]; then
    find "$sdk_dir/build-tools" -name apksigner -type f | sort | tail -n 1
    return 0
  fi

  return 1
}

for arg in "$@"; do
  case "$arg" in
    debug|profile|release)
      BUILD_MODE="$arg"
      ;;
    --upload)
      UPLOAD_RELEASE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$BUILD_MODE" in
  debug|profile|release)
    ;;
  *)
    usage
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

APKSIGNER="$(find_apksigner || true)"
if [[ -z "$APKSIGNER" ]]; then
  echo "Could not find apksigner; unable to verify whether the APK is installable." >&2
  exit 1
fi

if ! "$APKSIGNER" verify --verbose "$APK_PATH" >/dev/null 2>&1; then
  echo "APK was built but is not signed, so Android will reject it during install." >&2
  echo "For local Pixel testing, run: $0 debug" >&2
  echo "For release builds, create android/key.properties pointing to a release keystore, then rerun: $0 release" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_APK="$OUTPUT_DIR/openwalla-$BUILD_MODE.apk"
cp "$APK_PATH" "$OUTPUT_APK"

echo "APK created: $OUTPUT_APK"

if [[ "$UPLOAD_RELEASE" == true ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI is required for --upload. Install gh and run 'gh auth login' first." >&2
    exit 1
  fi

  VERSION="$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}')"
  VERSION_NAME="${VERSION%%+*}"
  RELEASE_TAG="${OPENWALLA_RELEASE_TAG:-v$VERSION_NAME}"
  RELEASE_TITLE="${OPENWALLA_RELEASE_TITLE:-Openwalla $RELEASE_TAG}"
  RELEASE_NOTES="${OPENWALLA_RELEASE_NOTES:-Release APK build.}"

  echo "Uploading APK to GitHub release: $RELEASE_TAG"
  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    gh release upload "$RELEASE_TAG" "$OUTPUT_APK" --clobber
  else
    gh release create "$RELEASE_TAG" "$OUTPUT_APK" \
      --title "$RELEASE_TITLE" \
      --notes "$RELEASE_NOTES"
  fi

  echo "APK uploaded to release: $RELEASE_TAG"
fi
