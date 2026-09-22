#!/usr/bin/env bash
set -euo pipefail

PRODUCTION_APP_NAME="Bairometer"
HOST_APP_NAME="BairometerUITestHost"
HOST_EXECUTABLE="BairometerTest"
HOST_BUNDLE_ID="io.github.Prontsevich.Bairometer.UITestHost"
HOST_DISPLAY_NAME="Bairometer UI Test Host"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PRODUCTION_BUNDLE="$DIST_DIR/$PRODUCTION_APP_NAME.app"
HOST_BUNDLE="$DIST_DIR/$HOST_APP_NAME.app"
HOST_CONTENTS="$HOST_BUNDLE/Contents"
HOST_MACOS="$HOST_CONTENTS/MacOS"
HOST_INFO_PLIST="$HOST_CONTENTS/Info.plist"

"$ROOT_DIR/script/stage_app_bundle.sh" --configuration debug

rm -rf "$HOST_BUNDLE"
/usr/bin/ditto "$PRODUCTION_BUNDLE" "$HOST_BUNDLE"
mv "$HOST_MACOS/$PRODUCTION_APP_NAME" "$HOST_MACOS/$HOST_EXECUTABLE"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $HOST_EXECUTABLE" "$HOST_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $HOST_BUNDLE_ID" "$HOST_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $HOST_APP_NAME" "$HOST_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $HOST_DISPLAY_NAME" "$HOST_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LSUIElement false" "$HOST_INFO_PLIST"

/usr/bin/plutil -lint "$HOST_INFO_PLIST" >/dev/null
/usr/bin/codesign --force --sign - --timestamp=none "$HOST_MACOS/$HOST_EXECUTABLE"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$HOST_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$HOST_BUNDLE"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$HOST_INFO_PLIST")" == "$HOST_EXECUTABLE" ]] || {
  echo "error: UI test host has an unexpected executable name" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOST_INFO_PLIST")" == "$HOST_BUNDLE_ID" ]] || {
  echo "error: UI test host has an unexpected bundle identifier" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$HOST_INFO_PLIST")" == "$HOST_DISPLAY_NAME" ]] || {
  echo "error: UI test host has an unexpected display name" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$HOST_INFO_PLIST")" == "false" ]] || {
  echo "error: UI test host must be a regular app" >&2
  exit 1
}
[[ -x "$HOST_MACOS/$HOST_EXECUTABLE" ]] || {
  echo "error: missing UI test host executable" >&2
  exit 1
}

echo "Staged $HOST_BUNDLE"
