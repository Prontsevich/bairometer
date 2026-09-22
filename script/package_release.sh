#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 MAJOR.MINOR.PATCH BUILD_NUMBER arm64|x86_64 [--signed-submission]" >&2
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

VERSION="$1"
BUILD_NUMBER="$2"
ARCHITECTURE="$3"
ARCHIVE_SUFFIX=""
if [[ $# -eq 4 ]]; then
  [[ "$4" == "--signed-submission" ]] || { usage; exit 2; }
  ARCHIVE_SUFFIX="-signed"
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must use MAJOR.MINOR.PATCH with numeric components" >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: build number must use one to three numeric components" >&2
  exit 2
fi

case "$ARCHITECTURE" in
  arm64|x86_64)
    ;;
  *)
    usage
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bairometer"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
OUTPUT_DIRECTORY="$ROOT_DIR/dist"
ARCHIVE="$OUTPUT_DIRECTORY/$APP_NAME-$VERSION-$ARCHITECTURE$ARCHIVE_SUFFIX.zip"
TEMP_DIRECTORY=""

cleanup() {
  [[ -z "$TEMP_DIRECTORY" ]] || rm -rf "$TEMP_DIRECTORY"
}
trap cleanup EXIT

"$ROOT_DIR/script/stage_app_bundle.sh" \
  --configuration release \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --arch "$ARCHITECTURE"

TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-release.XXXXXX")"
[[ -d "$OUTPUT_DIRECTORY" ]] || {
  echo "error: release output directory is missing at $OUTPUT_DIRECTORY" >&2
  exit 1
}
/bin/bash \
  "$ROOT_DIR/script/validate_release_bundle.sh" \
  "$APP_BUNDLE" \
  "$VERSION" \
  "$BUILD_NUMBER" \
  "$ARCHITECTURE"

rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
[[ -s "$ARCHIVE" ]] || { echo "error: release archive was not created" >&2; exit 1; }

EXTRACTION_DIRECTORY="$TEMP_DIRECTORY/archive"
mkdir -p "$EXTRACTION_DIRECTORY"
/usr/bin/ditto -x -k "$ARCHIVE" "$EXTRACTION_DIRECTORY"
EXTRACTED_APP="$EXTRACTION_DIRECTORY/$APP_NAME.app"
[[ -d "$EXTRACTED_APP" ]] || { echo "error: archive does not expand to $APP_NAME.app" >&2; exit 1; }

if find "$EXTRACTION_DIRECTORY" -mindepth 1 -maxdepth 1 \
  ! -name "$APP_NAME.app" \
  ! -name '__MACOSX' \
  -print -quit | grep -q .; then
  echo "error: archive contains an unexpected top-level item" >&2
  exit 1
fi

/bin/bash \
  "$ROOT_DIR/script/validate_release_bundle.sh" \
  "$EXTRACTED_APP" \
  "$VERSION" \
  "$BUILD_NUMBER" \
  "$ARCHITECTURE"
echo "Created $ARCHIVE"
