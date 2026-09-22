#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 ENTITLEMENTS_PLIST TEAM_ID BUNDLE_ID" >&2
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

ENTITLEMENTS_PLIST="$1"
EXPECTED_TEAM="$2"
EXPECTED_BUNDLE_ID="$3"
EXPECTED_APP_IDENTIFIER="$EXPECTED_TEAM.$EXPECTED_BUNDLE_ID"
TEMP_DIRECTORY=""

cleanup() {
  [[ -z "$TEMP_DIRECTORY" ]] || rm -rf "$TEMP_DIRECTORY"
}
trap cleanup EXIT

[[ -s "$ENTITLEMENTS_PLIST" ]] || {
  echo "error: release entitlements plist is missing" >&2
  exit 1
}
[[ -n "$EXPECTED_TEAM" ]] || {
  echo "error: expected signing team is missing" >&2
  exit 1
}
[[ -n "$EXPECTED_BUNDLE_ID" ]] || {
  echo "error: expected bundle identifier is missing" >&2
  exit 1
}

/usr/bin/plutil -lint "$ENTITLEMENTS_PLIST" >/dev/null

read_required_value() {
  local key="$1"
  local plist="$2"
  local value

  if ! value="$(
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null
  )"; then
    echo "error: release entitlements are missing $key" >&2
    exit 1
  fi
  printf '%s' "$value"
}

APP_IDENTIFIER="$(
  read_required_value "com.apple.application-identifier" "$ENTITLEMENTS_PLIST"
)"
SIGNED_TEAM="$(
  read_required_value "com.apple.developer.team-identifier" "$ENTITLEMENTS_PLIST"
)"
KEYCHAIN_GROUP="$(
  read_required_value "keychain-access-groups:0" "$ENTITLEMENTS_PLIST"
)"

[[ "$APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ]] || {
  echo "error: release entitlements contain an unexpected app identifier" >&2
  exit 1
}
[[ "$SIGNED_TEAM" == "$EXPECTED_TEAM" ]] || {
  echo "error: release entitlements contain an unexpected signing team" >&2
  exit 1
}
[[ "$KEYCHAIN_GROUP" == "$EXPECTED_APP_IDENTIFIER" ]] || {
  echo "error: release entitlements contain an unexpected Keychain group" >&2
  exit 1
}

TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-entitlements.XXXXXX")"
REMAINDER_PLIST="$TEMP_DIRECTORY/remainder.plist"
cp "$ENTITLEMENTS_PLIST" "$REMAINDER_PLIST"

/usr/libexec/PlistBuddy \
  -c "Delete :com.apple.application-identifier" \
  -c "Delete :com.apple.developer.team-identifier" \
  -c "Delete :keychain-access-groups:0" \
  "$REMAINDER_PLIST" >/dev/null

KEYCHAIN_REMAINDER="$(
  /usr/bin/plutil \
    -extract "keychain-access-groups" \
    json \
    -o - \
    "$REMAINDER_PLIST"
)"
[[ "$KEYCHAIN_REMAINDER" == "[]" ]] || {
  echo "error: release entitlements contain extra Keychain groups" >&2
  exit 1
}

/usr/libexec/PlistBuddy \
  -c "Delete :keychain-access-groups" \
  "$REMAINDER_PLIST" >/dev/null
ROOT_REMAINDER="$(
  /usr/bin/plutil -convert json -o - "$REMAINDER_PLIST"
)"
[[ "$ROOT_REMAINDER" == "{}" ]] || {
  echo "error: release entitlements contain unexpected keys" >&2
  exit 1
}
