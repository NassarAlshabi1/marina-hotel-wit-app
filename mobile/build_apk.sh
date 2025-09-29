#!/bin/bash
set -euo pipefail

echo "Marina Hotel Mobile - APK/AAB Builder"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found"
  exit 1
fi

VERSION_NAME=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
BUILD_NUMBER=${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}
DATE_UTC=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
OUT_DIR="$SCRIPT_DIR/../releases/apk"
mkdir -p "$OUT_DIR"

CI_MODE=false
RELEASE_ONLY=false
DEBUG_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci) CI_MODE=true ;;
    --release-only) RELEASE_ONLY=true ;;
    --debug-only) DEBUG_ONLY=true ;;
    --build-number) shift; BUILD_NUMBER="$1" ;;
  esac
  shift || true
done

flutter --version
flutter clean
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs

if [ "$RELEASE_ONLY" = false ]; then
  flutter build apk --debug \
    --target-platform android-arm,android-arm64,android-x64 \
    --split-per-abi
fi

if [ "$DEBUG_ONLY" = false ]; then
  flutter build apk --release \
    --build-number "$BUILD_NUMBER" \
    --target-platform android-arm,android-arm64,android-x64 \
    --split-per-abi
  flutter build appbundle --release --build-number "$BUILD_NUMBER"
fi

mapfile -t APK_DEBUG < <(ls build/app/outputs/flutter-apk/*-debug.apk 2>/dev/null || true)
mapfile -t APK_RELEASE < <(ls build/app/outputs/flutter-apk/*-release.apk 2>/dev/null || true)
AAB_RELEASE="build/app/outputs/bundle/release/app-release.aab"

map_abi() {
  case "$1" in
    *arm64-v8a*) echo "arm64" ;;
    *armeabi-v7a*) echo "armv7" ;;
    *x86_64*) echo "x86_64" ;;
    *) echo "unknown" ;;
  esac
}

meta_tmp="$(mktemp)"

for f in "${APK_DEBUG[@]}"; do
  [ -f "$f" ] || continue
  abi=$(map_abi "$f")
  out="$OUT_DIR/marina-hotel-v${VERSION_NAME}-${abi}-debug.apk"
  cp "$f" "$out"
  if ! unzip -l "$out" | grep -q AndroidManifest.xml; then
    echo "Invalid APK: $out" >&2; exit 1
  fi
  size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
  sha=$(sha256sum "$out" 2>/dev/null | awk '{print $1}')
  if [ -z "$sha" ]; then sha=$(shasum -a 256 "$out" | awk '{print $1}'); fi
  echo "$DATE_UTC,${VERSION_NAME},$BUILD_NUMBER,$(basename "$out"),$size,$sha" >> "$meta_tmp"
  echo "Created $(basename "$out")"
done

for f in "${APK_RELEASE[@]}"; do
  [ -f "$f" ] || continue
  abi=$(map_abi "$f")
  out="$OUT_DIR/marina-hotel-v${VERSION_NAME}-${abi}.apk"
  cp "$f" "$out"
  if ! unzip -l "$out" | grep -q AndroidManifest.xml; then
    echo "Invalid APK: $out" >&2; exit 1
  fi
  size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
  sha=$(sha256sum "$out" 2>/dev/null | awk '{print $1}')
  if [ -z "$sha" ]; then sha=$(shasum -a 256 "$out" | awk '{print $1}'); fi
  echo "$DATE_UTC,${VERSION_NAME},$BUILD_NUMBER,$(basename "$out"),$size,$sha" >> "$meta_tmp"
  echo "Created $(basename "$out")"
done

if [ -f "$AAB_RELEASE" ]; then
  out="$OUT_DIR/marina-hotel-v${VERSION_NAME}.aab"
  cp "$AAB_RELEASE" "$out"
  size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
  sha=$(sha256sum "$out" 2>/dev/null | awk '{print $1}')
  if [ -z "$sha" ]; then sha=$(shasum -a 256 "$out" | awk '{print $1}'); fi
  echo "$DATE_UTC,${VERSION_NAME},$BUILD_NUMBER,$(basename "$out"),$size,$sha" >> "$meta_tmp"
  echo "Created $(basename "$out")"
fi

if [ -s "$meta_tmp" ]; then
  {
    echo "date_utc,version,build_number,file,size_bytes,sha256"
    cat "$meta_tmp"
  } > "$OUT_DIR/marina-hotel-v${VERSION_NAME}-metadata.csv"
fi

if [ "$CI_MODE" = false ] && [ "$RELEASE_ONLY" = false ] && [ "$DEBUG_ONLY" = false ]; then
  echo "Done"
fi
