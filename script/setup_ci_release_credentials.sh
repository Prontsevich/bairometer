#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP_SCRIPT="$ROOT_DIR/script/cleanup_ci_release_credentials.sh"
PRIVATE_DIRECTORY="${BAIROMETER_CI_PRIVATE_DIRECTORY:-}"
KEYCHAIN_PATH="${BAIROMETER_CI_KEYCHAIN_PATH:-}"
RUNNER_TEMP_DIRECTORY="${RUNNER_TEMP:-}"
GITHUB_ENVIRONMENT_FILE="${GITHUB_ENV:-}"
SETUP_COMPLETE=0
PRIVATE_DIRECTORY_CREATED=0
OWNERSHIP_MARKER_WRITTEN=0
OWNERSHIP_TOKEN=""

SECURITY_COMMAND="/usr/bin/security"
XCRUN_COMMAND="/usr/bin/xcrun"
PLUTIL_COMMAND="/usr/bin/plutil"
PLIST_BUDDY_COMMAND="/usr/libexec/PlistBuddy"
BASE64_COMMAND="/usr/bin/base64"
OPENSSL_COMMAND="/usr/bin/openssl"
UUIDGEN_COMMAND="/usr/bin/uuidgen"
if [[ "${BAIROMETER_CI_CREDENTIAL_TEST_MODE:-0}" == "1" ]]; then
  SECURITY_COMMAND="${BAIROMETER_TEST_SECURITY_COMMAND:?}"
  XCRUN_COMMAND="${BAIROMETER_TEST_XCRUN_COMMAND:?}"
  PLUTIL_COMMAND="${BAIROMETER_TEST_PLUTIL_COMMAND:?}"
  PLIST_BUDDY_COMMAND="${BAIROMETER_TEST_PLIST_BUDDY_COMMAND:?}"
  OPENSSL_COMMAND="${BAIROMETER_TEST_OPENSSL_COMMAND:?}"
  UUIDGEN_COMMAND="${BAIROMETER_TEST_UUIDGEN_COMMAND:?}"
fi

cleanup_on_failure() {
  local exit_status=$?
  trap - EXIT
  if [[ "$SETUP_COMPLETE" -eq 0 ]]; then
    if [[ "$OWNERSHIP_MARKER_WRITTEN" -eq 1 ]]; then
      if ! BAIROMETER_CI_CREDENTIAL_OWNER="$OWNERSHIP_TOKEN" \
        /bin/bash "$CLEANUP_SCRIPT" >/dev/null 2>&1; then
        exit_status=1
      fi
    elif [[ "$PRIVATE_DIRECTORY_CREATED" -eq 1 ]]; then
      if ! /bin/rmdir "$PRIVATE_DIRECTORY" >/dev/null 2>&1; then
        exit_status=1
      fi
    fi
  fi
  exit "$exit_status"
}
trap cleanup_on_failure EXIT

fail() {
  echo "error: $1" >&2
  exit 1
}

required_secret_names=(
  BAIROMETER_CI_DEVELOPER_ID_P12_BASE64
  BAIROMETER_CI_DEVELOPER_ID_P12_PASSWORD
  BAIROMETER_CI_PROVISIONING_PROFILE_BASE64
  BAIROMETER_CI_NOTARYTOOL_APPLE_ID
  BAIROMETER_CI_NOTARYTOOL_TEAM_ID
  BAIROMETER_CI_NOTARYTOOL_PASSWORD
)
for secret_name in "${required_secret_names[@]}"; do
  [[ -n "${!secret_name:-}" ]] || \
    fail "required protected release credentials are missing"
done

[[ -n "$RUNNER_TEMP_DIRECTORY" && "$RUNNER_TEMP_DIRECTORY" == /* ]] || \
  fail "RUNNER_TEMP must be an absolute path"
[[ "$RUNNER_TEMP_DIRECTORY" != "/" ]] || \
  fail "RUNNER_TEMP must not be the filesystem root"
[[ "$PRIVATE_DIRECTORY" == "$RUNNER_TEMP_DIRECTORY/Bairometer-ci-release-private" ]] || \
  fail "private release directory is outside the expected runner location"
[[ "$KEYCHAIN_PATH" == "$RUNNER_TEMP_DIRECTORY/Bairometer-ci-release.keychain-db" ]] || \
  fail "release keychain is outside the expected runner location"
[[ -n "$GITHUB_ENVIRONMENT_FILE" && -f "$GITHUB_ENVIRONMENT_FILE" &&
   ! -L "$GITHUB_ENVIRONMENT_FILE" ]] || \
  fail "GITHUB_ENV is unavailable or unsafe"
[[ ! -e "$PRIVATE_DIRECTORY" && ! -L "$PRIVATE_DIRECTORY" ]] || \
  fail "private release directory already exists"
[[ ! -e "$KEYCHAIN_PATH" && ! -L "$KEYCHAIN_PATH" ]] || \
  fail "release keychain path already exists"
[[ -x "$CLEANUP_SCRIPT" || -f "$CLEANUP_SCRIPT" ]] || \
  fail "release credential cleanup script is unavailable"

OWNERSHIP_TOKEN="$($UUIDGEN_COMMAND)"
[[ "$OWNERSHIP_TOKEN" =~ ^[A-Za-z0-9-]{16,128}$ ]] || \
  fail "release credential ownership token is invalid"
/bin/mkdir -m 700 "$PRIVATE_DIRECTORY"
PRIVATE_DIRECTORY_CREATED=1
OWNERSHIP_MARKER="$PRIVATE_DIRECTORY/.credential-owner"
KEYCHAIN_OWNERSHIP_MARKER="$PRIVATE_DIRECTORY/.keychain-owner"
if ! printf '%s\n' "$OWNERSHIP_TOKEN" >"$OWNERSHIP_MARKER"; then
  /bin/rm -f -- "$OWNERSHIP_MARKER"
  fail "release credential ownership marker could not be created"
fi
OWNERSHIP_MARKER_WRITTEN=1
if ! /bin/chmod 600 "$OWNERSHIP_MARKER"; then
  fail "release credential ownership marker could not be protected"
fi
DIAGNOSTICS="$PRIVATE_DIRECTORY/credential-setup.log"
P12_BASE64_FILE="$PRIVATE_DIRECTORY/developer-id.p12.base64"
P12_FILE="$PRIVATE_DIRECTORY/developer-id.p12"
PROFILE_BASE64_FILE="$PRIVATE_DIRECTORY/developer-id.provisionprofile.base64"
PROFILE_FILE="$PRIVATE_DIRECTORY/developer-id.provisionprofile"
PROFILE_PLIST="$PRIVATE_DIRECTORY/developer-id-profile.plist"
PROFILE_CERTIFICATE_BASE64="$PRIVATE_DIRECTORY/profile-certificate.base64"
PROFILE_CERTIFICATE_DER="$PRIVATE_DIRECTORY/profile-certificate.der"
IDENTITIES_FILE="$PRIVATE_DIRECTORY/codesigning-identities.txt"
NOTARYTOOL_PROFILE="bairometer-ci-notary"
KEYCHAIN_PASSWORD="$($UUIDGEN_COMMAND)"

printf '%s' "$BAIROMETER_CI_DEVELOPER_ID_P12_BASE64" >"$P12_BASE64_FILE"
printf '%s' "$BAIROMETER_CI_PROVISIONING_PROFILE_BASE64" >"$PROFILE_BASE64_FILE"
if ! "$BASE64_COMMAND" -D -i "$P12_BASE64_FILE" -o "$P12_FILE" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID certificate data is not valid base64"
fi
if ! "$BASE64_COMMAND" -D -i "$PROFILE_BASE64_FILE" -o "$PROFILE_FILE" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "provisioning profile data is not valid base64"
fi
[[ -s "$P12_FILE" && -s "$PROFILE_FILE" ]] || \
  fail "decoded release credentials are empty"

if ! printf '%s\n' "$OWNERSHIP_TOKEN" >"$KEYCHAIN_OWNERSHIP_MARKER"; then
  fail "release keychain ownership marker could not be created"
fi
if ! /bin/chmod 600 "$KEYCHAIN_OWNERSHIP_MARKER"; then
  fail "release keychain ownership marker could not be protected"
fi
if ! "$SECURITY_COMMAND" create-keychain \
  -p "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "ephemeral release keychain could not be created"
fi
if ! "$SECURITY_COMMAND" set-keychain-settings \
  -lut 7200 \
  "$KEYCHAIN_PATH" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "ephemeral release keychain settings could not be applied"
fi
if ! "$SECURITY_COMMAND" unlock-keychain \
  -p "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "ephemeral release keychain could not be unlocked"
fi
if ! "$SECURITY_COMMAND" import "$P12_FILE" \
  -k "$KEYCHAIN_PATH" \
  -P "$BAIROMETER_CI_DEVELOPER_ID_P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID signing material could not be imported"
fi
if ! "$SECURITY_COMMAND" set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID private-key access could not be configured"
fi
if ! "$SECURITY_COMMAND" list-keychains \
  -d user \
  -s "$KEYCHAIN_PATH" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "ephemeral release keychain could not be isolated"
fi
if ! "$SECURITY_COMMAND" default-keychain \
  -d user \
  -s "$KEYCHAIN_PATH" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "ephemeral release keychain could not be selected"
fi

if ! "$SECURITY_COMMAND" cms \
  -D \
  -i "$PROFILE_FILE" \
  -o "$PROFILE_PLIST" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID provisioning profile is invalid"
fi
if ! "$PLUTIL_COMMAND" -lint "$PROFILE_PLIST" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID provisioning profile is malformed"
fi

PROFILE_TEAM="$($PLIST_BUDDY_COMMAND -c "Print :TeamIdentifier:0" "$PROFILE_PLIST" 2>>"$DIAGNOSTICS")" || \
  fail "Developer ID provisioning profile has no signing team"
[[ "$PROFILE_TEAM" =~ ^[A-Z0-9]{10}$ ]] || \
  fail "Developer ID provisioning profile has an invalid signing team"
[[ "$PROFILE_TEAM" == "$BAIROMETER_CI_NOTARYTOOL_TEAM_ID" ]] || \
  fail "notary credentials do not match the provisioning profile"

if ! PROFILE_CERTIFICATES_XML="$($PLUTIL_COMMAND \
  -extract DeveloperCertificates \
  xml1 \
  -o - \
  "$PROFILE_PLIST" \
  2>>"$DIAGNOSTICS")"; then
  fail "Developer ID provisioning profile has no signing certificate"
fi
PROFILE_CERTIFICATE_COUNT="$(
  printf '%s' "$PROFILE_CERTIFICATES_XML" |
    /usr/bin/awk '/<data>/{count += 1} END{print count + 0}'
)"
[[ "$PROFILE_CERTIFICATE_COUNT" == "1" ]] || \
  fail "Developer ID provisioning profile must contain one signing certificate"
if ! "$PLUTIL_COMMAND" \
  -extract DeveloperCertificates.0 \
  raw \
  -o "$PROFILE_CERTIFICATE_BASE64" \
  "$PROFILE_PLIST" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID signing certificate could not be extracted"
fi
if ! "$BASE64_COMMAND" \
  -D \
  -i "$PROFILE_CERTIFICATE_BASE64" \
  -o "$PROFILE_CERTIFICATE_DER" \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "Developer ID signing certificate is malformed"
fi
if ! PROFILE_FINGERPRINT_OUTPUT="$($OPENSSL_COMMAND x509 \
  -inform DER \
  -in "$PROFILE_CERTIFICATE_DER" \
  -noout \
  -fingerprint \
  -sha1 \
  2>>"$DIAGNOSTICS")"; then
  fail "Developer ID signing certificate could not be inspected"
fi
PROFILE_FINGERPRINT="$(
  printf '%s' "$PROFILE_FINGERPRINT_OUTPUT" |
    /usr/bin/awk -F= 'NF == 2 {print $2}' |
    /usr/bin/tr -d ':[:space:]' |
    /usr/bin/tr '[:lower:]' '[:upper:]'
)"
[[ "$PROFILE_FINGERPRINT" =~ ^[A-F0-9]{40}$ ]] || \
  fail "Developer ID signing certificate fingerprint is invalid"

if ! "$SECURITY_COMMAND" find-identity \
  -v \
  -p codesigning \
  "$KEYCHAIN_PATH" \
  >"$IDENTITIES_FILE" \
  2>>"$DIAGNOSTICS"; then
  fail "Developer ID signing identity could not be inspected"
fi
IDENTITY_MATCH_COUNT="$(
  /usr/bin/awk -v fingerprint="$PROFILE_FINGERPRINT" \
    '$2 == fingerprint {count += 1} END{print count + 0}' \
    "$IDENTITIES_FILE"
)"
[[ "$IDENTITY_MATCH_COUNT" == "1" ]] || \
  fail "imported Developer ID identity does not match the provisioning profile"
DEVELOPER_IDENTITY="$(
  /usr/bin/awk -v fingerprint="$PROFILE_FINGERPRINT" '
    $2 == fingerprint {
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$IDENTITIES_FILE"
)"
[[ "$DEVELOPER_IDENTITY" == "Developer ID Application:"*" ($PROFILE_TEAM)" ]] || \
  fail "matching signing identity is not a Developer ID Application identity"
[[ "$DEVELOPER_IDENTITY" != *$'\n'* && "$DEVELOPER_IDENTITY" != *$'\r'* ]] || \
  fail "matching signing identity contains unsafe characters"

if ! "$XCRUN_COMMAND" notarytool store-credentials \
  "$NOTARYTOOL_PROFILE" \
  --apple-id "$BAIROMETER_CI_NOTARYTOOL_APPLE_ID" \
  --team-id "$BAIROMETER_CI_NOTARYTOOL_TEAM_ID" \
  --password "$BAIROMETER_CI_NOTARYTOOL_PASSWORD" \
  --keychain "$KEYCHAIN_PATH" \
  --validate \
  >>"$DIAGNOSTICS" 2>&1; then
  fail "notary credentials could not be validated"
fi

printf 'BAIROMETER_DEVELOPMENT_TEAM=%s\n' "$PROFILE_TEAM" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_DEVELOPER_IDENTITY=%s\n' "$DEVELOPER_IDENTITY" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_PROVISIONING_PROFILE=%s\n' "$PROFILE_FILE" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_NOTARYTOOL_PROFILE=%s\n' "$NOTARYTOOL_PROFILE" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_NOTARYTOOL_KEYCHAIN=%s\n' "$KEYCHAIN_PATH" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_CI_PRIVATE_DIRECTORY=%s\n' "$PRIVATE_DIRECTORY" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_CI_KEYCHAIN_PATH=%s\n' "$KEYCHAIN_PATH" >>"$GITHUB_ENVIRONMENT_FILE"
printf 'BAIROMETER_CI_CREDENTIAL_OWNER=%s\n' "$OWNERSHIP_TOKEN" >>"$GITHUB_ENVIRONMENT_FILE"

SETUP_COMPLETE=1
echo "Configured ephemeral protected release credentials."
