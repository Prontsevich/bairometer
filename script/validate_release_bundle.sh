#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 APP_BUNDLE MAJOR.MINOR.PATCH BUILD_NUMBER arm64|x86_64 [--require-notarization]" >&2
}

if [[ $# -lt 4 || $# -gt 5 ]]; then
  usage
  exit 2
fi

APP_BUNDLE="$1"
VERSION="$2"
BUILD_NUMBER="$3"
ARCHITECTURE="$4"
REQUIRE_NOTARIZATION=0
if [[ $# -eq 5 ]]; then
  [[ "$5" == "--require-notarization" ]] || { usage; exit 2; }
  REQUIRE_NOTARIZATION=1
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
HELPER_NAME="BairometerClaudeStatusLine"
EXPECTED_BUNDLE_ID="io.github.Prontsevich.Bairometer"
EXPECTED_TEAM="${BAIROMETER_DEVELOPMENT_TEAM:-}"
EXPECTED_IDENTITY="${BAIROMETER_DEVELOPER_IDENTITY:-}"
CODESIGN_COMMAND="/usr/bin/codesign"
LIPO_COMMAND="/usr/bin/lipo"
XCRUN_COMMAND="/usr/bin/xcrun"
SPCTL_COMMAND="/usr/sbin/spctl"
if [[ "${BAIROMETER_NOTARIZATION_TEST_MODE:-0}" == "1" ]]; then
  CODESIGN_COMMAND="${BAIROMETER_TEST_CODESIGN_COMMAND:?}"
  LIPO_COMMAND="${BAIROMETER_TEST_LIPO_COMMAND:?}"
  XCRUN_COMMAND="${BAIROMETER_TEST_XCRUN_COMMAND:?}"
  SPCTL_COMMAND="${BAIROMETER_TEST_SPCTL_COMMAND:?}"
fi
TEMP_DIRECTORY=""

cleanup() {
  [[ -z "$TEMP_DIRECTORY" ]] || rm -rf "$TEMP_DIRECTORY"
}
trap cleanup EXIT

[[ -n "$EXPECTED_TEAM" ]] || {
  echo "error: release validation requires BAIROMETER_DEVELOPMENT_TEAM." >&2
  exit 1
}
[[ -n "$EXPECTED_IDENTITY" ]] || {
  echo "error: release validation requires BAIROMETER_DEVELOPER_IDENTITY." >&2
  exit 1
}
[[ -d "$APP_BUNDLE" ]] || {
  echo "error: release app bundle is missing at $APP_BUNDLE" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: expected $label '$expected', found '$actual'" >&2
    exit 1
  fi
}

bundle_info="$APP_BUNDLE/Contents/Info.plist"
bundle_binary="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
bundle_helper="$APP_BUNDLE/Contents/Helpers/$HELPER_NAME"
bundle_icon="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
bundle_profile="$APP_BUNDLE/Contents/embedded.provisionprofile"
english_strings="$APP_BUNDLE/Contents/Resources/en.lproj/Localizable.strings"
russian_strings="$APP_BUNDLE/Contents/Resources/ru.lproj/Localizable.strings"

[[ -x "$bundle_binary" ]] || { echo "error: missing app executable" >&2; exit 1; }
[[ -x "$bundle_helper" ]] || { echo "error: missing helper executable" >&2; exit 1; }
[[ -s "$bundle_icon" ]] || { echo "error: missing compiled app icon" >&2; exit 1; }
[[ -s "$bundle_profile" ]] || { echo "error: missing Developer ID provisioning profile" >&2; exit 1; }
[[ -s "$english_strings" ]] || { echo "error: missing English localization resources" >&2; exit 1; }
[[ -s "$russian_strings" ]] || { echo "error: missing Russian localization resources" >&2; exit 1; }
[[ -d "$APP_BUNDLE/Contents/Resources/GRDB_GRDB.bundle" ]] || {
  echo "error: missing GRDB production resource bundle" >&2
  exit 1
}

if find "$APP_BUNDLE/Contents/Resources" -maxdepth 1 -name '*Tests.bundle' -print -quit | grep -q .; then
  echo "error: test resource bundle was staged into the app" >&2
  exit 1
fi

assert_equal "$EXPECTED_BUNDLE_ID" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_info")" "bundle identifier"
assert_equal "$VERSION" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle_info")" "short version"
assert_equal "$BUILD_NUMBER" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle_info")" "bundle version"
assert_equal "15.0" "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$bundle_info")" "minimum system version"
assert_equal "en" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$bundle_info")" "development region"
assert_equal "AppIcon" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$bundle_info")" "app icon file"
assert_equal "AppIcon" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$bundle_info")" "app icon name"
assert_equal "$ARCHITECTURE" "$("$LIPO_COMMAND" -archs "$bundle_binary")" "app architecture"
assert_equal "$ARCHITECTURE" "$("$LIPO_COMMAND" -archs "$bundle_helper")" "helper architecture"

TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-release-validation.XXXXXX")"
app_entitlements="$TEMP_DIRECTORY/app-entitlements.plist"
codesign_verification_log="$TEMP_DIRECTORY/codesign-verification.log"
stapler_validation_log="$TEMP_DIRECTORY/stapler-validation.log"
gatekeeper_assessment_log="$TEMP_DIRECTORY/gatekeeper-assessment.log"

if ! "$CODESIGN_COMMAND" \
  --verify \
  --deep \
  --strict \
  --verbose=2 \
  "$APP_BUNDLE" \
  >"$codesign_verification_log" \
  2>&1; then
  echo "error: strict release signature verification failed" >&2
  exit 1
fi
app_signing_state="$("$CODESIGN_COMMAND" -dvvv "$APP_BUNDLE" 2>&1)"
helper_signing_state="$("$CODESIGN_COMMAND" -dvvv "$bundle_helper" 2>&1)"
"$CODESIGN_COMMAND" \
  --display \
  --entitlements - \
  --xml \
  "$APP_BUNDLE" \
  >"$app_entitlements" \
  2>/dev/null
/bin/bash \
  "$ROOT_DIR/script/validate_release_entitlements.sh" \
  "$app_entitlements" \
  "$EXPECTED_TEAM" \
  "$EXPECTED_BUNDLE_ID"

[[ "$app_signing_state" == *"Authority=$EXPECTED_IDENTITY"* ]] || {
  echo "error: app is not Developer ID signed" >&2
  exit 1
}
[[ "$app_signing_state" == *"TeamIdentifier=$EXPECTED_TEAM"* ]] || {
  echo "error: app signature contains an unexpected team" >&2
  exit 1
}
[[ "$app_signing_state" == *"flags="*"runtime"* ]] || {
  echo "error: app signature is missing Hardened Runtime" >&2
  exit 1
}
[[ "$app_signing_state" == *"Timestamp="* ]] || {
  echo "error: app signature is missing a secure timestamp" >&2
  exit 1
}
[[ "$helper_signing_state" == *"Authority=$EXPECTED_IDENTITY"* ]] || {
  echo "error: helper is not Developer ID signed" >&2
  exit 1
}
[[ "$helper_signing_state" == *"TeamIdentifier=$EXPECTED_TEAM"* ]] || {
  echo "error: helper signature contains an unexpected team" >&2
  exit 1
}
[[ "$helper_signing_state" == *"flags="*"runtime"* ]] || {
  echo "error: helper signature is missing Hardened Runtime" >&2
  exit 1
}
[[ "$helper_signing_state" == *"Timestamp="* ]] || {
  echo "error: helper signature is missing a secure timestamp" >&2
  exit 1
}

if [[ "$REQUIRE_NOTARIZATION" -eq 1 ]]; then
  if ! "$XCRUN_COMMAND" stapler validate "$APP_BUNDLE" \
    >"$stapler_validation_log" \
    2>&1; then
    echo "error: stapler ticket validation failed" >&2
    exit 1
  fi
  if ! "$SPCTL_COMMAND" --assess --type execute --verbose=4 "$APP_BUNDLE" \
    >"$gatekeeper_assessment_log" \
    2>&1; then
    echo "error: Gatekeeper assessment failed" >&2
    exit 1
  fi
fi
